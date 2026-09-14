--!strict
--[[
	ClientWorld — نسخة العالم على العميل.
	تُولَّد محلياً من نفس البذرة، ثم تُطبَّق عليها تعديلات الخادم.
	تدير أيضاً الاشتراك في القطع حسب موقع الكاميرا.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Chunk = require(Shared.Chunk)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local World = require(Shared.World)

local ClientWorld = {}

local world: World.World? = nil
local subscribed: { [string]: boolean } = {}
local genQueue: { { number } } = {}
local genQueued: { [string]: boolean } = {}
local pendingRequest: { string } = {}
local lastChunkX, lastChunkY = -999, -999
local dirtyCallback: ((x: number, y: number) -> ())? = nil

function ClientWorld.get(): World.World
	assert(world, "لم تتم تهيئة عالم العميل بعد")
	return world :: World.World
end

function ClientWorld.isReady(): boolean
	return world ~= nil
end

function ClientWorld.onDirty(callback: (x: number, y: number) -> ())
	dirtyCallback = callback
end

function ClientWorld.init(seed: number)
	world = World.new(seed, 300)
	subscribed = {}
	table.clear(genQueue)
	table.clear(genQueued)
	lastChunkX, lastChunkY = -999, -999
end

-- ===== التوليد المُقسَّط =====
-- توليد قطعة يكلف ~1024 بلاطة بحسابات ضوضاء، لذا نولّد عدداً محدوداً كل إطار
-- بدل توليدها فجأة داخل حلقة الرسم (وإلا ظهرت تقطّعات عند الحركة السريعة).

local function queueChunk(cx: number, cy: number, priority: boolean?)
	if cx < 0 or cy < 0 or cx >= Config.CHUNKS_X or cy >= Config.CHUNKS_Y then return end
	local key = Chunk.keyOf(cx, cy)
	if genQueued[key] then return end
	if world and World.isLoaded(world :: World.World, cx, cy) then return end
	genQueued[key] = true
	if priority then
		table.insert(genQueue, 1, { cx, cy })
	else
		table.insert(genQueue, { cx, cy })
	end
end

ClientWorld.queueChunk = queueChunk

-- يولّد فوراً القطع المحيطة بنقطة (تُستعمل عند الدخول أو بعد الانتقال)
function ClientWorld.generateAround(x: number, y: number, radius: number)
	if not world then return end
	local cx, cy = math.floor(x) // Config.CHUNK, math.floor(y) // Config.CHUNK
	for dy = -radius, radius do
		for dx = -radius, radius do
			World.getChunk(world :: World.World, cx + dx, cy + dy)
		end
	end
end

function ClientWorld.pump(budget: number)
	if not world then return end
	local generated = 0
	while generated < budget and #genQueue > 0 do
		local entry = table.remove(genQueue, 1)
		if not entry then break end
		local cx, cy = entry[1], entry[2]
		genQueued[Chunk.keyOf(cx, cy)] = nil
		if not World.isLoaded(world :: World.World, cx, cy) then
			World.getChunk(world :: World.World, cx, cy)
			generated += 1
		end
	end
end

function ClientWorld.pendingChunks(): number
	return #genQueue
end

-- ===== الاشتراك في القطع =====

local function flushRequests()
	if #pendingRequest == 0 then return end
	local batch = pendingRequest
	pendingRequest = {}
	Net.get("RequestChunks"):FireServer(batch, false)
end

function ClientWorld.updateSubscriptions(camX: number, camY: number)
	if not world then return end
	local cx = math.floor(camX) // Config.CHUNK
	local cy = math.floor(camY) // Config.CHUNK
	if cx == lastChunkX and cy == lastChunkY then return end
	lastChunkX, lastChunkY = cx, cy

	local wanted: { [string]: boolean } = {}
	for dy = -Config.CHUNK_RADIUS_Y, Config.CHUNK_RADIUS_Y do
		for dx = -Config.CHUNK_RADIUS_X, Config.CHUNK_RADIUS_X do
			local tx, ty = cx + dx, cy + dy
			if tx >= 0 and ty >= 0 and tx < Config.CHUNKS_X and ty < Config.CHUNKS_Y then
				local key = Chunk.keyOf(tx, ty)
				wanted[key] = true
				queueChunk(tx, ty, math.abs(dx) <= 1 and math.abs(dy) <= 1)
				if not subscribed[key] then
					subscribed[key] = true
					table.insert(pendingRequest, key)
				end
			end
		end
	end

	-- ألغِ اشتراك القطع البعيدة وحرّر ذاكرتها
	local drop: { string } = {}
	for key in subscribed do
		if not wanted[key] then
			subscribed[key] = nil
			table.insert(drop, key)
			local dcx, dcy = Chunk.parseKey(key)
			World.unload(world :: World.World, dcx, dcy)
		end
	end
	if #drop > 0 then
		Net.get("RequestChunks"):FireServer(drop, true)
	end

	flushRequests()
end

-- ===== استقبال التحديثات =====

function ClientWorld.start()
	Net.get("ChunkDiff").OnClientEvent:Connect(function(cx: number, cy: number, flat: { number })
		if not world then return end
		if type(flat) ~= "table" or #flat == 0 then return end
		World.applyEncodedDiff(world :: World.World, cx, cy, flat)
		if dirtyCallback then
			dirtyCallback(cx * Config.CHUNK, cy * Config.CHUNK)
		end
	end)

	Net.get("BlockUpdate").OnClientEvent:Connect(function(x: number, y: number, fg: number, bg: number)
		if not world then return end
		local w = world :: World.World
		-- نكتب مباشرة في القطعة والتعديلات معاً
		World.set(w, x, y, fg, bg)
		if dirtyCallback then
			dirtyCallback(x, y)
		end
	end)
end

-- تعديل تفاؤلي محلي (قبل تأكيد الخادم) لاستجابة فورية
function ClientWorld.predictSet(x: number, y: number, fg: number, bg: number)
	if not world then return end
	World.set(world :: World.World, x, y, fg, bg)
	if dirtyCallback then dirtyCallback(x, y) end
end

return ClientWorld
