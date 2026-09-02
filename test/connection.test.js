'use strict'

const test = require('node:test')
const assert = require('node:assert')
const net = require('node:net')

const configLoader = require('../src/config')
const { createCompanion, buildBotOptions } = require('../src/index')

const silentLog = { info () {}, warn () {}, error () {}, debug () {} }

test('config is translated into mineflayer connection options', () => {
  const options = buildBotOptions({ host: 'example.local', port: 25566, username: 'Buddy', auth: 'offline' })
  assert.deepStrictEqual(options, {
    host: 'example.local',
    port: 25566,
    username: 'Buddy',
    auth: 'offline',
    hideErrors: false
  })
  assert.strictEqual(buildBotOptions({ host: 'h', port: 1, username: 'u', version: '1.20.4' }).version, '1.20.4')
  assert.strictEqual(buildBotOptions({ host: 'h', port: 1, username: 'u' }).version, undefined, 'version is auto-detected when unset')
})

// Uses a bare TCP listener rather than a real Minecraft server: it proves the
// bot dials the configured address and introduces itself with the configured
// username, which is the part our own code is responsible for.
test('the bot dials the configured address and sends its username', async t => {
  const server = net.createServer()
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
  const { port } = server.address()

  const handshake = new Promise(resolve => {
    server.once('connection', socket => {
      const chunks = []
      socket.on('data', chunk => {
        chunks.push(chunk)
        const seen = Buffer.concat(chunks).toString('latin1')
        if (seen.includes('TestCompanion')) resolve(seen)
      })
      socket.on('error', () => {})
    })
  })

  const config = configLoader.merge(configLoader.load({}), {
    host: '127.0.0.1',
    port,
    username: 'TestCompanion',
    version: '1.20.4',
    autoReconnect: false
  })
  const companion = createCompanion(config, { log: silentLog })
  t.after(() => {
    companion.quit('test finished')
    server.close()
  })

  const seen = await Promise.race([
    handshake,
    new Promise((_, reject) => {
      // unref'd so a fast success does not keep the test process alive
      setTimeout(() => reject(new Error('no handshake within 10s')), 10000).unref()
    })
  ])

  assert.ok(seen.includes('127.0.0.1'), 'handshake carries the configured host')
  assert.ok(seen.includes('TestCompanion'), 'login start carries the configured username')
})
