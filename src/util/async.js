'use strict'

class TaskCancelled extends Error {
  constructor (taskName) {
    super(`task "${taskName}" was cancelled`)
    this.name = 'TaskCancelled'
    this.taskName = taskName
  }
}

function sleep (ms) {
  return new Promise(resolve => setTimeout(resolve, ms))
}

// Resolves once `predicate()` is true, or throws after `timeoutMs`.
async function waitFor (predicate, { timeoutMs = 10000, intervalMs = 100 } = {}) {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    if (predicate()) return true
    await sleep(intervalMs)
  }
  throw new Error('timed out waiting for condition')
}

module.exports = { TaskCancelled, sleep, waitFor }
