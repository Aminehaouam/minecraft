'use strict'

const test = require('node:test')
const assert = require('node:assert')
const dgram = require('node:dgram')

const { parseLanBroadcast, discoverLanWorld, MULTICAST_ADDRESS, MULTICAST_PORT } = require('../src/util/lan-discovery')

test('reads the port and world name out of a LAN advert', () => {
  const advert = parseLanBroadcast("[MOTD]Amine's World[/MOTD][AD]54321[/AD]")
  assert.deepStrictEqual(advert, { port: 54321, motd: "Amine's World" })
})

test('copes with adverts that are missing or malformed', () => {
  assert.strictEqual(parseLanBroadcast('[MOTD]No port here[/MOTD]'), null)
  assert.strictEqual(parseLanBroadcast('nonsense'), null)
  assert.strictEqual(parseLanBroadcast('[AD]99999999[/AD]'), null, 'rejects impossible ports')
  assert.deepStrictEqual(parseLanBroadcast('[AD]25565[/AD]'), { port: 25565, motd: null })
})

test('gives up quietly when no world is being advertised', async t => {
  const found = await discoverLanWorld({ timeoutMs: 300 })
  // Someone may genuinely have a world open while running the tests.
  if (found) {
    t.skip(`a LAN world is live on this machine (${found.host}:${found.port})`)
    return
  }
  assert.strictEqual(found, null)
})

test('finds a world that is broadcasting', async t => {
  const sender = dgram.createSocket({ type: 'udp4', reuseAddr: true })
  await new Promise(resolve => sender.bind(resolve))
  try {
    sender.setMulticastTTL(1)
    sender.setMulticastLoopback(true)
  } catch (err) {
    t.skip(`multicast unavailable here: ${err.message}`)
    sender.close()
    return
  }

  const payload = Buffer.from('[MOTD]Test World[/MOTD][AD]54321[/AD]')
  const timer = setInterval(() => sender.send(payload, MULTICAST_PORT, MULTICAST_ADDRESS, () => {}), 200)
  t.after(() => {
    clearInterval(timer)
    sender.close()
  })

  const found = await discoverLanWorld({ timeoutMs: 4000 })
  if (!found) {
    t.skip('no multicast loopback in this environment')
    return
  }
  assert.strictEqual(found.port, 54321)
  assert.strictEqual(found.motd, 'Test World')
  assert.ok(found.host, 'reports which machine is hosting')
})
