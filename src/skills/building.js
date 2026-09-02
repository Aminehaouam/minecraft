'use strict'

const { Vec3 } = require('vec3')
const { goals } = require('mineflayer-pathfinder')
const { sleep } = require('../util/async')
const { travelTo } = require('./movement')
const names = require('../util/names')

const FACES = [
  new Vec3(0, -1, 0), new Vec3(0, 1, 0),
  new Vec3(1, 0, 0), new Vec3(-1, 0, 0),
  new Vec3(0, 0, 1), new Vec3(0, 0, -1)
]

// Cheap, plentiful blocks first — the bot should not wall itself in with diamonds.
const PREFERRED_MATERIALS = [
  'cobblestone', 'cobbled_deepslate', 'dirt', 'stone', 'andesite', 'granite', 'diorite',
  'netherrack', 'oak_planks', 'spruce_planks', 'birch_planks', 'jungle_planks',
  'acacia_planks', 'dark_oak_planks', 'sandstone', 'tuff', 'deepslate'
]

const NEVER_BUILD_WITH = new Set([
  'tnt', 'sand', 'red_sand', 'gravel', 'obsidian', 'crying_obsidian', 'bedrock',
  'chest', 'trapped_chest', 'ender_chest', 'shulker_box', 'barrel', 'spawner',
  'diamond_block', 'emerald_block', 'gold_block', 'netherite_block', 'ancient_debris'
])

/** Picks something sensible from the inventory to build with. */
function pickMaterial (bot) {
  const items = bot.inventory.items()
  for (const name of PREFERRED_MATERIALS) {
    const item = items.find(candidate => candidate.name === name)
    if (item) return item
  }
  return (
    items
      .filter(item => {
        if (NEVER_BUILD_WITH.has(item.name)) return false
        const block = bot.registry.blocksByName[item.name]
        return Boolean(block) && block.boundingBox === 'block'
      })
      .sort((a, b) => b.count - a.count)[0] || null
  )
}

function isReplaceable (block) {
  if (!block) return false
  return block.boundingBox === 'empty' || ['air', 'cave_air', 'void_air', 'water', 'lava', 'short_grass', 'grass', 'tall_grass', 'snow'].includes(block.name)
}

function occupiedByBot (bot, position) {
  const feet = bot.entity.position.floored()
  return position.equals(feet) || position.equals(feet.offset(0, 1, 0))
}

/** Places one block, choosing whichever neighbouring face has support. */
async function placeAt (bot, position, material) {
  const existing = bot.blockAt(position)
  if (!existing) return { ok: false, reason: 'unloaded' }
  if (!isReplaceable(existing)) return { ok: true, skipped: true }
  if (occupiedByBot(bot, position)) return { ok: false, reason: 'bot-in-the-way' }

  const item = bot.inventory.items().find(candidate => candidate.name === material.name)
  if (!item) return { ok: false, reason: 'out-of-material' }
  if (!bot.heldItem || bot.heldItem.name !== item.name) {
    try {
      await bot.equip(item, 'hand')
    } catch (err) {
      return { ok: false, reason: 'equip-failed', message: err.message }
    }
  }

  for (const face of FACES) {
    const reference = bot.blockAt(position.plus(face))
    if (!reference || reference.boundingBox !== 'block') continue
    try {
      await bot.placeBlock(reference, face.scaled(-1))
      await sleep(120)
      return { ok: true }
    } catch (err) {
      bot.companion.log.debug(`placeBlock at ${position}: ${err.message}`)
    }
  }
  return { ok: false, reason: 'no-support' }
}

/**
 * A 3x3 emergency shelter built around the bot: floor patched, walls two high,
 * roof on top. Small on purpose — it needs about 25 blocks.
 */
async function buildShelter (bot, ctx) {
  const material = pickMaterial(bot)
  if (!material) return { ok: false, reason: 'no-material' }

  const base = bot.entity.position.floored()
  const ring = []
  for (let dx = -1; dx <= 1; dx++) {
    for (let dz = -1; dz <= 1; dz++) {
      if (dx === 0 && dz === 0) continue
      ring.push(new Vec3(dx, 0, dz))
    }
  }
  const all = [...ring, new Vec3(0, 0, 0)]

  const plan = [
    ...all.map(offset => base.plus(offset).offset(0, -1, 0)), // floor
    ...ring.map(offset => base.plus(offset)), // wall, lower course
    ...ring.map(offset => base.plus(offset).offset(0, 1, 0)), // wall, upper course
    ...all.map(offset => base.plus(offset).offset(0, 2, 0)) // roof
  ]

  let placed = 0
  for (const position of plan) {
    ctx.checkCancelled()
    if (!bot.inventory.items().some(item => item.name === material.name)) {
      return { ok: placed > 0, reason: 'out-of-material', placed, material: material.name }
    }
    const result = await placeAt(bot, position, material)
    if (result.ok && !result.skipped) placed++
  }
  return { ok: true, reason: 'done', placed, material: material.name, position: base }
}

/** Pillars straight up by letting the pathfinder tower with our material. */
async function buildTower (bot, ctx, { height = 5 } = {}) {
  const material = pickMaterial(bot)
  if (!material) return { ok: false, reason: 'no-material' }

  const movements = bot.companion.movements
  const previousScaffolding = movements.scafoldingBlocks
  movements.scafoldingBlocks = [material.type, ...previousScaffolding]
  movements.allow1by1towers = true

  const base = bot.entity.position.floored()
  try {
    const result = await travelTo(bot, new goals.GoalBlock(base.x, base.y + height, base.z), { ctx, timeoutMs: 60000 })
    const climbed = Math.max(0, Math.round(bot.entity.position.y - base.y))
    return { ok: result.ok || climbed > 0, reason: result.ok ? 'done' : result.reason, climbed, material: material.name }
  } finally {
    movements.scafoldingBlocks = previousScaffolding
    bot.pathfinder.setMovements(movements)
  }
}

/** A straight wall in front of the bot. */
async function buildWall (bot, ctx, { length = 5, height = 2 } = {}) {
  const material = pickMaterial(bot)
  if (!material) return { ok: false, reason: 'no-material' }

  const yaw = bot.entity.yaw
  const forwardRaw = new Vec3(-Math.sin(yaw), 0, Math.cos(yaw))
  const forward = Math.abs(forwardRaw.x) > Math.abs(forwardRaw.z)
    ? new Vec3(Math.sign(forwardRaw.x), 0, 0)
    : new Vec3(0, 0, Math.sign(forwardRaw.z))
  const side = new Vec3(-forward.z, 0, forward.x)

  const start = bot.entity.position.floored().plus(forward.scaled(2))
  let placed = 0

  for (let i = 0; i < length; i++) {
    ctx.checkCancelled()
    const column = start.plus(side.scaled(i - Math.floor(length / 2)))
    if (column.offset(0, 0, 0).distanceTo(bot.entity.position) > 3.5) {
      await travelTo(bot, new goals.GoalNear(column.x, column.y, column.z, 2), { ctx, timeoutMs: 20000 })
    }
    for (let h = 0; h < height; h++) {
      ctx.checkCancelled()
      if (!bot.inventory.items().some(item => item.name === material.name)) {
        return { ok: placed > 0, reason: 'out-of-material', placed, material: material.name }
      }
      const result = await placeAt(bot, column.offset(0, h, 0), material)
      if (result.ok && !result.skipped) placed++
    }
  }
  return { ok: placed > 0, reason: placed > 0 ? 'done' : 'nothing-placed', placed, material: material.name }
}

// alias -> canonical structure
const STRUCTURES = {
  shelter: 'shelter',
  hut: 'shelter',
  house: 'shelter',
  home: 'shelter',
  base: 'shelter',
  box: 'shelter',
  tower: 'tower',
  pillar: 'tower',
  column: 'tower',
  wall: 'wall',
  fence: 'wall',
  barrier: 'wall'
}

const BUILDERS = {
  shelter: buildShelter,
  tower: buildTower,
  wall: buildWall
}

/** Maps a loose structure name onto one of the builders above. */
function resolveStructure (query) {
  const key = names.normalize(query || 'shelter')
  if (!key) return { name: 'shelter', kind: 'shelter', build: buildShelter }
  for (const [alias, kind] of Object.entries(STRUCTURES)) {
    if (key === alias || key.includes(alias)) return { name: kind, kind, build: BUILDERS[kind] }
  }
  return null
}

module.exports = {
  buildShelter,
  buildTower,
  buildWall,
  placeAt,
  pickMaterial,
  resolveStructure,
  STRUCTURES,
  BUILDERS,
  PREFERRED_MATERIALS
}
