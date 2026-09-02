'use strict'

const { Movements, goals } = require('mineflayer-pathfinder')
const { Vec3 } = require('vec3')
const { sleep } = require('../util/async')

// Blocks the bot should never path through, on top of pathfinder's defaults.
const EXTRA_HAZARDS = [
  'lava',
  'flowing_lava',
  'fire',
  'soul_fire',
  'campfire',
  'soul_campfire',
  'magma_block',
  'cactus',
  'sweet_berry_bush',
  'powder_snow',
  'wither_rose',
  'pointed_dripstone'
]

/** Builds the Movements profile used for every path the bot walks. */
function buildMovements (bot, config = {}) {
  const movements = new Movements(bot)
  const registry = bot.registry

  movements.canDig = config.canDig !== false
  movements.allowParkour = config.allowParkour !== false
  movements.allowSprinting = config.allowSprinting !== false
  movements.allow1by1towers = config.allow1by1towers !== false

  if (config.avoidHazards !== false) {
    for (const name of EXTRA_HAZARDS) {
      const block = registry.blocksByName[name]
      if (block) movements.blocksToAvoid.add(block.id)
    }
    // Never mine away the block a player might be standing on above lava, and
    // never break containers that could hold the player's loot.
    for (const name of ['chest', 'trapped_chest', 'ender_chest', 'barrel', 'shulker_box', 'furnace', 'crafting_table', 'bed']) {
      const block = registry.blocksByName[name]
      if (block) movements.blocksCantBreak.add(block.id)
    }
  }
  return movements
}

/**
 * Walks to a goal, translating pathfinder's rejections into a plain result so
 * callers can report something useful in chat instead of crashing.
 */
async function travelTo (bot, goal, { ctx = null, timeoutMs = 90000 } = {}) {
  let timer = null
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => {
      const err = new Error('travel timed out')
      err.name = 'Timeout'
      reject(err)
    }, timeoutMs)
  })

  try {
    await Promise.race([bot.pathfinder.goto(goal), timeout])
    return { ok: true }
  } catch (err) {
    if (ctx) ctx.checkCancelled() // a new command took over: unwind the task
    if (err.name === 'Timeout') {
      bot.pathfinder.setGoal(null)
      return { ok: false, reason: 'timeout' }
    }
    if (err.name === 'NoPath') return { ok: false, reason: 'nopath' }
    if (err.name === 'GoalChanged' || err.name === 'PathStopped') return { ok: false, reason: 'interrupted' }
    throw err
  } finally {
    clearTimeout(timer)
  }
}

function playerEntity (bot, username) {
  const player = bot.players[username]
  return player && player.entity ? player.entity : null
}

/** Long-running: keeps a dynamic follow goal pointed at the player. */
async function followPlayer (bot, ctx, username, range = 3) {
  const say = bot.companion.say
  let trackedId = null
  let lostSince = null
  let lostAnnounced = false
  // Players go in and out of entity range constantly; only complain once the
  // bot has genuinely lost them for a few seconds.
  const graceMs = 5000

  while (true) {
    ctx.checkCancelled()
    const target = playerEntity(bot, username)

    if (!target) {
      if (lostSince === null) {
        lostSince = Date.now()
        bot.pathfinder.setGoal(null)
        trackedId = null
      } else if (!lostAnnounced && Date.now() - lostSince > graceMs) {
        lostAnnounced = true
        say(`I lost sight of ${username} — waiting here.`)
      }
      await sleep(1500)
      continue
    }

    if (lostAnnounced) say(`Found you again, ${username}!`)
    lostSince = null
    lostAnnounced = false

    // Re-issue the goal only when the entity is replaced (respawn, re-render),
    // otherwise the dynamic goal keeps tracking on its own.
    if (target.id !== trackedId) {
      trackedId = target.id
      bot.pathfinder.setGoal(new goals.GoalFollow(target, range), true)
    }
    await sleep(1000)
  }
}

/** One-shot: walk to the player and stop there. */
async function comeToPlayer (bot, ctx, username, range = 2) {
  const target = playerEntity(bot, username)
  if (!target) return { ok: false, reason: 'unknown-player' }
  const goal = new goals.GoalNear(target.position.x, target.position.y, target.position.z, range)
  return travelTo(bot, goal, { ctx })
}

async function gotoCoordinates (bot, ctx, x, y, z, range = 1) {
  const goal = new goals.GoalNear(x, y, z, range)
  return travelTo(bot, goal, { ctx, timeoutMs: 180000 })
}

/** Moves within reach of a block, with a fallback for blocks with no clear line of sight. */
async function gotoBlock (bot, ctx, position, { reach = 4 } = {}) {
  const lookGoal = new goals.GoalLookAtBlock(position, bot.world, { reach })
  const first = await travelTo(bot, lookGoal, { ctx, timeoutMs: 45000 })
  if (first.ok) return first
  if (first.reason === 'interrupted') return first
  return travelTo(bot, new goals.GoalNear(position.x, position.y, position.z, 2), { ctx, timeoutMs: 45000 })
}

/** Runs away from a position (used when fleeing or standing in something nasty). */
async function retreatFrom (bot, ctx, position, distance = 16) {
  const away = bot.entity.position.minus(position)
  const flat = new Vec3(away.x, 0, away.z)
  const norm = flat.norm() < 0.5 ? new Vec3(1, 0, 0) : flat.normalize()
  const target = bot.entity.position.plus(norm.scaled(distance))
  return travelTo(bot, new goals.GoalNearXZ(target.x, target.z, 2), { ctx, timeoutMs: 20000 })
}

module.exports = {
  buildMovements,
  travelTo,
  followPlayer,
  comeToPlayer,
  gotoCoordinates,
  gotoBlock,
  retreatFrom,
  playerEntity,
  EXTRA_HAZARDS
}
