--!strict
--[[
	Panels — نوافذ المخزون والمحطات والمتجر، مع تلميحات العناصر.

	نافذة المحطة واحدة بتبويبات، ويتغيّر محتواها حسب ما تفاعلت معه:
		تصنيع  — لكل المحطات (مع بحث)
		صهر    — الفرن: مُدخل + وقود + ناتج + شريط تقدّم حيّ
		تطوير  — السندان: رفع مستوى الأداة/الدرع (+1 حتى +5)
		سحر    — طاولة السحر: منح صفة عشوائية قابلة لإعادة الرمي

	التفاعل موحّد: نقرة لاختيار خانة ثم نقرة على الهدف. يعمل بالفأرة واللمس.
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
local Smelting = require(Shared.Smelting)
local Upgrades = require(Shared.Upgrades)
local World = require(Shared.World)

local ClientWorld = require(script.Parent.Parent.ClientWorld)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)

local Panels = {}

local SLOT = 46
local GAP = 5
local STATION_RANGE = 7

-- ===== المراجع =====
local root: Frame
local invPanel: Frame
local stationPanel: Frame
local shopPanel: Frame
local tooltip: Frame
local tooltipTitle: TextLabel
local tooltipBody: TextLabel

type SlotView = { button: TextButton, swatch: Frame, count: TextLabel, glow: UIStroke }

local slotButtons: { SlotView } = {}
local armorButtons: { [string]: SlotView } = {}

local stationTitle: TextLabel
local tabRow: Frame
local tabButtons: { [string]: TextButton } = {}
local contentFrames: { [string]: Frame } = {}

local craftList: ScrollingFrame
local craftRows: { Frame } = {}
local craftSearch: TextBox
local stationHint: TextLabel

local furnaceSlots: { [string]: SlotView } = {}
local furnaceProgress: Theme.Bar
local furnaceBurn: Theme.Bar
local furnaceHint: TextLabel

local modTarget: { [string]: TextLabel } = {}
local modCost: { [string]: TextLabel } = {}
local modButton: { [string]: TextButton } = {}
local modPreview: { [string]: TextLabel } = {}

local shopList: ScrollingFrame
local shopCoins: TextLabel

-- ===== الحالة =====
local selected: number? = nil
local shopData: any = nil
local stationData: any = nil
local activeTab = "craft"
local craftDirty = true
local craftRefresh = 0
local stationSignature = ""
local searchText = ""

local TAB_NAMES = { craft = "تصنيع", smelt = "صهر", upgrade = "تطوير", enchant = "سحر" }
local STATION_NAMES = {
	workbench = "طاولة العمل",
	furnace = "الفرن",
	anvil = "السندان",
	alchemy = "طاولة الخيمياء",
	enchant = "طاولة السحر",
}

-- ===== أدوات مشتركة =====

local function stackOf(data: any): Inventory.Stack?
	if type(data) ~= "table" or type(data.id) ~= "string" then return nil end
	local stack: Inventory.Stack = { id = data.id, n = data.n or 1 }
	if type(data.lvl) == "number" then
		stack.up = Upgrades.normalize({ lvl = data.lvl, aff = data.aff })
	end
	return stack
end

local function makeSlot(parent: Instance, position: UDim2, size: number?): SlotView
	local edge = size or SLOT
	local button = Theme.new("TextButton", {
		BackgroundColor3 = Theme.colors.slot,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(edge, edge),
		Position = position,
		ZIndex = 32,
	}, parent)
	Theme.corner(button, 7)
	local glow = Theme.stroke(button, Color3.fromRGB(10, 10, 14), 1.5)

	local swatch = Theme.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(200, 200, 200),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(edge * 0.56, edge * 0.56),
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

	return { button = button, swatch = swatch, count = count, glow = glow }
end

local function paintSlot(view: SlotView, stack: Inventory.Stack?, highlighted: boolean?)
	if stack then
		local item = Items.get(stack.id)
		view.swatch.Visible = true
		view.swatch.BackgroundColor3 = if item then item.color else Color3.fromRGB(200, 200, 200)
		view.count.Text = if stack.n > 1 then tostring(stack.n) else ""
		if Upgrades.isModified(stack) then
			-- إطار متوهج يميّز الغرض المطوّر أو المسحور
			view.glow.Color = Upgrades.displayColor(stack)
			view.glow.Thickness = 2.5
		else
			view.glow.Color = Color3.fromRGB(10, 10, 14)
			view.glow.Thickness = 1.5
		end
	else
		view.swatch.Visible = false
		view.count.Text = ""
		view.glow.Color = Color3.fromRGB(10, 10, 14)
		view.glow.Thickness = 1.5
	end
	if highlighted ~= nil then
		view.button.BackgroundColor3 = if highlighted then Theme.colors.slotActive else Theme.colors.slot
	end
end

-- ===== التلميح =====

local function buildTooltip(parent: Instance)
	tooltip = Theme.panel(parent, "Tooltip")
	tooltip.Size = UDim2.fromOffset(280, 120)
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

local function describe(stack: Inventory.Stack): string
	local item = Items.get(stack.id)
	if not item then return stack.id end
	local lines = {}

	if item.cat == "block" then table.insert(lines, "بلاطة قابلة للبناء") end

	-- الأرقام المعروضة هي الفعلية بعد التطوير والصفة
	if item.damage then table.insert(lines, string.format("الضرر: %d", Upgrades.damage(stack))) end
	if item.pick and item.pick > 0 then
		table.insert(lines, string.format("قوة المعول: %d", item.pick + Upgrades.powerBonus(stack)))
	end
	if item.axe and item.axe > 0 then
		table.insert(lines, string.format("قوة الفأس: %d", item.axe + Upgrades.powerBonus(stack)))
	end
	if item.useTime then table.insert(lines, string.format("زمن الاستخدام: %.2fث", Upgrades.useTime(stack))) end
	if item.defense then table.insert(lines, string.format("الدفاع: %d", Upgrades.defense(stack))) end
	if item.setBonus then table.insert(lines, "طقم كامل: +6 دفاع") end
	if item.heal then table.insert(lines, string.format("يستعيد %d حياة", item.heal)) end
	if item.restoreMana then table.insert(lines, string.format("يستعيد %d مانا", item.restoreMana)) end
	if item.food then table.insert(lines, string.format("يشبع %d", item.food)) end
	if item.mana then table.insert(lines, string.format("كلفة المانا: %d", item.mana)) end
	if item.ranged then table.insert(lines, "يحتاج ذخيرة: سهام") end

	local affix = Upgrades.affixOf(stack)
	if affix then
		table.insert(lines, "✦ " .. affix.name .. ": " .. affix.desc)
	end
	local level = Upgrades.levelOf(stack)
	if level > 0 then
		table.insert(lines, string.format("مستوى التطوير: +%d / +%d", level, Upgrades.MAX_LEVEL))
	end
	if Upgrades.canModify(stack.id) and level == 0 and not affix then
		table.insert(lines, "قابل للتطوير على السندان وللسحر على طاولة السحر")
	end

	local smelt = Smelting.recipeFor(stack.id)
	if smelt then
		table.insert(lines, string.format("يُصهر إلى: %s (%.0fث)", Items.name(smelt.out), smelt.time))
	end
	local fuel = Smelting.fuelValue(stack.id)
	if fuel > 0 then
		table.insert(lines, string.format("وقود: %.0f ثانية", fuel))
	end

	if item.desc then table.insert(lines, item.desc) end
	table.insert(lines, string.format("القيمة: %d عملة", item.value))
	return table.concat(lines, "\n")
end

local function showTooltip(stack: Inventory.Stack?)
	if not stack or not Items.get(stack.id) then
		tooltip.Visible = false
		return
	end
	tooltip.Visible = true
	tooltipTitle.Text = Upgrades.displayName(stack)
	tooltipTitle.TextColor3 = Upgrades.displayColor(stack)
	tooltipBody.Text = describe(stack)
	local lineCount = select(2, string.gsub(tooltipBody.Text, "\n", "")) + 1
	tooltip.Size = UDim2.fromOffset(280, 40 + lineCount * 16)
end

local function hookTooltip(button: GuiButton, getter: () -> Inventory.Stack?)
	button.MouseEnter:Connect(function() showTooltip(getter()) end)
	button.MouseLeave:Connect(function() showTooltip(nil) end)
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
				Net.get("InvAction"):FireServer("drop", index,
					if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then "all" else 1)
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
	for i, slotName in { "head", "chest", "feet" } do
		local label = Theme.label(armorBox, slotNames[slotName], 12, Theme.colors.textDim)
		label.Position = UDim2.fromOffset(0, (i - 1) * (SLOT + 22))
		label.Size = UDim2.fromOffset(120, 16)

		local view = makeSlot(armorBox, UDim2.fromOffset(120 - SLOT, (i - 1) * (SLOT + 22) + 18))
		view.button.MouseButton1Click:Connect(function()
			Net.get("InvAction"):FireServer("unequip", slotName)
		end)
		hookTooltip(view.button, function() return State.armor[slotName] end)
		armorButtons[slotName] = view
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
		local view = makeSlot(grid, UDim2.fromOffset(col * (SLOT + GAP), row * (SLOT + GAP)))
		view.button.MouseButton1Click:Connect(function() slotClicked(i, false) end)
		view.button.MouseButton2Click:Connect(function() slotClicked(i, true) end)
		hookTooltip(view.button, function() return State.slots[i] end)
		table.insert(slotButtons, view)
	end
end

-- ===== المحطات القريبة =====

local function stationsNear(): { [string]: boolean }
	local found: { [string]: boolean } = {}
	if not ClientWorld.isReady() then return found end
	local world = ClientWorld.get()
	local cx, cy = math.floor(State.body.x), math.floor(State.body.y)
	for ty = cy - STATION_RANGE, cy + STATION_RANGE do
		for tx = cx - STATION_RANGE, cx + STATION_RANGE do
			local block = Blocks.get(World.fg(world, tx, ty))
			if block.station then found[block.station] = true end
		end
	end
	return found
end

-- ===== تبويب التصنيع =====

local function refreshCrafting()
	for _, row in craftRows do row:Destroy() end
	table.clear(craftRows)

	local stations = stationsNear()
	local keys = {}
	for station in stations do table.insert(keys, station) end
	table.sort(keys)
	stationSignature = table.concat(keys, ",")

	local names = {}
	for _, station in keys do
		table.insert(names, STATION_NAMES[station] or station)
	end
	stationHint.Text = if #names > 0
		then "المحطات القريبة: " .. table.concat(names, "، ")
		else "لا توجد محطات قريبة — الوصفات اليدوية فقط"

	local query = string.lower(searchText)
	local available = Recipes.available(stations)
	local order = 0
	local totalHeight = 0

	for _, recipe in available do
		local outItem = Items.get(recipe.out.id)
		if outItem then
			local matches = query == "" or string.find(string.lower(outItem.name), query, 1, true) ~= nil
				or string.find(recipe.out.id, query, 1, true) ~= nil
			if matches then
				local canCraft = Inventory.canCraft(State.slots, recipe)
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
				hookTooltip(button, function() return { id = recipe.out.id, n = recipe.out.n } end)

				table.insert(craftRows, row)
				totalHeight += 59
			end
		end
	end

	craftList.CanvasSize = UDim2.fromOffset(0, totalHeight)
end

local function buildCraftTab(parent: Instance): Frame
	local frame = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = true,
		ZIndex = 31,
	}, parent)

	craftSearch = Theme.new("TextBox", {
		BackgroundColor3 = Theme.colors.slot,
		BorderSizePixel = 0,
		Font = Theme.font,
		PlaceholderText = "ابحث عن وصفة…",
		Text = "",
		TextSize = 13,
		TextColor3 = Theme.colors.text,
		PlaceholderColor3 = Theme.colors.textDim,
		ClearTextOnFocus = false,
		Size = UDim2.new(1, 0, 0, 26),
		ZIndex = 32,
	}, frame)
	Theme.corner(craftSearch, 6)
	craftSearch:GetPropertyChangedSignal("Text"):Connect(function()
		searchText = craftSearch.Text
		craftDirty = true
	end)

	stationHint = Theme.label(frame, "", 12, Theme.colors.textDim)
	stationHint.Position = UDim2.fromOffset(0, 30)
	stationHint.Size = UDim2.new(1, 0, 0, 18)

	craftList = Theme.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 1, -52),
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.colors.slotHover,
		ZIndex = 31,
	}, frame)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 5)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = craftList

	return frame
end

-- ===== تبويب الفرن =====

local function furnaceAction(slotName: string)
	if not stationData then return end
	local x, y = stationData.x, stationData.y
	if slotName ~= "output" and selected then
		Net.get("Station"):FireServer("give", x, y, selected, slotName)
		selected = nil
	else
		Net.get("Station"):FireServer("take", x, y, slotName)
	end
end

local function buildSmeltTab(parent: Instance): Frame
	local frame = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 31,
	}, parent)

	local big = 58
	local labels = { input = "المادة", fuel = "الوقود", output = "الناتج" }
	local positions = {
		input = UDim2.fromOffset(0, 22),
		fuel = UDim2.fromOffset(0, 22 + big + 34),
		output = UDim2.new(1, -big, 0, 22 + (big + 34) / 2),
	}

	for _, slotName in { "input", "fuel", "output" } do
		local caption = Theme.label(frame, labels[slotName], 12, Theme.colors.textDim)
		caption.Position = positions[slotName] - UDim2.fromOffset(0, 18)
		caption.Size = UDim2.fromOffset(big, 16)
		caption.TextXAlignment = Enum.TextXAlignment.Center

		local view = makeSlot(frame, positions[slotName], big)
		view.button.MouseButton1Click:Connect(function() furnaceAction(slotName) end)
		hookTooltip(view.button, function()
			return if stationData then stackOf(stationData[slotName]) else nil
		end)
		furnaceSlots[slotName] = view
	end

	furnaceProgress = Theme.bar(frame, Color3.fromRGB(60, 44, 26), Color3.fromRGB(240, 170, 70), 150, 18)
	furnaceProgress.root.Position = UDim2.fromOffset(big + 16, 22 + big / 2 - 9)

	furnaceBurn = Theme.bar(frame, Color3.fromRGB(52, 30, 24), Color3.fromRGB(230, 96, 48), 150, 12)
	furnaceBurn.root.Position = UDim2.fromOffset(big + 16, 22 + big / 2 + 16)

	furnaceHint = Theme.label(frame, "", 12, Theme.colors.textDim)
	furnaceHint.Position = UDim2.fromOffset(0, 22 + (big + 34) + big + 14)
	furnaceHint.Size = UDim2.new(1, 0, 0, 54)
	furnaceHint.TextWrapped = true
	furnaceHint.TextYAlignment = Enum.TextYAlignment.Top

	local reference = Theme.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 22 + (big + 34) + big + 72),
		Size = UDim2.new(1, 0, 1, -(22 + (big + 34) + big + 72)),
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollBarThickness = 6,
		ZIndex = 31,
	}, frame)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 3)
	layout.Parent = reference

	local height = 0
	for _, entry in Smelting.list() do
		local row = Theme.label(reference, string.format("%s ← %s ×%d (%.0fث)",
			Items.name(entry.out), Items.name(entry.input), entry.n, entry.time), 11, Theme.colors.textDim)
		row.Size = UDim2.new(1, -8, 0, 16)
		height += 19
	end
	reference.CanvasSize = UDim2.fromOffset(0, height)

	return frame
end

-- ===== تبويبا التطوير والسحر =====

local function buildModTab(parent: Instance, kind: string): Frame
	local frame = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 31,
	}, parent)

	local intro = Theme.label(frame,
		if kind == "upgrade"
			then "اختر أداة أو درعاً من المخزون، ثم طوّره. النجاح مضمون دائماً."
			else "اختر أداة أو درعاً، ثم امنحه صفة سحرية. يمكنك إعادة الرمي للحصول على صفة أخرى.",
		12, Theme.colors.textDim)
	intro.Position = UDim2.fromOffset(0, 0)
	intro.Size = UDim2.new(1, 0, 0, 34)
	intro.TextWrapped = true

	modTarget[kind] = Theme.label(frame, "لم تختر عنصراً", 16, Theme.colors.text)
	modTarget[kind].Position = UDim2.fromOffset(0, 42)
	modTarget[kind].Size = UDim2.new(1, 0, 0, 22)
	modTarget[kind].Font = Theme.fontBold

	modPreview[kind] = Theme.label(frame, "", 12, Theme.colors.textDim)
	modPreview[kind].Position = UDim2.fromOffset(0, 66)
	modPreview[kind].Size = UDim2.new(1, 0, 0, 50)
	modPreview[kind].TextWrapped = true
	modPreview[kind].TextYAlignment = Enum.TextYAlignment.Top

	modCost[kind] = Theme.label(frame, "", 13, Theme.colors.gold)
	modCost[kind].Position = UDim2.fromOffset(0, 120)
	modCost[kind].Size = UDim2.new(1, 0, 0, 40)
	modCost[kind].TextWrapped = true
	modCost[kind].TextYAlignment = Enum.TextYAlignment.Top

	modButton[kind] = Theme.button(frame,
		if kind == "upgrade" then "طوّر" else "اسحر",
		UDim2.new(1, 0, 0, 34), UDim2.fromOffset(0, 166))
	modButton[kind].TextSize = 16
	modButton[kind].MouseButton1Click:Connect(function()
		if not stationData or not selected then return end
		Net.get("Station"):FireServer(kind, stationData.x, stationData.y, selected)
	end)

	-- مرجع الصفات المتاحة
	local pool = if kind == "enchant" then "الصفات الممكنة:" else "كل مستوى: +12% للأرقام، +4 قوة أداة، −3% زمن استخدام."
	local poolLabel = Theme.label(frame, pool, 12, Theme.colors.textDim)
	poolLabel.Position = UDim2.fromOffset(0, 210)
	poolLabel.Size = UDim2.new(1, 0, 0, 18)

	if kind == "enchant" then
		local list = Theme.new("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 230),
			Size = UDim2.new(1, 0, 1, -230),
			CanvasSize = UDim2.fromOffset(0, 0),
			ScrollBarThickness = 6,
			ZIndex = 31,
		}, frame)
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 3)
		layout.Parent = list

		local height = 0
		local groupNames = { weapon = "الأسلحة", tool = "الأدوات", armor = "الدروع" }
		for _, group in { "weapon", "tool", "armor" } do
			local header = Theme.label(list, groupNames[group], 12, Theme.colors.text)
			header.Size = UDim2.new(1, -8, 0, 18)
			header.Font = Theme.fontBold
			height += 21
			for _, affix in Upgrades.pools[group] do
				local row = Theme.label(list, "✦ " .. affix.name .. " — " .. affix.desc, 11, affix.color)
				row.Size = UDim2.new(1, -8, 0, 16)
				height += 19
			end
		end
		list.CanvasSize = UDim2.fromOffset(0, height)
	end

	return frame
end

local function refreshModTab(kind: string)
	local targetLabel = modTarget[kind]
	local previewLabel = modPreview[kind]
	local costLabel = modCost[kind]
	local button = modButton[kind]
	if not targetLabel then return end

	local stack = if selected then State.slots[selected] else nil

	if not stack then
		targetLabel.Text = "لم تختر عنصراً"
		targetLabel.TextColor3 = Theme.colors.textDim
		previewLabel.Text = "انقر على أداة أو درع في المخزون لاختياره."
		costLabel.Text = ""
		button.AutoButtonColor = false
		button.BackgroundColor3 = Theme.colors.slot
		return
	end

	if not Upgrades.canModify(stack.id) then
		targetLabel.Text = Upgrades.displayName(stack)
		targetLabel.TextColor3 = Theme.colors.bad
		previewLabel.Text = "هذا العنصر غير قابل للتطوير أو السحر — الأدوات والأسلحة والدروع فقط."
		costLabel.Text = ""
		button.AutoButtonColor = false
		button.BackgroundColor3 = Theme.colors.slot
		return
	end

	targetLabel.Text = Upgrades.displayName(stack)
	targetLabel.TextColor3 = Upgrades.displayColor(stack)

	local level = Upgrades.levelOf(stack)
	local affix = Upgrades.affixOf(stack)
	local lines = {}
	table.insert(lines, string.format("المستوى الحالي: +%d / +%d", level, Upgrades.MAX_LEVEL))
	table.insert(lines, if affix then "الصفة الحالية: " .. affix.name .. " — " .. affix.desc else "بلا صفة سحرية")
	previewLabel.Text = table.concat(lines, "\n")

	local cost = if kind == "upgrade"
		then Upgrades.upgradeCost(stack.id, level)
		else Upgrades.enchantCost(stack.id)

	if not cost then
		costLabel.Text = "بلغ هذا العنصر أقصى تطوير."
		costLabel.TextColor3 = Theme.colors.textDim
		button.AutoButtonColor = false
		button.BackgroundColor3 = Theme.colors.slot
		return
	end

	local haveMaterial = Inventory.count(State.slots, cost.material)
	local haveCoins = Inventory.count(State.slots, "coin")
	local affordable = haveMaterial >= cost.amount and haveCoins >= cost.coins

	costLabel.Text = string.format("الكلفة: %s %d/%d · عملات %d/%d",
		Items.name(cost.material), haveMaterial, cost.amount, haveCoins, cost.coins)
	costLabel.TextColor3 = if affordable then Theme.colors.good else Theme.colors.bad
	button.AutoButtonColor = affordable
	button.BackgroundColor3 = if affordable then Theme.colors.panelLight else Theme.colors.slot
end

-- ===== نافذة المحطة =====

local function setTab(tab: string)
	activeTab = tab
	for name, frame in contentFrames do
		frame.Visible = name == tab
	end
	for name, button in tabButtons do
		button.BackgroundColor3 = if name == tab then Theme.colors.slotActive else Theme.colors.panelLight
	end
	if tab == "craft" then craftDirty = true end
end

local function setAvailableTabs(tabs: { string })
	local x = 0
	local present: { [string]: boolean } = {}
	for _, tab in tabs do present[tab] = true end

	for name, button in tabButtons do
		button.Visible = present[name] == true
	end
	for _, tab in tabs do
		local button = tabButtons[tab]
		if button then
			button.Position = UDim2.fromOffset(x, 0)
			x += 84
		end
	end

	if not present[activeTab] then
		setTab(tabs[1] or "craft")
	else
		setTab(activeTab)
	end
end

local function buildStation(parent: Instance)
	stationPanel = Theme.panel(parent, "Station")
	stationPanel.Size = UDim2.fromOffset(400, 500)
	stationPanel.Position = UDim2.new(1, -430, 0, 90)
	Theme.padding(stationPanel, 12)

	stationTitle = Theme.label(stationPanel, "التصنيع", 18, Theme.colors.text)
	stationTitle.Size = UDim2.new(1, 0, 0, 22)
	stationTitle.Font = Theme.fontBold

	tabRow = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 28),
		ZIndex = 31,
	}, stationPanel)

	for _, tab in { "craft", "smelt", "upgrade", "enchant" } do
		local button = Theme.button(tabRow, TAB_NAMES[tab], UDim2.fromOffset(78, 26), UDim2.fromOffset(0, 0))
		button.Visible = false
		button.MouseButton1Click:Connect(function() setTab(tab) end)
		tabButtons[tab] = button
	end

	local content = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 1, -60),
		ZIndex = 31,
	}, stationPanel)

	contentFrames.craft = buildCraftTab(content)
	contentFrames.smelt = buildSmeltTab(content)
	contentFrames.upgrade = buildModTab(content, "upgrade")
	contentFrames.enchant = buildModTab(content, "enchant")
end

-- ===== المتجر =====

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
		if not selected then return end
		local stack = State.slots[selected]
		if stack then
			Net.get("Shop"):FireServer("sell", stack.id, stack.n)
			selected = nil
		end
	end)
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
	buildStation(root)
	buildShop(parent)
	buildTooltip(parent)
	setAvailableTabs({ "craft" })
end

function Panels.setOpen(open: boolean)
	root.Visible = open
	State.uiOpen = open
	if not open then
		selected = nil
		showTooltip(nil)
		if stationData then
			Net.get("Station"):FireServer("close")
			stationData = nil
		end
		stationTitle.Text = "التصنيع"
		setAvailableTabs({ "craft" })
	else
		craftDirty = true
	end
end

function Panels.isOpen(): boolean
	return root.Visible
end

-- استُدعيت عند فتح محطة من العالم (الزر الأيمن على البلاطة)
function Panels.openStation(payload: any)
	if type(payload) ~= "table" or payload.open ~= true then
		stationData = nil
		if root.Visible then
			stationTitle.Text = "التصنيع"
			setAvailableTabs({ "craft" })
		end
		return
	end

	stationData = payload
	root.Visible = true
	State.uiOpen = true
	stationTitle.Text = STATION_NAMES[payload.kind] or "محطة"

	local tabs = { "craft" }
	if payload.kind == "furnace" then
		table.insert(tabs, "smelt")
	elseif payload.kind == "anvil" then
		table.insert(tabs, "upgrade")
	elseif payload.kind == "enchant" then
		table.insert(tabs, "enchant")
	end

	-- افتح مباشرة على التبويب المميّز لهذه المحطة
	local preferred = tabs[#tabs]
	activeTab = preferred
	setAvailableTabs(tabs)
	craftDirty = true
end

function Panels.closeAll()
	Panels.setOpen(false)
	shopPanel.Visible = false
	State.shopOpen = false
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

function Panels.onInventoryChanged()
	craftDirty = true
	if shopPanel.Visible and shopData then
		shopData.coins = Inventory.count(State.slots, "coin")
		shopCoins.Text = string.format("عملاتك: %d", shopData.coins)
	end
end

function Panels.update(dt: number)
	if not root.Visible then return end

	for i, view in slotButtons do
		local stack = State.slots[i]
		local isSelected = selected == i
		view.button.BackgroundColor3 = if isSelected then Theme.colors.slotActive
			elseif i <= Config.HOTBAR then Theme.colors.slotHover
			else Theme.colors.slot
		paintSlot(view, stack)
	end

	for slotName, view in armorButtons do
		paintSlot(view, State.armor[slotName])
	end

	if activeTab == "craft" then
		craftRefresh -= dt
		if craftRefresh <= 0 then
			craftRefresh = 0.35
			local stations = stationsNear()
			local keys = {}
			for station in stations do table.insert(keys, station) end
			table.sort(keys)
			if table.concat(keys, ",") ~= stationSignature then craftDirty = true end
		end
		if craftDirty then
			craftDirty = false
			refreshCrafting()
		end

	elseif activeTab == "smelt" then
		if stationData then
			for slotName, view in furnaceSlots do
				paintSlot(view, stackOf(stationData[slotName]))
			end
			local progressMax = stationData.progressMax or 0
			Theme.setBar(furnaceProgress, stationData.progress or 0, math.max(0.01, progressMax),
				if progressMax > 0 then string.format("%.0f%%", (stationData.progress or 0) / progressMax * 100) else "متوقف")
			local burnMax = stationData.burnMax or 0
			Theme.setBar(furnaceBurn, stationData.burn or 0, math.max(0.01, burnMax),
				if (stationData.burn or 0) > 0 then string.format("وقود %.0fث", stationData.burn) else "بلا وقود")

			local input = stackOf(stationData.input)
			local smelt = Smelting.recipeFor(if input then input.id else nil)
			if not input then
				furnaceHint.Text = "ضع مادة خاماً في خانة المادة، ووقوداً (فحم أو خشب) في خانة الوقود."
			elseif not smelt then
				furnaceHint.Text = "هذه المادة لا تُصهر."
			elseif (stationData.burn or 0) <= 0 and Smelting.fuelValue(if stackOf(stationData.fuel) then (stackOf(stationData.fuel) :: Inventory.Stack).id else nil) <= 0 then
				furnaceHint.Text = "الفرن بحاجة إلى وقود."
			else
				furnaceHint.Text = string.format("يصهر %s ← %s. الفرن يعمل حتى وأنت بعيد عنه.",
					Items.name(input.id), Items.name(smelt.out))
			end
		end

	elseif activeTab == "upgrade" or activeTab == "enchant" then
		refreshModTab(activeTab)
	end

	if tooltip.Visible then
		local mouse = UserInputService:GetMouseLocation()
		local inset = GuiService:GetGuiInset()
		tooltip.Position = UDim2.fromOffset(mouse.X + inset.X + 18, mouse.Y + inset.Y + 12)
	end
end

return Panels
