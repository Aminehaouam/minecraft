# Minecraft Companion Bot

A [Mineflayer](https://github.com/PrismarineJS/mineflayer) bot that joins your Minecraft
Java Edition world as a second player, follows you around, and does what you tell it in
chat — mining, chopping, fighting, fetching, building.

Command understanding is **entirely local**: messages are matched against keyword and
regex rules in `src/commands/parser.js`. There is no LLM call, no API key, and nothing
to pay for.

```
<You>          bot can you mine some iron
<CompanionBot> Mining 4x iron ore...
<CompanionBot> Done — mined 4 iron ore.
```

---

## Quick start (one click)

1. **Download this project** — green **Code** button → **Download ZIP** → unzip it
   (or `git clone` it if you prefer).
2. **Open your world to LAN** — load your world in Minecraft, press `Esc` →
   **Open to LAN** → **Start LAN World**.
3. **Double-click the launcher** in the unzipped folder:
   - **Windows** → `start.bat`
   - **macOS** → `start.command`
   - **Linux** → `start.sh` (or `./start.sh` in a terminal)

That's it. The launcher installs what it needs on first run, writes its own config, finds
your LAN world, and the bot walks up to you a few seconds later.

```
  ┌────────────────────────────────────────────┐
  │        Minecraft Companion Bot             │
  └────────────────────────────────────────────┘
  First run — installing the libraries the bot needs.
  (about a minute, only ever happens once)

  Libraries installed.
  Created config.json with default settings.
  Nothing to fill in: the bot finds your LAN world by itself.

[18:49:13] INFO  looking for a Minecraft world opened to LAN...
[18:49:14] INFO  found "Amine's World" at 192.168.1.42:54321
[18:49:14] INFO  spawned at (311, 21, 47) (version 1.20.4)
```

**You never have to look up the LAN port.** Minecraft broadcasts it on your network every
couple of seconds, and the bot listens for that. Re-open the world tomorrow, get a
different port, double-click the same file — it still works. Close the window (or
`Ctrl+C`) to stop the bot.

The only thing not bundled is **Node.js**, the runtime the bot needs. If it is missing,
the launcher offers to install it (winget on Windows, Homebrew on macOS) or opens
[nodejs.org](https://nodejs.org) for you — install it, then double-click the launcher
again.

### First thing to try in game

```
bot follow me
bot help
```

And hand it a tool, since it is slow bare-handed (needs cheats enabled on the LAN world):

```
/give CompanionBot minecraft:iron_pickaxe
/give CompanionBot minecraft:iron_sword
/give CompanionBot minecraft:cooked_beef 16
bot equip iron pickaxe
```

## Running it from a terminal instead

```bash
npm install
npm start
```

`npm start` behaves exactly like the launcher, minus the setup checks.

## Configuration

`config.json` is created for you on first run and is git-ignored, so your server details
stay private. Everything in it is optional — anything you leave out falls back to
`config.example.json`.

```jsonc
{
  "host": "auto",              // "auto" = find the LAN world; or "localhost" / an IP
  "port": "auto",              // "auto" = read the port from Minecraft's LAN broadcast
  "username": "CompanionBot",  // the bot's in-game name
  "auth": "offline",           // "offline" for LAN/cracked servers, "microsoft" for online-mode
  "version": null,             // null = auto-detect, or pin it: "1.20.4"
  "commandPrefixes": ["bot,", "bot", "!bot", "@bot"],
  "owners": []                 // [] = anyone may command the bot; ["YourName"] = only you
}
```

Set `host` and `port` explicitly when you are connecting to a real server rather than a
LAN world (auto-detect waits ~6 seconds, then falls back to `localhost:25565`).

Environment variables win over the file, which is handy for a one-off:

```bash
MC_HOST=192.168.1.42 MC_PORT=25565 MC_USERNAME=Buddy npm start
```

Supported: `MC_HOST`, `MC_PORT`, `MC_USERNAME`, `MC_AUTH`, `MC_VERSION`, `MC_PASSWORD`,
`BOT_OWNERS`, `BOT_LOG_LEVEL`.

## Connecting to a server (instead of a LAN world)

1. Put the server address in `host` and its port (default `25565`) in `port`.
2. If `white-list=true`, whitelist the bot: `/whitelist add CompanionBot`, then
   `/whitelist reload`.
3. If `online-mode=true`, the bot needs a real Microsoft account: set
   `"auth": "microsoft"` and put that account's email in `"username"` — a browser sign-in
   code appears in the console on first launch. On a private server it is simpler to set
   `online-mode=false` and keep `"auth": "offline"`.

## Commands

Type in normal in-game chat, starting with `bot` (or `!bot`, `@bot`, or the bot's name).
Phrasing is flexible — `bot mine stone`, `bot can you mine some stone please` and
`bot dig 10 stone` all work.

| What you say | What it does |
| --- | --- |
| `bot follow me` | Follows you around (the default behaviour on spawn) |
| `bot stop` / `bot stay put` | Cancels the current job and holds position |
| `bot come here` | Walks to you once, then goes back to following |
| `bot go to 120 64 -35` | Paths to those coordinates |
| `bot mine stone` / `bot mine 10 iron ore` | Finds, walks to, and digs that block, picking up the drops |
| `bot chop wood` | Fells whole trees until it has enough logs |
| `bot collect diamonds` | Picks up matching drops nearby; mines them if none are lying around |
| `bot attack` / `bot kill that zombie` | Fights nearby hostiles (or one you name) |
| `bot defend me` | Guard mode: stays close and intercepts anything hostile |
| `bot equip diamond sword` | Equips it — armour goes to the right slot automatically |
| `bot drop cobblestone` / `bot give me 5 bread` | Drops items, or walks over and hands them to you |
| `bot eat` | Eats the best food it is carrying |
| `bot build shelter` / `bot build a tower 8` / `bot build a wall` | Builds a small structure from cheap blocks it is carrying |
| `bot status` | Reports health, hunger, position, current job, and inventory |
| `bot help` | Lists the commands in chat |

Names are matched loosely too: `wood` covers every log type, `stone` covers cobblestone
and deepslate, `diamonds` finds diamond ore, `pickaxe` finds whichever pickaxe it owns.

To check how a phrase will be understood, without starting Minecraft:

```bash
npm run parse -- "bot can you grab some logs"
# bot can you grab some logs  ->  chop {"count":null}
```

## Staying alive

Configured under `survival` in `config.json`:

- **Auto-eat** when hunger drops below `eatWhenFoodBelow` (default 16) and it has food.
  It prefers cooked meat and bread, and only touches rotten flesh as a last resort.
- **Fight or flight**: it fights back when hurt, but runs away and says so once health
  drops below `fleeWhenHealthBelow` (default 7).
- **Hazards**: lava, fire, magma, cactus, berry bushes and powder snow are excluded from
  pathfinding, it refuses to dig a block with lava behind it, and it walks itself out of
  anything dangerous it ends up standing in.
- It will not break your chests, furnaces or beds while pathing, and it never builds with
  diamond/gold/netherite blocks.

## Project layout

```
start.bat / start.command / start.sh   one-click launchers
scripts/launch.js     first-run setup: deps, config, then start
config.example.json   default settings (copied to config.json on first run)
src/
  index.js            connect, LAN auto-detect, reconnect, wiring
  config.js           config file + environment loading
  logger.js           timestamped console logging
  tasks.js            one job at a time, with cancellation
  commands/
    parser.js         local intent matching (no LLM)
    handlers.js       one handler per intent, replies in chat
    index.js          chat/whisper listeners and permission check
  skills/
    movement.js       pathfinder setup, follow, come, goto, retreat
    mining.js         mining, tree felling, picking up drops
    combat.js         target selection, melee loop, guard mode
    building.js       block placement, shelter/tower/wall
    inventory.js      status, equip, drop, give, eat
    survival.js       auto-eat, damage reactions, hazard escape
  util/
    lan-discovery.js  reads Minecraft's "Open to LAN" broadcast
    names.js          "wood" -> oak_log, birch_log, ...
    chat.js           rate-limited chat queue
    async.js          sleep/cancellation helpers
scripts/try-parse.js  offline command-phrasing checker
test/                 unit tests + connection and LAN-discovery tests
```

## Tests

```bash
npm test
```

Covers command parsing, name resolution, config loading, LAN broadcast handling, and the
inventory/building/combat helpers, plus a connection test that points the bot at a local
TCP listener to confirm it dials the configured address and sends its username. Behaviour
that needs a real world (following a player, mining, combat) is best checked in-game.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `no LAN world is being advertised` | The world is not open to LAN yet — do that first, then restart the bot. If it still misses it, your firewall is blocking UDP port 4445; set `host`/`port` in `config.json` manually. |
| macOS: "start.command can't be opened" | Right-click the file → **Open** → **Open** (once), or run `chmod +x start.command start.sh` in the folder. |
| macOS/Linux: double-click does nothing | The executable bit was lost when unzipping: `chmod +x start.command start.sh`. |
| Kicked with a whitelist message | `/whitelist add CompanionBot` on the server, then `/whitelist reload`. |
| Kicked for a version mismatch | Set `"version"` in `config.json` to your exact Minecraft version, e.g. `"1.20.4"`. |
| `Invalid session` / auth errors | Online-mode server: use `"auth": "microsoft"` with a real account, or set `online-mode=false` for LAN. |
| The bot ignores you | Check the prefix (`bot ...`) and, if `owners` is set, that your name is in it. |
| "I lost sight of you" | You are outside the server's entity view distance — walk closer. |
| The bot has no tools | It works fine bare-handed but is slow; `/give CompanionBot minecraft:iron_pickaxe` helps a lot. |

## Licence

MIT.
