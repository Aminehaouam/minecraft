#!/usr/bin/env node
'use strict'

/**
 * Offline helper: see how a chat line would be understood, without starting
 * Minecraft.  Usage:  npm run parse -- "bot can you mine some iron"
 */

const configLoader = require('../src/config')
const { parse } = require('../src/commands/parser')

const config = configLoader.load()
const options = { prefixes: config.commandPrefixes, botUsername: config.username }

const examples = [
  'bot follow me',
  'bot can you come over here please',
  'bot mine 10 iron ore',
  'bot chop some wood',
  'bot go to 120 64 -35',
  'bot defend me',
  'bot give me 3 bread',
  'bot build a small shelter',
  'bot status'
]

const messages = process.argv.slice(2)
const lines = messages.length > 0 ? messages : examples
if (messages.length === 0) console.log('No message given — showing examples.\n')

for (const line of lines) {
  const parsed = parse(line, options)
  if (!parsed) {
    console.log(`${line.padEnd(40)} ->  (ignored: not addressed to the bot)`)
    continue
  }
  console.log(`${line.padEnd(40)} ->  ${parsed.intent} ${JSON.stringify(parsed.args)}`)
}
