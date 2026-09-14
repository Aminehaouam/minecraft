--!strict
--[[
	WorldService — مرجع الحقيقة للعالم على الخادم.

	مسؤولياته:
	* امتلاك نسخة World الموثوقة وحفظ/تحميل تعديلات اللاعبين بالمناطق.
	* التحقق من كل طلب تعدين أو بناء (مدى، أداة، سرعة، أحقية العنصر).
	* بثّ تغيّرات البلاطات للاعبين القريبين فقط.
	* محاكاة السوائل وسقوط البلاطات غير المسنودة.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Blocks = require(Shared.Blocks)
local Chunk = require(Shared.Chunk)
local Config = require(Shared.Config)
local Inventory = require(Shared.Inventory)
local Items = require(Shared.Items)
local Mining = require(Shared.Mining)
local Net = require(Shared.Net)
local Upgrades = require(Shared.Upgrades)
local Util = require(Shared.Util)
local World = require(Shared.World)
local WorldGen = require(Shared.WorldGen)

local Services = require(script.Parent.Services)
local SaveService = require(script.Parent.SaveService)

local B = Blocks.ID
local SIZE = Config.CHUNK

local WorldService = {}

local world: World.World
local seed: number = 0
local spawnX, spawnY = 0, 0

-- حالة المناطق: nil | "loading" | "ready"
local regionState: { [string]: string } = {}
local dirtyRegions: { [string]: boolean } = {}

-- اشتراكات القطع لكل لاعب (لتقليل البث)
local subs: { [Player]: { [string]: boolean } } = {}

-- عدّاد مضاد للغش
type EditGuard = { tokens: number, last: number, lastBreak: number }
local guards: { [Player]: EditGuard } = {}

-- طابور محاكاة السوائل
local liquidQueue: { [string]: boolean } = {}
local liquidOrder: { { number } } = {}

function WorldService.getWorld(): World.World
	return world
end

function WorldService.getSeed(): number
	return seed
end

function WorldService.getSpawn(): (number, number)
	return spawnX, spawnY
end

-- ===== المناطق =====

local function regionOf(cx: number, cy: number): (number, number)
	return cx // Config.REGION, cy // Config.REGION
end

local function regionKey(rx: number, ry: number): string
	return rx .. "," .. ry
end

local function ensureRegion(rx: number, ry: number)
	local key = regionKey(rx, ry)
	local state = regionState[key]
	if state == "ready" then return end
	if state == "loading" then
		local guard = 0
		while regionState[key] == "loading" and guard < 600 do
			task.wait(0.05)
			guard += 1
		end
		return
	end

	regionState[key] = "loading"
	local data = SaveService.loadRegion(rx, ry)
	if type(data) == "table" then
		-- الصيغة الحالية: { tiles = {...}, stations = {...} }
		-- الصيغة الأقدم: خريطة مسطّحة من مفتاح القطعة إلى التعديلات
		local tiles = if type(data.tiles) == "table" then data.tiles else data
		for chunkKey, flat in tiles do
			if type(flat) == "table" then
				local cx, cy = Chunk.parseKey(chunkKey)
				World.applyEncodedDiff(world, cx, cy, flat)
			end
		end
		if type(data.stations) == "table" and Services.Station then
			Services.Station.importRegion(data.stations)
		end
	end
	regionState[key] = "ready"
end

local function markDirty(cx: number, cy: number)
	local rx, ry = regionOf(cx, cy)
	dirtyRegions[regionKey(rx, ry)] = true
end

function WorldService.saveDirtyRegions()
	-- ادمج المناطق التي غيّرتها المحطات (محتويات الأفران)
	if Services.Station then
		for key in Services.Station.consumeDirtyRegions() do
			dirtyRegions[key] = true
		end
	end

	local pending = {}
	for key in dirtyRegions do
		table.insert(pending, key)
	end
	table.clear(dirtyRegions)

	for _, key in pending do
		local parts = string.split(key, ",")
		local rx, ry = tonumber(parts[1]) or 0, tonumber(parts[2]) or 0
		local tiles: { [string]: { number } } = {}
		local any = false
		for cy = ry * Config.REGION, (ry + 1) * Config.REGION - 1 do
			for cx = rx * Config.REGION, (rx + 1) * Config.REGION - 1 do
				local flat = World.encodeDiff(world, cx, cy)
				if flat and #flat > 0 then
					tiles[Chunk.keyOf(cx, cy)] = flat
					any = true
				end
			end
		end

		local stations = if Services.Station then Services.Station.exportRegion(rx, ry) else nil
		if any or stations then
			SaveService.saveRegion(rx, ry, { tiles = tiles, stations = stations } :: any)
		end
		task.wait(0.12) -- احترام حدود معدّل DataStore
	end
end

-- ===== الاشتراكات والبثّ =====

local function chunkKeyOfTile(x: number, y: number): string
	return Chunk.keyOf(x // SIZE, y // SIZE)
end

local function broadcastBlock(x: number, y: number, fg: number, bg: number)
	local key = chunkKeyOfTile(x, y)
	local remote = Net.get("BlockUpdate")
	for player, set in subs do
		if set[key] then
			remote:FireClient(player, x, y, fg, bg)
		end
	end
end

-- ===== تعديل البلاطات (داخلي، بلا تحقق) =====

function WorldService.setTile(x: number, y: number, fg: number, bg: number)
	if not World.inBounds(x, y) then return end
	local oldFg = World.fg(world, x, y)
	local oldBg = World.bg(world, x, y)
	if oldFg == fg and oldBg == bg then return end

	World.set(world, x, y, fg, bg)
	markDirty(x // SIZE, y // SIZE)
	broadcastBlock(x, y, fg, bg)

	-- أيقظ السوائل والبلاطات المعلّقة حول التغيير
	WorldService.wakeLiquid(x, y)
	for _, offset in { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
		WorldService.wakeLiquid(x + offset[1], y + offset[2])
	end
	if fg == B.AIR then
		WorldService.checkSupport(x, y - 1)
		WorldService.checkSupport(x - 1, y)
		WorldService.checkSupport(x + 1, y)
	end
end

-- بلاطة تحتاج سنداً وفقدته -> تنكسر وتسقط كغرض
function WorldService.checkSupport(x: number, y: number)
	local id = World.fg(world, x, y)
	if not Blocks.needsSupport(id) then return end
	local below = World.fg(world, x, y + 1)
	local left = World.fg(world, x - 1, y)
	local right = World.fg(world, x + 1, y)
	local wall = World.bg(world, x, y)
	local supported = Blocks.isSolid(below) or Blocks.isSolid(left) or Blocks.isSolid(right) or wall ~= B.AIR
	if not supported then
		local drop = Items.fromBlock(id)
		WorldService.setTile(x, y, B.AIR, wall)
		if drop and Services.Entity then
			Services.Entity.spawnItem(x + 0.5, y + 0.5, drop, 1)
		end
	end
end

-- ===== محاكاة السوائل =====
--[[
	سائل بمستويات حقيقية (1..8) محفوظ في البتّات العليا من معرّف البلاطة.
	القواعد ثلاث فقط، وهي كافية لسلوك مقنع:
	  1. السائل يهبط إلى ما تحته حتى يمتلئ.
	  2. إن لم يستطع الهبوط، يتسوّى أفقياً مع جاره الأقل منه.
	  3. الماء + الحمم = سبج.
	الكتلة محفوظة تماماً: كل وحدة تُنقل تُطرح من مصدرها وتُضاف لهدفها،
	فلا يتكاثر الماء ولا يتبخّر (هناك اختبار يتحقق من ذلك).
]]

function WorldService.wakeLiquid(x: number, y: number)
	if not World.inBounds(x, y) then return end
	local key = x .. "," .. y
	if liquidQueue[key] then return end
	if not Blocks.isLiquid(World.fg(world, x, y)) then return end
	liquidQueue[key] = true
	table.insert(liquidOrder, { x, y })
end

-- كتابة سائل عبر المسار الرسمي حتى يُبثّ ويُحفظ
local function setLiquidTile(x: number, y: number, id: number, level: number)
	local bg = World.bg(world, x, y)
	if level <= 0 then
		WorldService.setTile(x, y, B.AIR, bg)
		return
	end
	local clamped = math.min(math.floor(level), World.LIQUID_FULL)
	WorldService.setTile(x, y, id + bit32.lshift(clamped, World.LIQUID_SHIFT), bg)
end

WorldService.setLiquidTile = setLiquidTile

local function obsidianAt(x: number, y: number)
	WorldService.setTile(x, y, B.OBSIDIAN, World.bg(world, x, y))
end

-- يحاول تحويل التقاء الماء بالحمم إلى سبج؛ يُعيد true إن حدث تفاعل
local function reactLiquids(x: number, y: number, id: number): boolean
	for _, offset in { { 0, 1 }, { 0, -1 }, { -1, 0 }, { 1, 0 } } do
		local nx, ny = x + offset[1], y + offset[2]
		local other = World.fg(world, nx, ny)
		if Blocks.isLiquid(other) and other ~= id then
			-- الحمم هي التي تتصلّب، والماء يتبخّر عند نقطة التماس
			if id == B.LAVA then
				obsidianAt(x, y)
			else
				obsidianAt(nx, ny)
				setLiquidTile(x, y, id, 0)
			end
			return true
		end
	end
	return false
end

local function stepLiquids()
	local budget = 300
	local processed = 0

	while processed < budget and #liquidOrder > 0 do
		local cell = table.remove(liquidOrder, 1)
		if not cell then break end
		local x, y = cell[1], cell[2]
		liquidQueue[x .. "," .. y] = nil
		processed += 1

		local id = World.fg(world, x, y)
		if not Blocks.isLiquid(id) then continue end

		local level = World.liquidLevel(world, x, y)
		if level <= 0 then
			setLiquidTile(x, y, id, 0)
			continue
		end

		if reactLiquids(x, y, id) then continue end

		-- 1) الهبوط
		local belowId = World.fg(world, x, y + 1)
		if belowId == id then
			local belowLevel = World.liquidLevel(world, x, y + 1)
			if belowLevel < World.LIQUID_FULL then
				local move = math.min(level, World.LIQUID_FULL - belowLevel)
				setLiquidTile(x, y + 1, id, belowLevel + move)
				setLiquidTile(x, y, id, level - move)
				continue
			end
		elseif Blocks.isReplaceable(belowId) and not Blocks.isLiquid(belowId) then
			setLiquidTile(x, y + 1, id, level)
			setLiquidTile(x, y, id, 0)
			continue
		end

		-- 2) التسوية الأفقية (وحدة أو أكثر نحو الجار الأقل)
		local dirs: { number } = if math.random() < 0.5 then { -1, 1 } else { 1, -1 }
		local remaining = level
		for _, dx in dirs do
			if remaining <= 1 then break end
			local sideId = World.fg(world, x + dx, y)
			local sideLevel = 0
			local canFlow = false

			if sideId == id then
				sideLevel = World.liquidLevel(world, x + dx, y)
				canFlow = sideLevel < remaining - 1
			elseif Blocks.isReplaceable(sideId) and not Blocks.isLiquid(sideId) then
				canFlow = true
			end

			if canFlow then
				local gap = remaining - sideLevel
				local move = math.max(1, gap // 3)
				move = math.min(move, remaining - 1, World.LIQUID_FULL - sideLevel)
				if move > 0 then
					setLiquidTile(x + dx, y, id, sideLevel + move)
					remaining -= move
				end
			end
		end

		if remaining ~= level then
			setLiquidTile(x, y, id, remaining)
		end
	end
end

-- ===== قطع الأشجار =====
-- كسر جذع يُسقط الشجرة كلها (كما في تيراريا) بدل تركها معلّقة في الهواء.
local function fellTree(x: number, y: number): number
	local logs = 0
	local cursor = y
	while cursor > Config.SKY_TOP and logs < 40 do
		if World.fg(world, x, cursor) ~= B.LOG then break end
		WorldService.setTile(x, cursor, B.AIR, World.bg(world, x, cursor))
		logs += 1
		cursor -= 1
	end
	-- نظّف الأوراق المحيطة بالتاج
	for dy = -5, 2 do
		for dx = -4, 4 do
			local lx, ly = x + dx, cursor + dy
			if World.fg(world, lx, ly) == B.LEAVES then
				WorldService.setTile(lx, ly, B.AIR, World.bg(world, lx, ly))
				if math.random() < 0.12 and Services.Entity then
					Services.Entity.spawnItem(lx + 0.5, ly + 0.5, "sapling", 1)
				end
			end
		end
	end
	return logs
end

-- ===== حساب زمن الكسر =====

function WorldService.breakTime(blockId: number, itemId: string?, miningMult: number?): number?
	return Mining.breakTime(blockId, itemId, miningMult)
end

-- ===== التحقق من الطلبات =====

local function getGuard(player: Player): EditGuard
	local guard = guards[player]
	if not guard then
		guard = { tokens = Config.MAX_EDITS_PER_SEC, last = os.clock(), lastBreak = 0 }
		guards[player] = guard
	end
	return guard
end

local function consumeToken(player: Player): boolean
	local guard = getGuard(player)
	local now = os.clock()
	guard.tokens = math.min(Config.MAX_EDITS_PER_SEC, guard.tokens + (now - guard.last) * Config.MAX_EDITS_PER_SEC)
	guard.last = now
	if guard.tokens < 1 then return false end
	guard.tokens -= 1
	return true
end

-- كسر بلاطة بناءً على طلب لاعب
local function handleBreak(player: Player, x: number, y: number, layer: string)
	local state = Services.Player.get(player)
	if not state or state.dead then return end
	if not World.inBounds(x, y) then return end
	if y >= Config.BEDROCK_Y then return end

	local held = Services.Player.heldItem(player)
	local heldId = if held then held.id else nil

	local px, py = state.body.x, state.body.y
	local reach = Config.REACH + Upgrades.reachBonus(held) + 1.2
	if Util.dist(px, py, x + 0.5, y + 0.5) > reach then return end
	if not consumeToken(player) then return end

	if layer == "wall" then
		local item = if heldId then Items.get(heldId) else nil
		if not item or item.tool ~= "hammer" then return end
		local wall = World.bg(world, x, y)
		if wall == B.AIR or wall == B.BEDROCK then return end
		local now = os.clock()
		local guard = getGuard(player)
		if now - guard.lastBreak < 0.18 then return end
		guard.lastBreak = now
		WorldService.setTile(x, y, World.fg(world, x, y), B.AIR)
		local drop = Items.fromBlock(wall)
		if drop then
			Services.Player.giveItem(player, drop, 1, x + 0.5, y + 0.5)
		end
		Net.get("Fx"):FireAllClients({ kind = "break", x = x, y = y, block = wall })
		return
	end

	local blockId = World.fg(world, x, y)
	if blockId == B.AIR or Blocks.isLiquid(blockId) then return end

	local buffs = Services.Player.buffAggregate(player)
	local required = Mining.breakTime(
		blockId,
		heldId,
		buffs.mining * Upgrades.miningMultiplier(held),
		Upgrades.powerBonus(held)
	)
	if not required then
		Net.get("Notify"):FireClient(player, { text = "تحتاج معولاً أقوى", color = { 230, 160, 80 } })
		return
	end

	-- تحقق زمني متسامح مع زمن الشبكة: لا يمكن كسر أسرع من 75% من الزمن المطلوب
	local now = os.clock()
	local guard = getGuard(player)
	if now - guard.lastBreak < required * 0.75 then return end
	guard.lastBreak = now

	local block = Blocks.get(blockId)
	local wall = World.bg(world, x, y)
	local extraLogs = 0

	-- محطة ذات حالة: انثر محتوياتها قبل إزالتها
	if block.station and Services.Station then
		Services.Station.onBlockRemoved(x, y)
	end

	if blockId == B.LOG then
		extraLogs = fellTree(x, y) - 1
	else
		WorldService.setTile(x, y, B.AIR, wall)
	end

	-- الإسقاط
	local dropBlock = block.drop or blockId
	local dropItem = Items.fromBlock(dropBlock)
	local chance = block.dropChance or 1
	if dropItem and math.random() <= chance then
		local count = 1
		if blockId == B.LOG then
			count = 1 + math.max(0, extraLogs)
			dropItem = "wood"
		elseif blockId == B.COAL_ORE then
			dropItem = "coal"
		elseif blockId == B.DIAMOND_ORE then
			dropItem = "diamond"
			count = math.random(1, 2)
		elseif blockId == B.GRASS_TUFT or blockId == B.FLOWER then
			dropItem = if math.random() < 0.35 then "herb" else dropItem
		end
		-- صفة «موفّق»: فرصة مضاعفة الإسقاط
		local fortune = Upgrades.fortune(held)
		if fortune > 0 and math.random() < fortune then
			count *= 2
		end
		Services.Player.giveItem(player, dropItem, count, x + 0.5, y + 0.5)
	end

	state.blocksMined += 1
	Net.get("Fx"):FireAllClients({ kind = "break", x = x, y = y, block = blockId })
end

-- وضع بلاطة
local function handlePlace(player: Player, x: number, y: number, layer: string, slotIndex: number)
	local state = Services.Player.get(player)
	if not state or state.dead then return end
	if not World.inBounds(x, y) then return end
	if y >= Config.BEDROCK_Y or y < Config.SKY_TOP then return end

	local px, py = state.body.x, state.body.y
	local reach = Config.REACH + Upgrades.reachBonus(Services.Player.heldItem(player)) + 1.2
	if Util.dist(px, py, x + 0.5, y + 0.5) > reach then return end
	if not consumeToken(player) then return end

	local stack = state.slots[slotIndex]
	if not stack then return end
	local item = Items.get(stack.id)
	if not item or not item.place then return end

	local now = os.clock()
	local guard = getGuard(player)
	if now - guard.lastBreak < 0.1 then return end
	guard.lastBreak = now

	local blockId = item.place
	local block = Blocks.get(blockId)

	if layer == "wall" then
		if not item.wall then return end
		if World.bg(world, x, y) ~= B.AIR then return end
		-- الجدران تحتاج جواراً
		local neighbour = World.bg(world, x - 1, y) ~= B.AIR or World.bg(world, x + 1, y) ~= B.AIR
			or World.bg(world, x, y - 1) ~= B.AIR or World.bg(world, x, y + 1) ~= B.AIR
			or Blocks.isSolid(World.fg(world, x, y))
		if not neighbour then return end
		Inventory.removeFromSlot(state.slots, slotIndex, 1)
		WorldService.setTile(x, y, World.fg(world, x, y), blockId)
		Services.Player.syncInventory(player)
		return
	end

	local existing = World.fg(world, x, y)
	if not Blocks.isReplaceable(existing) then return end

	-- لا تبنِ داخل جسد لاعب أو وحش
	if block.solid then
		for _, other in Players:GetPlayers() do
			local otherState = Services.Player.get(other)
			if otherState and not otherState.dead then
				local body = otherState.body
				if math.abs(body.x - (x + 0.5)) < (body.w / 2 + 0.5)
					and math.abs(body.y - (y + 0.5)) < (body.h / 2 + 0.5) then
					return
				end
			end
		end
		if Services.Entity.blockedBy(x, y) then return end
	end

	-- يجب أن تلتصق البلاطة بشيء (بلاطة مجاورة أو جدار خلفي)
	local attached = Blocks.isSolid(World.fg(world, x - 1, y)) or Blocks.isSolid(World.fg(world, x + 1, y))
		or Blocks.isSolid(World.fg(world, x, y - 1)) or Blocks.isSolid(World.fg(world, x, y + 1))
		or World.bg(world, x, y) ~= B.AIR
		or Blocks.isPlatform(World.fg(world, x - 1, y)) or Blocks.isPlatform(World.fg(world, x + 1, y))
	if not attached then return end

	if Blocks.needsSupport(blockId) then
		local ok = Blocks.isSolid(World.fg(world, x, y + 1)) or Blocks.isSolid(World.fg(world, x - 1, y))
			or Blocks.isSolid(World.fg(world, x + 1, y)) or World.bg(world, x, y) ~= B.AIR
		if not ok then return end
	end

	Inventory.removeFromSlot(state.slots, slotIndex, 1)
	WorldService.setTile(x, y, blockId, World.bg(world, x, y))
	Services.Player.syncInventory(player)
	Net.get("Fx"):FireAllClients({ kind = "place", x = x, y = y, block = blockId })
end

-- ===== الاشتراك في القطع =====

local function handleRequestChunks(player: Player, keys: { string })
	if type(keys) ~= "table" or #keys > 80 then return end
	local set = subs[player]
	if not set then
		set = {}
		subs[player] = set
	end

	local remote = Net.get("ChunkDiff")
	for _, key in keys do
		if type(key) == "string" and not set[key] then
			local cx, cy = Chunk.parseKey(key)
			if cx >= 0 and cy >= 0 and cx < Config.CHUNKS_X and cy < Config.CHUNKS_Y then
				set[key] = true
				local rx, ry = regionOf(cx, cy)
				ensureRegion(rx, ry)
				local flat = World.encodeDiff(world, cx, cy)
				remote:FireClient(player, cx, cy, flat or {})
			end
		end
	end
end

local function handleDropSubs(player: Player, keys: { string })
	local set = subs[player]
	if not set then return end
	for _, key in keys do
		set[key] = nil
	end
end

-- ===== الإقلاع =====

function WorldService.start()
	-- البذرة: ثابتة عبر كل الخوادم حتى يكون العالم واحداً للجميع
	local meta = SaveService.loadMeta()
	if type(meta) == "table" and type(meta.seed) == "number" then
		seed = meta.seed
		Services.Time.load(meta.time)
	else
		seed = math.random(1, 2 ^ 30)
		SaveService.saveMeta({ seed = seed, time = Services.Time.serialize(), created = os.time() })
	end

	world = World.new(seed, 900)
	spawnX, spawnY = WorldGen.spawnPoint(seed)

	-- حمّل منطقة الظهور مسبقاً
	task.spawn(function()
		local cx, cy = math.floor(spawnX) // SIZE, math.floor(spawnY) // SIZE
		ensureRegion(regionOf(cx, cy))
	end)

	Net.get("RequestChunks").OnServerEvent:Connect(function(player, keys, drop)
		if drop == true then
			handleDropSubs(player, keys)
		else
			handleRequestChunks(player, keys)
		end
	end)

	Net.get("Edit").OnServerEvent:Connect(function(player, action, x, y, layer, slotIndex)
		if type(x) ~= "number" or type(y) ~= "number" then return end
		x, y = math.floor(x), math.floor(y)
		if action == "break" then
			handleBreak(player, x, y, if layer == "wall" then "wall" else "fg")
		elseif action == "place" then
			if type(slotIndex) ~= "number" then return end
			slotIndex = math.floor(slotIndex)
			if slotIndex < 1 or slotIndex > Config.INV_SLOTS then return end
			handlePlace(player, x, y, if layer == "wall" then "wall" else "fg", slotIndex)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		subs[player] = nil
		guards[player] = nil
	end)

	-- محاكاة السوائل
	task.spawn(function()
		while true do
			task.wait(0.1)
			local ok, err = pcall(stepLiquids)
			if not ok then warn("[WorldService] خطأ في محاكاة السوائل: " .. tostring(err)) end
		end
	end)

	-- الحفظ التلقائي
	task.spawn(function()
		while true do
			task.wait(Config.AUTOSAVE)
			local ok, err = pcall(WorldService.saveDirtyRegions)
			if not ok then warn("[WorldService] فشل الحفظ التلقائي: " .. tostring(err)) end
			SaveService.saveMeta({ seed = seed, time = Services.Time.serialize(), created = os.time() })
		end
	end)

	game:BindToClose(function()
		pcall(WorldService.saveDirtyRegions)
		pcall(function()
			SaveService.saveMeta({ seed = seed, time = Services.Time.serialize(), created = os.time() })
		end)
	end)

	RunService.Heartbeat:Connect(function()
		-- لا شيء دائم هنا؛ محجوز لتوسعات مستقبلية (نمو النباتات، إلخ)
	end)

	-- نمو النباتات والشتلات
	task.spawn(function()
		while true do
			task.wait(6)
			for player, set in subs do
				local state = Services.Player.get(player)
				if state then
					for _ = 1, 3 do
						local gx = math.floor(state.body.x) + math.random(-30, 30)
						local gy = math.floor(state.body.y) + math.random(-16, 16)
						if World.inBounds(gx, gy) then
							local id = World.fg(world, gx, gy)
							if id == B.SAPLING and Blocks.isSolid(World.fg(world, gx, gy + 1)) then
								if math.random() < 0.25 then
									-- تنمو الشتلة إلى جذع صغير
									WorldService.setTile(gx, gy, B.LOG, World.bg(world, gx, gy))
									for i = 1, math.random(4, 7) do
										if World.fg(world, gx, gy - i) == B.AIR then
											WorldService.setTile(gx, gy - i, B.LOG, World.bg(world, gx, gy - i))
										end
									end
								end
							elseif id == B.AIR and World.fg(world, gx, gy + 1) == B.GRASS then
								if math.random() < 0.06 then
									WorldService.setTile(gx, gy, B.GRASS_TUFT, World.bg(world, gx, gy))
								end
							end
						end
					end
				end
			end
		end
	end)
end

WorldService.ensureRegionAt = function(x: number, y: number)
	ensureRegion(regionOf(x // SIZE, y // SIZE))
end

return WorldService
