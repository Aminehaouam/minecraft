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

## 1. Requirements

- **Node.js 18 or newer** (22 recommended) — https://nodejs.org (the LTS installer is fine).
  Check with `node --version`.
- **Minecraft: Java Edition** (Bedrock/Pocket/console editions will not work).
- A world the bot can reach: an open-to-LAN singleplayer world, or a server you run.

## 2. Install

```bash
git clone <this repo>
cd minecraft
npm install
```

## 3. Configure

Copy the example config and edit it:

```bash
cp config.example.json config.json
```

```jsonc
{
  "host": "localhost",   // server address; for LAN use the IP shown in chat
  "port": 25565,         // the port your world/server is listening on
  "username": "CompanionBot", // the bot's in-game name
  "auth": "offline",     // "offline" for LAN/cracked servers, "microsoft" for online-mode
  "version": null,       // null = auto-detect, or pin it: "1.20.4"
  "commandPrefixes": ["bot,", "bot", "!bot", "@bot"],
  "owners": []           // [] = anyone may command the bot; ["YourName"] = only you
}
```

`config.json` is git-ignored, so your server details stay private. Anything you leave out
falls back to `config.example.json`. Environment variables win over both, which is handy
for a quick test:

```bash
MC_HOST=192.168.1.42 MC_PORT=54321 MC_USERNAME=Buddy npm start
```

Supported variables: `MC_HOST`, `MC_PORT`, `MC_USERNAME`, `MC_AUTH`, `MC_VERSION`,
`MC_PASSWORD`, `BOT_OWNERS`, `BOT_LOG_LEVEL`.

## 4. Let the bot into your world

**Singleplayer, open to LAN (easiest):**

1. Load your world, press `Esc` → **Open to LAN**.
2. Set **Allow Cheats: ON** (optional, but lets you `/give` the bot tools) and
   **Game Mode: Survival**, then **Start LAN World**.
3. Minecraft prints `Local game hosted on port 54321` in chat — put that number in
   `config.json` as `port`, and keep `host` as `localhost` if the bot runs on the same PC.
4. LAN worlds are offline-mode, so keep `"auth": "offline"`.

> The port changes every time you re-open the world to LAN, so update `port` each session
> (or pass `MC_PORT=...` on the command line).

**Your own server (`server.jar`, Paper, Spigot):**

1. In `server.properties`, note the `server-port` (default `25565`).
2. If `online-mode=true`, the bot needs a real Microsoft account: set `"auth": "microsoft"`
   and `"username"` to that account's email — a browser sign-in code appears in the terminal
   on first launch. For a private LAN server it is simpler to set `online-mode=false` and
   keep `"auth": "offline"`.
3. If `white-list=true`, whitelist the bot: `/whitelist add CompanionBot` from the console
   or in-game, then `/whitelist reload`.

## 5. Run it

```bash
npm start
```

You should see:

```
[18:24:30] INFO  connecting to localhost:54321 as CompanionBot...
[18:24:30] INFO  logged in as CompanionBot on localhost:54321
[18:24:30] INFO  spawned at (311, 21, 47) (version 1.20.4)
```

The bot announces itself in chat and starts following you. Stop it with `Ctrl+C`.

If it drops out (world closed, server restart) it reconnects every 10 seconds —
turn that off with `"autoReconnect": false`.

## 6. Talking to the bot

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

To check how a phrase will be understood without starting Minecraft:

```bash
npm run parse -- "bot can you grab some logs"
# bot can you grab some logs  ->  chop {"count":null}
```

## 7. Staying alive

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

## 8. Project layout

```
config.example.json   default settings (copy to config.json)
src/
  index.js            connect, spawn, reconnect, wire everything together
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
    names.js          "wood" -> oak_log, birch_log, ...
    chat.js           rate-limited chat queue
    async.js          sleep/cancellation helpers
scripts/try-parse.js  offline command-phrasing checker
test/                 unit tests + a connection test
```

## 9. Tests

```bash
npm test
```

Covers command parsing, name resolution, config loading, inventory/building/combat
helpers, and a connection test that points the bot at a local TCP listener to confirm it
dials the configured address and sends its username. Behaviour that needs a real world
(following a player, mining, combat) is best checked in-game.

## 10. Troubleshooting

| Symptom | Fix |
| --- | --- |
| `nothing is listening on localhost:25565` | The world is not open to LAN, or the port changed — re-check the port from the LAN message. |
| Kicked with a whitelist message | `/whitelist add CompanionBot` on the server, then `/whitelist reload`. |
| Kicked for a version mismatch | Set `"version"` in `config.json` to your exact Minecraft version, e.g. `"1.20.4"`. |
| `Invalid session` / auth errors | Online-mode server: use `"auth": "microsoft"` with a real account, or set `online-mode=false` for LAN. |
| The bot ignores you | Check the prefix (`bot ...`) and, if `owners` is set, that your name is in it. |
| "I lost sight of you" | You are outside the server's entity view distance — walk closer. |
| The bot has no tools | It works fine bare-handed but is slow; `/give CompanionBot minecraft:iron_pickaxe` helps a lot. |

## Licence

MIT.
