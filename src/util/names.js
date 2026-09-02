'use strict'

/**
 * Turns loose player wording ("wood", "diamonds", "Oak Log") into concrete
 * Minecraft block/item names for the connected server's version. Everything
 * here is local pattern matching — no network calls, no API keys.
 */

// "*" matches any run of characters, so "*_log" covers oak_log, birch_log, ...
const BLOCK_ALIASES = {
  wood: ['*_log', '*_wood'],
  log: ['*_log'],
  tree: ['*_log'],
  timber: ['*_log'],
  lumber: ['*_log'],
  plank: ['*_planks'],
  leaf: ['*_leaves'],
  stone: ['stone', 'cobblestone', 'deepslate', 'cobbled_deepslate', 'granite', 'diorite', 'andesite', 'tuff'],
  cobble: ['cobblestone'],
  rock: ['stone', 'cobblestone'],
  ore: ['*_ore'],
  coal: ['coal_ore', 'deepslate_coal_ore'],
  iron: ['iron_ore', 'deepslate_iron_ore'],
  gold: ['gold_ore', 'deepslate_gold_ore', 'nether_gold_ore'],
  diamond: ['diamond_ore', 'deepslate_diamond_ore'],
  emerald: ['emerald_ore', 'deepslate_emerald_ore'],
  copper: ['copper_ore', 'deepslate_copper_ore'],
  redstone: ['redstone_ore', 'deepslate_redstone_ore'],
  lapis: ['lapis_ore', 'deepslate_lapis_ore'],
  quartz: ['nether_quartz_ore'],
  dirt: ['dirt', 'coarse_dirt', 'rooted_dirt'],
  grass: ['grass_block'],
  glass: ['glass'],
  wool: ['*_wool'],
  crop: ['wheat', 'carrots', 'potatoes', 'beetroots'],
  flower: ['*_tulip', 'poppy', 'dandelion', 'cornflower', 'oxeye_daisy', 'allium']
}

const ITEM_ALIASES = {
  wood: ['*_log'],
  log: ['*_log'],
  plank: ['*_planks'],
  sword: ['*_sword'],
  pickaxe: ['*_pickaxe'],
  pick: ['*_pickaxe'],
  axe: ['*_axe'],
  shovel: ['*_shovel'],
  hoe: ['*_hoe'],
  helmet: ['*_helmet'],
  chestplate: ['*_chestplate'],
  leggings: ['*_leggings'],
  boots: ['*_boots'],
  armor: ['*_helmet', '*_chestplate', '*_leggings', '*_boots'],
  torch: ['torch'],
  cobble: ['cobblestone'],
  ore: ['*_ore'],
  meat: ['cooked_beef', 'cooked_porkchop', 'cooked_chicken', 'cooked_mutton', 'cooked_rabbit', 'beef', 'porkchop', 'chicken', 'mutton'],
  steak: ['cooked_beef']
}

function normalize (query) {
  return String(query || '')
    .toLowerCase()
    .trim()
    .replace(/^minecraft:/, '')
    .replace(/[^a-z0-9_\s]/g, '')
    .replace(/\s+/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_|_$/g, '')
}

// "logs" -> "log", "diamonds" -> "diamond" (but leave "leaves"/"glass" alone).
function singular (name) {
  if (name.length > 3 && name.endsWith('s') && !name.endsWith('ss') && !name.endsWith('es')) {
    return name.slice(0, -1)
  }
  return name
}

function expandPattern (pattern, universe) {
  if (!pattern.includes('*')) return universe.includes(pattern) ? [pattern] : []
  const regex = new RegExp('^' + pattern.split('*').map(escapeRegex).join('.*') + '$')
  return universe.filter(name => regex.test(name))
}

function escapeRegex (text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function aliasLookup (aliases, key, universe) {
  const patterns = aliases[key]
  if (!patterns) return []
  const matches = patterns.flatMap(pattern => expandPattern(pattern, universe))
  // Prefer natural blocks over their stripped/processed variants.
  const natural = matches.filter(name => !name.startsWith('stripped_'))
  return natural.length > 0 ? natural : matches
}

function fuzzy (universe, key) {
  const exact = universe.filter(name => name === key)
  if (exact.length) return exact
  const scored = universe
    .map(name => ({ name, score: score(name, key) }))
    .filter(entry => entry.score > 0)
    .sort((a, b) => b.score - a.score || a.name.length - b.name.length)
  return scored.map(entry => entry.name)
}

function score (name, key) {
  if (name === key) return 100
  if (name.endsWith('_' + key)) return 80
  if (name.startsWith(key + '_')) return 60
  if (name.includes('_' + key + '_')) return 40
  if (name.includes(key)) return 20
  return 0
}

function resolveNames (universe, query, aliases) {
  const raw = normalize(query)
  if (!raw) return []
  const keys = raw === singular(raw) ? [raw] : [raw, singular(raw)]
  if (raw !== singular(raw)) keys.push(singular(raw))
  for (const key of [...new Set([raw, singular(raw)])]) {
    const aliased = aliasLookup(aliases, key, universe)
    if (aliased.length) return aliased
    const direct = universe.includes(key) ? [key] : []
    if (direct.length) return direct
  }
  for (const key of [...new Set([raw, singular(raw)])]) {
    const matches = fuzzy(universe, key)
    if (matches.length) return matches
  }
  return []
}

function blockNames (registry, query) {
  return resolveNames(Object.keys(registry.blocksByName), query, BLOCK_ALIASES)
}

function itemNames (registry, query) {
  return resolveNames(Object.keys(registry.itemsByName), query, ITEM_ALIASES)
}

function blockIds (registry, query) {
  return blockNames(registry, query).map(name => registry.blocksByName[name].id)
}

function itemIds (registry, query) {
  return itemNames(registry, query).map(name => registry.itemsByName[name].id)
}

/** "oak_log" -> "oak log", for chat messages. */
function pretty (name) {
  return String(name || '').replace(/_/g, ' ')
}

module.exports = {
  normalize,
  singular,
  blockNames,
  blockIds,
  itemNames,
  itemIds,
  pretty,
  BLOCK_ALIASES,
  ITEM_ALIASES
}
