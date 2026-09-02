'use strict'

const mineflayer = require('mineflayer')
const { pathfinder } = require('mineflayer-pathfinder')

const configLoader = require('./config')
const loggerFactory = require('./logger')
const TaskManager = require('./tasks')
const { createSpeaker } = require('./util/chat')
const { discoverLanWorld } = require('./util/lan-discovery')
const movement = require('./skills/movement')
const survival = require('./skills/survival')
const commands = require('./commands')

/** Translates our config into mineflayer's createBot options. */
function buildBotOptions (config) {
  const options = {
    host: config.host,
    port: config.port,
    username: config.username,
    auth: config.auth || 'offline',
    hideErrors: false
  }
  if (config.version) options.version = config.version
  if (config.password) options.password = config.password
  return options
}

/**
 * Creates a connected companion bot. The returned object exposes the raw
 * mineflayer bot plus a `quit()` helper; reconnection is handled by main().
 */
function createCompanion (config, { log = loggerFactory.create(config.logLevel) } = {}) {
  const bot = mineflayer.createBot(buildBotOptions(config))
  bot.loadPlugin(pathfinder)

  const speaker = createSpeaker(bot, { minIntervalMs: config.chat.minIntervalMs, log })
  const tasks = new TaskManager(bot, log)

  bot.companion = {
    config,
    log,
    tasks,
    say: speaker.say,
    whisper: speaker.whisper,
    movements: null,
    followMode: config.behavior.followByDefault !== false,
    followTarget: null,
    lastCommander: null
  }

  // When a job finishes on its own, drift back to following.
  tasks.onIdle = () => resumeIdleBehaviour()

  function onlinePlayers () {
    return Object.keys(bot.players).filter(name => name !== bot.username)
  }

  function pickFollowTarget () {
    const companion = bot.companion
    if (companion.followTarget && bot.players[companion.followTarget]) return companion.followTarget
    const preferred = (config.owners || []).find(name => bot.players[name])
    if (preferred) return preferred
    if (companion.lastCommander && bot.players[companion.lastCommander]) return companion.lastCommander
    return onlinePlayers()[0] || null
  }

  function resumeIdleBehaviour () {
    const companion = bot.companion
    if (!companion.followMode || tasks.busy) return
    const target = pickFollowTarget()
    if (!target) return
    companion.followTarget = target
    tasks.run(`following ${target}`, ctx =>
      movement.followPlayer(bot, ctx, target, config.behavior.followRange)
    )
  }

  let started = false

  bot.on('login', () => {
    log.info(`logged in as ${bot.username} on ${config.host}:${config.port}`)
  })

  bot.on('spawn', () => {
    log.info(`spawned at ${bot.entity.position.floored()} (version ${bot.version})`)

    const movements = movement.buildMovements(bot, config.movement)
    bot.companion.movements = movements
    bot.pathfinder.setMovements(movements)

    if (!started) {
      started = true
      commands.install(bot)
      survival.install(bot, config)
      if (config.behavior.announceOnSpawn) {
        speaker.say(`${bot.username} reporting in — say "${config.commandPrefixes[0]} help" for what I can do.`)
      }
    }

    setTimeout(resumeIdleBehaviour, 2000)
  })

  bot.on('death', () => {
    log.warn('the bot died')
    tasks.cancel()
    speaker.say('I died... heading back to you once I respawn.')
  })

  bot.on('playerJoined', player => {
    if (player.username === bot.username) return
    if (bot.companion.followMode && !bot.companion.followTarget) setTimeout(resumeIdleBehaviour, 1000)
  })

  bot.on('kicked', reason => {
    log.error('kicked from the server:', typeof reason === 'string' ? reason : JSON.stringify(reason))
    const text = String(typeof reason === 'string' ? reason : JSON.stringify(reason)).toLowerCase()
    if (text.includes('whitelist')) log.error('hint: add the bot username to the server whitelist, or open the world to LAN with cheats allowed')
    if (text.includes('outdated') || text.includes('version')) log.error('hint: set "version" in config.json to your Minecraft version, e.g. "1.20.4"')
  })

  bot.on('error', err => {
    if (err.code === 'ECONNREFUSED') {
      log.error(`nothing is listening on ${config.host}:${config.port} — is the world open to LAN, and is the port right?`)
    } else {
      log.error('bot error:', err.message)
    }
  })

  bot.on('end', reason => {
    log.warn('disconnected:', reason || 'connection closed')
    tasks.cancel()
    speaker.clear()
  })

  return {
    bot,
    quit (reason = 'shutting down') {
      tasks.cancel()
      speaker.clear()
      try {
        bot.quit(reason)
      } catch (err) {
        log.debug('quit:', err.message)
      }
    }
  }
}

/**
 * Fills in "auto" host/port by listening for a Minecraft LAN broadcast, so a
 * freshly opened LAN world needs no configuration at all. Runs before every
 * connection attempt because Minecraft picks a new port each time.
 */
async function resolveTarget (config, log) {
  const autoHost = config.host === 'auto'
  const autoPort = config.port === 'auto'
  if (!autoHost && !autoPort) return config

  log.info('looking for a Minecraft world opened to LAN...')
  const found = await discoverLanWorld({ timeoutMs: config.lanDiscoveryTimeoutMs ?? 6000, log })

  if (found) {
    log.info(`found ${found.motd ? `"${found.motd}"` : 'a LAN world'} at ${found.host}:${found.port}`)
    return {
      ...config,
      host: autoHost ? found.host : config.host,
      port: autoPort ? found.port : config.port
    }
  }

  log.warn('no LAN world is being advertised — falling back to localhost:25565')
  log.warn('(open your world to LAN, or set "host"/"port" in config.json)')
  return {
    ...config,
    host: autoHost ? 'localhost' : config.host,
    port: autoPort ? 25565 : config.port
  }
}

async function main () {
  const config = configLoader.load()
  const log = loggerFactory.create(config.logLevel)

  if (!configLoader.hasUserConfig()) {
    log.warn('no config.json found — using config.example.json defaults (copy it to config.json to customise)')
  }

  let current = null
  let stopping = false

  const connect = async () => {
    const target = await resolveTarget(config, log)
    if (stopping) return
    log.info(`connecting to ${target.host}:${target.port} as ${target.username}...`)
    current = createCompanion(target, { log })
    current.bot.on('end', () => {
      if (stopping || !config.autoReconnect) {
        if (!stopping) process.exitCode = 1
        return
      }
      log.info(`reconnecting in ${Math.round(config.reconnectDelayMs / 1000)}s...`)
      setTimeout(() => {
        connect().catch(err => log.error('reconnect failed:', err.message))
      }, config.reconnectDelayMs)
    })
  }

  const shutdown = () => {
    if (stopping) return
    stopping = true
    log.info('shutting down')
    if (current) current.quit('bye')
    setTimeout(() => process.exit(0), 500)
  }

  process.on('SIGINT', shutdown)
  process.on('SIGTERM', shutdown)
  await connect()
}

if (require.main === module) {
  main().catch(err => {
    console.error('failed to start:', err.message)
    process.exitCode = 1
  })
}

module.exports = { createCompanion, buildBotOptions, main, resolveTarget }
