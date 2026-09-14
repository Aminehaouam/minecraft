--!strict
--[[
	StationService — المحطات ذات الحالة في العالم.

	* **الفرن**: كيان بلاطة حقيقي له مُدخل ووقود وناتج وشريط تقدّم. يستمر في
	  الصهر وأنت بعيد عنه، وتُحفظ محتوياته مع تعديلات العالم، وتتناثر عند كسره.
	* **السندان**: تطوير الأدوات والدروع (+1 حتى +5) — مضمون النجاح.
	* **طاولة السحر**: منح صفة سحرية عشوائية قابلة لإعادة الرمي.

	كل شيء يُتحقق منه على الخادم: وجود البلاطة، قرب اللاعب، ملكية العناصر،
	وكفاية المواد والعملات.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Blocks = require(Shared.Blocks)
local Config = require(Shared.Config)
local Inventory = require(Shared.Inventory)
local Items = require(Shared.Items)
local Net = require(Shared.Net)
local Smelting = require(Shared.Smelting)
local Upgrades = require(Shared.Upgrades)
local Util = require(Shared.Util)
local World = require(Shared.World)

local Services = require(script.Parent.Services)

local StationService = {}

local USE_RANGE = 9 -- أقصى مسافة للتفاعل مع محطة
local CHEST_SLOTS = 27 -- ثلاثة صفوف × تسع خانات
local TICK = 0.25
local PUSH_HZ = 5 -- تحديثات الواجهة للمشاهدين

export type Furnace = {
	x: number,
	y: number,
	input: Inventory.Stack?,
	fuel: Inventory.Stack?,
	output: Inventory.Stack?,
	burn: number, -- ثواني وقود متبقية
	burnMax: number,
	progress: number, -- ثواني صهر متراكمة
	progressMax: number,
}

export type Chest = {
	x: number,
	y: number,
	slots: Inventory.Slots,
}

local furnaces: { [string]: Furnace } = {}
local chests: { [string]: Chest } = {}
-- اللاعب -> المحطة المفتوحة حالياً
local viewing: { [Player]: { x: number, y: number, kind: string } } = {}

local function key(x: number, y: number): string
	return x .. "," .. y
end

-- ===== أدوات =====

local function netStack(stack: Inventory.Stack?): any
	if not stack then return nil end
	local out = { id = stack.id, n = stack.n }
	if stack.up then
		out.lvl = stack.up.lvl
		out.aff = stack.up.aff or ""
	end
	return out
end

local function stationAt(x: number, y: number): string?
	local world = Services.World.getWorld()
	local block = Blocks.get(World.fg(world, x, y))
	if block.container then return "chest" end
	return block.station
end

local function playerNear(player: Player, x: number, y: number): boolean
	local state = Services.Player.get(player)
	if not state or state.dead then return false end
	return Util.dist(state.body.x, state.body.y, x + 0.5, y + 0.5) <= USE_RANGE
end

local function getFurnace(x: number, y: number, create: boolean?): Furnace?
	local k = key(x, y)
	local furnace = furnaces[k]
	if furnace then return furnace end
	if not create then return nil end
	if stationAt(x, y) ~= "furnace" then return nil end
	furnace = {
		x = x, y = y,
		input = nil, fuel = nil, output = nil,
		burn = 0, burnMax = 0, progress = 0, progressMax = 0,
	}
	furnaces[k] = furnace
	return furnace
end

local function getChest(x: number, y: number, create: boolean?): Chest?
	local k = key(x, y)
	local chest = chests[k]
	if chest then return chest end
	if not create then return nil end
	if stationAt(x, y) ~= "chest" then return nil end
	chest = { x = x, y = y, slots = Inventory.new() }
	chests[k] = chest
	return chest
end

-- ===== إرسال الحالة =====

local function buildPayload(player: Player, x: number, y: number, kind: string): any
	local payload: any = {
		open = true,
		kind = kind,
		x = x, y = y,
	}

	if kind == "furnace" then
		local furnace = getFurnace(x, y, true)
		if furnace then
			payload.input = netStack(furnace.input)
			payload.fuel = netStack(furnace.fuel)
			payload.output = netStack(furnace.output)
			payload.burn = math.floor(furnace.burn * 10) / 10
			payload.burnMax = furnace.burnMax
			payload.progress = math.floor(furnace.progress * 100) / 100
			payload.progressMax = furnace.progressMax
		end
	elseif kind == "chest" then
		local chest = getChest(x, y, true)
		if chest then
			local slots = {}
			for i = 1, CHEST_SLOTS do
				slots[i] = netStack(chest.slots[i])
			end
			payload.slots = slots
			payload.count = CHEST_SLOTS
		end
	end

	return payload
end

local function pushState(player: Player)
	local view = viewing[player]
	if not view then return end
	Net.get("Station"):FireClient(player, buildPayload(player, view.x, view.y, view.kind))
end

function StationService.close(player: Player, silent: boolean?)
	viewing[player] = nil
	if not silent then
		Net.get("Station"):FireClient(player, { open = false })
	end
end

-- ===== محاكاة الفرن =====

local function outputAccepts(furnace: Furnace, itemId: string, count: number): boolean
	local output = furnace.output
	if not output then return true end
	if output.id ~= itemId then return false end
	return output.n + count <= Items.maxStack(itemId)
end

local function stepFurnace(furnace: Furnace, dt: number): boolean
	local changed = false

	-- الوقود المشتعل يستمر حتى ينفد
	if furnace.burn > 0 then
		furnace.burn = math.max(0, furnace.burn - dt)
		changed = true
	end

	local recipe = Smelting.recipeFor(if furnace.input then (furnace.input :: Inventory.Stack).id else nil)
	local canWork = recipe ~= nil and outputAccepts(furnace, (recipe :: Smelting.SmeltRecipe).out, (recipe :: Smelting.SmeltRecipe).n)

	if not canWork then
		if furnace.progress > 0 then
			furnace.progress = 0
			furnace.progressMax = 0
			changed = true
		end
		return changed
	end

	local smelt = recipe :: Smelting.SmeltRecipe
	furnace.progressMax = smelt.time

	-- أشعل وقوداً جديداً عند الحاجة
	if furnace.burn <= 0 then
		local fuel = furnace.fuel
		local value = Smelting.fuelValue(if fuel then (fuel :: Inventory.Stack).id else nil)
		if value > 0 and fuel then
			furnace.burn = value
			furnace.burnMax = value
			fuel.n -= 1
			if fuel.n <= 0 then furnace.fuel = nil end
			changed = true
		else
			-- لا وقود: يبرد التقدّم تدريجياً بدل أن يضيع فوراً
			if furnace.progress > 0 then
				furnace.progress = math.max(0, furnace.progress - dt * 0.5)
				changed = true
			end
			return changed
		end
	end

	furnace.progress += dt
	changed = true

	if furnace.progress >= smelt.time then
		furnace.progress -= smelt.time
		local input = furnace.input
		if input then
			input.n -= 1
			if input.n <= 0 then furnace.input = nil end
		end
		if furnace.output then
			(furnace.output :: Inventory.Stack).n += smelt.n
		else
			furnace.output = { id = smelt.out, n = smelt.n }
		end
	end

	return changed
end

-- ===== نقل العناصر =====

local function handleGive(player: Player, x: number, y: number, playerSlot: number, target: string)
	local state = Services.Player.get(player)
	if not state or not playerNear(player, x, y) then return end
	if stationAt(x, y) ~= "furnace" then return end
	if playerSlot < 1 or playerSlot > Config.INV_SLOTS then return end

	local stack = state.slots[playerSlot]
	if not stack then return end

	local furnace = getFurnace(x, y, true)
	if not furnace then return end

	if target == "input" then
		if not Smelting.recipeFor(stack.id) then
			Net.get("Notify"):FireClient(player, { text = "هذا العنصر لا يُصهر", color = { 230, 160, 90 } })
			return
		end
	elseif target == "fuel" then
		if not Smelting.isFuel(stack.id) then
			Net.get("Notify"):FireClient(player, { text = "هذا العنصر ليس وقوداً", color = { 230, 160, 90 } })
			return
		end
	else
		return -- الناتج للأخذ فقط
	end

	local slot = if target == "input" then furnace.input else furnace.fuel
	local max = Items.maxStack(stack.id)

	if slot and slot.id ~= stack.id then
		-- بادل المحتويين
		local removed = Inventory.removeFromSlot(state.slots, playerSlot, stack.n)
		local swapped: Inventory.Stack = { id = stack.id, n = removed }
		if target == "input" then
			state.slots[playerSlot] = slot
			furnace.input = swapped
		else
			state.slots[playerSlot] = slot
			furnace.fuel = swapped
		end
	else
		local space = if slot then max - slot.n else max
		local move = math.min(space, stack.n)
		if move <= 0 then return end
		Inventory.removeFromSlot(state.slots, playerSlot, move)
		if slot then
			slot.n += move
		elseif target == "input" then
			furnace.input = { id = stack.id, n = move }
		else
			furnace.fuel = { id = stack.id, n = move }
		end
	end

	Services.Player.syncInventory(player)
	pushState(player)
	StationService.markDirty(x, y)
end

local function handleTake(player: Player, x: number, y: number, source: string)
	local state = Services.Player.get(player)
	if not state or not playerNear(player, x, y) then return end

	local furnace = getFurnace(x, y, false)
	if not furnace then return end

	local slot: Inventory.Stack? = nil
	if source == "input" then slot = furnace.input
	elseif source == "fuel" then slot = furnace.fuel
	elseif source == "output" then slot = furnace.output
	else return end
	if not slot then return end

	local leftover = Inventory.add(state.slots, slot.id, slot.n)
	local taken = slot.n - leftover
	if taken <= 0 then
		Net.get("Notify"):FireClient(player, { text = "المخزون ممتلئ", color = { 230, 120, 100 } })
		return
	end

	slot.n = leftover
	if slot.n <= 0 then
		if source == "input" then furnace.input = nil
		elseif source == "fuel" then furnace.fuel = nil
		else furnace.output = nil end
	end

	Services.Player.syncInventory(player)
	pushState(player)
	StationService.markDirty(x, y)
end

-- تبادل خانة بين مخزون اللاعب والصندوق (نفس منطق تبديل المخزون)
local function handleChestSwap(player: Player, x: number, y: number, playerSlot: number, chestSlot: number)
	local state = Services.Player.get(player)
	if not state or not playerNear(player, x, y) then return end
	if stationAt(x, y) ~= "chest" then return end
	if playerSlot < 1 or playerSlot > Config.INV_SLOTS then return end
	if chestSlot < 1 or chestSlot > CHEST_SLOTS then return end

	local chest = getChest(x, y, true)
	if not chest then return end

	local playerStack = state.slots[playerSlot]
	local chestStack = chest.slots[chestSlot]

	-- دمج الأكوام المتطابقة غير المطوّرة بدل تبديلها
	if playerStack and chestStack and playerStack.id == chestStack.id
		and playerStack.up == nil and chestStack.up == nil then
		local max = Items.maxStack(playerStack.id)
		local move = math.min(max - chestStack.n, playerStack.n)
		if move > 0 then
			chestStack.n += move
			playerStack.n -= move
			if playerStack.n <= 0 then state.slots[playerSlot] = nil end
			Services.Player.syncInventory(player)
			pushState(player)
			StationService.markDirty(x, y)
			return
		end
	end

	state.slots[playerSlot] = chestStack
	chest.slots[chestSlot] = playerStack

	Services.Player.syncInventory(player)
	pushState(player)
	StationService.markDirty(x, y)
end

-- «أودِع الكل»: ينقل كل ما يماثل محتويات الصندوق من المخزون إليه
local function handleChestDeposit(player: Player, x: number, y: number)
	local state = Services.Player.get(player)
	if not state or not playerNear(player, x, y) then return end
	if stationAt(x, y) ~= "chest" then return end
	local chest = getChest(x, y, true)
	if not chest then return end

	local moved = 0
	for i = Config.HOTBAR + 1, Config.INV_SLOTS do
		local stack = state.slots[i]
		if stack and stack.up == nil then
			local emptied = false
			for j = 1, CHEST_SLOTS do
				local target = chest.slots[j]
				if target and target.id == stack.id and target.up == nil then
					local space = Items.maxStack(stack.id) - target.n
					local move = math.min(space, stack.n)
					if move > 0 then
						target.n += move
						stack.n -= move
						moved += move
						if stack.n <= 0 then
							state.slots[i] = nil
							emptied = true
							break
						end
					end
				end
			end
			if not emptied and state.slots[i] then
				for j = 1, CHEST_SLOTS do
					if not chest.slots[j] then
						chest.slots[j] = state.slots[i]
						moved += 1
						state.slots[i] = nil
						break
					end
				end
			end
		end
	end

	if moved > 0 then
		Services.Player.syncInventory(player)
		pushState(player)
		StationService.markDirty(x, y)
	end
end

-- ===== التطوير والسحر =====

local function payCost(state: any, cost: Upgrades.Cost): boolean
	if Inventory.count(state.slots, cost.material) < cost.amount then return false end
	if Inventory.count(state.slots, "coin") < cost.coins then return false end
	Inventory.remove(state.slots, cost.material, cost.amount)
	Inventory.remove(state.slots, "coin", cost.coins)
	return true
end

local function handleUpgrade(player: Player, x: number, y: number, slotIndex: number)
	local state = Services.Player.get(player)
	if not state or not playerNear(player, x, y) then return end
	if stationAt(x, y) ~= "anvil" then return end
	if slotIndex < 1 or slotIndex > Config.INV_SLOTS then return end

	local stack = state.slots[slotIndex]
	if not stack then return end
	if not Upgrades.canModify(stack.id) then
		Net.get("Notify"):FireClient(player, { text = "هذا العنصر غير قابل للتطوير", color = { 230, 160, 90 } })
		return
	end

	local level = Upgrades.levelOf(stack)
	local cost = Upgrades.upgradeCost(stack.id, level)
	if not cost then
		Net.get("Notify"):FireClient(player, { text = "بلغ العنصر أقصى تطوير (+" .. Upgrades.MAX_LEVEL .. ")", color = { 240, 200, 110 } })
		return
	end

	if not payCost(state, cost) then
		Net.get("Notify"):FireClient(player, {
			text = string.format("تحتاج %d × %s و %d عملة", cost.amount, Items.name(cost.material), cost.coins),
			color = { 230, 120, 100 },
		})
		return
	end

	stack.up = { lvl = level + 1, aff = if stack.up then stack.up.aff else nil }
	Services.Player.syncInventory(player)
	Services.Player.syncStats(player)
	Net.get("Notify"):FireClient(player, {
		text = Upgrades.displayName(stack) .. " — تمّ التطوير!",
		color = { 250, 210, 110 },
	})
	Net.get("Fx"):FireAllClients({ kind = "upgrade", x = state.body.x, y = state.body.y })
end

local function handleEnchant(player: Player, x: number, y: number, slotIndex: number)
	local state = Services.Player.get(player)
	if not state or not playerNear(player, x, y) then return end
	if stationAt(x, y) ~= "enchant" then return end
	if slotIndex < 1 or slotIndex > Config.INV_SLOTS then return end

	local stack = state.slots[slotIndex]
	if not stack then return end
	local category = Upgrades.categoryOf(stack.id)
	if not category then
		Net.get("Notify"):FireClient(player, { text = "هذا العنصر غير قابل للسحر", color = { 230, 160, 90 } })
		return
	end

	local cost = Upgrades.enchantCost(stack.id)
	if not cost then return end
	if not payCost(state, cost) then
		Net.get("Notify"):FireClient(player, {
			text = string.format("تحتاج %d × %s و %d عملة", cost.amount, Items.name(cost.material), cost.coins),
			color = { 230, 120, 100 },
		})
		return
	end

	local current = if stack.up then stack.up.aff else nil
	local affixId = Upgrades.rollAffix(category, math.random(), current)
	stack.up = { lvl = Upgrades.levelOf(stack), aff = affixId }

	Services.Player.syncInventory(player)
	Services.Player.syncStats(player)
	local affix = Upgrades.affix(affixId)
	Net.get("Notify"):FireClient(player, {
		text = Upgrades.displayName(stack) .. (if affix then " — " .. affix.desc else ""),
		color = { 190, 150, 250 },
	})
	Net.get("Fx"):FireAllClients({ kind = "enchant", x = state.body.x, y = state.body.y })
end

-- ===== كسر البلاطة =====

-- يُستدعى من WorldService قبل إزالة بلاطة: تتناثر محتويات الفرن
function StationService.onBlockRemoved(x: number, y: number)
	local k = key(x, y)
	local furnace = furnaces[k]
	local chest = chests[k]
	if not furnace and not chest then return end

	if furnace then
		furnaces[k] = nil
		for _, stack in { furnace.input, furnace.fuel, furnace.output } do
			if stack then
				Services.Entity.spawnItem(x + 0.5, y + 0.5, stack.id, stack.n)
			end
		end
	end

	if chest then
		chests[k] = nil
		for i = 1, CHEST_SLOTS do
			local stack = chest.slots[i]
			if stack then
				local upgrade = if stack.up then { lvl = stack.up.lvl, aff = stack.up.aff } else nil
				Services.Entity.spawnItem(x + 0.5, y + 0.5, stack.id, stack.n, nil, nil, nil, upgrade)
			end
		end
	end

	for player, view in viewing do
		if view.x == x and view.y == y then
			StationService.close(player)
		end
	end
	StationService.markDirty(x, y)
end

-- ===== الحفظ =====

local dirtyRegions: { [string]: boolean } = {}

function StationService.markDirty(x: number, y: number)
	local rx = (x // Config.CHUNK) // Config.REGION
	local ry = (y // Config.CHUNK) // Config.REGION
	dirtyRegions[rx .. "," .. ry] = true
end

function StationService.consumeDirtyRegions(): { [string]: boolean }
	local snapshot = dirtyRegions
	dirtyRegions = {}
	return snapshot
end

local function serializeStack(stack: Inventory.Stack?): any
	if not stack then return nil end
	local out: { any } = { stack.id, stack.n }
	if stack.up then
		out[3] = stack.up.lvl
		out[4] = stack.up.aff or ""
	end
	return out
end

local function deserializeStack(data: any): Inventory.Stack?
	if type(data) ~= "table" then return nil end
	local id, n = data[1], data[2]
	if type(id) ~= "string" or type(n) ~= "number" or n <= 0 then return nil end
	if not Items.get(id) then return nil end
	local stack: Inventory.Stack = { id = id, n = math.min(n, Items.maxStack(id)) }
	if type(data[3]) == "number" and Upgrades.canModify(id) then
		stack.up = Upgrades.normalize({ lvl = data[3], aff = data[4] })
	end
	return stack
end

function StationService.exportRegion(rx: number, ry: number): { [string]: any }?
	local out: { [string]: any } = {}
	local any = false
	local minX = rx * Config.REGION * Config.CHUNK
	local maxX = minX + Config.REGION * Config.CHUNK - 1
	local minY = ry * Config.REGION * Config.CHUNK
	local maxY = minY + Config.REGION * Config.CHUNK - 1

	for k, furnace in furnaces do
		if furnace.x >= minX and furnace.x <= maxX and furnace.y >= minY and furnace.y <= maxY then
			if furnace.input or furnace.fuel or furnace.output or furnace.burn > 0 then
				out[k] = {
					t = "f",
					i = serializeStack(furnace.input),
					f = serializeStack(furnace.fuel),
					o = serializeStack(furnace.output),
					b = math.floor(furnace.burn),
					bm = math.floor(furnace.burnMax),
					p = math.floor(furnace.progress * 10) / 10,
				}
				any = true
			end
		end
	end

	for k, chest in chests do
		if chest.x >= minX and chest.x <= maxX and chest.y >= minY and chest.y <= maxY then
			local packed = {}
			for i = 1, CHEST_SLOTS do
				local stack = chest.slots[i]
				if stack then
					table.insert(packed, { i, serializeStack(stack) })
				end
			end
			if #packed > 0 then
				out[k] = { t = "c", s = packed }
				any = true
			end
		end
	end

	return if any then out else nil
end

function StationService.importRegion(data: any)
	if type(data) ~= "table" then return end
	for k, entry in data do
		if type(k) == "string" and type(entry) == "table" then
			local parts = string.split(k, ",")
			local x, y = tonumber(parts[1]), tonumber(parts[2])
			if x and y then
				if entry.t == "c" then
					local slots = Inventory.new()
					if type(entry.s) == "table" then
						for _, pair in entry.s do
							local index = tonumber(pair[1])
							local stack = deserializeStack(pair[2])
							if index and stack and index >= 1 and index <= CHEST_SLOTS then
								slots[index] = stack
							end
						end
					end
					chests[k] = { x = x, y = y, slots = slots }
				else
					furnaces[k] = {
						x = x, y = y,
						input = deserializeStack(entry.i),
						fuel = deserializeStack(entry.f),
						output = deserializeStack(entry.o),
						burn = tonumber(entry.b) or 0,
						burnMax = tonumber(entry.bm) or 0,
						progress = tonumber(entry.p) or 0,
						progressMax = 0,
					}
				end
			end
		end
	end
end

-- ===== المعالجات =====

local function handleOpen(player: Player, x: number, y: number)
	if not playerNear(player, x, y) then
		Net.get("Notify"):FireClient(player, { text = "اقترب من المحطة", color = { 220, 180, 100 } })
		return
	end
	local kind = stationAt(x, y)
	if not kind then return end

	viewing[player] = { x = x, y = y, kind = kind }
	if kind == "furnace" then
		getFurnace(x, y, true)
	elseif kind == "chest" then
		getChest(x, y, true)
		Net.get("Fx"):FireAllClients({ kind = "chest_open", x = x + 0.5, y = y + 0.5 })
	end
	pushState(player)
end

function StationService.start()
	Net.get("Station").OnServerEvent:Connect(function(player, action, x, y, a, b)
		if action == "close" then
			StationService.close(player, true)
			return
		end
		if type(x) ~= "number" or type(y) ~= "number" then return end
		x, y = math.floor(x), math.floor(y)
		if not World.inBounds(x, y) then return end

		if action == "open" then
			handleOpen(player, x, y)
		elseif action == "give" then
			if type(a) == "number" and type(b) == "string" then
				handleGive(player, x, y, math.floor(a), b)
			end
		elseif action == "take" then
			if type(a) == "string" then
				handleTake(player, x, y, a)
			end
		elseif action == "upgrade" then
			if type(a) == "number" then
				handleUpgrade(player, x, y, math.floor(a))
			end
		elseif action == "enchant" then
			if type(a) == "number" then
				handleEnchant(player, x, y, math.floor(a))
			end
		elseif action == "chest_swap" then
			if type(a) == "number" and type(b) == "number" then
				handleChestSwap(player, x, y, math.floor(a), math.floor(b))
			end
		elseif action == "chest_deposit" then
			handleChestDeposit(player, x, y)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		viewing[player] = nil
	end)

	-- محاكاة الأفران
	local accumulator = 0
	local pushTimer = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= TICK then
			local step = accumulator
			accumulator = 0
			for _, furnace in furnaces do
				local ok, err = pcall(stepFurnace, furnace, step)
				if not ok then
					warn("[StationService] خطأ في محاكاة الفرن: " .. tostring(err))
				end
			end
		end

		pushTimer += dt
		if pushTimer >= 1 / PUSH_HZ then
			pushTimer = 0
			for player, view in viewing do
				-- أغلق النافذة إن ابتعد اللاعب أو كُسرت المحطة
				if not playerNear(player, view.x, view.y) or stationAt(view.x, view.y) ~= view.kind then
					StationService.close(player)
				else
					pushState(player)
				end
			end
		end
	end)

	-- حفظ دوري لحالات الأفران يُحرّكه WorldService عبر consumeDirtyRegions
	task.spawn(function()
		while true do
			task.wait(20)
			for _, furnace in furnaces do
				if furnace.burn > 0 or furnace.progress > 0 then
					StationService.markDirty(furnace.x, furnace.y)
				end
			end
		end
	end)
end

function StationService.furnaceCount(): number
	local n = 0
	for _ in furnaces do n += 1 end
	return n
end

function StationService.chestCount(): number
	local n = 0
	for _ in chests do n += 1 end
	return n
end

StationService.CHEST_SLOTS = CHEST_SLOTS

return StationService
