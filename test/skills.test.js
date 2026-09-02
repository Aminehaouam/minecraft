'use strict'

const test = require('node:test')
const assert = require('node:assert')
const { Vec3 } = require('vec3')

const { createFakeBot, fakeBlock, registry } = require('./helpers/fake-bot')
const inventory = require('../src/skills/inventory')
const building = require('../src/skills/building')
const combat = require('../src/skills/combat')
const mining = require('../src/skills/mining')
const movement = require('../src/skills/movement')

test('items go to the right equipment slot', () => {
  assert.strictEqual(inventory.equipDestination('diamond_helmet'), 'head')
  assert.strictEqual(inventory.equipDestination('iron_chestplate'), 'torso')
  assert.strictEqual(inventory.equipDestination('leather_boots'), 'feet')
  assert.strictEqual(inventory.equipDestination('shield'), 'off-hand')
  assert.strictEqual(inventory.equipDestination('iron_sword'), 'hand')
})

test('inventory summary groups and sorts stacks', () => {
  const bot = createFakeBot({ items: [{ name: 'cobblestone', count: 32 }, { name: 'bread', count: 5 }, { name: 'cobblestone', count: 12 }] })
  const summary = inventory.inventorySummary(bot)
  assert.strictEqual(summary.isEmpty, false)
  assert.strictEqual(summary.shown[0], 'cobblestone x44')
  assert.strictEqual(summary.shown[1], 'bread x5')
})

test('findItem understands loose wording', () => {
  const bot = createFakeBot({ items: [{ name: 'diamond_sword' }, { name: 'oak_log', count: 3 }] })
  assert.strictEqual(inventory.findItem(bot, 'sword').name, 'diamond_sword')
  assert.strictEqual(inventory.findItem(bot, 'wood').name, 'oak_log')
  assert.strictEqual(inventory.findItem(bot, 'golden apple'), null)
})

test('the bot prefers real food over rotten flesh', () => {
  const bot = createFakeBot({ items: [{ name: 'rotten_flesh', count: 8 }, { name: 'bread', count: 2 }, { name: 'cooked_beef', count: 1 }] })
  assert.strictEqual(inventory.bestFood(bot).name, 'cooked_beef')
  const desperate = createFakeBot({ items: [{ name: 'rotten_flesh', count: 8 }] })
  assert.strictEqual(desperate.inventory.items().length, 1)
  assert.strictEqual(inventory.bestFood(desperate), null)
  assert.strictEqual(inventory.bestFood(desperate, { allowBad: true }).name, 'rotten_flesh')
})

test('building picks cheap materials, never valuables', () => {
  const bot = createFakeBot({ items: [{ name: 'diamond_block', count: 10 }, { name: 'cobblestone', count: 64 }] })
  assert.strictEqual(building.pickMaterial(bot).name, 'cobblestone')
  const poor = createFakeBot({ items: [{ name: 'diamond_block', count: 10 }] })
  assert.strictEqual(building.pickMaterial(poor), null, 'refuses to build with diamond blocks')
  const empty = createFakeBot({ items: [] })
  assert.strictEqual(building.pickMaterial(empty), null)
})

test('structure names are matched loosely', () => {
  assert.strictEqual(building.resolveStructure('a small shelter').name, 'shelter')
  assert.strictEqual(building.resolveStructure('hut').name, 'shelter')
  assert.strictEqual(building.resolveStructure('tall tower').name, 'tower')
  assert.strictEqual(building.resolveStructure('wall').name, 'wall')
  assert.strictEqual(building.resolveStructure('cathedral'), null)
  assert.strictEqual(building.resolveStructure(null).name, 'shelter')
})

test('hostility classification', () => {
  assert.strictEqual(combat.isHostile({ name: 'zombie', type: 'mob', kind: 'Hostile mobs' }), true)
  assert.strictEqual(combat.isHostile({ name: 'cow', type: 'mob', kind: 'Passive mobs' }), false)
  assert.strictEqual(combat.isHostile({ name: 'Steve', type: 'player' }), false)
  assert.strictEqual(combat.isHostile({ name: 'enderman', type: 'mob', kind: 'Passive mobs' }), true)
})

test('target selection skips neutral mobs unless named', () => {
  const entities = {
    1: { id: 1, name: 'enderman', type: 'mob', kind: 'Hostile mobs', position: new Vec3(2, 64, 0) },
    2: { id: 2, name: 'zombie', type: 'mob', kind: 'Hostile mobs', position: new Vec3(6, 64, 0) },
    3: { id: 3, name: 'cow', type: 'mob', kind: 'Passive mobs', position: new Vec3(1, 64, 0) }
  }
  const bot = createFakeBot({ entities })
  assert.strictEqual(combat.nearestHostile(bot, { radius: 16 }).name, 'zombie', 'ignores the closer enderman')
  assert.strictEqual(combat.nearestHostile(bot, { radius: 16, includeNeutral: true }).name, 'enderman')
  assert.strictEqual(combat.nearestHostile(bot, { radius: 16, nameFilter: 'cow' }).name, 'cow')
  assert.strictEqual(combat.nearestHostile(bot, { radius: 3 }), null, 'respects the search radius')
})

test('connected logs are found and chopped bottom-up', () => {
  const blocks = {}
  const positions = [new Vec3(0, 64, 0), new Vec3(0, 65, 0), new Vec3(0, 66, 0), new Vec3(1, 67, 0)]
  for (const pos of positions) blocks[pos.toString()] = fakeBlock('oak_log', pos)
  blocks[new Vec3(5, 64, 5).toString()] = fakeBlock('oak_log', new Vec3(5, 64, 5)) // separate tree
  const bot = createFakeBot({ blocks })
  const logIds = [registry.blocksByName.oak_log.id]
  const found = mining.findConnectedLogs(bot, blocks[positions[0].toString()], logIds)
  assert.strictEqual(found.length, 4, 'follows the trunk and its branch')
  assert.deepStrictEqual(found.map(block => block.position.y), [64, 65, 66, 67])
})

test('digging next to lava is refused', () => {
  const target = new Vec3(0, 64, 0)
  const blocks = { [target.toString()]: fakeBlock('stone', target) }
  const safeBot = createFakeBot({ blocks })
  assert.strictEqual(mining.isDangerousToDig(safeBot, blocks[target.toString()]), false)

  const lavaPos = target.offset(1, 0, 0)
  blocks[lavaPos.toString()] = fakeBlock('lava', lavaPos)
  const riskyBot = createFakeBot({ blocks })
  assert.strictEqual(mining.isDangerousToDig(riskyBot, blocks[target.toString()]), true)
})

test('movement profile avoids hazards and protects containers', () => {
  const bot = createFakeBot()
  const movements = movement.buildMovements(bot, { avoidHazards: true })
  assert.ok(movements.blocksToAvoid.has(registry.blocksByName.lava.id))
  assert.ok(movements.blocksToAvoid.has(registry.blocksByName.magma_block.id))
  assert.ok(movements.blocksToAvoid.has(registry.blocksByName.cactus.id))
  assert.ok(movements.blocksCantBreak.has(registry.blocksByName.chest.id))
  assert.strictEqual(movements.canDig, true)

  const careful = movement.buildMovements(bot, { canDig: false, allowParkour: false })
  assert.strictEqual(careful.canDig, false)
  assert.strictEqual(careful.allowParkour, false)
})
