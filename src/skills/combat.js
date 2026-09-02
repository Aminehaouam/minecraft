'use strict'

const { goals } = require('mineflayer-pathfinder')
const { sleep } = require('../util/async')
const { travelTo, playerEntity } = require('./movement')

// Mobs worth swinging at even when the server reports an unusual category.
const HOSTILE_NAMES = new Set([
  'zombie', 'zombie_villager', 'husk', 'drowned', 'zombified_piglin',
  'skeleton', 'stray', 'wither_skeleton', 'bogged',
  'creeper', 'spider', 'cave_spider', 'silverfish', 'endermite',
  'witch', 'slime', 'magma_cube', 'blaze', 'ghast', 'phantom',
  'pillager', 'vindicator', 'evoker', 'ravager', 'vex', 'illusioner',
  'guardian', 'elder_guardian', 'shulker', 'hoglin', 'zoglin', 'piglin_brute',
  'warden', 'breeze', 'enderman'
])

// Neutral mobs only fight back when provoked, so the bot leaves them alone
// unless the player names them explicitly ("bot attack that enderman").
const NEUTRAL_NAMES = new Set(['enderman', 'zombified_piglin', 'piglin', 'wolf', 'llama', 'panda', 'bee', 'iron_golem', 'goat', 'polar_bear', 'dolphin'])

// Melee reach is about 3 blocks; anything further and the swing whiffs.
const ATTACK_RANGE = 3.2
const SWING_INTERVAL_MS = 620

const WEAPON_SCORES = [
  ['netherite_sword', 100], ['diamond_sword', 90], ['iron_sword', 80],
  ['netherite_axe', 75], ['diamond_axe', 70], ['stone_sword', 60],
  ['golden_sword', 55], ['iron_axe', 50], ['wooden_sword', 45],
  ['stone_axe', 40], ['golden_axe', 35], ['wooden_axe', 30], ['trident', 85]
]

function isHostile (entity) {
  if (!entity || entity.type === 'player' || entity.type === 'object') return false
  if (NEUTRAL_NAMES.has(entity.name)) return true // hostile once provoked
  if (entity.kind === 'Hostile mobs') return true
  return HOSTILE_NAMES.has(entity.name)
}

function weaponScore (item) {
  const match = WEAPON_SCORES.find(([name]) => name === item.name)
  return match ? match[1] : 0
}

async function equipBestWeapon (bot) {
  const best = bot.inventory
    .items()
    .filter(item => weaponScore(item) > 0)
    .sort((a, b) => weaponScore(b) - weaponScore(a))[0]
  if (!best) return null
  if (bot.heldItem && bot.heldItem.type === best.type) return best
  try {
    await bot.equip(best, 'hand')
    return best
  } catch (err) {
    bot.companion.log.debug('equipBestWeapon:', err.message)
    return null
  }
}

/**
 * @param {object} options.near  optional entity/position to search around
 */
function nearestHostile (bot, { radius = 16, near = null, nameFilter = null, includeNeutral = false } = {}) {
  const origin = near ? (near.position || near) : bot.entity.position
  let best = null
  let bestDistance = Infinity
  for (const entity of Object.values(bot.entities)) {
    if (entity === bot.entity) continue
    if (nameFilter) {
      // The player named a specific mob, so hostility does not matter.
      if (entity.name !== nameFilter || entity.type === 'player') continue
    } else if (!isHostile(entity)) {
      continue
    } else if (!includeNeutral && NEUTRAL_NAMES.has(entity.name)) {
      continue
    }
    const distance = entity.position.distanceTo(origin)
    if (distance > radius || distance >= bestDistance) continue
    best = entity
    bestDistance = distance
  }
  return best
}

function entityAlive (bot, entity) {
  return Boolean(entity) && Boolean(bot.entities[entity.id]) && entity.isValid !== false
}

/**
 * Chases and hits one entity until it dies, disappears, or the bot's health
 * drops below `fleeBelowHealth`.
 */
async function attackEntity (bot, ctx, target, { fleeBelowHealth = 7, timeoutMs = 60000 } = {}) {
  await equipBestWeapon(bot)
  const deadline = Date.now() + timeoutMs
  bot.pathfinder.setGoal(new goals.GoalFollow(target, 2), true)

  try {
    while (entityAlive(bot, target)) {
      ctx.checkCancelled()
      if (bot.health <= fleeBelowHealth) return { ok: false, reason: 'low-health' }
      if (Date.now() > deadline) return { ok: false, reason: 'timeout' }

      const distance = target.position.distanceTo(bot.entity.position)
      if (distance <= ATTACK_RANGE) {
        try {
          await bot.lookAt(target.position.offset(0, target.height ? target.height * 0.8 : 1.4, 0), true)
          bot.attack(target)
        } catch (err) {
          bot.companion.log.debug('attack failed:', err.message)
        }
        await sleep(SWING_INTERVAL_MS)
      } else if (distance > 24) {
        return { ok: false, reason: 'lost' }
      } else {
        await sleep(180)
      }
    }
    return { ok: true, reason: 'killed' }
  } finally {
    bot.pathfinder.setGoal(null)
  }
}

/** "bot attack": clears out hostiles around the bot. */
async function fightNearby (bot, ctx, { radius = 16, nameFilter = null, fleeBelowHealth = 7, maxTargets = 6 } = {}) {
  let killed = 0
  for (let i = 0; i < maxTargets; i++) {
    ctx.checkCancelled()
    const target = nearestHostile(bot, { radius, nameFilter })
    if (!target) return { ok: true, reason: killed > 0 ? 'clear' : 'nothing-here', killed }
    const result = await attackEntity(bot, ctx, target, { fleeBelowHealth })
    if (result.ok) killed++
    else if (result.reason === 'low-health') return { ok: false, reason: 'low-health', killed }
  }
  return { ok: true, reason: 'clear', killed }
}

/**
 * "bot defend me": stays near the player and intercepts anything hostile that
 * comes close. Runs until cancelled.
 */
async function guardPlayer (bot, ctx, username, { radius = 12, followRange = 4, fleeBelowHealth = 7 } = {}) {
  const say = bot.companion.say

  while (true) {
    ctx.checkCancelled()
    const owner = playerEntity(bot, username)
    const threat = nearestHostile(bot, { radius, near: owner || bot.entity })

    if (threat) {
      say(`${threat.displayName || threat.name} spotted — on it!`)
      const result = await attackEntity(bot, ctx, threat, { fleeBelowHealth })
      if (result.reason === 'low-health') {
        say("I'm too hurt to keep fighting!")
        return { ok: false, reason: 'low-health' }
      }
      continue
    }

    if (owner) {
      const distance = owner.position.distanceTo(bot.entity.position)
      if (distance > followRange + 2) {
        await travelTo(bot, new goals.GoalNear(owner.position.x, owner.position.y, owner.position.z, followRange), {
          ctx,
          timeoutMs: 20000
        })
      }
    }
    await sleep(700)
  }
}

module.exports = {
  isHostile,
  nearestHostile,
  attackEntity,
  fightNearby,
  guardPlayer,
  equipBestWeapon,
  HOSTILE_NAMES,
  NEUTRAL_NAMES
}
