'use strict'

const registry = require('minecraft-data')('1.20.4')
const { Vec3 } = require('vec3')

/** A tiny stand-in for a mineflayer bot, enough for the pure skill helpers. */
function createFakeBot ({ items = [], entities = {}, position = new Vec3(0, 64, 0), blocks = {} } = {}) {
  const inventoryItems = items.map((item, index) => ({
    name: item.name,
    count: item.count ?? 1,
    type: registry.itemsByName[item.name] ? registry.itemsByName[item.name].id : index,
    slot: 36 + index
  }))

  const bot = {
    registry,
    username: 'TestBot',
    health: 20,
    food: 20,
    heldItem: null,
    entity: { id: 0, position, type: 'player', name: 'player' },
    entities,
    players: {},
    inventory: { items: () => inventoryItems },
    blockAt: pos => blocks[pos.toString()] || null,
    companion: {
      log: { info () {}, warn () {}, error () {}, debug () {} },
      say () {},
      tasks: { name: 'idle', busy: false }
    }
  }
  return bot
}

/** Builds a block object of the given type at a position. */
function fakeBlock (name, pos) {
  const data = registry.blocksByName[name]
  return {
    name,
    type: data ? data.id : -1,
    position: pos,
    boundingBox: data && data.boundingBox ? data.boundingBox : 'block',
    diggable: true
  }
}

module.exports = { createFakeBot, fakeBlock, registry, Vec3 }
