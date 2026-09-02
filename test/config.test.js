'use strict'

const test = require('node:test')
const assert = require('node:assert')
const configLoader = require('../src/config')

test('loads defaults from config.example.json', () => {
  const config = configLoader.load({})
  assert.strictEqual(config.host, 'localhost')
  assert.strictEqual(config.port, 25565)
  assert.ok(config.commandPrefixes.includes('bot'))
  assert.strictEqual(typeof config.survival.autoEat, 'boolean')
})

test('environment variables override the files', () => {
  const config = configLoader.load({
    MC_HOST: '192.168.1.50',
    MC_PORT: '25566',
    MC_USERNAME: 'Buddy',
    BOT_OWNERS: 'Alice, Bob'
  })
  assert.strictEqual(config.host, '192.168.1.50')
  assert.strictEqual(config.port, 25566)
  assert.strictEqual(config.username, 'Buddy')
  assert.deepStrictEqual(config.owners, ['Alice', 'Bob'])
})

test('merge only overrides the keys it names', () => {
  const merged = configLoader.merge(
    { host: 'localhost', behavior: { followRange: 3, searchRadius: 48 } },
    { behavior: { followRange: 6 } }
  )
  assert.strictEqual(merged.host, 'localhost')
  assert.strictEqual(merged.behavior.followRange, 6)
  assert.strictEqual(merged.behavior.searchRadius, 48)
})
