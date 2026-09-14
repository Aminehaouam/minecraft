--!strict
--[[
	PlayerService — حالة اللاعبين: المخزون، الإحصاءات، الحركة، استخدام العناصر، الحفظ.

	الحركة: يتنبأ العميل محلياً (استجابة فورية) والخادم يتحقق من المعقولية
	(سرعة قصوى + عدم الاختراق داخل الصخر) فيمنع الطيران والانتقال اللحظي
	دون أن يُدخل تأخيراً محسوساً على اللعب.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Blocks = require(Shared.Blocks)
local Buffs = require(Shared.Buffs)
local Config = require(Shared.Config)
local Inventory = require(Shared.Inventory)
local Items = require(Shared.Items)
local Net = require(Shared.Net)
local Physics = require(Shared.Physics)
local Util = require(Shared.Util)
local World = require(Shared.World)

local Services = require(script.Parent.Services)
local SaveService = require(script.Parent.SaveService)

local PlayerService = {}

export type PlayerState = {
	player: Player,
	body: Physics.Body,
	slots: Inventory.Slots,
	armor: { [string]: Inventory.Stack? },
	hotbar: number,
	hp: number,
	maxHp: number,
	mana: number,
	maxMana: number,
	food: number,
	buffs: { [string]: number },
	dead: boolean,
	respawnAt: number,
	spawnX: number,
	spawnY: number,
	lastDamage: number,
	lastAttack: number,
	lastUse: number,
	facing: number,
	anim: string,
	fallPeak: number,
	aimX: number,
	aimY: number,
	underwater: number,
	kills: number,
	deaths: number,
	blocksMined: number,
	joinedAt: number,
	loaded: boolean,
	dirty: boolean,
}

local states: { [Player]: PlayerState } = {}

function PlayerService.get(player: Player): PlayerState?
	return states[player]
end

function PlayerService.all(): { [Player]: PlayerState }
	return states
end

function PlayerService.heldItem(player: Player): Inventory.Stack?
	local state = states[player]
	if not state then return nil end
	return state.slots[state.hotbar]
end

-- ===== الإحصاءات =====

function PlayerService.buffAggregate(player: Player): Buffs.Aggregate
	local state = states[player]
	if not state then return Buffs.aggregate({}) end
	return Buffs.aggregate(state.buffs)
end

function PlayerService.defense(state: PlayerState): number
	local total = 0
	local setName: string? = nil
	local setCount = 0
	for _, slot in { "head", "chest", "feet" } do
		local stack = state.armor[slot]
		if stack then
			local item = Items.get(stack.id)
			if item and item.defense then
				total += item.defense
				if item.setBonus then
					if setName == nil or setName == item.setBonus then
						setName = item.setBonus
						setCount += 1
					end
				end
			end
		end
	end
	if setCount == 3 then
		total += 6 -- مكافأة الطقم الكامل
	end
	total += Buffs.aggregate(state.buffs).defense
	return total
end

function PlayerService.syncStats(player: Player)
	local state = states[player]
	if not state then return end
	local buffList = {}
	for id, remaining in state.buffs do
		if remaining > 0 then
			table.insert(buffList, { id = id, t = math.floor(remaining * 10) / 10 })
		end
	end
	Net.get("Stats"):FireClient(player, {
		hp = math.floor(state.hp + 0.5),
		maxHp = state.maxHp,
		mana = math.floor(state.mana + 0.5),
		maxMana = state.maxMana,
		food = math.floor(state.food + 0.5),
		defense = PlayerService.defense(state),
		dead = state.dead,
		respawnIn = math.max(0, state.respawnAt - os.clock()),
		buffs = buffList,
		kills = state.kills,
		deaths = state.deaths,
		mined = state.blocksMined,
	})
end

function PlayerService.syncInventory(player: Player)
	local state = states[player]
	if not state then return end
	local armor = {}
	for slot, stack in state.armor do
		if stack then armor[slot] = { stack.id, stack.n } end
	end
	Net.get("Inventory"):FireClient(player, {
		slots = Inventory.toNetwork(state.slots),
		armor = armor,
		hotbar = state.hotbar,
	})
	state.dirty = true
end

-- ===== إعطاء العناصر =====

function PlayerService.giveItem(player: Player, id: string, count: number, dropX: number?, dropY: number?)
	local state = states[player]
	if not state then return end
	local leftover = Inventory.add(state.slots, id, count)
	if leftover > 0 and dropX and dropY and Services.Entity then
		Services.Entity.spawnItem(dropX, dropY, id, leftover)
	end
	PlayerService.syncInventory(player)
end

-- ===== الضرر والموت =====

function PlayerService.damage(player: Player, amount: number, source: string?, knockX: number?, knockY: number?)
	local state = states[player]
	if not state or state.dead then return end
	local now = os.clock()
	if now - state.lastDamage < Config.IFRAMES and source ~= "environment" then return end

	local defense = PlayerService.defense(state)
	local final = math.max(1, amount - defense * 0.5)
	state.hp -= final
	state.lastDamage = now

	if knockX then state.body.vx += knockX end
	if knockY then state.body.vy += knockY end

	Net.get("Hit"):FireAllClients({
		kind = "player", x = state.body.x, y = state.body.y,
		amount = math.floor(final + 0.5), player = player.UserId,
	})

	if state.hp <= 0 then
		PlayerService.kill(player, source)
	else
		PlayerService.syncStats(player)
	end
end

function PlayerService.kill(player: Player, source: string?)
	local state = states[player]
	if not state or state.dead then return end
	state.hp = 0
	state.dead = true
	state.deaths += 1
	state.respawnAt = os.clock() + Config.RESPAWN_TIME
	state.body.vx, state.body.vy = 0, 0

	-- عقوبة الموت: نصف العملات تتناثر
	local coins = Inventory.count(state.slots, "coin")
	if coins > 0 then
		local lost = math.floor(coins / 2)
		if lost > 0 and Inventory.remove(state.slots, "coin", lost) then
			if Services.Entity then
				Services.Entity.spawnItem(state.body.x, state.body.y, "coin", lost)
			end
		end
	end

	PlayerService.syncInventory(player)
	PlayerService.syncStats(player)
	Net.get("Fx"):FireAllClients({ kind = "death", x = state.body.x, y = state.body.y })
	Net.get("Notify"):FireClient(player, { text = "لقد مِتّ! " .. (source or ""), color = { 220, 70, 70 }, big = true })
end

function PlayerService.respawn(player: Player)
	local state = states[player]
	if not state then return end
	if state.dead and os.clock() < state.respawnAt then return end

	state.dead = false
	state.hp = state.maxHp
	state.mana = state.maxMana
	state.food = math.max(state.food, 45)
	state.body.x = state.spawnX
	state.body.y = state.spawnY
	state.body.vx, state.body.vy = 0, 0
	table.clear(state.buffs)

	Net.get("Respawn"):FireClient(player, state.body.x, state.body.y)
	PlayerService.syncStats(player)
end

function PlayerService.heal(player: Player, amount: number)
	local state = states[player]
	if not state or state.dead then return end
	state.hp = math.min(state.maxHp, state.hp + amount)
	Net.get("Hit"):FireClient(player, { kind = "heal", x = state.body.x, y = state.body.y, amount = amount })
	PlayerService.syncStats(player)
end

-- ===== استخدام العناصر =====

local function useConsumable(player: Player, state: PlayerState, item: Items.Item, slotIndex: number): boolean
	local agg = Buffs.aggregate(state.buffs)
	if item.heal and item.heal > 0 and item.buff == "potion_sickness" and agg.blockPotion then
		Net.get("Notify"):FireClient(player, { text = "ما زلت مُجهداً من الجرعة السابقة", color = { 200, 160, 200 } })
		return false
	end

	local used = false
	if item.heal then
		state.hp = math.min(state.maxHp, state.hp + item.heal)
		used = true
	end
	if item.restoreMana then
		state.mana = math.min(state.maxMana, state.mana + item.restoreMana)
		used = true
	end
	if item.food then
		state.food = math.min(Config.FOOD_MAX, state.food + item.food)
		state.buffs.well_fed = math.max(state.buffs.well_fed or 0, 120)
		used = true
	end
	if item.buff then
		state.buffs[item.buff] = math.max(state.buffs[item.buff] or 0, item.buffTime or 60)
		used = true
	end

	if item.id == "life_crystal" then
		if state.maxHp >= 300 then
			Net.get("Notify"):FireClient(player, { text = "بلغت الحد الأقصى للحياة", color = { 240, 120, 140 } })
			return false
		end
		state.maxHp = math.min(300, state.maxHp + 20)
		state.hp = math.min(state.maxHp, state.hp + 20)
		used = true
	elseif item.id == "mana_crystal" then
		if state.maxMana >= 200 then
			Net.get("Notify"):FireClient(player, { text = "بلغت الحد الأقصى للمانا", color = { 140, 160, 250 } })
			return false
		end
		state.maxMana = math.min(200, state.maxMana + 20)
		state.mana = state.maxMana
		used = true
	end

	if used then
		Inventory.removeFromSlot(state.slots, slotIndex, 1)
		PlayerService.syncInventory(player)
		PlayerService.syncStats(player)
		Net.get("Fx"):FireAllClients({ kind = "consume", x = state.body.x, y = state.body.y, item = item.id })
	end
	return used
end

local function useSpecial(player: Player, state: PlayerState, item: Items.Item, slotIndex: number): boolean
	if item.id == "magic_mirror" or item.id == "recall_stone" then
		state.body.x = state.spawnX
		state.body.y = state.spawnY
		state.body.vx, state.body.vy = 0, 0
		Net.get("Respawn"):FireClient(player, state.body.x, state.body.y)
		Net.get("Fx"):FireAllClients({ kind = "teleport", x = state.body.x, y = state.body.y })
		if item.id == "recall_stone" then
			Inventory.removeFromSlot(state.slots, slotIndex, 1)
			PlayerService.syncInventory(player)
		end
		return true
	end

	if item.summon then
		if item.nightOnly and not Services.Time.isNight() then
			Net.get("Notify"):FireClient(player, { text = "يُستخدم ليلاً فقط", color = { 200, 120, 200 } })
			return false
		end
		if Services.Entity.bossActive() then
			Net.get("Notify"):FireClient(player, { text = "هناك زعيم حيّ بالفعل!", color = { 220, 90, 90 } })
			return false
		end
		Inventory.removeFromSlot(state.slots, slotIndex, 1)
		PlayerService.syncInventory(player)
		Services.Entity.spawnBoss(item.summon, state.body.x, state.body.y - 14)
		return true
	end

	return false
end

local function attack(player: Player, state: PlayerState, aimX: number, aimY: number)
	local stack = state.slots[state.hotbar]
	local item = if stack then Items.get(stack.id) else nil
	local now = os.clock()

	local damage = 6
	local useTime = 0.35
	local knockback = 3
	local crit = 0.03

	if item then
		damage = item.damage or damage
		useTime = item.useTime or useTime
		knockback = item.knockback or knockback
		crit = item.crit or crit
	end

	if now - state.lastAttack < useTime * 0.85 then return end
	state.lastAttack = now

	local dx, dy = aimX - state.body.x, aimY - state.body.y
	local len = math.max(0.001, math.sqrt(dx * dx + dy * dy))
	dx, dy = dx / len, dy / len
	state.facing = if dx >= 0 then 1 else -1

	-- سلاح بعيد المدى
	if item and item.ranged then
		local ammoSlot, ammoId = nil, nil
		for i = 1, Config.INV_SLOTS do
			local candidate = state.slots[i]
			if candidate then
				local candidateItem = Items.get(candidate.id)
				if candidateItem and candidateItem.ammo == item.ranged then
					ammoSlot, ammoId = i, candidate.id
					break
				end
			end
		end
		if not ammoSlot or not ammoId then
			Net.get("Notify"):FireClient(player, { text = "لا توجد ذخيرة", color = { 220, 180, 90 } })
			return
		end
		local ammoItem = Items.get(ammoId)
		Inventory.removeFromSlot(state.slots, ammoSlot, 1)
		PlayerService.syncInventory(player)

		local speed = item.shootSpeed or 34
		Services.Entity.spawnProjectile(
			ammoId,
			state.body.x + dx * 1.2,
			state.body.y + dy * 1.2 - 0.3,
			dx * speed,
			dy * speed,
			damage + ((ammoItem and ammoItem.damage) or 0),
			knockback,
			player
		)
		return
	end

	-- سلاح سحري
	if item and item.magic then
		local cost = item.mana or 0
		if state.mana < cost then
			Net.get("Notify"):FireClient(player, { text = "المانا غير كافية", color = { 120, 150, 250 } })
			return
		end
		state.mana -= cost
		PlayerService.syncStats(player)
		local speed = item.shootSpeed or 30
		Services.Entity.spawnProjectile(
			item.magic,
			state.body.x + dx * 1.2,
			state.body.y + dy * 1.2 - 0.3,
			dx * speed,
			dy * speed,
			damage,
			knockback,
			player
		)
		return
	end

	-- ضربة قريبة
	local reach = 3.0
	local hitX = state.body.x + dx * reach * 0.6
	local hitY = state.body.y + dy * reach * 0.6
	local isCrit = math.random() < crit
	local finalDamage = if isCrit then damage * 2 else damage

	Services.Entity.meleeHit(player, hitX, hitY, reach, finalDamage, knockback, dx, dy, isCrit)
	Net.get("Fx"):FireAllClients({
		kind = "swing", x = state.body.x, y = state.body.y,
		dx = dx, dy = dy, item = if item then item.id else "hand", player = player.UserId,
	})
end

local function handleUseItem(player: Player, mode: string, aimX: number, aimY: number)
	local state = states[player]
	if not state or state.dead then return end
	if type(aimX) ~= "number" or type(aimY) ~= "number" then return end
	if Util.dist(state.body.x, state.body.y, aimX, aimY) > 60 then return end

	state.aimX, state.aimY = aimX, aimY

	if mode == "attack" then
		attack(player, state, aimX, aimY)
		return
	end

	if mode == "use" then
		local stack = state.slots[state.hotbar]
		if not stack then return end
		local item = Items.get(stack.id)
		if not item then return end
		local now = os.clock()
		if now - state.lastUse < (item.useTime or 0.4) then return end
		state.lastUse = now

		if item.cat == "consumable" then
			useConsumable(player, state, item, state.hotbar)
		elseif item.cat == "misc" then
			useSpecial(player, state, item, state.hotbar)
		end
	end
end

-- ===== أفعال المخزون =====

local function handleInvAction(player: Player, action: string, a: any, b: any)
	local state = states[player]
	if not state then return end

	if action == "hotbar" then
		if type(a) == "number" and a >= 1 and a <= Config.HOTBAR then
			state.hotbar = math.floor(a)
		end
		return
	end

	if action == "swap" then
		if type(a) ~= "number" or type(b) ~= "number" then return end
		a, b = math.floor(a), math.floor(b)
		if a < 1 or a > Config.INV_SLOTS or b < 1 or b > Config.INV_SLOTS then return end
		Inventory.swap(state.slots, a, b)
		PlayerService.syncInventory(player)
		return
	end

	if action == "drop" then
		if type(a) ~= "number" then return end
		a = math.floor(a)
		if a < 1 or a > Config.INV_SLOTS then return end
		local stack = state.slots[a]
		if not stack then return end
		local amount = if b == "all" then stack.n else 1
		local id = stack.id
		local taken = Inventory.removeFromSlot(state.slots, a, amount)
		if taken > 0 then
			Services.Entity.spawnItem(
				state.body.x + state.facing * 1.2,
				state.body.y - 0.5,
				id, taken, state.facing * 7, -6, player
			)
			PlayerService.syncInventory(player)
		end
		return
	end

	if action == "equip" then
		if type(a) ~= "number" then return end
		a = math.floor(a)
		local stack = state.slots[a]
		if not stack then return end
		local item = Items.get(stack.id)
		if not item or item.cat ~= "armor" or not item.slot then return end
		local current = state.armor[item.slot]
		state.armor[item.slot] = { id = stack.id, n = 1 }
		state.slots[a] = current
		PlayerService.syncInventory(player)
		PlayerService.syncStats(player)
		return
	end

	if action == "unequip" then
		if type(a) ~= "string" then return end
		local stack = state.armor[a]
		if not stack then return end
		if Inventory.add(state.slots, stack.id, 1) == 0 then
			state.armor[a] = nil
			PlayerService.syncInventory(player)
			PlayerService.syncStats(player)
		end
		return
	end

	if action == "sort" then
		local collected: { Inventory.Stack } = {}
		for i = Config.HOTBAR + 1, Config.INV_SLOTS do
			local stack = state.slots[i]
			if stack then
				table.insert(collected, stack)
				state.slots[i] = nil
			end
		end
		table.sort(collected, function(left, right)
			local li, ri = Items.get(left.id), Items.get(right.id)
			if not li or not ri then return false end
			if li.cat ~= ri.cat then return li.cat < ri.cat end
			if li.rarity ~= ri.rarity then return li.rarity > ri.rarity end
			return left.id < right.id
		end)
		for _, stack in collected do
			Inventory.add(state.slots, stack.id, stack.n)
		end
		PlayerService.syncInventory(player)
		return
	end
end

-- ===== الحركة =====

local function handlePlayerState(player: Player, x: number, y: number, vx: number, vy: number, facing: number, anim: string)
	local state = states[player]
	if not state or state.dead then return end
	if type(x) ~= "number" or type(y) ~= "number" then return end
	if x ~= x or y ~= y then return end -- NaN
	if not World.inBounds(math.floor(x), math.floor(y)) then return end

	local body = state.body
	local dt = math.max(1 / 60, 1 / Config.STATE_HZ)
	local agg = Buffs.aggregate(state.buffs)
	local maxStep = (Config.WALK_SPEED * agg.speed + Config.MAX_FALL) * dt * 2.2 + 2.5
	local delta = Util.dist(body.x, body.y, x, y)

	if delta > maxStep then
		-- حركة غير معقولة: أعد اللاعب لموضعه الأخير المعروف
		Net.get("Respawn"):FireClient(player, body.x, body.y)
		return
	end

	local world = Services.World.getWorld()
	if Physics.boxOverlapsSolid(world, x, y, body.w, body.h) then
		-- داخل الصخر: اسمح فقط إن كان الموضع السابق أيضاً داخل الصخر (خروج من حشر)
		if not Physics.boxOverlapsSolid(world, body.x, body.y, body.w, body.h) then
			Net.get("Respawn"):FireClient(player, body.x, body.y)
			return
		end
	end

	local prevY = body.y
	body.x, body.y = x, y
	body.vx = if type(vx) == "number" then vx else 0
	body.vy = if type(vy) == "number" then vy else 0
	state.facing = if facing == -1 then -1 else 1
	state.anim = if type(anim) == "string" then anim else "idle"

	-- ضرر السقوط يُحسب على الخادم من ذروة سرعة الهبوط المرصودة
	local falling = (y - prevY) / dt
	if falling > state.fallPeak then state.fallPeak = falling end

	local grounded = Physics.boxOverlapsSolid(world, body.x, body.y + 0.12, body.w, body.h)
	local inLiquid = Blocks.isLiquid(World.fg(world, math.floor(body.x), math.floor(body.y)))
	body.inLiquid = if inLiquid then World.fg(world, math.floor(body.x), math.floor(body.y)) else 0
	if (grounded or inLiquid) and state.fallPeak > 0 then
		local tiles = (state.fallPeak * state.fallPeak) / (2 * Config.GRAVITY)
		if tiles > Config.FALL_SAFE and not inLiquid then
			local damage = (tiles - Config.FALL_SAFE) * Config.FALL_DMG_PER_TILE
			PlayerService.damage(player, damage, "السقوط")
		end
		state.fallPeak = 0
	end
end

local function broadcastPeers()
	local payload = {}
	for player, state in states do
		table.insert(payload, {
			u = player.UserId,
			n = player.DisplayName,
			x = math.floor(state.body.x * 32) / 32,
			y = math.floor(state.body.y * 32) / 32,
			f = state.facing,
			hp = math.floor(state.hp / math.max(1, state.maxHp) * 100),
			d = state.dead,
			it = if state.slots[state.hotbar] then (state.slots[state.hotbar] :: Inventory.Stack).id else "",
			hd = if state.armor.head then (state.armor.head :: Inventory.Stack).id else "",
			ch = if state.armor.chest then (state.armor.chest :: Inventory.Stack).id else "",
		})
	end
	if #payload == 0 then return end
	Net.get("PeerState"):FireAllClients(payload)
end

-- ===== التحديث الدوري =====

local function tickPlayer(state: PlayerState, dt: number)
	local player = state.player
	if state.dead then
		return
	end

	local agg = Buffs.aggregate(state.buffs)
	local world = Services.World.getWorld()

	-- التعزيزات
	local expired = false
	for id, remaining in state.buffs do
		local left = remaining - dt
		if left <= 0 then
			state.buffs[id] = nil
			expired = true
		else
			state.buffs[id] = left
		end
	end

	-- الجوع
	state.food = math.max(0, state.food - Config.FOOD_DRAIN * dt)
	if state.food <= 0 then
		state.hp -= Config.STARVE_DPS * dt
	end

	-- تجدد الحياة
	if os.clock() - state.lastDamage > Config.HP_REGEN_DELAY and state.food > 10 then
		local regen = Config.HP_REGEN * (state.food / Config.FOOD_MAX) + agg.regen
		state.hp = math.min(state.maxHp, state.hp + regen * dt)
	elseif agg.regen > 0 then
		state.hp = math.min(state.maxHp, state.hp + agg.regen * dt)
	end

	-- المانا
	state.mana = math.min(state.maxMana, state.mana + Config.MANA_REGEN * dt)

	-- ضرر مستمر من التعزيزات السلبية
	if agg.dps > 0 then
		state.hp -= agg.dps * dt
	end

	-- ضرر البيئة (حمم، صبّار)
	local contact = Physics.contactDamage(world, state.body)
	if contact > 0 then
		PlayerService.damage(player, contact * dt * 6, "environment")
	end

	-- الغرق
	local headTile = World.fg(world, math.floor(state.body.x), math.floor(state.body.y - state.body.h / 2 + 0.3))
	if Blocks.isLiquid(headTile) and headTile == Blocks.ID.WATER then
		state.underwater += dt
		if state.underwater > Config.DROWN_TIME then
			state.hp -= Config.DROWN_DPS * dt
		end
	else
		state.underwater = math.max(0, state.underwater - dt * 3)
	end

	if state.hp <= 0 then
		PlayerService.kill(player, "البيئة")
		return
	end

	if expired then
		PlayerService.syncStats(player)
	end
end

-- ===== الحفظ =====

local function serialize(state: PlayerState): any
	local armor = {}
	for slot, stack in state.armor do
		if stack then armor[slot] = stack.id end
	end
	return {
		v = 1,
		inv = Inventory.serialize(state.slots),
		armor = armor,
		hp = math.floor(state.hp),
		maxHp = state.maxHp,
		maxMana = state.maxMana,
		food = math.floor(state.food),
		x = state.body.x,
		y = state.body.y,
		spawnX = state.spawnX,
		spawnY = state.spawnY,
		hotbar = state.hotbar,
		kills = state.kills,
		deaths = state.deaths,
		mined = state.blocksMined,
		playtime = os.time() - state.joinedAt,
	}
end

function PlayerService.save(player: Player)
	local state = states[player]
	if not state or not state.loaded then return end
	SaveService.savePlayer(player.UserId, serialize(state))
	state.dirty = false
end

-- ===== الانضمام والمغادرة =====

local STARTER_KIT: { { id: string, n: number } } = {
	{ id = "wood_pickaxe", n = 1 },
	{ id = "wood_axe", n = 1 },
	{ id = "wood_sword", n = 1 },
	{ id = "torch", n = 20 },
	{ id = "apple", n = 5 },
	{ id = "plank", n = 20 },
}

local function onPlayerAdded(player: Player)
	-- أمان: لو ظهرت شخصية روبلوكس (مثلاً لاعب دخل قبل تعطيل الظهور التلقائي)
	-- فأزلها — اللعبة ثنائية الأبعاد بالكامل ولا تستعمل الشخصيات.
	player.CharacterAdded:Connect(function(character)
		task.defer(function()
			if character and character.Parent then character:Destroy() end
		end)
	end)
	if player.Character then
		player.Character:Destroy()
	end

	local spawnX, spawnY = Services.World.getSpawn()
	local state: PlayerState = {
		player = player,
		body = Physics.newBody(spawnX, spawnY, Config.PLAYER_W, Config.PLAYER_H),
		slots = Inventory.new(),
		armor = {},
		hotbar = 1,
		hp = Config.BASE_HP,
		maxHp = Config.BASE_HP,
		mana = Config.BASE_MANA,
		maxMana = Config.BASE_MANA,
		food = Config.FOOD_MAX,
		buffs = {},
		dead = false,
		respawnAt = 0,
		spawnX = spawnX,
		spawnY = spawnY,
		lastDamage = 0,
		lastAttack = 0,
		lastUse = 0,
		facing = 1,
		anim = "idle",
		fallPeak = 0,
		aimX = spawnX,
		aimY = spawnY,
		underwater = 0,
		kills = 0,
		deaths = 0,
		blocksMined = 0,
		joinedAt = os.time(),
		loaded = false,
		dirty = false,
	} :: any
	states[player] = state

	-- حمّل البيانات المحفوظة
	local saved = SaveService.loadPlayer(player.UserId)
	if type(saved) == "table" then
		state.slots = Inventory.deserialize(saved.inv)
		if type(saved.armor) == "table" then
			for slot, id in saved.armor do
				if type(id) == "string" and Items.get(id) then
					state.armor[slot] = { id = id, n = 1 }
				end
			end
		end
		state.maxHp = math.clamp(tonumber(saved.maxHp) or Config.BASE_HP, Config.BASE_HP, 300)
		state.maxMana = math.clamp(tonumber(saved.maxMana) or Config.BASE_MANA, Config.BASE_MANA, 200)
		state.hp = math.clamp(tonumber(saved.hp) or state.maxHp, 1, state.maxHp)
		state.mana = state.maxMana
		state.food = math.clamp(tonumber(saved.food) or Config.FOOD_MAX, 0, Config.FOOD_MAX)
		state.hotbar = math.clamp(math.floor(tonumber(saved.hotbar) or 1), 1, Config.HOTBAR)
		state.kills = tonumber(saved.kills) or 0
		state.deaths = tonumber(saved.deaths) or 0
		state.blocksMined = tonumber(saved.mined) or 0
		if type(saved.spawnX) == "number" then
			state.spawnX = saved.spawnX
			state.spawnY = saved.spawnY
		end
		if type(saved.x) == "number" and type(saved.y) == "number" then
			state.body.x = math.clamp(saved.x, 2, Config.WORLD_W - 2)
			state.body.y = math.clamp(saved.y, 2, Config.WORLD_H - 2)
		end
	else
		for _, entry in STARTER_KIT do
			Inventory.add(state.slots, entry.id, entry.n)
		end
	end
	state.loaded = true

	-- تأكد من تحميل تعديلات منطقة الظهور قبل إرسال Hello
	Services.World.ensureRegionAt(math.floor(state.body.x), math.floor(state.body.y))

	Net.get("Hello"):FireClient(player, {
		seed = Services.World.getSeed(),
		x = state.body.x,
		y = state.body.y,
		spawnX = state.spawnX,
		spawnY = state.spawnY,
		worldW = Config.WORLD_W,
		worldH = Config.WORLD_H,
		userId = player.UserId,
	})
	PlayerService.syncInventory(player)
	PlayerService.syncStats(player)
	Services.Time.broadcast(player)
end

local function onPlayerRemoving(player: Player)
	PlayerService.save(player)
	states[player] = nil
end

function PlayerService.start()
	Net.get("PlayerState").OnServerEvent:Connect(handlePlayerState)
	Net.get("InvAction").OnServerEvent:Connect(handleInvAction)
	Net.get("UseItem").OnServerEvent:Connect(handleUseItem)
	Net.get("Respawn").OnServerEvent:Connect(function(player)
		PlayerService.respawn(player)
	end)

	Players.PlayerAdded:Connect(function(player)
		local ok, err = pcall(onPlayerAdded, player)
		if not ok then
			warn("[PlayerService] فشل تجهيز اللاعب: " .. tostring(err))
		end
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- التحديث الدوري
	local accumulator = 0
	local statsTimer = 0
	local peerTimer = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.1 then
			for _, state in states do
				tickPlayer(state, accumulator)
			end
			accumulator = 0
		end

		statsTimer += dt
		if statsTimer >= 0.5 then
			statsTimer = 0
			for player in states do
				PlayerService.syncStats(player)
			end
		end

		peerTimer += dt
		if peerTimer >= 1 / Config.STATE_HZ then
			peerTimer = 0
			broadcastPeers()
		end
	end)

	-- حفظ دوري
	task.spawn(function()
		while true do
			task.wait(Config.AUTOSAVE)
			for player, state in states do
				if state.dirty then
					pcall(PlayerService.save, player)
					task.wait(0.2)
				end
			end
		end
	end)

	game:BindToClose(function()
		for player in states do
			pcall(PlayerService.save, player)
		end
	end)
end

return PlayerService
