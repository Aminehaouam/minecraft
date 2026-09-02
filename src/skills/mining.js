'use strict'

const { Vec3 } = require('vec3')
const { goals } = require('mineflayer-pathfinder')
const { sleep } = require('../util/async')
const { travelTo, gotoBlock } = require('./movement')
const names = require('../util/names')

const NEIGHBOURS = [
  new Vec3(1, 0, 0), new Vec3(-1, 0, 0),
  new Vec3(0, 1, 0), new Vec3(0, -1, 0),
  new Vec3(0, 0, 1), new Vec3(0, 0, -1)
]

const LAVA = new Set(['lava', 'flowing_lava'])

/** Refuses to break a block that would drop lava on the bot. */
function isDangerousToDig (bot, block) {
  for (const offset of NEIGHBOURS) {
    const neighbour = bot.blockAt(block.position.plus(offset))
    if (neighbour && LAVA.has(neighbour.name)) return true
  }
  const above = bot.blockAt(block.position.offset(0, 2, 0))
  return Boolean(above && LAVA.has(above.name))
}

async function equipBestTool (bot, block) {
  try {
    const tool = bot.pathfinder.bestHarvestTool(block)
    if (tool && (!bot.heldItem || bot.heldItem.type !== tool.type)) await bot.equip(tool, 'hand')
  } catch (err) {
    bot.companion.log.debug('equipBestTool:', err.message)
  }
}

function isDroppedItem (entity) {
  return Boolean(entity) && (entity.name === 'item' || entity.name === 'item_stack' || entity.displayName === 'Item')
}

function droppedItemName (entity) {
  try {
    const item = entity.getDroppedItem && entity.getDroppedItem()
    return item ? item.name : null
  } catch (err) {
    return null
  }
}

/** Walks over nearby dropped items so the bot actually keeps what it mined. */
async function collectNearbyDrops (bot, ctx, { radius = 8, itemNames = null, max = 12, settleMs = 400 } = {}) {
  // Drops appear a tick or two after the block breaks.
  if (settleMs > 0) await sleep(settleMs)
  let picked = 0
  for (let attempt = 0; attempt < max; attempt++) {
    if (ctx) ctx.checkCancelled()
    const drops = Object.values(bot.entities)
      .filter(isDroppedItem)
      .filter(entity => entity.position.distanceTo(bot.entity.position) <= radius)
      .filter(entity => {
        if (!itemNames) return true
        const name = droppedItemName(entity)
        return !name || itemNames.includes(name)
      })
      .sort((a, b) => a.position.distanceTo(bot.entity.position) - b.position.distanceTo(bot.entity.position))

    if (drops.length === 0) return picked
    const target = drops[0]
    const result = await travelTo(bot, new goals.GoalNear(target.position.x, target.position.y, target.position.z, 1), {
      ctx,
      timeoutMs: 15000
    })
    if (!result.ok && result.reason === 'interrupted') return picked
    await sleep(250)
    picked++
  }
  return picked
}

function countInInventory (bot, itemNames) {
  return bot.inventory
    .items()
    .filter(item => itemNames.includes(item.name))
    .reduce((total, item) => total + item.count, 0)
}

/**
 * Mines up to `count` blocks matching `query`.
 * Returns a summary the caller turns into a chat message.
 */
async function mineBlocks (bot, ctx, { query, count = 1, maxDistance = 48 } = {}) {
  const blockNames = names.blockNames(bot.registry, query)
  if (blockNames.length === 0) return { ok: false, reason: 'unknown-block', query }

  const ids = blockNames.map(name => bot.registry.blocksByName[name].id)
  const skipped = new Set()
  let mined = 0
  let failures = 0

  while (mined < count) {
    ctx.checkCancelled()
    const block = bot.findBlock({
      matching: ids,
      maxDistance,
      useExtraInfo: candidate => !skipped.has(candidate.position.toString())
    })
    if (!block) return { ok: mined > 0, reason: mined > 0 ? 'exhausted' : 'not-found', mined, blockNames }

    const key = block.position.toString()
    if (isDangerousToDig(bot, block)) {
      skipped.add(key)
      bot.companion.log.debug(`skipping ${block.name} at ${key}: lava nearby`)
      continue
    }

    const approach = await gotoBlock(bot, ctx, block.position)
    ctx.checkCancelled()
    if (!approach.ok) {
      skipped.add(key)
      if (approach.reason === 'interrupted') ctx.checkCancelled()
      if (++failures > 8) return { ok: mined > 0, reason: 'unreachable', mined, blockNames }
      continue
    }

    // The world may have changed while we walked over.
    const current = bot.blockAt(block.position)
    if (!current || !ids.includes(current.type)) {
      skipped.add(key)
      continue
    }
    if (!bot.canDigBlock(current)) {
      skipped.add(key)
      if (++failures > 8) return { ok: mined > 0, reason: 'unreachable', mined, blockNames }
      continue
    }

    await equipBestTool(bot, current)
    try {
      await bot.dig(current)
      mined++
      failures = 0
    } catch (err) {
      skipped.add(key)
      bot.companion.log.debug('dig failed:', err.message)
      if (++failures > 8) return { ok: mined > 0, reason: 'dig-failed', mined, blockNames }
      continue
    }

    // Unfiltered: ores drop raw metals, so matching on the block name would
    // leave the good stuff on the floor.
    await collectNearbyDrops(bot, ctx, { radius: 6, max: 3 })
  }

  return { ok: true, reason: 'done', mined, blockNames }
}

/** Breadth-first walk over the logs connected to `start`, so a whole trunk comes down. */
function findConnectedLogs (bot, start, logIds, limit = 24) {
  const found = []
  const seen = new Set([start.position.toString()])
  const queue = [start.position]

  while (queue.length > 0 && found.length < limit) {
    const position = queue.shift()
    const block = bot.blockAt(position)
    if (!block || !logIds.includes(block.type)) continue
    found.push(block)

    for (let dx = -1; dx <= 1; dx++) {
      for (let dy = -1; dy <= 1; dy++) {
        for (let dz = -1; dz <= 1; dz++) {
          if (dx === 0 && dy === 0 && dz === 0) continue
          const next = position.offset(dx, dy, dz)
          const key = next.toString()
          if (seen.has(key)) continue
          seen.add(key)
          queue.push(next)
        }
      }
    }
  }
  // Bottom-up: chopping the base first can strand the bot on floating logs.
  return found.sort((a, b) => a.position.y - b.position.y)
}

/** Fells whole trees until `count` logs are in the inventory. */
async function chopWood (bot, ctx, { count = 8, maxDistance = 64 } = {}) {
  const logNames = names.blockNames(bot.registry, 'wood')
  const logIds = logNames.map(name => bot.registry.blocksByName[name].id)
  const itemNames = logNames.filter(name => bot.registry.itemsByName[name])
  const startCount = countInInventory(bot, itemNames)
  let chopped = 0
  let trees = 0

  while (chopped < count) {
    ctx.checkCancelled()
    const trunk = bot.findBlock({ matching: logIds, maxDistance })
    if (!trunk) return { ok: chopped > 0, reason: chopped > 0 ? 'exhausted' : 'not-found', chopped, trees }

    const logs = findConnectedLogs(bot, trunk, logIds)
    trees++
    for (const log of logs) {
      ctx.checkCancelled()
      if (chopped >= count) break
      const fresh = bot.blockAt(log.position)
      if (!fresh || !logIds.includes(fresh.type)) continue
      const approach = await gotoBlock(bot, ctx, fresh.position)
      if (!approach.ok) continue
      const stillThere = bot.blockAt(log.position)
      if (!stillThere || !logIds.includes(stillThere.type) || !bot.canDigBlock(stillThere)) continue
      await equipBestTool(bot, stillThere)
      try {
        await bot.dig(stillThere)
        chopped++
      } catch (err) {
        bot.companion.log.debug('chop failed:', err.message)
      }
    }
    await collectNearbyDrops(bot, ctx, { radius: 10, max: 8 })
  }

  await collectNearbyDrops(bot, ctx, { radius: 10, max: 6 })
  return { ok: true, reason: 'done', chopped, trees, gained: countInInventory(bot, itemNames) - startCount }
}

/**
 * "collect X": picks up matching drops lying around, and falls back to mining
 * the block when there is nothing on the ground.
 */
async function collectItem (bot, ctx, { query, count = 1, maxDistance = 48 } = {}) {
  const wanted = names.itemNames(bot.registry, query)
  if (wanted.length === 0) return { ok: false, reason: 'unknown-item', query }

  const before = countInInventory(bot, wanted)
  const nearbyDrops = Object.values(bot.entities).filter(entity => {
    if (!isDroppedItem(entity)) return false
    if (entity.position.distanceTo(bot.entity.position) > maxDistance) return false
    const name = droppedItemName(entity)
    return !name || wanted.includes(name)
  })

  if (nearbyDrops.length > 0) {
    await collectNearbyDrops(bot, ctx, { radius: maxDistance, itemNames: wanted, max: Math.max(4, count) })
    const gained = countInInventory(bot, wanted) - before
    if (gained > 0) return { ok: true, reason: 'picked-up', gained, itemNames: wanted }
  }

  // Nothing on the floor — try to mine it instead.
  const mineable = names.blockNames(bot.registry, query)
  if (mineable.length === 0) return { ok: false, reason: 'nothing-to-collect', itemNames: wanted }
  const result = await mineBlocks(bot, ctx, { query, count, maxDistance })
  return { ...result, viaMining: true, itemNames: wanted }
}

module.exports = {
  mineBlocks,
  chopWood,
  collectItem,
  collectNearbyDrops,
  countInInventory,
  isDangerousToDig,
  findConnectedLogs,
  equipBestTool
}
