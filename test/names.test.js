'use strict'

const test = require('node:test')
const assert = require('node:assert')
const registry = require('minecraft-data')('1.20.4')
const names = require('../src/util/names')

test('resolves plain block names', () => {
  assert.deepStrictEqual(names.blockNames(registry, 'stone').slice(0, 2), ['stone', 'cobblestone'])
  assert.deepStrictEqual(names.blockNames(registry, 'Oak Log'), ['oak_log'])
  assert.deepStrictEqual(names.blockNames(registry, 'iron ore'), ['iron_ore'])
})

test('expands loose words into families of blocks', () => {
  const wood = names.blockNames(registry, 'wood')
  assert.ok(wood.includes('oak_log') && wood.includes('birch_log'))
  assert.ok(!wood.some(name => name.startsWith('stripped_')), 'prefers natural logs')
  const logs = names.blockNames(registry, 'logs')
  assert.ok(logs.every(name => wood.includes(name)), '"logs" is a subset of "wood"')
  assert.deepStrictEqual(names.blockNames(registry, 'diamonds'), ['diamond_ore', 'deepslate_diamond_ore'])
})

test('resolves items separately from blocks', () => {
  assert.deepStrictEqual(names.itemNames(registry, 'cooked beef'), ['cooked_beef'])
  assert.ok(names.itemNames(registry, 'pickaxe').includes('diamond_pickaxe'))
  assert.ok(names.itemNames(registry, 'sword').every(name => name.endsWith('_sword')))
  assert.deepStrictEqual(names.itemNames(registry, 'diamond')[0], 'diamond')
})

test('returns nothing for gibberish', () => {
  assert.deepStrictEqual(names.blockNames(registry, 'unobtainium'), [])
  assert.deepStrictEqual(names.itemNames(registry, ''), [])
})

test('normalises and prettifies', () => {
  assert.strictEqual(names.normalize('  Deepslate Iron Ore! '), 'deepslate_iron_ore')
  assert.strictEqual(names.normalize('minecraft:oak_log'), 'oak_log')
  assert.strictEqual(names.pretty('deepslate_iron_ore'), 'deepslate iron ore')
  assert.strictEqual(names.singular('logs'), 'log')
  assert.strictEqual(names.singular('glass'), 'glass')
})
