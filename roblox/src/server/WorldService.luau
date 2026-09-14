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
		for chunkKey, flat in data do
			if type(flat) == "table" then
				local cx, cy = Chunk.parseKey(chunkKey)
				World.applyEncodedDiff(world, cx, cy, flat)
			end
		end
	end
	regionState[key] = "ready"
end

local function markDirty(cx: number, cy: number)
	local rx, ry = regionOf(cx, cy)
	dirtyRegions[regionKey(rx, ry)] = true
end

function WorldService.saveDirtyRegions()
	local pending = {}
	for key in dirtyRegions do
		table.insert(pending, key)
	end
	table.clear(dirtyRegions)

	for _, key in pending do
		local parts = string.split(key, ",")
		local rx, ry = tonumber(parts[1]) or 0, tonumber(parts[2]) or 0
		local payload: { [string]: { number } } = {}
		local any = false
		for cy = ry * Config.REGION, (ry + 1) * Config.REGION - 1 do
			for cx = rx * Config.REGION, (rx + 1) * Config.REGION - 1 do
				local flat = World.encodeDiff(world, cx, cy)
				if flat and #flat > 0 then
					payload[Chunk.keyOf(cx, cy)] = flat
					any = true
				end
			end
		end
		if any then
			SaveService.saveRegion(rx, ry, payload)
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
-- تدفّق محافظ على الكتلة: السائل يهبط، وينزلق جانباً فقط إن وجد منفذاً للهبوط.
-- هذا يمنع التكاثر اللانهائي للماء ويبقى رخيصاً حسابياً.

function WorldService.wakeLiquid(x: number, y: number)
	if not World.inBounds(x, y) then return end
	local key = x .. "," .. y
	if liquidQueue[key] then return end
	local id = World.fg(world, x, y)
	if not Blocks.isLiquid(id) then return end
	liquidQueue[key] = true
	table.insert(liquidOrder, { x, y })
end

local function stepLiquids()
	local budget = 260
	local processed = 0
	while processed < budget and #liquidOrder > 0 do
		local cell = table.remove(liquidOrder, 1)
		if not cell then break end
		local x, y = cell[1], cell[2]
		liquidQueue[x .. "," .. y] = nil
		processed += 1

		local id = World.fg(world, x, y)
		if Blocks.isLiquid(id) then
			local belowId = World.fg(world, x, y + 1)

			-- ماء + حمم = سبج
			if id == B.WATER and belowId == B.LAVA then
				WorldService.setTile(x, y, B.AIR, World.bg(world, x, y))
				WorldService.setTile(x, y + 1, B.OBSIDIAN, World.bg(world, x, y + 1))
				continue
			end
			if id == B.LAVA and belowId == B.WATER then
				WorldService.setTile(x, y, B.AIR, World.bg(world, x, y))
				WorldService.setTile(x, y + 1, B.OBSIDIAN, World.bg(world, x, y + 1))
				continue
			end

			if Blocks.isReplaceable(belowId) and belowId ~= id and not Blocks.isLiquid(belowId) then
				-- اهبط
				WorldService.setTile(x, y, B.AIR, World.bg(world, x, y))
				WorldService.setTile(x, y + 1, id, World.bg(world, x, y + 1))
			else
				-- انزلق جانباً نحو منفذ هبوط
				local dirs: { number } = if math.random() < 0.5 then { -1, 1 } else { 1, -1 }
				for _, dx in dirs do
					local sideId = World.fg(world, x + dx, y)
					local sideBelow = World.fg(world, x + dx, y + 1)
					if Blocks.isReplaceable(sideId) and not Blocks.isLiquid(sideId)
						and Blocks.isReplaceable(sideBelow) and not Blocks.isLiquid(sideBelow) then
						WorldService.setTile(x, y, B.AIR, World.bg(world, x, y))
						WorldService.setTile(x + dx, y, id, World.bg(world, x + dx, y))
						break
					end
				end
			end
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

	local px, py = state.body.x, state.body.y
	if Util.dist(px, py, x + 0.5, y + 0.5) > Config.REACH + 1.2 then return end
	if not consumeToken(player) then return end

	local held = Services.Player.heldItem(player)
	local heldId = if held then held.id else nil

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
	local required = WorldService.breakTime(blockId, heldId, buffs.mining)
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
	if Util.dist(px, py, x + 0.5, y + 0.5) > Config.REACH + 1.2 then return end
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
