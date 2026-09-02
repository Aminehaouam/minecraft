'use strict'

const movement = require('../skills/movement')
const mining = require('../skills/mining')
const combat = require('../skills/combat')
const building = require('../skills/building')
const inv = require('../skills/inventory')
const names = require('../util/names')

const HELP_LINES = [
  'Commands: follow me / stop / come here / go to X Y Z / mine <block> / chop wood /',
  'collect <item> / attack / defend me / equip <item> / drop <item> / give me <item> /',
  'build shelter|tower|wall / eat / status. Phrasing is flexible, e.g. "bot can you mine some iron".'
]

function clampCount (value, fallback, max) {
  const count = Number.isFinite(value) && value > 0 ? value : fallback
  return Math.min(count, max)
}

/**
 * One handler per intent. Each receives:
 *   bot     the mineflayer bot (with bot.companion attached)
 *   args    parsed arguments from parser.js
 *   source  { username, reply(text) }
 */
const handlers = {
  help (bot, args, source) {
    HELP_LINES.forEach(line => source.reply(line))
  },

  status (bot, args, source) {
    inv.formatStatus(bot).forEach(line => source.reply(line))
  },

  stop (bot, args, source) {
    const companion = bot.companion
    companion.followMode = false
    companion.tasks.cancel()
    source.reply("Stopping — I'll stay right here.")
  },

  follow (bot, args, source) {
    const companion = bot.companion
    const who = args.who || source.username
    if (!bot.players[who]) {
      source.reply(`I can't see a player called ${who}.`)
      return
    }
    companion.followMode = true
    companion.followTarget = who
    source.reply(who === source.username ? 'Following you!' : `Following ${who}!`)
    companion.tasks.run(`following ${who}`, ctx =>
      movement.followPlayer(bot, ctx, who, companion.config.behavior.followRange)
    )
  },

  come (bot, args, source) {
    const companion = bot.companion
    source.reply('On my way!')
    companion.tasks.run(`coming to ${source.username}`, async ctx => {
      const result = await movement.comeToPlayer(bot, ctx, source.username)
      if (result.ok) source.reply('Here!')
      else if (result.reason === 'unknown-player') source.reply("I can't see where you are.")
      else if (result.reason === 'nopath') source.reply("I can't find a way to you from here.")
      else if (result.reason === 'timeout') source.reply('That is taking too long — giving up for now.')
    })
  },

  goto (bot, args, source) {
    const { x, y, z } = args
    source.reply(`Heading to ${x} ${y} ${z}.`)
    bot.companion.tasks.run(`walking to ${x} ${y} ${z}`, async ctx => {
      const result = await movement.gotoCoordinates(bot, ctx, x, y, z)
      if (result.ok) source.reply(`Arrived at ${x} ${y} ${z}.`)
      else if (result.reason === 'nopath') source.reply(`I can't find a path to ${x} ${y} ${z}.`)
      else if (result.reason === 'timeout') source.reply('That walk was taking too long — stopping here.')
    })
  },

  mine (bot, args, source) {
    const behavior = bot.companion.config.behavior
    if (!args.target) {
      source.reply('Mine what? Try "bot mine stone".')
      return
    }
    const blockNames = names.blockNames(bot.registry, args.target)
    if (blockNames.length === 0) {
      source.reply(`I don't know a block called "${args.target}".`)
      return
    }
    const count = clampCount(args.count, behavior.defaultMineCount, behavior.maxMineCount)
    source.reply(`Mining ${count}x ${names.pretty(blockNames[0])}...`)
    bot.companion.tasks.run(`mining ${names.pretty(blockNames[0])}`, async ctx => {
      const result = await mining.mineBlocks(bot, ctx, {
        query: args.target,
        count,
        maxDistance: behavior.searchRadius
      })
      if (result.reason === 'not-found') source.reply(`I can't find any ${names.pretty(blockNames[0])} within ${behavior.searchRadius} blocks.`)
      else if (result.reason === 'exhausted') source.reply(`Ran out of ${names.pretty(blockNames[0])} nearby — mined ${result.mined}.`)
      else if (result.reason === 'unreachable') source.reply(`I mined ${result.mined}, but I can't reach any more.`)
      else if (result.mined > 0) source.reply(`Done — mined ${result.mined} ${names.pretty(blockNames[0])}.`)
    })
  },

  chop (bot, args, source) {
    const behavior = bot.companion.config.behavior
    const count = clampCount(args.count, behavior.defaultChopCount, behavior.maxMineCount)
    source.reply(`Chopping wood — going for ${count} logs.`)
    bot.companion.tasks.run('chopping wood', async ctx => {
      const result = await mining.chopWood(bot, ctx, { count, maxDistance: behavior.searchRadius + 16 })
      if (result.reason === 'not-found') source.reply("I can't see any trees around here.")
      else if (result.chopped > 0) source.reply(`Got ${result.chopped} logs from ${result.trees} tree${result.trees === 1 ? '' : 's'}.`)
      else source.reply("I couldn't chop anything.")
    })
  },

  collect (bot, args, source) {
    const behavior = bot.companion.config.behavior
    if (!args.target) {
      source.reply('Collect what? Try "bot collect diamonds".')
      return
    }
    const count = clampCount(args.count, behavior.defaultCollectCount, behavior.maxMineCount)
    source.reply(`Looking for ${names.pretty(names.normalize(args.target))}...`)
    bot.companion.tasks.run(`collecting ${args.target}`, async ctx => {
      const result = await mining.collectItem(bot, ctx, {
        query: args.target,
        count,
        maxDistance: behavior.searchRadius
      })
      if (result.reason === 'unknown-item') source.reply(`I don't know an item called "${args.target}".`)
      else if (result.reason === 'picked-up') source.reply(`Picked up ${result.gained} ${names.pretty(args.target)}.`)
      else if (result.viaMining && result.mined > 0) source.reply(`Nothing was lying around, so I mined ${result.mined} for you.`)
      else if (result.reason === 'not-found' || result.reason === 'nothing-to-collect') source.reply(`I can't find any ${names.pretty(args.target)} nearby.`)
      else source.reply(`Collected what I could (${result.mined || 0}).`)
    })
  },

  attack (bot, args, source) {
    const survival = bot.companion.config.survival
    const nameFilter = args.target ? resolveMobName(bot, args.target) : null
    if (args.target && !nameFilter) {
      source.reply(`I don't know a mob called "${args.target}".`)
      return
    }
    const target = combat.nearestHostile(bot, {
      radius: survival.hostileScanRadius,
      nameFilter,
      includeNeutral: Boolean(nameFilter)
    })
    if (!target) {
      source.reply(nameFilter ? `No ${names.pretty(nameFilter)} in sight.` : 'Nothing hostile nearby.')
      return
    }
    source.reply(`Attacking ${target.displayName || names.pretty(target.name)}!`)
    bot.companion.tasks.run('attacking', async ctx => {
      const result = await combat.fightNearby(bot, ctx, {
        radius: survival.hostileScanRadius,
        nameFilter,
        fleeBelowHealth: survival.fleeWhenHealthBelow
      })
      if (result.reason === 'low-health') source.reply("I'm too hurt to keep fighting!")
      else if (result.killed > 0) source.reply(`Area clear — took down ${result.killed}.`)
    })
  },

  defend (bot, args, source) {
    const survival = bot.companion.config.survival
    const behavior = bot.companion.config.behavior
    source.reply(`Guarding you, ${source.username} — anything hostile gets a sword.`)
    bot.companion.tasks.run('defending', ctx =>
      combat.guardPlayer(bot, ctx, source.username, {
        radius: survival.hostileScanRadius,
        followRange: behavior.followRange + 1,
        fleeBelowHealth: survival.fleeWhenHealthBelow
      })
    )
  },

  async equip (bot, args, source) {
    if (!args.item) {
      source.reply('Equip what? Try "bot equip iron sword".')
      return
    }
    const result = await inv.equipItem(bot, args.item)
    if (result.ok) source.reply(`Equipped ${names.pretty(result.item.name)}${result.destination === 'hand' ? '' : ` (${result.destination})`}.`)
    else if (result.reason === 'not-in-inventory') source.reply(`I don't have any ${names.pretty(args.item)}.`)
    else source.reply(`I couldn't equip that: ${result.message}`)
  },

  async drop (bot, args, source) {
    const result = await inv.dropItem(bot, { query: args.item, count: args.count })
    if (result.ok) source.reply(`Dropped ${result.amount} ${names.pretty(result.item.name)}.`)
    else if (result.reason === 'not-in-inventory') source.reply(`I don't have any ${names.pretty(args.item || 'that')}.`)
    else if (result.reason === 'empty-hand') source.reply("I'm not holding anything to drop.")
    else source.reply(`I couldn't drop that: ${result.message}`)
  },

  give (bot, args, source) {
    bot.companion.tasks.run(`giving ${source.username} items`, async ctx => {
      const result = await inv.giveToPlayer(bot, ctx, source.username, { query: args.item, count: args.count })
      if (result.ok && result.reason === 'dropped-here') {
        source.reply(`I can't see you, so I left ${result.amount} ${names.pretty(result.item.name)} on the ground here.`)
      } else if (result.ok) source.reply(`Here you go — ${result.amount} ${names.pretty(result.item.name)}.`)
      else if (result.reason === 'not-in-inventory') source.reply(`I don't have any ${names.pretty(args.item || 'that')}.`)
      else if (result.reason === 'empty-hand') source.reply("I'm not holding anything to give.")
      else if (result.reason === 'cannot-reach') source.reply("I can't get to you to hand it over.")
      else source.reply("I couldn't hand that over.")
    })
  },

  async eat (bot, args, source) {
    const result = await inv.eat(bot)
    if (result.ok) source.reply(`Ate ${names.pretty(result.food.name)} — hunger now ${Math.round(bot.food)}/20.`)
    else if (result.reason === 'no-food') source.reply('I have no food on me.')
    else source.reply("I couldn't eat right now.")
  },

  build (bot, args, source) {
    const behavior = bot.companion.config.behavior
    const structure = building.resolveStructure(args.structure)
    if (!structure) {
      source.reply(`I can build a shelter, a tower or a wall — "${args.structure}" is beyond me.`)
      return
    }
    const material = building.pickMaterial(bot)
    if (!material) {
      source.reply("I have nothing to build with — give me some cobblestone or dirt.")
      return
    }
    source.reply(`Building a ${structure.name} out of ${names.pretty(material.name)}...`)
    bot.companion.tasks.run(`building a ${structure.name}`, async ctx => {
      const options = structure.kind === 'tower'
        ? { height: clampCount(args.size, behavior.defaultTowerHeight, 32) }
        : { length: clampCount(args.size, behavior.defaultWallLength, 24) }
      const result = await structure.build(bot, ctx, options)
      const prefix = bot.companion.config.commandPrefixes[0]
      if (result.reason === 'no-material') source.reply('I ran out of things to build with.')
      else if (result.reason === 'out-of-material') source.reply(`Out of ${names.pretty(result.material)} — I placed ${result.placed} blocks.`)
      else if (structure.kind === 'shelter') {
        source.reply(`Shelter's up (${result.placed} blocks). I'm sealed inside — say "${prefix} come here" and I'll dig my way out.`)
      } else if (structure.kind === 'tower') {
        source.reply(`Towered up ${result.climbed} blocks.`)
      } else {
        source.reply(`Wall done — ${result.placed} blocks placed.`)
      }
    })
  },

  unknown (bot, args, source) {
    source.reply(`Not sure what you meant. Try "${bot.companion.config.commandPrefixes[0]} help".`)
  }
}

/** Maps "zombie"/"creepers" onto a real mob name for targeted attacks. */
function resolveMobName (bot, query) {
  const key = names.normalize(query)
  const singular = names.singular(key)
  const mobs = Object.values(bot.registry.entitiesByName || {}).map(entity => entity.name)
  for (const candidate of [key, singular]) {
    if (mobs.includes(candidate)) return candidate
  }
  const partial = mobs.find(name => name.includes(singular) || singular.includes(name))
  return partial || null
}

module.exports = { handlers, HELP_LINES, resolveMobName, clampCount }
