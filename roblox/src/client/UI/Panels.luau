--!strict
--[[
	Panels — نوافذ المخزون والتصنيع والمتجر، مع تلميحات العناصر.
	التفاعل: نقرة لاختيار خانة ثم نقرة أخرى للتبديل (يعمل بالفأرة واللمس معاً).
]]

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Blocks = require(Shared.Blocks)
local Config = require(Shared.Config)
local Inventory = require(Shared.Inventory)
local Items = require(Shared.Items)
local Net = require(Shared.Net)
local Recipes = require(Shared.Recipes)
local World = require(Shared.World)

local ClientWorld = require(script.Parent.Parent.ClientWorld)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)

local Panels = {}

local root: Frame
local invPanel: Frame
local craftPanel: Frame
local shopPanel: Frame
local tooltip: Frame
local tooltipTitle: TextLabel
local tooltipBody: TextLabel

local slotButtons: { { button: TextButton, swatch: Frame, count: TextLabel } } = {}
local armorButtons: { [string]: { button: TextButton, swatch: Frame } } = {}
local craftList: ScrollingFrame
local craftRows: { Frame } = {}
local stationLabel: TextLabel
local shopList: ScrollingFrame
local shopCoins: TextLabel

local selected: number? = nil
local shopData: any = nil
local craftRefresh = 0
local craftDirty = true
local stationSignature = ""

local SLOT = 46
local GAP = 5

-- ===== التلميح =====

local function buildTooltip(parent: Instance)
	tooltip = Theme.panel(parent, "Tooltip")
	tooltip.Size = UDim2.fromOffset(260, 120)
	tooltip.Visible = false
	tooltip.ZIndex = 60
	Theme.padding(tooltip, 10)

	tooltipTitle = Theme.label(tooltip, "", 16, Theme.colors.text)
	tooltipTitle.Size = UDim2.new(1, 0, 0, 20)
	tooltipTitle.Font = Theme.fontBold
	tooltipTitle.ZIndex = 61

	tooltipBody = Theme.label(tooltip, "", 13, Theme.colors.textDim)
	tooltipBody.Position = UDim2.fromOffset(0, 24)
	tooltipBody.Size = UDim2.new(1, 0, 1, -24)
	tooltipBody.TextYAlignment = Enum.TextYAlignment.Top
	tooltipBody.TextWrapped = true
	tooltipBody.ZIndex = 61
end

local function itemDescription(item: Items.Item): string
	local lines = {}
	if item.cat == "block" then table.insert(lines, "بلاطة قابلة للبناء") end
	if item.damage then table.insert(lines, string.format("الضرر: %d", item.damage)) end
	if item.pick and item.pick > 0 then table.insert(lines, string.format("قوة المعول: %d", item.pick)) end
	if item.axe and item.axe > 0 then table.insert(lines, string.format("قوة الفأس: %d", item.axe)) end
	if item.useTime then table.insert(lines, string.format("سرعة الاستخدام: %.2fث", item.useTime)) end
	if item.knockback then table.insert(lines, string.format("الارتداد: %.1f", item.knockback)) end
	if item.defense then table.insert(lines, string.format("الدفاع: %d", item.defense)) end
	if item.setBonus then table.insert(lines, "طقم كامل: +6 دفاع") end
	if item.heal then table.insert(lines, string.format("يستعيد %d حياة", item.heal)) end
	if item.restoreMana then table.insert(lines, string.format("يستعيد %d مانا", item.restoreMana)) end
	if item.food then table.insert(lines, string.format("يشبع %d", item.food)) end
	if item.mana then table.insert(lines, string.format("كلفة المانا: %d", item.mana)) end
	if item.ranged then table.insert(lines, "يحتاج ذخيرة: سهام") end
	if item.buff then table.insert(lines, "يمنح تأثيراً مؤقتاً") end
	if item.desc then table.insert(lines, item.desc) end
	table.insert(lines, string.format("القيمة: %d عملة", item.value))
	return table.concat(lines, "\n")
end

local function showTooltip(itemId: string?)
	if not itemId then
		tooltip.Visible = false
		return
	end
	local item = Items.get(itemId)
	if not item then
		tooltip.Visible = false
		return
	end
	tooltip.Visible = true
	tooltipTitle.Text = item.name
	tooltipTitle.TextColor3 = Items.RARITY_COLORS[item.rarity] or Theme.colors.text
	tooltipBody.Text = itemDescription(item)
	local lineCount = select(2, string.gsub(tooltipBody.Text, "\n", "")) + 1
	tooltip.Size = UDim2.fromOffset(260, 40 + lineCount * 16)
end

-- ===== المخزون =====

local function slotClicked(index: number, alternate: boolean)
	local stack = State.slots[index]

	if alternate then
		if stack then
			local item = Items.get(stack.id)
			if item and item.cat == "armor" then
				Net.get("InvAction"):FireServer("equip", index)
			else
				Net.get("InvAction"):FireServer("drop", index, if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then "all" else 1)
			end
		end
		selected = nil
		return
	end

	if selected == nil then
		if stack then selected = index end
	elseif selected == index then
		selected = nil
	else
		Net.get("InvAction"):FireServer("swap", selected, index)
		selected = nil
	end
end

local function buildInventory(parent: Instance)
	local width = Config.HOTBAR * SLOT + (Config.HOTBAR - 1) * GAP
	local height = (Config.INV_ROWS + 1) * SLOT + Config.INV_ROWS * GAP

	invPanel = Theme.panel(parent, "Inventory")
	invPanel.Size = UDim2.fromOffset(width + 150, height + 70)
	invPanel.Position = UDim2.fromOffset(30, 90)
	Theme.padding(invPanel, 14)

	local title = Theme.label(invPanel, "المخزون", 18, Theme.colors.text)
	title.Size = UDim2.new(1, 0, 0, 22)
	title.Font = Theme.fontBold
	title.TextXAlignment = Enum.TextXAlignment.Right

	local sortButton = Theme.button(invPanel, "ترتيب", UDim2.fromOffset(74, 24), UDim2.fromOffset(0, 0))
	sortButton.MouseButton1Click:Connect(function()
		Net.get("InvAction"):FireServer("sort")
	end)

	-- خانات الدرع
	local armorBox = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.fromOffset(130, height),
		ZIndex = 31,
	}, invPanel)

	local slotNames = { head = "الرأس", chest = "الصدر", feet = "القدم" }
	local order = { "head", "chest", "feet" }
	for i, slotName in order do
		local label = Theme.label(armorBox, slotNames[slotName], 12, Theme.colors.textDim)
		label.Position = UDim2.fromOffset(0, (i - 1) * (SLOT + 22))
		label.Size = UDim2.fromOffset(120, 16)
		label.TextXAlignment = Enum.TextXAlignment.Right

		local button = Theme.new("TextButton", {
			BackgroundColor3 = Theme.colors.slot,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.fromOffset(SLOT, SLOT),
			Position = UDim2.fromOffset(120 - SLOT, (i - 1) * (SLOT + 22) + 18),
			ZIndex = 32,
		}, armorBox)
		Theme.corner(button, 7)
		Theme.stroke(button, Color3.fromRGB(10, 10, 14), 1.5)

		local swatch = Theme.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(200, 200, 200),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(26, 26),
			Visible = false,
			ZIndex = 33,
		}, button)
		Theme.corner(swatch, 5)

		button.MouseButton1Click:Connect(function()
			Net.get("InvAction"):FireServer("unequip", slotName)
		end)
		button.MouseEnter:Connect(function()
			local stack = State.armor[slotName]
			showTooltip(if stack then stack.id else nil)
		end)
		button.MouseLeave:Connect(function() showTooltip(nil) end)

		armorButtons[slotName] = { button = button, swatch = swatch }
	end

	-- شبكة الخانات
	local grid = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(140, 32),
		Size = UDim2.fromOffset(width, height),
		ZIndex = 31,
	}, invPanel)

	for i = 1, Config.INV_SLOTS do
		local col = (i - 1) % Config.HOTBAR
		local row = (i - 1) // Config.HOTBAR

		local button = Theme.new("TextButton", {
			BackgroundColor3 = Theme.colors.slot,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.fromOffset(SLOT, SLOT),
			Position = UDim2.fromOffset(col * (SLOT + GAP), row * (SLOT + GAP)),
			ZIndex = 32,
		}, grid)
		Theme.corner(button, 7)
		Theme.stroke(button, Color3.fromRGB(10, 10, 14), 1.5)

		local swatch = Theme.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(200, 200, 200),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromOffset(26, 26),
			Visible = false,
			ZIndex = 33,
		}, button)
		Theme.corner(swatch, 5)

		local count = Theme.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.fontBold,
			Text = "",
			TextSize = 12,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextStrokeTransparency = 0.35,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -3, 1, -1),
			Size = UDim2.fromOffset(38, 14),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 34,
		}, button)

		button.MouseButton1Click:Connect(function() slotClicked(i, false) end)
		button.MouseButton2Click:Connect(function() slotClicked(i, true) end)
		button.MouseEnter:Connect(function()
			local stack = State.slots[i]
			showTooltip(if stack then stack.id else nil)
		end)
		button.MouseLeave:Connect(function() showTooltip(nil) end)

		table.insert(slotButtons, { button = button, swatch = swatch, count = count })
	end
end

-- ===== التصنيع =====

local function stationsNear(): { [string]: boolean }
	local found: { [string]: boolean } = {}
	if not ClientWorld.isReady() then return found end
	local world = ClientWorld.get()
	local cx, cy = math.floor(State.body.x), math.floor(State.body.y)
	for ty = cy - 7, cy + 7 do
		for tx = cx - 7, cx + 7 do
			local block = Blocks.get(World.fg(world, tx, ty))
			if block.station then found[block.station] = true end
		end
	end
	return found
end

local STATION_NAMES = {
	workbench = "طاولة عمل",
	furnace = "فرن",
	anvil = "سندان",
	alchemy = "طاولة خيمياء",
}

local function buildCrafting(parent: Instance)
	craftPanel = Theme.panel(parent, "Crafting")
	craftPanel.Size = UDim2.fromOffset(380, 460)
	craftPanel.Position = UDim2.new(1, -410, 0, 90)
	Theme.padding(craftPanel, 12)

	local title = Theme.label(craftPanel, "التصنيع", 18, Theme.colors.text)
	title.Size = UDim2.new(1, 0, 0, 22)
	title.Font = Theme.fontBold

	stationLabel = Theme.label(craftPanel, "", 12, Theme.colors.textDim)
	stationLabel.Position = UDim2.fromOffset(0, 24)
	stationLabel.Size = UDim2.new(1, 0, 0, 18)

	craftList = Theme.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 1, -46),
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.colors.slotHover,
		ZIndex = 31,
	}, craftPanel)

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 5)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = craftList
end

local function refreshCrafting()
	for _, row in craftRows do row:Destroy() end
	table.clear(craftRows)

	local stations = stationsNear()
	local names = {}
	local keys = {}
	for station in stations do table.insert(keys, station) end
	table.sort(keys)
	stationSignature = table.concat(keys, ",")

	for station in stations do
		table.insert(names, STATION_NAMES[station] or station)
	end
	stationLabel.Text = if #names > 0 then "المحطات القريبة: " .. table.concat(names, "، ") else "لا توجد محطات قريبة (باليد فقط)"

	local available = Recipes.available(stations)
	local order = 0
	local totalHeight = 0

	for _, recipe in available do
		local canCraft = Inventory.canCraft(State.slots, recipe)
		local outItem = Items.get(recipe.out.id)
		if outItem then
			order += 1
			local row = Theme.new("Frame", {
				BackgroundColor3 = Theme.colors.panelLight,
				BackgroundTransparency = if canCraft then 0.1 else 0.55,
				BorderSizePixel = 0,
				Size = UDim2.new(1, -8, 0, 54),
				LayoutOrder = if canCraft then order else order + 1000,
				ZIndex = 32,
			}, craftList)
			Theme.corner(row, 7)

			local swatch = Theme.new("Frame", {
				BackgroundColor3 = outItem.color,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(30, 30),
				ZIndex = 33,
			}, row)
			Theme.corner(swatch, 5)

			local name = Theme.label(row, string.format("%s ×%d", outItem.name, recipe.out.n), 14,
				Items.RARITY_COLORS[outItem.rarity] or Theme.colors.text)
			name.Position = UDim2.fromOffset(0, 6)
			name.Size = UDim2.new(1, -48, 0, 18)
			name.Font = Theme.fontBold

			local parts = {}
			for _, ingredient in recipe.ins do
				local have = Inventory.count(State.slots, ingredient.id)
				table.insert(parts, string.format("%s %d/%d", Items.name(ingredient.id), have, ingredient.n))
			end
			local ingredients = Theme.label(row, table.concat(parts, " · "), 11,
				if canCraft then Theme.colors.good else Theme.colors.textDim)
			ingredients.Position = UDim2.fromOffset(0, 26)
			ingredients.Size = UDim2.new(1, -48, 0, 24)
			ingredients.TextWrapped = true

			local button = Theme.new("TextButton", {
				BackgroundTransparency = 1,
				Text = "",
				Size = UDim2.fromScale(1, 1),
				ZIndex = 34,
			}, row)
			button.MouseButton1Click:Connect(function()
				Net.get("Craft"):FireServer(recipe.key, 1)
			end)
			button.MouseButton2Click:Connect(function()
				Net.get("Craft"):FireServer(recipe.key, 10)
			end)
			button.MouseEnter:Connect(function() showTooltip(recipe.out.id) end)
			button.MouseLeave:Connect(function() showTooltip(nil) end)

			table.insert(craftRows, row)
			totalHeight += 59
		end
	end

	craftList.CanvasSize = UDim2.fromOffset(0, totalHeight)
end

-- ===== المتجر =====

local function buildShop(parent: Instance)
	shopPanel = Theme.panel(parent, "Shop")
	shopPanel.Size = UDim2.fromOffset(360, 420)
	shopPanel.Position = UDim2.new(0.5, -180, 0.5, -210)
	shopPanel.Visible = false
	Theme.padding(shopPanel, 12)

	local title = Theme.label(shopPanel, "متجر التاجر", 18, Theme.colors.text)
	title.Size = UDim2.new(1, 0, 0, 22)
	title.Font = Theme.fontBold

	shopCoins = Theme.label(shopPanel, "", 13, Theme.colors.gold)
	shopCoins.Position = UDim2.fromOffset(0, 24)
	shopCoins.Size = UDim2.new(1, 0, 0, 18)

	local closeButton = Theme.button(shopPanel, "إغلاق", UDim2.fromOffset(70, 24), UDim2.fromOffset(0, 0))
	closeButton.MouseButton1Click:Connect(function()
		shopPanel.Visible = false
		State.shopOpen = false
	end)

	shopList = Theme.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 1, -84),
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollBarThickness = 6,
		ZIndex = 31,
	}, shopPanel)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = shopList

	local sellButton = Theme.button(shopPanel, "بيع العنصر المحدد", UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 1, -30))
	sellButton.MouseButton1Click:Connect(function()
		local index = selected
		if not index then
			return
		end
		local stack = State.slots[index]
		if stack then
			Net.get("Shop"):FireServer("sell", stack.id, stack.n)
			selected = nil
		end
	end)
end

local function refreshShop()
	if not shopData then return end
	for _, child in shopList:GetChildren() do
		if child:IsA("Frame") then child:Destroy() end
	end

	shopCoins.Text = string.format("عملاتك: %d", shopData.coins or 0)
	local height = 0
	for _, entry in shopData.stock or {} do
		local item = Items.get(entry.id)
		if item and entry.price > 0 then
			local row = Theme.new("Frame", {
				BackgroundColor3 = Theme.colors.panelLight,
				BackgroundTransparency = 0.1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, -8, 0, 38),
				ZIndex = 32,
			}, shopList)
			Theme.corner(row, 6)

			local swatch = Theme.new("Frame", {
				BackgroundColor3 = item.color,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -6, 0.5, 0),
				Size = UDim2.fromOffset(24, 24),
				ZIndex = 33,
			}, row)
			Theme.corner(swatch, 4)

			local label = Theme.label(row, string.format("%s — %d عملة", item.name, entry.price), 13, Theme.colors.text)
			label.Position = UDim2.fromOffset(76, 0)
			label.Size = UDim2.new(1, -110, 1, 0)

			local buy1 = Theme.button(row, "شراء", UDim2.fromOffset(50, 24), UDim2.fromOffset(4, 7))
			buy1.MouseButton1Click:Connect(function()
				Net.get("Shop"):FireServer("buy", entry.id, 1)
			end)
			local buy10 = Theme.button(row, "×10", UDim2.fromOffset(38, 24), UDim2.fromOffset(56, 7))
			buy10.MouseButton1Click:Connect(function()
				Net.get("Shop"):FireServer("buy", entry.id, 10)
			end)

			height += 42
		end
	end
	shopList.CanvasSize = UDim2.fromOffset(0, height)
end

-- ===== الواجهة العامة =====

function Panels.build(parent: Instance)
	root = Theme.new("Frame", {
		Name = "Panels",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 30,
	}, parent)

	buildInventory(root)
	buildCrafting(root)
	buildShop(parent)
	buildTooltip(parent)
end

function Panels.setOpen(open: boolean)
	root.Visible = open
	State.uiOpen = open
	if not open then
		selected = nil
		showTooltip(nil)
	else
		craftDirty = true
	end
end

function Panels.isOpen(): boolean
	return root.Visible
end

function Panels.openShop(payload: any)
	shopData = payload
	if payload.open then
		shopPanel.Visible = true
		State.shopOpen = true
		refreshShop()
	else
		shopPanel.Visible = false
		State.shopOpen = false
	end
end

function Panels.closeAll()
	Panels.setOpen(false)
	shopPanel.Visible = false
	State.shopOpen = false
end

function Panels.onInventoryChanged()
	craftDirty = true
	if shopPanel.Visible and shopData then
		local coins = 0
		for i = 1, Config.INV_SLOTS do
			local stack = State.slots[i]
			if stack and stack.id == "coin" then coins += stack.n end
		end
		shopData.coins = coins
		shopCoins.Text = string.format("عملاتك: %d", coins)
	end
end

function Panels.update(dt: number)
	if not root.Visible then return end

	for i, entry in slotButtons do
		local stack = State.slots[i]
		local isSelected = selected == i
		entry.button.BackgroundColor3 = if isSelected then Theme.colors.slotActive
			elseif i <= Config.HOTBAR then Theme.colors.slotHover
			else Theme.colors.slot
		if stack then
			local item = Items.get(stack.id)
			entry.swatch.Visible = true
			entry.swatch.BackgroundColor3 = if item then item.color else Color3.fromRGB(200, 200, 200)
			entry.count.Text = if stack.n > 1 then tostring(stack.n) else ""
		else
			entry.swatch.Visible = false
			entry.count.Text = ""
		end
	end

	for slotName, entry in armorButtons do
		local stack = State.armor[slotName]
		if stack then
			local item = Items.get(stack.id)
			entry.swatch.Visible = true
			entry.swatch.BackgroundColor3 = if item then item.color else Color3.fromRGB(200, 200, 200)
		else
			entry.swatch.Visible = false
		end
	end

	-- تحديث قائمة التصنيع بمعدل منخفض (مكلفة نسبياً)
	-- قائمة التصنيع مكلفة البناء: نعيدها فقط عند تغيّر المخزون أو المحطات القريبة
	craftRefresh -= dt
	if craftRefresh <= 0 then
		craftRefresh = 0.35
		local stations = stationsNear()
		local keys = {}
		for station in stations do table.insert(keys, station) end
		table.sort(keys)
		if table.concat(keys, ",") ~= stationSignature then
			craftDirty = true
		end
	end
	if craftDirty then
		craftDirty = false
		refreshCrafting()
	end

	-- التلميح يتبع المؤشر
	if tooltip.Visible then
		local mouse = UserInputService:GetMouseLocation()
		local inset = GuiService:GetGuiInset()
		tooltip.Position = UDim2.fromOffset(mouse.X + inset.X + 18, mouse.Y + inset.Y + 12)
	end
end

return Panels
