'use strict'

const fs = require('fs')
const path = require('path')

const ROOT = path.join(__dirname, '..')
const USER_CONFIG = path.join(ROOT, 'config.json')
const EXAMPLE_CONFIG = path.join(ROOT, 'config.example.json')

function isPlainObject (value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

// Deep merge that lets a partial config.json override only the keys it names.
function merge (base, override) {
  const out = { ...base }
  for (const [key, value] of Object.entries(override || {})) {
    if (isPlainObject(value) && isPlainObject(base[key])) out[key] = merge(base[key], value)
    else if (value !== undefined) out[key] = value
  }
  return out
}

function readJson (file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'))
  } catch (err) {
    if (err.code === 'ENOENT') return null
    throw new Error(`Could not parse ${path.basename(file)}: ${err.message}`)
  }
}

// Environment variables win over the files, so you can do
// MC_HOST=192.168.1.20 npm start without editing config.json.
function applyEnv (config, env) {
  const out = { ...config }
  if (env.MC_HOST) out.host = env.MC_HOST
  if (env.MC_PORT) out.port = Number(env.MC_PORT)
  if (env.MC_USERNAME) out.username = env.MC_USERNAME
  if (env.MC_AUTH) out.auth = env.MC_AUTH
  if (env.MC_VERSION) out.version = env.MC_VERSION
  if (env.MC_PASSWORD) out.password = env.MC_PASSWORD
  if (env.BOT_OWNERS) out.owners = env.BOT_OWNERS.split(',').map(s => s.trim()).filter(Boolean)
  if (env.BOT_LOG_LEVEL) out.logLevel = env.BOT_LOG_LEVEL
  return out
}

function validate (config) {
  if (!config.host) throw new Error('config: "host" is required')
  if (!Number.isInteger(config.port)) throw new Error('config: "port" must be a whole number')
  if (!config.username) throw new Error('config: "username" is required')
  if (!Array.isArray(config.commandPrefixes) || config.commandPrefixes.length === 0) {
    throw new Error('config: "commandPrefixes" must be a non-empty array')
  }
  return config
}

function load (env = process.env) {
  const defaults = readJson(EXAMPLE_CONFIG)
  if (!defaults) throw new Error('config.example.json is missing — it holds the default values')
  const user = readJson(USER_CONFIG)
  return validate(applyEnv(merge(defaults, user || {}), env))
}

module.exports = { load, merge, hasUserConfig: () => fs.existsSync(USER_CONFIG) }
