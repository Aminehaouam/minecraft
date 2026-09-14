--!strict
--[[
	CraftService — التصنيع ومتجر التاجر.
	محطات التصنيع تُكتشف من العالم حول اللاعب (لا يثق الخادم بما يرسله العميل).
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Blocks = require(Shared.Blocks)
local Inventory = require(Shared.Inventory)
local Items = require(Shared.Items)
local Net = require(Shared.Net)
local Recipes = require(Shared.Recipes)
local Util = require(Shared.Util)
local World = require(Shared.World)

local Services = require(script.Parent.Services)

local CraftService = {}

local STATION_RANGE = 7

-- المحطات المتاحة حول اللاعب
function CraftService.stationsNear(x: number, y: number): { [string]: boolean }
	local found: { [string]: boolean } = {}
	local world = Services.World.getWorld()
	local cx, cy = math.floor(x), math.floor(y)
	for ty = cy - STATION_RANGE, cy + STATION_RANGE do
		for tx = cx - STATION_RANGE, cx + STATION_RANGE do
			local block = Blocks.get(World.fg(world, tx, ty))
			if block.station then
				found[block.station] = true
			end
		end
	end
	return found
end

local function handleCraft(player: Player, key: string, times: number?)
	local state = Services.Player.get(player)
	if not state or state.dead then return end
	if type(key) ~= "string" then return end

	local recipe = Recipes.byKey[key]
	if not recipe then return end

	local stations = CraftService.stationsNear(state.body.x, state.body.y)
	if recipe.station and not stations[recipe.station] then
		Net.get("Notify"):FireClient(player, { text = "تحتاج محطة تصنيع مناسبة", color = { 230, 170, 90 } })
		return
	end

	local count = math.clamp(math.floor(tonumber(times) or 1), 1, 50)
	local crafted = 0
	for _ = 1, count do
		if not Inventory.craft(state.slots, recipe) then break end
		crafted += 1
	end

	if crafted > 0 then
		Services.Player.syncInventory(player)
		Net.get("Fx"):FireClient(player, {
			kind = "craft", x = state.body.x, y = state.body.y,
			item = recipe.out.id, count = recipe.out.n * crafted,
		})
	else
		Net.get("Notify"):FireClient(player, { text = "المواد غير كافية", color = { 230, 120, 100 } })
	end
end

-- ===== المتجر =====
-- التاجر متاح قرب نقطة الظهور. الشراء بالعملات التي تسقط من الوحوش.

local SHOP_STOCK = {
	{ id = "torch", price = 2 },
	{ id = "arrow", price = 3 },
	{ id = "rope_placeholder", price = 0 }, -- محجوز
	{ id = "health_potion", price = 45 },
	{ id = "mana_potion", price = 40 },
	{ id = "apple", price = 8 },
	{ id = "bread", price = 14 },
	{ id = "glass", price = 10 },
	{ id = "wood_bow", price = 90 },
	{ id = "iron_bar", price = 65 },
	{ id = "recall_stone", price = 120 },
	{ id = "life_crystal", price = 900 },
}

local stock = {}
for _, entry in SHOP_STOCK do
	if Items.get(entry.id) then
		table.insert(stock, entry)
	end
end

function CraftService.shopStock()
	return stock
end

local function nearTrader(state: any): boolean
	return Util.dist(state.body.x, state.body.y, state.spawnX, state.spawnY) < 26
end

local function handleShop(player: Player, action: string, id: string, qty: number?)
	local state = Services.Player.get(player)
	if not state or state.dead then return end

	if action == "open" then
		Net.get("Shop"):FireClient(player, {
			open = nearTrader(state),
			stock = stock,
			coins = Inventory.count(state.slots, "coin"),
		})
		return
	end

	if not nearTrader(state) then
		Net.get("Notify"):FireClient(player, { text = "التاجر قرب نقطة الظهور فقط", color = { 220, 180, 100 } })
		return
	end

	local amount = math.clamp(math.floor(tonumber(qty) or 1), 1, 99)

	if action == "buy" then
		local entry = nil
		for _, candidate in stock do
			if candidate.id == id then
				entry = candidate
				break
			end
		end
		if not entry or entry.price <= 0 then return end

		local total = entry.price * amount
		if Inventory.count(state.slots, "coin") < total then
			Net.get("Notify"):FireClient(player, { text = "العملات غير كافية", color = { 230, 120, 100 } })
			return
		end
		if not Inventory.hasRoom(state.slots, id, amount) then
			Net.get("Notify"):FireClient(player, { text = "المخزون ممتلئ", color = { 230, 120, 100 } })
			return
		end
		Inventory.remove(state.slots, "coin", total)
		Inventory.add(state.slots, id, amount)
		Services.Player.syncInventory(player)
		Net.get("Shop"):FireClient(player, { open = true, stock = stock, coins = Inventory.count(state.slots, "coin") })
		return
	end

	if action == "sell" then
		local item = Items.get(id)
		if not item or item.value <= 0 or id == "coin" then return end
		local have = Inventory.count(state.slots, id)
		amount = math.min(amount, have)
		if amount <= 0 then return end
		local payout = math.max(1, math.floor(item.value * 0.4)) * amount
		if not Inventory.remove(state.slots, id, amount) then return end
		Inventory.add(state.slots, "coin", payout)
		Services.Player.syncInventory(player)
		Net.get("Shop"):FireClient(player, { open = true, stock = stock, coins = Inventory.count(state.slots, "coin") })
		return
	end
end

function CraftService.start()
	Net.get("Craft").OnServerEvent:Connect(handleCraft)
	Net.get("Shop").OnServerEvent:Connect(handleShop)
end

return CraftService
