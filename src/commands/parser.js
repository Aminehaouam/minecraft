'use strict'

/**
 * Local, dependency-free intent parsing.
 *
 * Nothing here calls out to an LLM or any paid service: a message is stripped
 * of its prefix and filler words, then run through an ordered list of rules
 * until one matches. Rules are deliberately loose, so "bot mine stone",
 * "bot can you mine some stone please" and "bot dig 10 stone for me" all land
 * on the same intent.
 */

const FILLERS = [
  /\bcan you please\b/g,
  /\b(can|could|would|will) you\b/g,
  /\bi (want|need) you to\b/g,
  /\bgo ahead and\b/g,
  /\bplease\b/g,
  /\bthanks?\b/g,
  /\bthank you\b/g,
  /\b(hey|hi|hello|yo|ok|okay|alright)\b/g,
  /\bright now\b/g,
  /\bfor me\b/g,
  /\bwould you mind\b/g,
  /\bif you (can|could)\b/g
]

const NUMBER_WORDS = {
  a: 1,
  an: 1,
  one: 1,
  two: 2,
  three: 3,
  four: 4,
  five: 5,
  six: 6,
  seven: 7,
  eight: 8,
  nine: 9,
  ten: 10,
  eleven: 11,
  twelve: 12,
  dozen: 12,
  fifteen: 15,
  twenty: 20,
  thirty: 30,
  couple: 2,
  few: 3,
  several: 4,
  stack: 64
}

const NUMBER_WORD_PATTERN = Object.keys(NUMBER_WORDS).join('|')
const TARGET_NOISE = new RegExp(
  '^(?:me|us|some|the|that|this|those|these|any|more|of|up|out|down|nearest|closest|nearby|near|bunch|lot|lots|' +
    'block|blocks|piece|pieces|item|items|' + NUMBER_WORD_PATTERN + ')\\b\\s*'
)

/**
 * Removes the command prefix. Returns the remaining text, or null when the
 * message was not addressed to the bot at all.
 */
function stripPrefix (message, { prefixes = [], botUsername = '' } = {}) {
  const text = String(message || '').trim()
  if (!text) return null
  const candidates = [...prefixes]
  if (botUsername) candidates.push(botUsername, '@' + botUsername)
  // Longest first so "!bot" wins over "bot".
  const sorted = [...new Set(candidates.filter(Boolean))].sort((a, b) => b.length - a.length)
  for (const prefix of sorted) {
    const lower = text.toLowerCase()
    const key = prefix.toLowerCase()
    if (!lower.startsWith(key)) continue
    const rest = text.slice(prefix.length)
    // The prefix must be a whole word: "bot, follow" and "bot follow" match,
    // "bottle of water" does not.
    if (rest.length > 0 && !/^[\s,:;!.-]/.test(rest)) continue
    return rest.replace(/^[\s,:;!.-]+/, '').trim()
  }
  return null
}

function normalize (text) {
  let out = ' ' + String(text || '').toLowerCase().replace(/[^\w\s-]/g, ' ') + ' '
  for (const filler of FILLERS) out = out.replace(filler, ' ')
  return out.replace(/\s+/g, ' ').trim()
}

function parseCount (text, fallback = null) {
  const digits = text.match(/\b(\d{1,4})\b/)
  if (digits) return Number(digits[1])
  for (const [word, value] of Object.entries(NUMBER_WORDS)) {
    if (word === 'a' || word === 'an') continue
    if (new RegExp(`\\b${word}\\b`).test(text)) return value
  }
  return fallback
}

/** Cleans the noun phrase that follows a verb: "some 10 blocks of stone" -> "stone". */
function cleanTarget (text) {
  let out = String(text || '').replace(/\b\d{1,4}\b/g, ' ').trim()
  let previous = null
  while (out !== previous) {
    previous = out
    out = out.replace(TARGET_NOISE, '').trim()
  }
  out = out
    .replace(/\b(for|to)\s+(me|us)\b/g, ' ')
    .replace(/\b(over|around|nearby|near|here|there|now)\b/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
  return out
}

const WOOD_WORDS = /\b(wood|woods|log|logs|tree|trees|timber|lumber)\b/
const MOVE_VERB = /\b(go|goto|move|walk|travel|head|navigate|run|path|teleport|tp)\b/
const COORDS = /(-?\d+)\s*[,\s]\s*(-?\d+)\s*[,\s]\s*(-?\d+)/

const RULES = [
  {
    // Checked before "help" so "what do you have" reports the inventory.
    intent: 'status',
    match: text => {
      if (/\b(status|report|sitrep)\b/.test(text)) return {}
      if (/\bhow (are|is|you)\b/.test(text)) return {}
      if (/\bwhat (do|have) you (have|got|hold)/.test(text)) return {}
      // A bare mention of health/hunger/inventory only counts when the player
      // is not asking the bot to *do* something with food or items.
      const stateWords = /\b(health|hp|hunger|food|inventory|items|stuff)\b/
      const actionWords = /\b(give|hand|bring|share|drop|toss|throw|equip|hold|wear|wield|eat|collect|grab|fetch|get|find|mine|dig|need|want)\b/
      return stateWords.test(text) && !actionWords.test(text) ? {} : null
    }
  },
  {
    intent: 'help',
    match: text =>
      /\b(help|commands|command list|how do you work)\b/.test(text) || /\bwhat (do|can)\b/.test(text)
        ? {}
        : null
  },
  {
    intent: 'stop',
    match: text =>
      /\b(stop|stay|halt|wait|freeze|hold on|hold up|stand still|stay put|stay here|chill|relax|cancel|nevermind|never mind|quit|abort)\b/.test(text) ||
      /\bdon'?t move\b/.test(text)
        ? {}
        : null
  },
  {
    intent: 'eat',
    match: text => (/\b(eat|feed yourself|snack|have some food)\b/.test(text) ? {} : null)
  },
  {
    intent: 'goto',
    match: text => {
      const coords = text.match(COORDS)
      if (!coords) return null
      if (!MOVE_VERB.test(text) && !/\b(coords|coordinates|position|spot|location)\b/.test(text)) return null
      return { x: Number(coords[1]), y: Number(coords[2]), z: Number(coords[3]) }
    }
  },
  {
    intent: 'come',
    match: text =>
      /\b(come|over here|get over here|to me|my position|my location|find me|back to me)\b/.test(text) ? {} : null
  },
  {
    intent: 'follow',
    match: text => {
      if (!/\b(follow|tail|stick with|stay with|come with|accompany|escort)\b/.test(text)) return null
      const named = text.match(/\bfollow(?:ing)?\s+(?!me\b|us\b)([a-z0-9_]{3,16})\b/)
      return { who: named ? named[1] : null }
    }
  },
  {
    intent: 'defend',
    match: text =>
      /\b(defend|protect|guard|cover me|watch my back|keep me safe|bodyguard)\b/.test(text) ? {} : null
  },
  {
    intent: 'attack',
    match: text => {
      if (!/\b(attack|kill|fight|slay|hit|engage|destroy)(?:s|ed|ing)?\b/.test(text)) return null
      const rest = text.replace(/^.*?\b(attack|kill|fight|slay|hit|engage|destroy)(?:s|ed|ing)?\b/, '')
      const target = cleanTarget(rest)
      return { target: target && !/^(mobs?|them|it|enemies|hostiles?|anything)$/.test(target) ? target : null }
    }
  },
  {
    intent: 'chop',
    match: text => {
      if (!WOOD_WORDS.test(text)) return null
      if (!/\b(chop|cut|fell|punch|get|gather|collect|mine|harvest|need|bring|farm)(?:s|ed|ing|ping|ning)?\b/.test(text)) return null
      return { count: parseCount(text, null) }
    }
  },
  {
    intent: 'mine',
    match: text => {
      const verb = text.match(/\b(mine|dig|break|harvest|quarry|excavate)(?:s|ed|ing|ging|ning)?\b/)
      if (!verb) return null
      const rest = text.slice(text.indexOf(verb[0]) + verb[0].length)
      const target = cleanTarget(rest)
      return { target: target || null, count: parseCount(rest, null) }
    }
  },
  {
    intent: 'collect',
    match: text => {
      const verb = text.match(/\b(collect|pick up|pickup|grab|fetch|gather|loot|get|find)(?:s|ed|ing|ting|ding)?\b/)
      if (!verb) return null
      const rest = text.slice(text.indexOf(verb[0]) + verb[0].length)
      const target = cleanTarget(rest)
      return { target: target || null, count: parseCount(rest, null) }
    }
  },
  {
    intent: 'equip',
    match: text => {
      const verb = text.match(/\b(equip|hold|wield|wear|put on|arm yourself with|switch to)\b/)
      if (!verb) return null
      const rest = text.slice(text.indexOf(verb[0]) + verb[0].length)
      const target = cleanTarget(rest)
      return { item: target || null }
    }
  },
  {
    intent: 'give',
    match: text => {
      if (!/\b(give|hand|bring|deliver|share)\b/.test(text) && !/\b(toss|throw|drop)\s+me\b/.test(text)) return null
      const verb = text.match(/\b(give|hand|bring|deliver|share|toss|throw|drop)\b/)
      const rest = text.slice(text.indexOf(verb[0]) + verb[0].length)
      const target = cleanTarget(rest)
      return { item: target || null, count: parseCount(rest, null) }
    }
  },
  {
    intent: 'drop',
    match: text => {
      const verb = text.match(/\b(drop|toss|throw|discard|dump)\b/)
      if (!verb) return null
      const rest = text.slice(text.indexOf(verb[0]) + verb[0].length)
      const target = cleanTarget(rest)
      return { item: target || null, count: parseCount(rest, null) }
    }
  },
  {
    intent: 'build',
    match: text => {
      const verb = text.match(/\b(build|construct|make|erect|put up)(?:s|ed|ing)?\b/)
      if (!verb) return null
      const rest = text.slice(text.indexOf(verb[0]) + verb[0].length)
      const structure = cleanTarget(rest.replace(/\b(small|little|quick|simple|basic|tiny|emergency)\b/g, ' '))
      return { structure: structure || null, size: parseCount(rest, null) }
    }
  }
]

/**
 * @param {string} message  raw chat line
 * @param {{prefixes: string[], botUsername?: string}} options
 * @returns {null | {intent: string, args: object, text: string, raw: string}}
 *   null means "not addressed to the bot"; intent "unknown" means addressed
 *   but not understood.
 */
function parse (message, options = {}) {
  const body = stripPrefix(message, options)
  if (body === null) return null
  const text = normalize(body)
  if (!text) return { intent: 'help', args: {}, text, raw: message }
  for (const rule of RULES) {
    const args = rule.match(text)
    if (args) return { intent: rule.intent, args, text, raw: message }
  }
  return { intent: 'unknown', args: {}, text, raw: message }
}

module.exports = { parse, stripPrefix, normalize, cleanTarget, parseCount, RULES }
