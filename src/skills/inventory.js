'use strict'

const { goals } = require('mineflayer-pathfinder')
const { sleep } = require('../util/async')
const { travelTo, playerEntity } = require('./movement')
const names = require('../util/names')

// Edible, but the bot should not eat these unless there is nothing else.
const BAD_FOODS = new Set([
  'rotten_flesh', 'spider_eye', 'poisonous_potato', 'pufferfish',
  'suspicious_stew', 'chicken', 'rabbit', 'mutton', 'porkchop', 'beef', 'cod', 'salmon'
])

const ARMOUR_SLOTS = [
  [/_helmet$|^turtle_helmet$|^carved_pumpkin$/, 'head'],
  [/_chestplate$|^elytra$/, 'torso'],
  [/_leggings$/, 'legs'],
  [/_boots$/, 'feet'],
  [/^shield$|^totem_of_undying$/, 'off-hand']
]

function equipDestination (itemName) {
  const match = ARMOUR_SLOTS.find(([pattern]) => pattern.test(itemName))
  return match ? match[1] : 'hand'
}

/** Groups the inventory into "name xN" pairs, biggest stacks first. */
function inventorySummary (bot, limit = 8) {
  const totals = new Map()
  for (const item of bot.inventory.items()) {
    totals.set(item.name, (totals.get(item.name) || 0) + item.count)
  }
  const sorted = [...totals.entries()].sort((a, b) => b[1] - a[1])
  const shown = sorted.slice(0, limit).map(([name, count]) => `${names.pretty(name)} x${count}`)
  return { total: sorted.length, shown, isEmpty: sorted.length === 0 }
}

function findItem (bot, query) {
  const wanted = names.itemNames(bot.registry, query)
  if (wanted.length === 0) return null
  for (const name of wanted) {
    const item = bot.inventory.items().find(candidate => candidate.name === name)
    if (item) return item
  }
  return null
}

async function equipItem (bot, query) {
  const item = findItem(bot, query)
  if (!item) return { ok: false, reason: 'not-in-inventory' }
  const destination = equipDestination(item.name)
  try {
    await bot.equip(item, destination)
    return { ok: true, item, destination }
  } catch (err) {
    return { ok: false, reason: 'equip-failed', message: err.message, item }
  }
}

async function dropItem (bot, { query, count = null }) {
  const item = query ? findItem(bot, query) : bot.heldItem
  if (!item) return { ok: false, reason: query ? 'not-in-inventory' : 'empty-hand' }
  const owned = bot.inventory.items().filter(candidate => candidate.name === item.name)
  const available = owned.reduce((total, candidate) => total + candidate.count, 0)
  const amount = count === null ? available : Math.min(count, available)
  try {
    await bot.toss(item.type, null, amount)
    return { ok: true, item, amount }
  } catch (err) {
    return { ok: false, reason: 'toss-failed', message: err.message }
  }
}

/** Walks to the player, faces them, and tosses the items at their feet. */
async function giveToPlayer (bot, ctx, username, { query, count = null }) {
  const item = query ? findItem(bot, query) : bot.heldItem
  if (!item) return { ok: false, reason: query ? 'not-in-inventory' : 'empty-hand' }

  const target = playerEntity(bot, username)
  if (target) {
    const distance = target.position.distanceTo(bot.entity.position)
    if (distance > 3) {
      const approach = await travelTo(bot, new goals.GoalNear(target.position.x, target.position.y, target.position.z, 2), {
        ctx,
        timeoutMs: 45000
      })
      if (!approach.ok && approach.reason !== 'timeout') return { ok: false, reason: 'cannot-reach' }
    }
    const fresh = playerEntity(bot, username)
    if (fresh) {
      try {
        await bot.lookAt(fresh.position.offset(0, 1.2, 0), true)
      } catch (err) {
        bot.companion.log.debug('lookAt failed:', err.message)
      }
    }
  }

  const result = await dropItem(bot, { query, count })
  if (target || !result.ok) return result
  // Player is out of range: the items are on the ground where the bot stands.
  return { ...result, reason: 'dropped-here' }
}

function bestFood (bot, { allowBad = false } = {}) {
  const foods = bot.registry.foodsByName || {}
  const candidates = bot.inventory
    .items()
    .filter(item => foods[item.name])
    .filter(item => allowBad || !BAD_FOODS.has(item.name))
    .sort((a, b) => (foods[b.name].foodPoints || 0) - (foods[a.name].foodPoints || 0))
  return candidates[0] || null
}

/** Eats the best food available, then puts the previous item back in hand. */
async function eat (bot) {
  const food = bestFood(bot) || bestFood(bot, { allowBad: true })
  if (!food) return { ok: false, reason: 'no-food' }
  const previous = bot.heldItem
  try {
    await bot.equip(food, 'hand')
    await bot.consume()
    return { ok: true, food }
  } catch (err) {
    return { ok: false, reason: 'eat-failed', message: err.message }
  } finally {
    if (previous && previous.type !== food.type) {
      try {
        await bot.equip(previous, 'hand')
      } catch (err) {
        bot.companion.log.debug('re-equip after eating failed:', err.message)
      }
    }
    await sleep(100)
  }
}

function statusReport (bot) {
  const position = bot.entity.position.floored()
  const inventory = inventorySummary(bot)
  const held = bot.heldItem ? names.pretty(bot.heldItem.name) : 'nothing'
  return {
    health: Math.round(bot.health ?? 0),
    food: Math.round(bot.food ?? 0),
    position,
    held,
    task: bot.companion.tasks.name,
    inventory
  }
}

function formatStatus (bot) {
  const status = statusReport(bot)
  const lines = [
    `Health ${status.health}/20, hunger ${status.food}/20, at ${status.position.x} ${status.position.y} ${status.position.z}.`,
    `Currently: ${status.task}. Holding: ${status.held}.`,
    status.inventory.isEmpty
      ? 'My inventory is empty.'
      : `Inventory: ${status.inventory.shown.join(', ')}${status.inventory.total > status.inventory.shown.length ? ', ...' : ''}`
  ]
  return lines
}

module.exports = {
  inventorySummary,
  findItem,
  equipItem,
  dropItem,
  giveToPlayer,
  eat,
  bestFood,
  statusReport,
  formatStatus,
  equipDestination,
  BAD_FOODS
}
