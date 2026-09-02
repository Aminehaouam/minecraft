'use strict'

const MAX_MESSAGE_LENGTH = 240

/**
 * Minecraft servers kick clients that chat too fast, so every outgoing line
 * goes through a small queue with a minimum gap between messages.
 */
function createSpeaker (bot, { minIntervalMs = 1200, log } = {}) {
  const queue = []
  let timer = null
  let lastSentAt = 0

  function flush () {
    timer = null
    const next = queue.shift()
    if (!next) return
    try {
      if (next.to) bot.whisper(next.to, next.text)
      else bot.chat(next.text)
      lastSentAt = Date.now()
    } catch (err) {
      if (log) log.warn('chat failed:', err.message)
    }
    schedule()
  }

  function schedule () {
    if (timer || queue.length === 0) return
    const wait = Math.max(0, minIntervalMs - (Date.now() - lastSentAt))
    timer = setTimeout(flush, wait)
  }

  function enqueue (text, to = null) {
    if (!text) return
    const clean = String(text).replace(/\s+/g, ' ').trim().slice(0, MAX_MESSAGE_LENGTH)
    if (!clean) return
    if (log) log.info(to ? `-> /msg ${to}: ${clean}` : `-> chat: ${clean}`)
    queue.push({ text: clean, to })
    schedule()
  }

  return {
    say: text => enqueue(text),
    whisper: (to, text) => enqueue(text, to),
    /** Drops anything still queued (used on disconnect). */
    clear () {
      queue.length = 0
      if (timer) clearTimeout(timer)
      timer = null
    },
    get pending () {
      return queue.length
    }
  }
}

module.exports = { createSpeaker, MAX_MESSAGE_LENGTH }
