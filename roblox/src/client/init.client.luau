--!strict
--[[
	نقطة إقلاع العميل — تربط الشبكة بالمحرك والواجهة ثم تدير الحلقة الرئيسية.
]]

local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Blocks = require(Shared.Blocks)
local Buffs = require(Shared.Buffs)
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Net = require(Shared.Net)

local ClientWorld = require(script.ClientWorld)
local Controller = require(script.Controller)
local Fx = require(script.Fx)
local Lighting = require(script.Lighting)
local Renderer = require(script.Renderer)
local Sfx = require(script.Sfx)
local State = require(script.State)

local Hud = require(script.UI.Hud)
local Panels = require(script.UI.Panels)

-- ===== تهيئة الواجهة =====

Renderer.init()
ClientWorld.start()
ClientWorld.onDirty(function()
	Lighting.markDirty()
end)

local gui = Renderer.gui()
Hud.build(gui)
Panels.build(gui)

pcall(function()
	StarterGui:SetCore("TopbarEnabled", false)
	-- خاصية حديثة نسبياً؛ نتجاهلها بهدوء على الإصدارات الأقدم
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)
UserInputService.MouseIconEnabled = true

-- ===== ربط الأحداث =====

Hud.onHotbar(function(index)
	Controller.selectHotbar(index)
end)

Hud.onInventoryButton(function()
	Panels.setOpen(not Panels.isOpen())
	Sfx.play("ui")
end)

Hud.onTouch(function(action, down)
	Controller.setTouch(action, down)
end)

Controller.on("toggleInventory", function()
	Panels.setOpen(not Panels.isOpen())
	Sfx.play("ui")
end)

Controller.on("closeAll", function()
	Panels.closeAll()
end)

Controller.on("wallMode", function(enabled: boolean)
	Hud.setWallMode(enabled)
	Sfx.play("ui")
end)

Controller.on("sfx", function(name: string, blockId: number?)
	if name == "mine" and blockId then
		Sfx.block("mine", blockId)
	elseif name == "break" and blockId then
		Sfx.block("break", blockId)
	else
		Sfx.play(name)
	end
end)

Controller.on("particles", function(tx: number, ty: number, blockId: number)
	Fx.blockBurst(tx, ty, blockId, 4)
end)

-- ===== قنوات الخادم =====

Net.get("Hello").OnClientEvent:Connect(function(payload)
	State.seed = payload.seed
	State.userId = payload.userId
	State.spawnX = payload.spawnX
	State.spawnY = payload.spawnY
	State.body.x = payload.x
	State.body.y = payload.y
	State.camX = payload.x
	State.camY = payload.y
	ClientWorld.init(payload.seed)
	-- ولّد محيط اللاعب فوراً حتى لا يسقط في فراغ غير محمّل
	ClientWorld.generateAround(payload.x, payload.y, 1)
	ClientWorld.updateSubscriptions(State.camX, State.camY)
	Lighting.markDirty()
	State.ready = true
	Hud.notify("أهلاً بك في TerraCraft — ابنِ، نقّب، وانجُ!", Color3.fromRGB(140, 220, 250), true)
end)

Net.get("Inventory").OnClientEvent:Connect(function(payload)
	local slots = {}
	for index, entry in (payload.slots or {}) :: { [number]: any } do
		slots[tonumber(index) or 0] = { id = entry[1], n = entry[2] }
	end
	State.slots = slots

	local armor = {}
	for slotName, entry in (payload.armor or {}) :: { [string]: any } do
		armor[slotName] = { id = entry[1], n = entry[2] }
	end
	State.armor = armor

	if payload.hotbar then State.hotbar = payload.hotbar end
	Panels.onInventoryChanged()
end)

Net.get("Stats").OnClientEvent:Connect(function(payload)
	local wasDead = State.dead
	State.hp = payload.hp
	State.maxHp = payload.maxHp
	State.mana = payload.mana
	State.maxMana = payload.maxMana
	State.food = payload.food
	State.defense = payload.defense
	State.dead = payload.dead
	State.respawnIn = payload.respawnIn or 0
	State.buffs = payload.buffs or {}
	State.kills = payload.kills or 0
	State.deaths = payload.deaths or 0

	if payload.dead and not wasDead then
		Sfx.play("hurt")
		Panels.closeAll()
	end
end)

Net.get("TimeSync").OnClientEvent:Connect(function(payload)
	State.time = payload.t
	State.day = payload.day
	State.bloodMoon = payload.blood == true
end)

Net.get("Entities").OnClientEvent:Connect(function(list)
	if type(list) ~= "table" then return end
	local seen: { [number]: boolean } = {}

	for _, packet in list do
		local id = packet.i
		seen[id] = true
		local existing = State.entities[id]
		if existing then
			existing.vx = (packet.x - existing.x) * Config.ENTITY_HZ
			existing.vy = (packet.y - existing.y) * Config.ENTITY_HZ
			existing.x = packet.x
			existing.y = packet.y
			existing.f = packet.f
			existing.a = packet.a
			existing.h = packet.h
			existing.n = packet.n
			existing.t = packet.t
			existing.k = packet.k
		else
			packet.rx = packet.x
			packet.ry = packet.y
			packet.vx = 0
			packet.vy = 0
			State.entities[id] = packet
		end
	end

	for id in State.entities do
		if not seen[id] then
			State.entities[id] = nil
		end
	end
end)

Net.get("PeerState").OnClientEvent:Connect(function(list)
	if type(list) ~= "table" then return end
	local seen: { [number]: boolean } = {}
	for _, packet in list do
		seen[packet.u] = true
		local existing = State.peers[packet.u]
		if existing then
			existing.vx = (packet.x - existing.x) * Config.STATE_HZ
			existing.x = packet.x
			existing.y = packet.y
			existing.f = packet.f
			existing.d = packet.d
			existing.n = packet.n
			existing.it = packet.it
			existing.hd = packet.hd
			existing.ch = packet.ch
		else
			packet.rx = packet.x
			packet.ry = packet.y
			packet.vx = 0
			State.peers[packet.u] = packet
		end
	end
	for userId in State.peers do
		if not seen[userId] then
			State.peers[userId] = nil
		end
	end
end)

Net.get("Fx").OnClientEvent:Connect(function(payload)
	Fx.handle(payload)
	if type(payload) == "table" then
		if payload.kind == "pickup" then
			Sfx.play("pickup")
		elseif payload.kind == "craft" then
			Sfx.play("craft")
		elseif payload.kind == "mob_death" then
			Sfx.play("break_block")
		end
	end
end)

Net.get("Hit").OnClientEvent:Connect(function(payload)
	Fx.handleHit(payload)
	if type(payload) == "table" and payload.kind == "player" and payload.player == State.userId then
		Sfx.play("hurt")
	end
end)

Net.get("Notify").OnClientEvent:Connect(function(payload)
	local color = if payload.color
		then Color3.fromRGB(payload.color[1], payload.color[2], payload.color[3])
		else nil
	Hud.notify(payload.text, color, payload.big)
end)

Net.get("Boss").OnClientEvent:Connect(function(payload)
	State.boss = payload
end)

Net.get("Respawn").OnClientEvent:Connect(function(x: number, y: number)
	State.body.x = x
	State.body.y = y
	State.body.vx = 0
	State.body.vy = 0
	State.camX = x
	State.camY = y
	ClientWorld.generateAround(x, y, 1)
	Lighting.markDirty()
end)

Net.get("Shop").OnClientEvent:Connect(function(payload)
	Panels.openShop(payload)
	if payload.open then
		Sfx.play("ui")
	else
		Hud.notify("لا يوجد تاجر هنا — اقترب من نقطة الظهور", Color3.fromRGB(230, 190, 110))
	end
end)

-- ===== الحلقة الرئيسية =====

Controller.start()

local lightTimer = 0
local footstepTimer = 0

RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt, 1 / 20) -- لا تسمح لقفزة إطار بكسر الفيزياء

	if not State.ready or not ClientWorld.isReady() then
		return
	end

	ClientWorld.updateSubscriptions(State.camX, State.camY)
	-- توليد مُقسَّط: قطعة واحدة كحد أقصى، وفقط إن كان الإطار السابق مريحاً.
	-- هكذا يبقى تحميل العالم غير مرئي بدل أن يُحدث تقطّعاً أثناء اللعب.
	if dt < 1 / 45 then
		ClientWorld.pump(1)
	end
	State.pending = ClientWorld.pendingChunks()
	Controller.update(dt)

	-- استيفاء مواضع الكيانات لحركة ناعمة بين حزم الشبكة
	local blend = math.min(1, dt * 16)
	for _, entity in State.entities do
		entity.rx = (entity.rx or entity.x) + (entity.x - (entity.rx or entity.x)) * blend
		entity.ry = (entity.ry or entity.y) + (entity.y - (entity.ry or entity.y)) * blend
	end
	for _, peer in State.peers do
		peer.rx = (peer.rx or peer.x) + (peer.x - (peer.rx or peer.x)) * blend
		peer.ry = (peer.ry or peer.y) + (peer.y - (peer.ry or peer.y)) * blend
	end

	-- مصادر الضوء الديناميكية: المشعل المحمول وتعزيز التوهج
	lightTimer -= dt
	if lightTimer <= 0 then
		lightTimer = 0.15
		local sources = {}
		local held = State.heldItem()
		local glow = 0
		if held then
			local item = Items.get(held.id)
			if item and item.place then
				glow = math.max(glow, Blocks.light(item.place))
			end
		end
		local buffMap = {}
		for _, buff in State.buffs do buffMap[buff.id] = buff.t end
		glow = math.max(glow, Buffs.aggregate(buffMap).light)
		if glow > 0 then
			table.insert(sources, { x = State.body.x, y = State.body.y, level = glow })
		end
		Lighting.setDynamicSources(sources)

		-- ضوء الشمس حسب وقت اليوم
		local t = State.time
		local sun = 0
		if t >= 0.27 and t <= 0.73 then
			sun = 1
		elseif t > 0.73 and t < Config.NIGHT_FROM then
			sun = 1 - (t - 0.73) / (Config.NIGHT_FROM - 0.73)
		elseif t > Config.NIGHT_TO and t < 0.27 then
			sun = (t - Config.NIGHT_TO) / (0.27 - Config.NIGHT_TO)
		end
		Lighting.setSunlight(math.max(0.08, sun))
	end

	-- صوت الخطوات
	if State.body.onGround and math.abs(State.body.vx) > 2 then
		footstepTimer -= dt
		if footstepTimer <= 0 then
			footstepTimer = 0.34
			Sfx.play("step", 0.25)
		end
	else
		footstepTimer = 0
	end

	Renderer.render(dt)
	Fx.update(dt)
	Hud.update(dt)
	Panels.update(dt)
end)

print("[TerraCraft] العميل جاهز")
