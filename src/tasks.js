'use strict'

const { TaskCancelled } = require('./util/async')

/**
 * One job at a time. Starting a task cancels whatever the bot was doing, and
 * long-running skills call `ctx.checkCancelled()` inside their loops so a new
 * command (or the survival monitor) can interrupt them promptly.
 */
class TaskManager {
  constructor (bot, log) {
    this.bot = bot
    this.log = log
    this.current = null
    this.onIdle = null
  }

  get name () {
    return this.current ? this.current.name : 'idle'
  }

  get busy () {
    return this.current !== null
  }

  /**
   * @param {string} name           label shown by "bot status"
   * @param {(ctx) => Promise<any>} fn  the work itself
   * @param {{ resumeIdle?: boolean }} options
   */
  run (name, fn, { resumeIdle = true } = {}) {
    this.cancel()
    const ctx = {
      name,
      cancelled: false,
      checkCancelled () {
        if (this.cancelled) throw new TaskCancelled(this.name)
      }
    }
    this.current = ctx

    const promise = (async () => fn(ctx))()
    return promise
      .catch(err => {
        if (err instanceof TaskCancelled) {
          this.log.debug(`task ${name} cancelled`)
          return
        }
        // Tasks are started fire-and-forget, so failures are reported here
        // rather than escalating into an unhandled rejection.
        this.log.error(`task "${name}" failed:`, err.stack || err.message)
        const say = this.bot.companion && this.bot.companion.say
        if (say) say(`I hit a problem while ${name}: ${err.message}`)
      })
      .finally(() => {
        if (this.current !== ctx) return // something else already took over
        this.current = null
        this.stopMotion()
        if (resumeIdle && this.onIdle) this.onIdle()
      })
  }

  /** Cancels the running task and clears movement/controls. */
  cancel () {
    if (this.current) {
      this.current.cancelled = true
      this.current = null
    }
    this.stopMotion()
  }

  stopMotion () {
    const { bot } = this
    try {
      if (bot.pathfinder) bot.pathfinder.setGoal(null)
      bot.clearControlStates()
    } catch (err) {
      this.log.debug('stopMotion:', err.message)
    }
  }
}

module.exports = TaskManager
