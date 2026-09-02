'use strict'

const { parse } = require('./parser')
const { handlers } = require('./handlers')

/** Hooks chat + whisper events up to the parser and the handlers. */
function install (bot) {
  const { config, log } = bot.companion
  let lastRefusalAt = 0

  const owners = (config.owners || []).map(name => name.toLowerCase())
  function isAuthorized (username) {
    return owners.length === 0 || owners.includes(username.toLowerCase())
  }

  async function dispatch (username, message, { whisper = false } = {}) {
    if (!username || username === bot.username) return
    const parsed = parse(message, {
      prefixes: config.commandPrefixes,
      botUsername: bot.username
    })
    if (!parsed) return // not addressed to the bot

    const reply = text => {
      if (whisper && config.chat.whisperReplies) bot.companion.whisper(username, text)
      else bot.companion.say(text)
    }

    if (!isAuthorized(username)) {
      if (Date.now() - lastRefusalAt > 30000) {
        lastRefusalAt = Date.now()
        reply(`Sorry ${username}, I only take orders from ${config.owners.join(', ')}.`)
      }
      return
    }

    log.info(`<${username}> ${message}  ->  ${parsed.intent} ${JSON.stringify(parsed.args)}`)
    bot.companion.lastCommander = username
    if (bot.companion.followMode && !bot.companion.followTarget) bot.companion.followTarget = username

    const handler = handlers[parsed.intent] || handlers.unknown
    try {
      await handler(bot, parsed.args, { username, whisper, reply })
    } catch (err) {
      log.error(`handler "${parsed.intent}" failed:`, err.message)
      reply(`Something went wrong: ${err.message}`)
    }
  }

  bot.on('chat', (username, message) => {
    dispatch(username, message).catch(err => log.error('dispatch:', err.message))
  })
  bot.on('whisper', (username, message) => {
    dispatch(username, message, { whisper: true }).catch(err => log.error('dispatch:', err.message))
  })

  return { dispatch }
}

module.exports = { install, parse, handlers }
