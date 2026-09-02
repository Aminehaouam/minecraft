'use strict'

const dgram = require('node:dgram')

/**
 * Minecraft advertises a world that has been opened to LAN by broadcasting
 *   [MOTD]<world name>[/MOTD][AD]<port>[/AD]
 * to the multicast group 224.0.2.60:4445, roughly every 1.5 seconds.
 * Listening for it means the player never has to copy the random LAN port
 * into a config file.
 */

const MULTICAST_ADDRESS = '224.0.2.60'
const MULTICAST_PORT = 4445

/** Pulls the port (and world name) out of one broadcast payload. */
function parseLanBroadcast (message) {
  const text = String(message)
  const advert = text.match(/\[AD\]\s*(\d{1,5})\s*\[\/AD\]/i)
  if (!advert) return null
  const port = Number(advert[1])
  if (!Number.isInteger(port) || port < 1 || port > 65535) return null
  const motd = text.match(/\[MOTD\]([\s\S]*?)\[\/MOTD\]/i)
  return { port, motd: motd ? motd[1].trim() : null }
}

/**
 * Waits for the first LAN broadcast and reports where the world lives.
 * Resolves with null when nothing shows up before the timeout — the caller
 * then falls back to the configured/default address.
 *
 * @returns {Promise<null | {host: string, port: number, motd: string|null}>}
 */
function discoverLanWorld ({ timeoutMs = 6000, log = null } = {}) {
  return new Promise(resolve => {
    let socket
    let timer = null
    let settled = false

    const finish = result => {
      if (settled) return
      settled = true
      if (timer) clearTimeout(timer)
      try {
        socket.close()
      } catch (err) {
        if (log) log.debug('lan discovery close:', err.message)
      }
      resolve(result)
    }

    try {
      socket = dgram.createSocket({ type: 'udp4', reuseAddr: true })
    } catch (err) {
      if (log) log.debug('lan discovery unavailable:', err.message)
      return resolve(null)
    }

    socket.on('error', err => {
      if (log) log.debug('lan discovery error:', err.message)
      finish(null)
    })

    socket.on('message', (message, rinfo) => {
      const parsed = parseLanBroadcast(message)
      if (!parsed) return
      finish({ host: rinfo.address, port: parsed.port, motd: parsed.motd })
    })

    socket.bind(MULTICAST_PORT, () => {
      try {
        socket.addMembership(MULTICAST_ADDRESS)
      } catch (err) {
        // Some networks (or containers) refuse multicast; broadcasts sent to
        // this port may still arrive, so keep listening rather than bailing.
        if (log) log.debug('could not join the multicast group:', err.message)
      }
    })

    timer = setTimeout(() => finish(null), timeoutMs)
  })
}

module.exports = { discoverLanWorld, parseLanBroadcast, MULTICAST_ADDRESS, MULTICAST_PORT }
