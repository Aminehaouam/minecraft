'use strict'

const LEVELS = { error: 0, warn: 1, info: 2, debug: 3 }

function create (level = 'info') {
  const threshold = LEVELS[level] ?? LEVELS.info
  const emit = (name, stream, args) => {
    if (LEVELS[name] > threshold) return
    const stamp = new Date().toISOString().slice(11, 19)
    stream(`[${stamp}] ${name.toUpperCase().padEnd(5)}`, ...args)
  }
  return {
    error: (...args) => emit('error', console.error, args),
    warn: (...args) => emit('warn', console.warn, args),
    info: (...args) => emit('info', console.log, args),
    debug: (...args) => emit('debug', console.log, args)
  }
}

module.exports = { create }
