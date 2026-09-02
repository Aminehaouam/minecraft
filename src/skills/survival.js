'use strict'

const { sleep } = require('../util/async')
const { retreatFrom } = require('./movement')
const combat = require('./combat')
const inventory = require('./inventory')

const HAZARD_BLOCKS = new Set(['lava', 'flowing_lava', 'fire', 'soul_fire', 'magma_block', 'campfire', 'soul_campfire'])
const MONITOR_INTERVAL_MS = 1000

/**
 * Keeps the bot alive: eats when hungry, gets out of lava, and decides whether
 * to fight back or run when something hits it.
 */
function install (bot, config) {
  const survival = config.survival || {}
  const say = bot.companion.say
  const log = bot.companion.log

  let eating = false
  let reactingAt = 0
  let lowHealthAnnouncedAt = 0
  let noFoodAnnouncedAt = 0

  const state = { lastHealth: bot.health ?? 20 }

  function throttled (timestamp, ms) {
    return Date.now() - timestamp > ms
  }

  async function maybeEat () {
    if (!survival.autoEat || eating) return
    const threshold = survival.eatWhenFoodBelow ?? 16
    if ((bot.food ?? 20) > threshold) return
    const food = inventory.bestFood(bot) || inventory.bestFood(bot, { allowBad: true })
    if (!food) {
      if (throttled(noFoodAnnouncedAt, 120000) && (bot.food ?? 20) <= 6) {
        noFoodAnnouncedAt = Date.now()
        say("I'm starving and I have no food on me.")
      }
      return
    }
    eating = true
    try {
      const result = await inventory.eat(bot)
      if (result.ok) log.info(`ate ${result.food.name} (food now ${bot.food})`)
    } catch (err) {
      log.debug('auto-eat failed:', err.message)
    } finally {
      eating = false
    }
  }

  function hazardUnderfoot () {
    if (survival.escapeHazards === false) return null
    const feet = bot.blockAt(bot.entity.position)
    const legs = bot.blockAt(bot.entity.position.offset(0, 1, 0))
    const below = bot.blockAt(bot.entity.position.offset(0, -1, 0))
    for (const block of [feet, legs, below]) {
      if (block && HAZARD_BLOCKS.has(block.name)) return block
    }
    return null
  }

  function escapeHazard (block) {
    const tasks = bot.companion.tasks
    if (tasks.name === 'escaping danger') return
    say(`Yikes — ${block.name.replace(/_/g, ' ')}! Getting out of here.`)
    tasks.run('escaping danger', async ctx => {
      await retreatFrom(bot, ctx, block.position, 8)
      await sleep(200)
    })
  }

  /** Something hit us: fight back if healthy enough, otherwise run. */
  function reactToDamage () {
    const cooldownMs = 2500
    if (!throttled(reactingAt, cooldownMs)) return
    const tasks = bot.companion.tasks
    const fleeBelow = survival.fleeWhenHealthBelow ?? 7
    const fightAbove = survival.fightBackWhenHealthAbove ?? 10
    const attacker = combat.nearestHostile(bot, { radius: survival.hostileScanRadius ?? 16, includeNeutral: true })

    if (bot.health <= fleeBelow) {
      if (tasks.name === 'fleeing') return
      reactingAt = Date.now()
      say("I'm low on health — falling back!")
      tasks.run('fleeing', async ctx => {
        if (attacker) await retreatFrom(bot, ctx, attacker.position, 20)
        else await sleep(500)
        await maybeEat()
      })
      return
    }

    if (!attacker) return
    if (tasks.name === 'fighting back' || tasks.name === 'attacking' || tasks.name === 'defending') return
    // Above the fight-back threshold the bot always retaliates; when it is
    // already hurt it only does so if it was not busy with a real job.
    if (bot.health <= fightAbove && tasks.busy) return
    reactingAt = Date.now()
    say(`Under attack by ${attacker.displayName || attacker.name} — fighting back!`)
    tasks.run('fighting back', async ctx => {
      await combat.attackEntity(bot, ctx, attacker, { fleeBelowHealth: fleeBelow })
    })
  }

  function onHealth () {
    const previous = state.lastHealth
    state.lastHealth = bot.health
    if (bot.health < previous) reactToDamage()
    if (bot.health <= (survival.fleeWhenHealthBelow ?? 7) && throttled(lowHealthAnnouncedAt, 15000)) {
      lowHealthAnnouncedAt = Date.now()
      say(`I'm low on health! (${Math.round(bot.health)}/20)`)
    }
  }

  function onEntityHurt (entity) {
    if (entity !== bot.entity) return
    reactToDamage()
  }

  const timer = setInterval(() => {
    if (!bot.entity) return
    const hazard = hazardUnderfoot()
    if (hazard) escapeHazard(hazard)
    maybeEat().catch(err => log.debug('maybeEat:', err.message))
  }, MONITOR_INTERVAL_MS)

  bot.on('health', onHealth)
  bot.on('entityHurt', onEntityHurt)
  bot.once('end', () => clearInterval(timer))

  return {
    stop () {
      clearInterval(timer)
      bot.removeListener('health', onHealth)
      bot.removeListener('entityHurt', onEntityHurt)
    },
    maybeEat
  }
}

module.exports = { install, HAZARD_BLOCKS }
