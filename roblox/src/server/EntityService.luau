--!strict
--[[
	EntityService — كل ما يتحرك في العالم عدا اللاعبين:
	الوحوش، الأغراض الساقطة، المقذوفات، والزعماء.

	المحاكاة كاملة على الخادم بمعدل 20 مرة/ثانية، والبثّ 14 مرة/ثانية
	للاعبين القريبين فقط، مع استيفاء (interpolation) على العميل.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Blocks = require(Shared.Blocks)
local Config = require(Shared.Config)
local Inventory = require(Shared.Inventory)
local Items = require(Shared.Items)
local Mobs = require(Shared.Mobs)
local Net = require(Shared.Net)
local Physics = require(Shared.Physics)
local Upgrades = require(Shared.Upgrades)
local Util = require(Shared.Util)
local World = require(Shared.World)
local WorldGen = require(Shared.WorldGen)

local Services = require(script.Parent.Services)

local EntityService = {}

export type Entity = {
	id: number,
	kind: string, -- mob | item | proj
	type: string,
	body: Physics.Body,
	hp: number,
	maxHp: number,
	def: Mobs.MobDef?,
	facing: number,
	anim: string,
	age: number,
	life: number,
	target: Player?,
	attackCd: number,
	jumpCd: number,
	wander: number,
	owner: Player?,
	damage: number,
	knockback: number,
	pierce: number,
	hitList: { [number]: boolean },
	itemId: string?,
	itemUpgrade: Upgrades.Upgrade?,
	count: number,
	pickupDelay: number,
	boss: boolean,
	phase: number,
	stateTimer: number,
	moveDir: number,
	dead: boolean,
}

local entities: { [number]: Entity } = {}
local nextId = 1
local bossId: number? = nil
local spawnTimer = 0

local function world(): World.World
	return Services.World.getWorld()
end

-- ===== إنشاء الكيانات =====

local function register(entity: Entity): Entity
	entities[entity.id] = entity
	return entity
end

local function newEntity(kind: string, typeId: string, x: number, y: number, w: number, h: number): Entity
	local id = nextId
	nextId += 1
	return {
		id = id,
		kind = kind,
		type = typeId,
		body = Physics.newBody(x, y, w, h),
		hp = 1,
		maxHp = 1,
		def = nil,
		facing = 1,
		anim = "idle",
		age = 0,
		life = math.huge,
		target = nil,
		attackCd = 0,
		jumpCd = 0,
		wander = 0,
		owner = nil,
		damage = 0,
		knockback = 0,
		pierce = 0,
		hitList = {},
		itemId = nil,
		itemUpgrade = nil,
		count = 1,
		pickupDelay = 0,
		boss = false,
		phase = 1,
		stateTimer = 0,
		moveDir = 1,
		dead = false,
	}
end

function EntityService.spawnMob(typeId: string, x: number, y: number, hpScale: number?): Entity?
	local def = Mobs.get(typeId)
	if not def then return nil end
	local entity = newEntity("mob", typeId, x, y, def.w, def.h)
	entity.def = def
	entity.maxHp = math.floor(def.hp * (hpScale or 1))
	entity.hp = entity.maxHp
	entity.damage = def.damage
	entity.boss = def.boss == true
	entity.body.stepUp = true
	return register(entity)
end

function EntityService.spawnBoss(typeId: string, x: number, y: number)
	if bossId then return end
	local playerCount = math.max(1, #Players:GetPlayers())
	local entity = EntityService.spawnMob(typeId, x, y, 1 + (playerCount - 1) * 0.55)
	if not entity then return end
	bossId = entity.id
	local def = entity.def
	Net.get("Boss"):FireAllClients({
		active = true, id = entity.id,
		name = if def then def.name else "زعيم",
		hp = entity.hp, maxHp = entity.maxHp,
	})
	Net.get("Notify"):FireAllClients({
		text = ((def and def.name) or "زعيم") .. " استيقظ!",
		color = { 220, 60, 70 }, big = true,
	})
end

function EntityService.bossActive(): boolean
	return bossId ~= nil
end

function EntityService.spawnItem(x: number, y: number, itemId: string, count: number, vx: number?, vy: number?, owner: Player?, upgrade: Upgrades.Upgrade?): Entity?
	if not Items.get(itemId) or count <= 0 then return nil end

	-- ادمج مع غرض قريب من النوع نفسه (لا ندمج المطوّر أبداً)
	for _, other in entities do
		if other.kind == "item" and other.itemId == itemId and not other.dead
			and other.itemUpgrade == nil and upgrade == nil then
			if Util.dist2(other.body.x, other.body.y, x, y) < 9 then
				local max = Items.maxStack(itemId)
				if other.count + count <= max then
					other.count += count
					return other
				end
			end
		end
	end

	local entity = newEntity("item", itemId, x, y, 0.7, 0.7)
	entity.itemId = itemId
	entity.itemUpgrade = upgrade
	entity.count = count
	entity.life = Config.ITEM_DESPAWN
	entity.pickupDelay = if owner then Config.PICKUP_DELAY * 2 else Config.PICKUP_DELAY
	entity.owner = owner
	entity.body.vx = vx or (math.random() - 0.5) * 5
	entity.body.vy = vy or -6
	return register(entity)
end

function EntityService.spawnProjectile(typeId: string, x: number, y: number, vx: number, vy: number, damage: number, knockback: number, owner: Player?): Entity?
	local def = Mobs.projectiles[typeId]
	if not def then return nil end
	local entity = newEntity("proj", typeId, x, y, def.w, def.h)
	entity.body.vx = vx
	entity.body.vy = vy
	entity.body.stepUp = false
	entity.damage = damage
	entity.knockback = knockback
	entity.pierce = def.pierce
	entity.life = def.life
	entity.owner = owner
	entity.facing = if vx >= 0 then 1 else -1
	return register(entity)
end

-- هل يشغل وحش هذه البلاطة؟ (لمنع البناء داخله)
function EntityService.blockedBy(tx: number, ty: number): boolean
	for _, entity in entities do
		if entity.kind == "mob" and not entity.dead then
			local body = entity.body
			if math.abs(body.x - (tx + 0.5)) < (body.w / 2 + 0.5)
				and math.abs(body.y - (ty + 0.5)) < (body.h / 2 + 0.5) then
				return true
			end
		end
	end
	return false
end

-- ===== الضرر =====

local function dropLoot(entity: Entity)
	local def = entity.def
	if not def then return end
	for _, drop in def.drops do
		if math.random() <= drop.chance then
			local count = math.random(drop.min, drop.max)
			if count > 0 then
				EntityService.spawnItem(entity.body.x, entity.body.y, drop.id, count)
			end
		end
	end
	local coins = math.random(def.coins.min, def.coins.max)
	if coins > 0 then
		EntityService.spawnItem(entity.body.x, entity.body.y, "coin", coins)
	end
end

function EntityService.damageMob(entity: Entity, amount: number, kbx: number, kby: number, byPlayer: Player?, crit: boolean?)
	if entity.dead or entity.kind ~= "mob" then return end
	local def = entity.def
	local defense = if def then def.defense else 0
	local final = math.max(1, amount - defense * 0.5)
	entity.hp -= final

	local resist = if def then def.knockbackResist else 0
	entity.body.vx += kbx * (1 - resist)
	entity.body.vy += kby * (1 - resist)

	Net.get("Hit"):FireAllClients({
		kind = "mob", x = entity.body.x, y = entity.body.y - entity.body.h / 2,
		amount = math.floor(final + 0.5), crit = crit == true, id = entity.id,
	})

	if entity.boss and bossId == entity.id then
		Net.get("Boss"):FireAllClients({
			active = true, id = entity.id,
			name = if def then def.name else "زعيم",
			hp = math.max(0, entity.hp), maxHp = entity.maxHp,
		})
	end

	if entity.hp <= 0 then
		entity.dead = true
		dropLoot(entity)
		Net.get("Fx"):FireAllClients({ kind = "mob_death", x = entity.body.x, y = entity.body.y, mob = entity.type })

		if byPlayer then
			local state = Services.Player.get(byPlayer)
			if state then
				state.kills += 1
			end
		end

		if entity.boss and bossId == entity.id then
			bossId = nil
			Net.get("Boss"):FireAllClients({ active = false })
			Net.get("Notify"):FireAllClients({
				text = ((def and def.name) or "الزعيم") .. " هُزم!",
				color = { 120, 230, 140 }, big = true,
			})
		end
	end
end

-- ضربة قريبة من لاعب
-- يُعيد مجموع الضرر الموقع (يحتاجه امتصاص الحياة في PlayerService)
function EntityService.meleeHit(player: Player, hx: number, hy: number, reach: number, damage: number, knockback: number, dx: number, dy: number, crit: boolean): number
	local hit = false
	local dealt = 0
	for _, entity in entities do
		if entity.kind == "mob" and not entity.dead then
			local body = entity.body
			if Util.dist(body.x, body.y, hx, hy) <= reach + math.max(body.w, body.h) / 2 then
				EntityService.damageMob(entity, damage, dx * knockback * 3, dy * knockback * 1.4 - 5, player, crit)
				dealt += damage
				hit = true
			end
		end
	end

	-- الضربة تكسر خيوط العنكبوت والنباتات الهشة أمام اللاعب
	if not hit then
		local tx, ty = math.floor(hx), math.floor(hy)
		local id = World.fg(world(), tx, ty)
		local block = Blocks.get(id)
		if block.fragile and id ~= Blocks.ID.AIR then
			Services.World.setTile(tx, ty, Blocks.ID.AIR, World.bg(world(), tx, ty))
			local drop = Items.fromBlock(id)
			if drop then EntityService.spawnItem(tx + 0.5, ty + 0.5, drop, 1) end
		end
	end

	return dealt
end

-- ===== الذكاء الاصطناعي =====

local function nearestPlayer(x: number, y: number, maxDist: number): (Player?, number)
	local best: Player? = nil
	local bestDist = maxDist
	for player, state in Services.Player.all() do
		if not state.dead then
			local d = Util.dist(x, y, state.body.x, state.body.y)
			if d < bestDist then
				best = player
				bestDist = d
			end
		end
	end
	return best, bestDist
end

local function tryAttackPlayer(entity: Entity, dt: number)
	entity.attackCd -= dt
	if entity.attackCd > 0 then return end
	local def = entity.def
	if not def then return end

	for player, state in Services.Player.all() do
		if not state.dead then
			local body = state.body
			if math.abs(body.x - entity.body.x) < (body.w + entity.body.w) / 2 + 0.2
				and math.abs(body.y - entity.body.y) < (body.h + entity.body.h) / 2 + 0.2 then
				entity.attackCd = def.attackCd
				local dir = Util.sign(body.x - entity.body.x)
				if dir == 0 then dir = entity.facing end
				Services.Player.damage(player, entity.damage, def.name, dir * 9, -8)

				-- صفة «شائك» على الدرع ترتدّ جزءاً من الضرر
				local thorns = Upgrades.armorBonus(state.armor).thorns
				if thorns > 0 then
					EntityService.damageMob(entity, entity.damage * thorns, -dir * 4, -3, player, false)
				end
				return
			end
		end
	end
end

local function aiWalker(entity: Entity, dt: number, climb: boolean)
	local def = entity.def
	if not def then return end
	local target = nearestPlayer(entity.body.x, entity.body.y, def.detect)
	local body = entity.body

	if target then
		local state = Services.Player.get(target)
		if state then
			local dir = Util.sign(state.body.x - body.x)
			entity.facing = if dir == 0 then entity.facing else dir
			body.vx = Util.approach(body.vx, dir * def.speed, 40 * dt)

			-- اقفز فوق العوائق أو الفجوات
			entity.jumpCd -= dt
			local aheadX = math.floor(body.x + dir * (body.w / 2 + 0.6))
			local feetY = math.floor(body.y + body.h / 2 - 0.1)
			local blockedAhead = Blocks.isSolid(World.fg(world(), aheadX, feetY))
			local gapAhead = not Blocks.isSolid(World.fg(world(), aheadX, feetY + 1))
			local higher = state.body.y < body.y - 2

			if body.onGround and entity.jumpCd <= 0 and (blockedAhead or gapAhead or higher) then
				body.vy = -def.jump
				entity.jumpCd = 0.45
			end

			-- العناكب تتسلق الجدران
			if climb and blockedAhead and not body.onGround then
				body.vy = math.min(body.vy, -def.speed * 0.7)
			end
		end
	else
		-- تجوال
		entity.wander -= dt
		if entity.wander <= 0 then
			entity.wander = math.random(120, 320) / 100
			entity.moveDir = if math.random() < 0.5 then -1 else 1
			if math.random() < 0.3 then entity.moveDir = 0 end
		end
		body.vx = Util.approach(body.vx, entity.moveDir * def.speed * 0.4, 20 * dt)
		if entity.moveDir ~= 0 then entity.facing = entity.moveDir end
	end

	entity.anim = if math.abs(body.vx) > 0.5 then "walk" else "idle"
	tryAttackPlayer(entity, dt)
end

local function aiJumper(entity: Entity, dt: number)
	local def = entity.def
	if not def then return end
	local body = entity.body
	local target = nearestPlayer(body.x, body.y, def.detect)

	entity.jumpCd -= dt
	if body.onGround then
		body.vx = Util.approach(body.vx, 0, 30 * dt)
		if entity.jumpCd <= 0 then
			entity.jumpCd = math.random(80, 170) / 100
			local dir = entity.moveDir
			if target then
				local state = Services.Player.get(target)
				if state then dir = Util.sign(state.body.x - body.x) end
			else
				dir = if math.random() < 0.5 then -1 else 1
			end
			if dir == 0 then dir = 1 end
			entity.facing = dir
			entity.moveDir = dir
			body.vy = -def.jump
			body.vx = dir * def.speed
		end
	end

	entity.anim = if body.onGround then "idle" else "jump"
	tryAttackPlayer(entity, dt)
end

local function aiFlyer(entity: Entity, dt: number)
	local def = entity.def
	if not def then return end
	local body = entity.body -- الطيران: الجاذبية معطّلة في Physics.step عبر noGravity
	local target, dist = nearestPlayer(body.x, body.y, def.detect)

	if target then
		local state = Services.Player.get(target)
		if state then
			local dx = state.body.x - body.x
			local dy = (state.body.y - 0.5) - body.y
			local len = math.max(0.001, math.sqrt(dx * dx + dy * dy))
			local wobble = math.sin(entity.age * 3.2) * 0.35
			body.vx = Util.approach(body.vx, dx / len * def.speed, 30 * dt)
			body.vy = Util.approach(body.vy, dy / len * def.speed + wobble * def.speed, 30 * dt)
			entity.facing = if dx >= 0 then 1 else -1

			-- المقذوفات (عفريت الحمم)
			if def.projectile then
				entity.attackCd -= dt
				if entity.attackCd <= 0 and dist < def.detect * 0.8
					and Physics.lineOfSight(world(), body.x, body.y, state.body.x, state.body.y) then
					entity.attackCd = def.attackCd
					local speed = 22
					EntityService.spawnProjectile(def.projectile, body.x, body.y, dx / len * speed, dy / len * speed, def.damage, 4, nil)
				end
			end
		end
	else
		entity.wander -= dt
		if entity.wander <= 0 then
			entity.wander = math.random(100, 260) / 100
			entity.moveDir = if math.random() < 0.5 then -1 else 1
		end
		body.vx = Util.approach(body.vx, entity.moveDir * def.speed * 0.35, 12 * dt)
		body.vy = Util.approach(body.vy, math.sin(entity.age * 1.6) * 2.5, 12 * dt)
		entity.facing = entity.moveDir
	end

	entity.anim = "fly"
	tryAttackPlayer(entity, dt)
end

local function aiShooter(entity: Entity, dt: number)
	local def = entity.def
	if not def then return end
	local body = entity.body
	local target, dist = nearestPlayer(body.x, body.y, def.detect)

	if target then
		local state = Services.Player.get(target)
		if state then
			local dir = Util.sign(state.body.x - body.x)
			entity.facing = if dir == 0 then entity.facing else dir

			-- يحافظ على مسافة متوسطة
			local desired = 9
			if dist < desired - 2 then
				body.vx = Util.approach(body.vx, -dir * def.speed, 40 * dt)
			elseif dist > desired + 3 then
				body.vx = Util.approach(body.vx, dir * def.speed, 40 * dt)
			else
				body.vx = Util.approach(body.vx, 0, 40 * dt)
			end

			entity.jumpCd -= dt
			local aheadX = math.floor(body.x + Util.sign(body.vx) * (body.w / 2 + 0.6))
			local feetY = math.floor(body.y + body.h / 2 - 0.1)
			if body.onGround and entity.jumpCd <= 0 and Blocks.isSolid(World.fg(world(), aheadX, feetY)) then
				body.vy = -def.jump
				entity.jumpCd = 0.5
			end

			entity.attackCd -= dt
			if entity.attackCd <= 0 and def.projectile
				and Physics.lineOfSight(world(), body.x, body.y - 0.5, state.body.x, state.body.y) then
				entity.attackCd = def.attackCd
				local dx = state.body.x - body.x
				local dy = state.body.y - body.y
				local len = math.max(0.001, math.sqrt(dx * dx + dy * dy))
				local speed = 26
				EntityService.spawnProjectile(def.projectile, body.x + dx / len, body.y - 0.4, dx / len * speed, dy / len * speed - 3, def.damage, 3, nil)
			end
		end
	else
		aiWalker(entity, dt, false)
		return
	end

	entity.anim = if math.abs(body.vx) > 0.5 then "walk" else "idle"
	tryAttackPlayer(entity, dt)
end

local function aiBoss(entity: Entity, dt: number)
	local def = entity.def
	if not def then return end
	local body = entity.body
	local target = nearestPlayer(body.x, body.y, 400)
	entity.stateTimer -= dt

	local hpPct = entity.hp / entity.maxHp
	local newPhase = if hpPct < 0.35 then 3 elseif hpPct < 0.7 then 2 else 1
	if newPhase ~= entity.phase then
		entity.phase = newPhase
		entity.stateTimer = 0
		Net.get("Fx"):FireAllClients({ kind = "boss_phase", x = body.x, y = body.y, phase = newPhase })
	end

	if not target then
		-- لا لاعبين: يختفي الزعيم
		body.vy = -8
		entity.life = math.min(entity.life, 6)
		return
	end

	local state = Services.Player.get(target)
	if not state then return end
	local dx = state.body.x - body.x
	local dy = state.body.y - body.y
	local len = math.max(0.001, math.sqrt(dx * dx + dy * dy))
	entity.facing = if dx >= 0 then 1 else -1

	local speed = def.speed * (1 + (entity.phase - 1) * 0.35)

	if entity.anim == "charge" then
		-- اندفاع مستقيم
		if entity.stateTimer <= 0 then
			entity.anim = "hover"
			entity.stateTimer = 2.2 - entity.phase * 0.35
		end
	elseif entity.stateTimer <= 0 then
		local roll = math.random()
		if roll < 0.45 then
			entity.anim = "charge"
			entity.stateTimer = 1.1
			body.vx = dx / len * speed * 2.1
			body.vy = dy / len * speed * 2.1
			Net.get("Fx"):FireAllClients({ kind = "boss_charge", x = body.x, y = body.y })
		elseif roll < 0.8 and entity.phase >= 2 then
			-- وابل مقذوفات
			for i = -2, 2 do
				local angle = math.atan2(dy, dx) + i * 0.18
				EntityService.spawnProjectile("blood_shot", body.x, body.y,
					math.cos(angle) * 24, math.sin(angle) * 24, def.damage * 0.7, 3, nil)
			end
			entity.anim = "hover"
			entity.stateTimer = 1.8
		else
			-- استدعاء أتباع
			if entity.phase >= 2 then
				for i = 1, 2 do
					EntityService.spawnMob("demon_eye", body.x + math.random(-4, 4), body.y + math.random(-3, 3))
				end
			end
			entity.anim = "hover"
			entity.stateTimer = 2.4
		end
	else
		-- تحويم حول اللاعب
		local orbit = math.sin(entity.age * 1.4) * 5
		local targetX = state.body.x - dx / len * 8
		local targetY = state.body.y - 9 + orbit
		body.vx = Util.approach(body.vx, (targetX - body.x) * 1.8, 60 * dt)
		body.vy = Util.approach(body.vy, (targetY - body.y) * 1.8, 60 * dt)
		body.vx = math.clamp(body.vx, -speed, speed)
		body.vy = math.clamp(body.vy, -speed, speed)
		entity.anim = "hover"
	end

	tryAttackPlayer(entity, dt)
end

-- ===== التحديث =====

local function updateMob(entity: Entity, dt: number)
	local def = entity.def
	if not def then return end

	if def.ai == "walker" then
		aiWalker(entity, dt, false)
	elseif def.ai == "climber" then
		aiWalker(entity, dt, true)
	elseif def.ai == "jumper" then
		aiJumper(entity, dt)
	elseif def.ai == "flyer" then
		aiFlyer(entity, dt)
	elseif def.ai == "shooter" then
		aiShooter(entity, dt)
	elseif def.ai == "boss" then
		aiBoss(entity, dt)
	end

	local flying = def.ai == "flyer" or def.ai == "boss"
	Physics.step(world(), entity.body, dt, {
		noGravity = flying,
		ignorePlatforms = flying,
	})

	if not flying then
		-- احتكاك أرضي
		if entity.body.onGround then
			entity.body.vx = Util.approach(entity.body.vx, 0, 12 * dt)
		end
	end

	-- ضرر البيئة (الحمم تؤذي غير سكان الجحيم)
	if def.layer ~= "hell" then
		local burn = Physics.contactDamage(world(), entity.body)
		if burn > 0 then
			entity.hp -= burn * dt * 4
			if entity.hp <= 0 then
				entity.dead = true
				dropLoot(entity)
			end
		end
	end

	-- الوحوش الليلية تحترق عند الفجر في العراء
	if def.flee and not Services.Time.isNight() then
		local surface = World.surfaceY(world(), math.floor(entity.body.x))
		if entity.body.y < surface then
			entity.hp -= 12 * dt
			if entity.hp <= 0 then
				entity.dead = true
				Net.get("Fx"):FireAllClients({ kind = "burn_away", x = entity.body.x, y = entity.body.y })
			end
		end
	end
end

local function updateItem(entity: Entity, dt: number)
	Physics.step(world(), entity.body, dt, {})
	if entity.body.onGround then
		entity.body.vx = Util.approach(entity.body.vx, 0, 22 * dt)
	end

	entity.pickupDelay -= dt
	if entity.pickupDelay > 0 then return end

	for player, state in Services.Player.all() do
		if not state.dead then
			local d = Util.dist(entity.body.x, entity.body.y, state.body.x, state.body.y)
			if d < Config.PICKUP_RANGE then
				local itemId = entity.itemId
				if itemId then
					local leftover
					if entity.itemUpgrade then
						-- غرض مطوّر: يحتاج خانة كاملة ولا يندمج
						local placed = Inventory.addStack(state.slots, {
							id = itemId, n = entity.count, up = entity.itemUpgrade,
						})
						leftover = if placed then 0 else entity.count
					else
						leftover = Inventory.add(state.slots, itemId, entity.count)
					end
					local picked = entity.count - leftover
					if picked > 0 then
						entity.count = leftover
						Services.Player.syncInventory(player)
						Net.get("Fx"):FireClient(player, {
							kind = "pickup", x = entity.body.x, y = entity.body.y,
							item = itemId, count = picked,
						})
						if leftover <= 0 then
							entity.dead = true
						end
					end
				end
				break
			elseif d < Config.PICKUP_RANGE * 3 then
				-- انجذاب نحو اللاعب
				local dx = state.body.x - entity.body.x
				local dy = state.body.y - entity.body.y
				local len = math.max(0.001, math.sqrt(dx * dx + dy * dy))
				entity.body.vx = Util.approach(entity.body.vx, dx / len * 14, 60 * dt)
				entity.body.vy = Util.approach(entity.body.vy, dy / len * 14, 60 * dt)
			end
		end
	end
end

local function updateProjectile(entity: Entity, dt: number)
	local def = Mobs.projectiles[entity.type]
	if not def then
		entity.dead = true
		return
	end

	local body = entity.body
	body.vy += def.gravity * dt
	body.x += body.vx * dt
	body.y += body.vy * dt
	entity.facing = if body.vx >= 0 then 1 else -1

	-- اصطدام بالبلاطات
	if Blocks.isSolid(World.fg(world(), math.floor(body.x), math.floor(body.y))) then
		entity.dead = true
		Net.get("Fx"):FireAllClients({ kind = "proj_hit", x = body.x, y = body.y, proj = entity.type })
		return
	end

	if not World.inBounds(math.floor(body.x), math.floor(body.y)) then
		entity.dead = true
		return
	end

	-- الإصابة
	if entity.owner then
		for _, other in entities do
			if other.kind == "mob" and not other.dead and not entity.hitList[other.id] then
				local ob = other.body
				if math.abs(ob.x - body.x) < (ob.w + body.w) / 2
					and math.abs(ob.y - body.y) < (ob.h + body.h) / 2 then
					entity.hitList[other.id] = true
					local dirX = Util.sign(body.vx)
					EntityService.damageMob(other, entity.damage, dirX * entity.knockback * 2.5, -4, entity.owner, false)
					if entity.type == "fire_arrow" then
						-- (تأثير الحرق يُحاكى كضرر إضافي فوري مبسّط)
						EntityService.damageMob(other, entity.damage * 0.4, 0, 0, entity.owner, false)
					end
					if entity.pierce > 0 then
						entity.pierce -= 1
					else
						entity.dead = true
						Net.get("Fx"):FireAllClients({ kind = "proj_hit", x = body.x, y = body.y, proj = entity.type })
						return
					end
				end
			end
		end
	else
		for player, state in Services.Player.all() do
			if not state.dead then
				local pb = state.body
				if math.abs(pb.x - body.x) < (pb.w + body.w) / 2
					and math.abs(pb.y - body.y) < (pb.h + body.h) / 2 then
					Services.Player.damage(player, entity.damage, "مقذوف", Util.sign(body.vx) * 6, -5)
					entity.dead = true
					Net.get("Fx"):FireAllClients({ kind = "proj_hit", x = body.x, y = body.y, proj = entity.type })
					return
				end
			end
		end
	end
end

-- ===== الظهور التلقائي =====

local function layerAt(y: number): string
	if y >= Config.HELL_Y then return "hell" end
	if y >= Config.CAVERN_Y then return "cavern" end
	if y >= Config.SURFACE + 40 then return "underground" end
	return "surface"
end

local function countMobs(): number
	local n = 0
	for _, entity in entities do
		if entity.kind == "mob" and not entity.dead and not entity.boss then n += 1 end
	end
	return n
end

local function trySpawnAround(state: any)
	local w = world()
	local seed = Services.World.getSeed()
	local px, py = math.floor(state.body.x), math.floor(state.body.y)

	for _ = 1, 8 do
		local angle = math.random() * math.pi * 2
		local radius = math.random(Config.MOB_SPAWN_MIN, Config.MOB_SPAWN_MAX)
		local x = px + math.floor(math.cos(angle) * radius)
		local y = py + math.floor(math.sin(angle) * radius * 0.7)

		if World.inBounds(x, y) and World.fg(w, x, y) == Blocks.ID.AIR then
			-- يجب أن يكون هناك مكان كافٍ
			if World.fg(w, x, y - 1) == Blocks.ID.AIR and World.fg(w, x, y - 2) == Blocks.ID.AIR then
				local layer = layerAt(y)
				local biome = WorldGen.biomeAt(seed, x)
				local night = Services.Time.isNight()
				local onGround = Blocks.isSolid(World.fg(w, x, y + 1))

				-- لا تظهر الوحوش في وضح النهار على السطح
				if layer == "surface" and not night then return end

				local candidates = {}
				for _, def in Mobs.list do
					if def.weight > 0 and not def.boss then
						local layerOk = def.layer == "any" or def.layer == layer
							or (def.layer == "underground" and (layer == "underground" or layer == "cavern"))
						local nightOk = not def.night or night
						local depthOk = not def.minDepth or y >= def.minDepth
						local biomeOk = true
						if def.biomes then
							biomeOk = false
							for _, b in def.biomes do
								if b == biome then
									biomeOk = true
									break
								end
							end
						end
						local moveOk = def.ai == "flyer" or onGround
						if layerOk and nightOk and depthOk and biomeOk and moveOk then
							table.insert(candidates, def)
						end
					end
				end

				if #candidates > 0 then
					local pick = Util.weightedPick(candidates :: any, math.random())
					if pick then
						local scale = 1
						if Services.Time.isBloodMoon() then scale = 1.5 end
						if y >= Config.CAVERN_Y then scale *= 1.15 end
						local mob = EntityService.spawnMob(pick.id, x + 0.5, y - pick.h / 2, scale)
						if mob and Services.Time.isBloodMoon() then
							mob.damage = math.floor(mob.damage * 1.3)
						end
						return
					end
				end
			end
		end
	end
end

local function spawnTick(dt: number)
	spawnTimer -= dt
	if spawnTimer > 0 then return end
	spawnTimer = Config.SPAWN_INTERVAL

	local players = Services.Player.all()
	local playerCount = 0
	for _ in players do playerCount += 1 end
	if playerCount == 0 then return end

	local cap = Config.MOB_CAP_PER_PLAYER * playerCount
	if Services.Time.isBloodMoon() then cap = math.floor(cap * 1.6) end
	if countMobs() >= cap then return end

	for _, state in players do
		if not state.dead then
			trySpawnAround(state)
		end
	end
end

-- ===== البثّ =====

local KIND_CODE = { mob = 1, item = 2, proj = 3 }

local function replicate()
	local packets: { [Player]: { any } } = {}
	for player in Services.Player.all() do
		packets[player] = {}
	end

	for _, entity in entities do
		if not entity.dead then
			local body = entity.body
			local packet = {
				i = entity.id,
				k = KIND_CODE[entity.kind],
				t = entity.type,
				x = math.floor(body.x * 32) / 32,
				y = math.floor(body.y * 32) / 32,
				f = entity.facing,
				a = entity.anim,
			}
			if entity.kind == "mob" then
				packet.h = math.floor(entity.hp / math.max(1, entity.maxHp) * 100)
			elseif entity.kind == "item" then
				packet.n = entity.count
			end

			for targetPlayer, state in Services.Player.all() do
				if math.abs(body.x - state.body.x) < 52 and math.abs(body.y - state.body.y) < 34 then
					local bucket = packets[targetPlayer]
					if bucket then table.insert(bucket, packet) end
				end
			end
		end
	end

	local remote = Net.get("Entities")
	for player, bucket in packets do
		remote:FireClient(player, bucket)
	end
end

-- ===== الحلقة الرئيسية =====

function EntityService.start()
	local accumulator = 0
	local replicateTimer = 0

	RunService.Heartbeat:Connect(function(frameDt)
		accumulator += frameDt
		local steps = 0
		while accumulator >= Config.MOB_TICK and steps < 4 do
			accumulator -= Config.MOB_TICK
			steps += 1
			local dt = Config.MOB_TICK

			local ok, err = pcall(function()
				for id, entity in entities do
					if entity.dead then
						entities[id] = nil
						continue
					end

					entity.age += dt
					entity.life -= dt
					if entity.life <= 0 then
						entity.dead = true
						if entity.boss and bossId == entity.id then
							bossId = nil
							Net.get("Boss"):FireAllClients({ active = false })
						end
						entities[id] = nil
						continue
					end

					if entity.kind == "mob" then
						updateMob(entity, dt)
					elseif entity.kind == "item" then
						updateItem(entity, dt)
					elseif entity.kind == "proj" then
						updateProjectile(entity, dt)
					end

					-- إزالة البعيدين جداً
					if entity.kind == "mob" and not entity.boss then
						local _, dist = nearestPlayer(entity.body.x, entity.body.y, 999)
						if dist > 95 then
							entities[id] = nil
						end
					end
				end

				spawnTick(dt)
			end)
			if not ok then
				warn("[EntityService] خطأ في المحاكاة: " .. tostring(err))
			end
		end

		replicateTimer += frameDt
		if replicateTimer >= 1 / Config.ENTITY_HZ then
			replicateTimer = 0
			local ok, err = pcall(replicate)
			if not ok then warn("[EntityService] خطأ في البثّ: " .. tostring(err)) end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		for _, entity in entities do
			if entity.owner == player then entity.owner = nil end
		end
	end)
end

function EntityService.count(): number
	local n = 0
	for _ in entities do n += 1 end
	return n
end

return EntityService
