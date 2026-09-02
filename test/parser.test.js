'use strict'

const test = require('node:test')
const assert = require('node:assert')
const { parse, stripPrefix, cleanTarget, parseCount } = require('../src/commands/parser')

const options = { prefixes: ['bot,', 'bot', '!bot', '@bot'], botUsername: 'CompanionBot' }
const intentOf = message => {
  const parsed = parse(message, options)
  return parsed ? parsed.intent : null
}

test('only reacts to messages addressed to the bot', () => {
  assert.strictEqual(parse('hello everyone', options), null)
  assert.strictEqual(parse('bottle of water', options), null)
  assert.strictEqual(parse('robot follow me', options), null)
  assert.strictEqual(intentOf('bot follow me'), 'follow')
  assert.strictEqual(intentOf('!bot follow me'), 'follow')
  assert.strictEqual(intentOf('@bot follow me'), 'follow')
  assert.strictEqual(intentOf('CompanionBot follow me'), 'follow')
  assert.strictEqual(intentOf('BOT, follow me'), 'follow')
})

test('stripPrefix returns the remaining command text', () => {
  assert.strictEqual(stripPrefix('bot, mine stone', options), 'mine stone')
  assert.strictEqual(stripPrefix('bot mine stone', options), 'mine stone')
  assert.strictEqual(stripPrefix('not a command', options), null)
})

test('recognises the documented commands', () => {
  const cases = {
    'bot follow me': 'follow',
    'bot stop': 'stop',
    'bot stay': 'stop',
    'bot come here': 'come',
    'bot mine stone': 'mine',
    'bot chop wood': 'chop',
    'bot collect diamonds': 'collect',
    'bot go to 100 64 -200': 'goto',
    'bot attack': 'attack',
    'bot defend me': 'defend',
    'bot equip iron sword': 'equip',
    'bot drop cobblestone': 'drop',
    'bot give me bread': 'give',
    'bot status': 'status',
    'bot build a small shelter': 'build',
    'bot eat': 'eat',
    'bot help': 'help'
  }
  for (const [message, intent] of Object.entries(cases)) {
    assert.strictEqual(intentOf(message), intent, `"${message}" should parse as ${intent}`)
  }
})

test('tolerates loose phrasing', () => {
  assert.strictEqual(intentOf('bot can you follow me'), 'follow')
  assert.strictEqual(intentOf('bot could you please come over here'), 'come')
  assert.strictEqual(intentOf('bot i need you to mine some stone'), 'mine')
  assert.strictEqual(intentOf('bot would you mind chopping some trees'), 'chop')
  assert.strictEqual(intentOf('bot hold on'), 'stop')
  assert.strictEqual(intentOf('bot how are you doing'), 'status')
  assert.strictEqual(intentOf('bot what can you do'), 'help')
  assert.strictEqual(intentOf('bot protect me please'), 'defend')
})

test('extracts targets and counts', () => {
  assert.deepStrictEqual(parse('bot mine 10 stone', options).args, { target: 'stone', count: 10 })
  assert.deepStrictEqual(parse('bot dig some iron ore', options).args, { target: 'iron ore', count: null })
  assert.deepStrictEqual(parse('bot mine the nearest diamond ore', options).args, { target: 'diamond ore', count: null })
  assert.deepStrictEqual(parse('bot give me 5 bread', options).args, { item: 'bread', count: 5 })
  assert.deepStrictEqual(parse('bot drop three torches', options).args, { item: 'torches', count: 3 })
  assert.strictEqual(parse('bot kill that zombie', options).args.target, 'zombie')
  assert.strictEqual(parse('bot follow Steve', options).args.who, 'Steve'.toLowerCase())
  assert.strictEqual(parse('bot build a tower 8', options).args.structure, 'tower')
})

test('parses coordinates, including negatives and commas', () => {
  assert.deepStrictEqual(parse('bot go to 100 64 -200', options).args, { x: 100, y: 64, z: -200 })
  assert.deepStrictEqual(parse('bot walk to -12, 70, 33', options).args, { x: -12, y: 70, z: 33 })
  // Bare numbers without a movement verb are not a destination.
  assert.notStrictEqual(intentOf('bot mine 3 stone'), 'goto')
})

test('food requests are not mistaken for status checks', () => {
  assert.strictEqual(intentOf('bot give me food'), 'give')
  assert.strictEqual(intentOf('bot what do you have'), 'status')
  assert.strictEqual(intentOf('bot inventory'), 'status')
})

test('unrecognised orders fall back to unknown', () => {
  assert.strictEqual(intentOf('bot do a backflip'), 'unknown')
  assert.strictEqual(intentOf('bot dance'), 'unknown')
})

test('helpers behave', () => {
  assert.strictEqual(cleanTarget('some 10 blocks of cobblestone'), 'cobblestone')
  assert.strictEqual(cleanTarget('the nearest iron ore'), 'iron ore')
  assert.strictEqual(parseCount('mine 12 stone', 1), 12)
  assert.strictEqual(parseCount('mine a couple of logs', 1), 2)
  assert.strictEqual(parseCount('mine stone', 4), 4)
})
