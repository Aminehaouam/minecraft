--!strict
--[[
	Controller — الإدخال، تنبؤ الحركة محلياً، والتعدين/البناء.

	الحركة تُحاكى فوراً على العميل بنفس وحدة الفيزياء المشتركة، وتُرسل الحالة
	18 مرة/ثانية. الخادم يرفض المستحيل فقط، فتبقى الاستجابة فورية بلا غش سهل.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Blocks = require(Shared.Blocks)
local Buffs = require(Shared.Buffs)
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Mining = require(Shared.Mining)
local Net = require(Shared.Net)
local Physics = require(Shared.Physics)
local Upgrades = require(Shared.Upgrades)
local Util = require(Shared.Util)
local World = require(Shared.World)

local ClientWorld = require(script.Parent.ClientWorld)
local Renderer = require(script.Parent.Renderer)
local State = require(script.Parent.State)

local Controller = {}

local input = {
	left = false,
	right = false,
	jump = false,
	down = false,
	up = false,
	primary = false,
	secondary = false,
}

local jumpHeld = 0
local coyote = 0
local jumpBuffer = 0
local sendAccumulator = 0
local placeCooldown = 0
local attackCooldown = 0
local wallMode = false

local callbacks: { [string]: (...any) -> () } = {}

function Controller.on(event: string, fn: (...any) -> ())
	callbacks[event] = fn
end

local function fire(event: string, ...)
	local fn = callbacks[event]
	if fn then fn(...) end
end

function Controller.wallMode(): boolean
	return wallMode
end

-- ===== الإدخال =====

local KEY_MOVE = {
	[Enum.KeyCode.A] = "left", [Enum.KeyCode.Left] = "left",
	[Enum.KeyCode.D] = "right", [Enum.KeyCode.Right] = "right",
	[Enum.KeyCode.W] = "up", [Enum.KeyCode.Up] = "up",
	[Enum.KeyCode.S] = "down", [Enum.KeyCode.Down] = "down",
	[Enum.KeyCode.Space] = "jump",
}

local HOTKEYS = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9,
	[Enum.KeyCode.Zero] = 10,
}

function Controller.selectHotbar(index: number)
	if index < 1 or index > Config.HOTBAR then return end
	State.hotbar = index
	Net.get("InvAction"):FireServer("hotbar", index)
	fire("hotbar", index)
end

local function onInput(io: InputObject, processed: boolean)
	if processed then return end

	if io.UserInputType == Enum.UserInputType.Keyboard then
		local move = KEY_MOVE[io.KeyCode]
		if move then
			input[move] = true
			if move == "jump" then jumpBuffer = Config.JUMP_BUFFER end
			return
		end

		local hotkey = HOTKEYS[io.KeyCode]
		if hotkey then
			Controller.selectHotbar(hotkey)
			return
		end

		if io.KeyCode == Enum.KeyCode.E then
			fire("toggleInventory")
		elseif io.KeyCode == Enum.KeyCode.Q then
			Net.get("InvAction"):FireServer("drop", State.hotbar, if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then "all" else 1)
		elseif io.KeyCode == Enum.KeyCode.F then
			wallMode = not wallMode
			fire("wallMode", wallMode)
		elseif io.KeyCode == Enum.KeyCode.R then
			Net.get("Shop"):FireServer("open")
		elseif io.KeyCode == Enum.KeyCode.Escape then
			fire("closeAll")
		end
		return
	end

	if io.UserInputType == Enum.UserInputType.MouseButton1 then
		input.primary = true
	elseif io.UserInputType == Enum.UserInputType.MouseButton2 then
		input.secondary = true
	elseif io.UserInputType == Enum.UserInputType.MouseWheel then
		local delta = if io.Position.Z > 0 then -1 else 1
		Controller.selectHotbar(((State.hotbar - 1 + delta) % Config.HOTBAR) + 1)
	end
end

local function onInputEnded(io: InputObject)
	if io.UserInputType == Enum.UserInputType.Keyboard then
		local move = KEY_MOVE[io.KeyCode]
		if move then input[move] = false end
	elseif io.UserInputType == Enum.UserInputType.MouseButton1 then
		input.primary = false
		State.mining = nil
	elseif io.UserInputType == Enum.UserInputType.MouseButton2 then
		input.secondary = false
	end
end

-- أزرار اللمس للأجهزة المحمولة
function Controller.setTouch(action: string, down: boolean)
	if action == "left" or action == "right" or action == "jump" or action == "down" then
		input[action] = down
		if action == "jump" and down then jumpBuffer = Config.JUMP_BUFFER end
	elseif action == "primary" then
		input.primary = down
		if not down then State.mining = nil end
	elseif action == "secondary" then
		input.secondary = down
	end
end

-- ===== الحركة =====

-- GetMouseLocation يتجاهل شريط Roblox العلوي بينما واجهتنا تتجاهل الإزاحة
-- (IgnoreGuiInset)، فنضيف الإزاحة يدوياً وإلا انحرف التصويب رأسياً.
local function mousePosition(): (number, number)
	local pos = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	return Renderer.screenToWorld(pos.X + inset.X, pos.Y + inset.Y)
end

Controller.aimWorld = mousePosition

local function updateMovement(dt: number)
	local body = State.body
	local world = ClientWorld.get()
	local agg = Buffs.aggregate((function()
		local map = {}
		for _, buff in State.buffs do map[buff.id] = buff.t end
		return map
	end)())

	local moveDir = 0
	if input.left then moveDir -= 1 end
	if input.right then moveDir += 1 end

	local armorSpeed = Upgrades.armorBonus(State.armor).speed
	local speed = Config.WALK_SPEED * agg.speed * armorSpeed
	local accel = if body.onGround then Config.WALK_ACCEL else Config.AIR_ACCEL
	local inWater = body.inLiquid ~= 0

	if inWater then
		speed = Config.SWIM_SPEED * agg.speed * armorSpeed
		accel *= 0.6
	end

	if moveDir ~= 0 then
		body.vx = Util.approach(body.vx, moveDir * speed, accel * dt)
		State.facing = moveDir
	else
		local friction = if body.onGround then Config.GROUND_FRICTION else Config.AIR_FRICTION
		body.vx = Util.approach(body.vx, 0, friction * dt)
	end

	-- التسلّق
	local climbing = Physics.canClimb(world, body)
	if climbing then
		if input.up then
			body.vy = -Config.WALK_SPEED * 0.62
		elseif input.down then
			body.vy = Config.WALK_SPEED * 0.62
		else
			body.vy *= 0.45
		end
	end

	-- القفز
	if body.onGround then
		coyote = Config.COYOTE_TIME
	else
		coyote = math.max(0, coyote - dt)
	end
	jumpBuffer = math.max(0, jumpBuffer - dt)

	if input.jump and (inWater or climbing) then
		body.vy = -Config.SWIM_SPEED * 1.15
		jumpHeld = 0
	elseif jumpBuffer > 0 and coyote > 0 then
		body.vy = -Config.JUMP_VELOCITY * agg.jump
		jumpHeld = Config.JUMP_HOLD_TIME
		jumpBuffer = 0
		coyote = 0
		fire("sfx", "jump")
	elseif input.jump and jumpHeld > 0 then
		-- قفزة متغيرة الارتفاع
		jumpHeld -= dt
		body.vy -= Config.GRAVITY * 0.55 * dt
	else
		jumpHeld = 0
	end

	if not input.jump then jumpHeld = 0 end

	-- النزول عبر المنصات
	if input.down and body.onGround then
		body.dropThrough = 0.24
	end

	local wasAir = not body.onGround
	local fallVelocity = body.vy

	Physics.step(world, body, dt, {})

	-- ضرر السقوط (تنبؤي؛ الخادم يطبّق ضرره الخاص أيضاً عند اللزوم)
	if wasAir and body.onGround and fallVelocity > 0 then
		local tiles = (fallVelocity * fallVelocity) / (2 * Config.GRAVITY)
		if tiles > Config.FALL_SAFE and body.inLiquid == 0 then
			fire("sfx", "hurt")
			Renderer.shake(math.min(18, (tiles - Config.FALL_SAFE) * 1.5), 0.25)
		elseif fallVelocity > 12 then
			fire("sfx", "land")
		end
	end

	-- الرسوم المتحركة
	if not body.onGround then
		State.anim = if body.vy < 0 then "jump" else "fall"
	elseif math.abs(body.vx) > 0.6 then
		State.anim = "walk"
	else
		State.anim = "idle"
	end
	State.animTime += dt * math.max(1, math.abs(body.vx) / 3)

	-- حدود العالم السفلى
	if body.y > Config.WORLD_H - 4 then
		body.y = Config.WORLD_H - 4
		body.vy = 0
	end
end

-- ===== التعدين والبناء =====

local function targetTile(): (number?, number?, boolean)
	local wx, wy = mousePosition()
	local tx, ty = math.floor(wx), math.floor(wy)
	if not World.inBounds(tx, ty) then return nil, nil, false end
	local body = State.body
	local reach = Config.REACH + Upgrades.reachBonus(State.heldItem())
	local inRange = Util.dist(body.x, body.y, tx + 0.5, ty + 0.5) <= reach
	return tx, ty, inRange
end

local function currentMiningMultiplier(): number
	local map = {}
	for _, buff in State.buffs do map[buff.id] = buff.t end
	return Buffs.aggregate(map).mining * Upgrades.miningMultiplier(State.heldItem())
end

local function tryPlace(tx: number, ty: number): boolean
	local held = State.heldItem()
	if not held then return false end
	local item = Items.get(held.id)
	if not item or not item.place then return false end

	local world = ClientWorld.get()

	if wallMode then
		if not item.wall then return false end
		if World.bg(world, tx, ty) ~= Blocks.ID.AIR then return false end
	else
		if not Blocks.isReplaceable(World.fg(world, tx, ty)) then return false end
		-- لا تبنِ داخل نفسك
		local body = State.body
		local block = Blocks.get(item.place)
		if block.solid then
			if math.abs(body.x - (tx + 0.5)) < (body.w / 2 + 0.5)
				and math.abs(body.y - (ty + 0.5)) < (body.h / 2 + 0.5) then
				return false
			end
		end
	end

	if placeCooldown > 0 then return true end
	placeCooldown = 0.14

	Net.get("Edit"):FireServer("place", tx, ty, if wallMode then "wall" else "fg", State.hotbar)
	-- تنبؤ محلي فوري
	if wallMode then
		ClientWorld.predictSet(tx, ty, World.fg(world, tx, ty), item.place)
	else
		ClientWorld.predictSet(tx, ty, item.place, World.bg(world, tx, ty))
	end
	fire("sfx", "place")
	State.lastSwing = os.clock()
	return true
end

local function tryMine(tx: number, ty: number, dt: number): boolean
	local world = ClientWorld.get()
	local held = State.heldItem()
	local heldId = if held then held.id else nil

	local targetId
	if wallMode then
		local item = if heldId then Items.get(heldId) else nil
		if not item or item.tool ~= "hammer" then return false end
		targetId = World.bg(world, tx, ty)
		if targetId == Blocks.ID.AIR then return false end
	else
		targetId = World.fg(world, tx, ty)
		if targetId == Blocks.ID.AIR or Blocks.isLiquid(targetId) then return false end
	end

	local required = Mining.breakTime(
		targetId,
		heldId,
		currentMiningMultiplier(),
		Upgrades.powerBonus(held)
	)
	if not required then
		State.mining = nil
		return false
	end
	if wallMode then required *= 0.6 end

	local mining = State.mining
	if not mining or mining.x ~= tx or mining.y ~= ty or mining.layer ~= (if wallMode then "wall" else "fg") then
		mining = { x = tx, y = ty, layer = if wallMode then "wall" else "fg", progress = 0, required = required }
		State.mining = mining
	end
	mining.required = required
	mining.progress += dt
	State.lastSwing = os.clock()

	if mining.progress % 0.28 < dt then
		fire("sfx", "mine", targetId)
		fire("particles", tx, ty, targetId)
	end

	if mining.progress >= required then
		Net.get("Edit"):FireServer("break", tx, ty, mining.layer)
		-- تنبؤ محلي
		if wallMode then
			ClientWorld.predictSet(tx, ty, World.fg(world, tx, ty), Blocks.ID.AIR)
		else
			ClientWorld.predictSet(tx, ty, Blocks.ID.AIR, World.bg(world, tx, ty))
		end
		fire("sfx", "break", targetId)
		fire("particles", tx, ty, targetId)
		State.mined += 1
		State.mining = nil
	end
	return true
end

local function attack(dt: number)
	if attackCooldown > 0 then return end
	local held = State.heldItem()
	local item = if held then Items.get(held.id) else nil
	attackCooldown = if item and item.useTime then item.useTime else 0.35

	local wx, wy = mousePosition()
	Net.get("UseItem"):FireServer("attack", wx, wy)
	State.lastSwing = os.clock()
	State.facing = if wx >= State.body.x then 1 else -1
	fire("sfx", "swing")
end

local function updateActions(dt: number)
	placeCooldown = math.max(0, placeCooldown - dt)
	attackCooldown = math.max(0, attackCooldown - dt)

	if State.dead or State.uiOpen or State.shopOpen then
		State.mining = nil
		Renderer.setSelection(nil, nil, false)
		Renderer.setMiningProgress(nil, nil, 0)
		return
	end

	local tx, ty, inRange = targetTile()
	Renderer.setSelection(tx, ty, inRange)

	if not tx or not ty or not inRange then
		State.mining = nil
		Renderer.setMiningProgress(nil, nil, 0)
		if input.primary or input.secondary then
			attack(dt)
		end
		return
	end

	if input.primary then
		local held = State.heldItem()
		local item = if held then Items.get(held.id) else nil
		local handled = false

		if item and item.place then
			handled = tryPlace(tx, ty)
		end
		if not handled then
			handled = tryMine(tx, ty, dt)
		end
		if not handled then
			attack(dt)
		end
	else
		State.mining = nil
	end

	if input.secondary then
		-- التفاعل مع محطة (فرن، طاولة عمل، سندان، طاولة سحر) له الأولوية
		local block = Blocks.get(World.fg(ClientWorld.get(), tx, ty))
		if block.station or block.container then
			input.secondary = false
			Net.get("Station"):FireServer("open", tx, ty)
			fire("sfx", "ui")
			return
		end

		local held = State.heldItem()
		local item = if held then Items.get(held.id) else nil
		if item and (item.cat == "consumable" or item.cat == "misc") then
			local wx, wy = mousePosition()
			Net.get("UseItem"):FireServer("use", wx, wy)
			attackCooldown = math.max(attackCooldown, item.useTime or 0.5)
			input.secondary = false
		else
			attack(dt)
		end
	end

	local mining = State.mining
	if mining then
		Renderer.setMiningProgress(mining.x, mining.y, mining.progress / math.max(0.01, mining.required))
	else
		Renderer.setMiningProgress(nil, nil, 0)
	end
end

-- ===== الشبكة =====

local function sendState(dt: number)
	sendAccumulator += dt
	if sendAccumulator < 1 / Config.STATE_HZ then return end
	sendAccumulator = 0
	local body = State.body
	Net.get("PlayerState"):FireServer(body.x, body.y, body.vx, body.vy, State.facing, State.anim)
end

-- ===== الحلقة =====

function Controller.update(dt: number)
	if not ClientWorld.isReady() then return end
	if not State.dead then
		updateMovement(dt)
	end
	updateActions(dt)
	sendState(dt)
end

function Controller.start()
	UserInputService.InputBegan:Connect(onInput)
	UserInputService.InputEnded:Connect(function(io) onInputEnded(io) end)

	UserInputService.WindowFocusReleased:Connect(function()
		for key in input do input[key] = false end
		State.mining = nil
	end)

	-- امنع قائمة Roblox الافتراضية من التقاط المفاتيح المستعملة
	ContextActionService:BindAction("TerraCraftBlockDefaults", function()
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Slash)
end

return Controller
