#!/usr/bin/env node
'use strict'

/**
 * The one-click entry point used by start.command / start.bat / start.sh.
 *
 * It uses Node built-ins only, so it can run before `npm install` has ever
 * happened: it checks the Node version, installs dependencies on first run,
 * creates config.json from the example, then starts the bot.
 */

const fs = require('node:fs')
const path = require('node:path')
const { spawnSync } = require('node:child_process')

const ROOT = path.join(__dirname, '..')
const MIN_NODE_MAJOR = 18

function line (text = '') {
  console.log(text)
}

function banner () {
  line()
  line('  ┌────────────────────────────────────────────┐')
  line('  │        Minecraft Companion Bot             │')
  line('  └────────────────────────────────────────────┘')
  line()
}

function checkNode () {
  const major = Number(process.versions.node.split('.')[0])
  if (major >= MIN_NODE_MAJOR) return
  line(`  Node.js ${process.versions.node} is too old — this bot needs ${MIN_NODE_MAJOR} or newer.`)
  line('  Install the LTS version from https://nodejs.org and run this again.')
  process.exit(1)
}

function npmCommand () {
  return process.platform === 'win32' ? 'npm.cmd' : 'npm'
}

function dependenciesInstalled () {
  return ['mineflayer', 'mineflayer-pathfinder', 'minecraft-data', 'vec3'].every(name =>
    fs.existsSync(path.join(ROOT, 'node_modules', name))
  )
}

function installDependencies () {
  if (dependenciesInstalled()) return
  line('  First run — installing the libraries the bot needs.')
  line('  (about a minute, only ever happens once)')
  line()
  const result = spawnSync(npmCommand(), ['install', '--no-audit', '--no-fund'], {
    cwd: ROOT,
    stdio: 'inherit',
    shell: process.platform === 'win32'
  })
  if (result.error || result.status !== 0) {
    line()
    line('  Installing the libraries failed.')
    line('  Check your internet connection, then try again.')
    if (result.error) line(`  (${result.error.message})`)
    process.exit(1)
  }
  line()
  line('  Libraries installed.')
  line()
}

function ensureConfig () {
  const userConfig = path.join(ROOT, 'config.json')
  if (fs.existsSync(userConfig)) return
  fs.copyFileSync(path.join(ROOT, 'config.example.json'), userConfig)
  line('  Created config.json with default settings.')
  line('  Nothing to fill in: the bot finds your LAN world by itself.')
  line()
}

function instructions () {
  line('  Before the bot can join:')
  line('    1. Load your world in Minecraft (Java Edition)')
  line('    2. Press Esc -> Open to LAN -> Start LAN World')
  line()
  line('  Then talk to it in chat:  bot follow me / bot mine stone / bot help')
  line('  Close this window (or press Ctrl+C) to stop the bot.')
  line()
  line('  ────────────────────────────────────────────────')
  line()
}

banner()
checkNode()
installDependencies()
ensureConfig()
instructions()

require(path.join(ROOT, 'src', 'index.js'))
  .main()
  .catch(err => {
    line()
    line(`  The bot could not start: ${err.message}`)
    process.exitCode = 1
  })
