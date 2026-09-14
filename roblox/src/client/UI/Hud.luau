--!strict
--[[
	Hud — الواجهة الدائمة: الأشرطة، شريط الأدوات، الساعة، التعزيزات،
	شريط الزعيم، الإشعارات، شاشة الموت، وأزرار اللمس.
]]

local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Buffs = require(Shared.Buffs)
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Net = require(Shared.Net)
local Util = require(Shared.Util)
local WorldGen = require(Shared.WorldGen)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)

local Hud = {}

local root: Frame
local hpBar: Theme.Bar
local manaBar: Theme.Bar
local foodBar: Theme.Bar
local defenseLabel: TextLabel
local clockLabel: TextLabel
local depthLabel: TextLabel
local coinLabel: TextLabel
local buffRow: Frame
local buffIcons: { Frame } = {}
local buffSignature = ""
local hotbarSlots: { { root: TextButton, swatch: Frame, count: TextLabel, key: TextLabel } } = {}
local hotbarName: TextLabel
local bossFrame: Frame
local bossBar: Theme.Bar
local bossName: TextLabel
local notifyRoot: Frame
local notifications: { { frame: Frame, life: number } } = {}
local deathFrame: Frame
local deathLabel: TextLabel
local respawnButton: TextButton
local wallModeLabel: TextLabel
local loadingLabel: TextLabel
local touchRoot: Frame

local onHotbarSelect: ((number) -> ())? = nil
local onToggleInventory: (() -> ())? = nil

-- ===== البناء =====

local function buildStats(parent: Instance)
	local box = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 14),
		Size = UDim2.fromOffset(260, 120),
		ZIndex = 30,
	}, parent)

	hpBar = Theme.bar(box, Theme.colors.hpBack, Theme.colors.hp, 230, 22)
	hpBar.root.Position = UDim2.fromOffset(0, 0)

	manaBar = Theme.bar(box, Theme.colors.manaBack, Theme.colors.mana, 180, 16)
	manaBar.root.Position = UDim2.fromOffset(0, 28)

	foodBar = Theme.bar(box, Theme.colors.foodBack, Theme.colors.food, 140, 12)
	foodBar.root.Position = UDim2.fromOffset(0, 50)

	defenseLabel = Theme.label(box, "", 14, Theme.colors.textDim)
	defenseLabel.Position = UDim2.fromOffset(0, 66)
	defenseLabel.Size = UDim2.fromOffset(230, 18)
	defenseLabel.TextXAlignment = Enum.TextXAlignment.Left

	buffRow = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 88),
		Size = UDim2.fromOffset(240, 26),
		ZIndex = 30,
	}, box)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 4)
	layout.Parent = buffRow
end

local function buildInfo(parent: Instance)
	local box = Theme.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(260, 90),
		ZIndex = 30,
	}, parent)

	clockLabel = Theme.label(box, "", 18, Theme.colors.text)
	clockLabel.Size = UDim2.fromOffset(260, 24)
	clockLabel.Font = Theme.fontBold

	depthLabel = Theme.label(box, "", 14, Theme.colors.textDim)
	depthLabel.Position = UDim2.fromOffset(0, 26)
	depthLabel.Size = UDim2.fromOffset(260, 20)

	coinLabel = Theme.label(box, "", 15, Theme.colors.gold)
	coinLabel.Position = UDim2.fromOffset(0, 48)
	coinLabel.Size = UDim2.fromOffset(260, 20)

	wallModeLabel = Theme.label(box, "", 13, Theme.colors.slotActive)
	wallModeLabel.Position = UDim2.fromOffset(0, 68)
	wallModeLabel.Size = UDim2.fromOffset(260, 18)

	loadingLabel = Theme.label(box, "", 12, Theme.colors.textDim)
	loadingLabel.Position = UDim2.fromOffset(0, 86)
	loadingLabel.Size = UDim2.fromOffset(260, 18)
end

local function buildHotbar(parent: Instance)
	local slotSize = 54
	local gap = 6
	local total = Config.HOTBAR * slotSize + (Config.HOTBAR - 1) * gap

	local box = Theme.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(total, slotSize + 22),
		ZIndex = 30,
	}, parent)

	hotbarName = Theme.label(box, "", 15, Theme.colors.text)
	hotbarName.AnchorPoint = Vector2.new(0.5, 0)
	hotbarName.Position = UDim2.new(0.5, 0, 0, 0)
	hotbarName.Size = UDim2.fromOffset(360, 18)
	hotbarName.TextXAlignment = Enum.TextXAlignment.Center
	hotbarName.Font = Theme.fontBold

	for i = 1, Config.HOTBAR do
		local button = Theme.new("TextButton", {
			BackgroundColor3 = Theme.colors.slot,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.fromOffset(slotSize, slotSize),
			Position = UDim2.fromOffset((i - 1) * (slotSize + gap), 20),
			ZIndex = 31,
		}, box)
		Theme.corner(button, 8)
		Theme.stroke(button, Color3.fromRGB(10, 10, 14), 2)

		local swatch = Theme.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(200, 200, 200),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromOffset(30, 30),
			Visible = false,
			ZIndex = 32,
		}, button)
		Theme.corner(swatch, 5)

		local count = Theme.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.fontBold,
			Text = "",
			TextSize = 13,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextStrokeTransparency = 0.3,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -4, 1, -2),
			Size = UDim2.fromOffset(40, 16),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 33,
		}, button)

		local key = Theme.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.font,
			Text = tostring(i % 10),
			TextSize = 11,
			TextColor3 = Theme.colors.textDim,
			Position = UDim2.fromOffset(4, 2),
			Size = UDim2.fromOffset(16, 14),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 33,
		}, button)

		button.MouseButton1Click:Connect(function()
			if onHotbarSelect then onHotbarSelect(i) end
		end)

		table.insert(hotbarSlots, { root = button, swatch = swatch, count = count, key = key })
	end
end

local function buildBoss(parent: Instance)
	bossFrame = Theme.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(460, 46),
		Visible = false,
		ZIndex = 34,
	}, parent)

	bossName = Theme.label(bossFrame, "", 18, Color3.fromRGB(255, 210, 210))
	bossName.Size = UDim2.fromOffset(460, 20)
	bossName.TextXAlignment = Enum.TextXAlignment.Center
	bossName.Font = Theme.fontBold

	bossBar = Theme.bar(bossFrame, Color3.fromRGB(58, 16, 20), Color3.fromRGB(228, 58, 62), 460, 20)
	bossBar.root.Position = UDim2.fromOffset(0, 24)
end

local function buildNotify(parent: Instance)
	notifyRoot = Theme.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.fromOffset(520, 200),
		ZIndex = 36,
	}, parent)
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = notifyRoot
end

local function buildDeath(parent: Instance)
	deathFrame = Theme.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 40,
	}, parent)

	deathLabel = Theme.label(deathFrame, "لقد مِتّ", 44, Color3.fromRGB(232, 72, 72))
	deathLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	deathLabel.Position = UDim2.fromScale(0.5, 0.42)
	deathLabel.Size = UDim2.fromOffset(600, 60)
	deathLabel.TextXAlignment = Enum.TextXAlignment.Center
	deathLabel.Font = Theme.fontBold
	deathLabel.ZIndex = 41

	respawnButton = Theme.button(deathFrame, "العودة للحياة", UDim2.fromOffset(220, 48), UDim2.fromScale(0.5, 0.55))
	respawnButton.AnchorPoint = Vector2.new(0.5, 0.5)
	respawnButton.TextSize = 18
	respawnButton.ZIndex = 42
	respawnButton.MouseButton1Click:Connect(function()
		Net.get("Respawn"):FireServer()
	end)
end

local function buildTouch(parent: Instance)
	touchRoot = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = UserInputService.TouchEnabled,
		ZIndex = 35,
	}, parent)

	local function touchButton(text: string, position: UDim2, size: Vector2, action: string)
		local button = Theme.new("TextButton", {
			BackgroundColor3 = Theme.colors.panelLight,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Text = text,
			Font = Theme.fontBold,
			TextSize = 22,
			TextColor3 = Theme.colors.text,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			Size = UDim2.fromOffset(size.X, size.Y),
			AutoButtonColor = false,
			ZIndex = 35,
		}, touchRoot)
		Theme.corner(button, 14)
		Theme.stroke(button, Color3.fromRGB(10, 10, 14), 2)

		button.InputBegan:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.Touch then
				Hud.touchAction(action, true)
				button.BackgroundTransparency = 0.1
			end
		end)
		button.InputEnded:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.Touch then
				Hud.touchAction(action, false)
				button.BackgroundTransparency = 0.35
			end
		end)
		return button
	end

	touchButton("◀", UDim2.new(0, 72, 1, -170), Vector2.new(70, 70), "left")
	touchButton("▶", UDim2.new(0, 156, 1, -170), Vector2.new(70, 70), "right")
	touchButton("▼", UDim2.new(0, 114, 1, -96), Vector2.new(70, 60), "down")
	touchButton("▲", UDim2.new(1, -90, 1, -180), Vector2.new(80, 80), "jump")
	touchButton("⛏", UDim2.new(1, -186, 1, -120), Vector2.new(76, 76), "primary")
	touchButton("⚔", UDim2.new(1, -96, 1, -96), Vector2.new(70, 66), "secondary")

	local invButton = Theme.button(touchRoot, "🎒", UDim2.fromOffset(60, 50), UDim2.new(1, -80, 0, 120))
	invButton.AnchorPoint = Vector2.new(0.5, 0.5)
	invButton.TextSize = 24
	invButton.MouseButton1Click:Connect(function()
		if onToggleInventory then onToggleInventory() end
	end)
end

local touchCallback: ((string, boolean) -> ())? = nil

function Hud.touchAction(action: string, down: boolean)
	if touchCallback then touchCallback(action, down) end
end

function Hud.onTouch(fn: (string, boolean) -> ())
	touchCallback = fn
end

function Hud.onHotbar(fn: (number) -> ())
	onHotbarSelect = fn
end

function Hud.onInventoryButton(fn: () -> ())
	onToggleInventory = fn
end

function Hud.build(parent: Instance)
	root = Theme.new("Frame", {
		Name = "Hud",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 30,
	}, parent)

	buildStats(root)
	buildInfo(root)
	buildHotbar(root)
	buildBoss(root)
	buildNotify(root)
	buildDeath(root)
	buildTouch(root)
end

-- ===== التحديث =====

local BIOME_NAMES = {
	forest = "غابة",
	desert = "صحراء",
	snow = "أرض ثلجية",
	jungle = "أدغال",
	plains = "سهول",
}

local function layerName(y: number): string
	if y >= Config.HELL_Y then return "الجحيم" end
	if y >= Config.CAVERN_Y then return "الأعماق" end
	if y >= Config.SURFACE + 40 then return "تحت الأرض" end
	if y >= Config.SURFACE - 20 then return "السطح" end
	return "السماء"
end

function Hud.update(dt: number)
	Theme.setBar(hpBar, State.hp, State.maxHp)
	Theme.setBar(manaBar, State.mana, State.maxMana)
	Theme.setBar(foodBar, State.food, Config.FOOD_MAX, string.format("طعام %d%%", math.floor(State.food)))
	defenseLabel.Text = string.format("الدفاع: %d   |   القتلى: %d", State.defense, State.kills)

	clockLabel.Text = string.format("%s — اليوم %d", Util.clock(State.time), State.day)
	local depth = math.floor(State.body.y - Config.SURFACE)
	local biome = BIOME_NAMES[WorldGen.biomeAt(State.seed, math.floor(State.body.x))] or ""
	depthLabel.Text = string.format("%s · %s · العمق %d م", layerName(State.body.y), biome, math.max(0, depth))

	local coins = 0
	for i = 1, Config.INV_SLOTS do
		local stack = State.slots[i]
		if stack and stack.id == "coin" then coins += stack.n end
	end
	coinLabel.Text = string.format("العملات: %d", coins)

	-- التعزيزات: نعيد البناء فقط عند تغيّر المجموعة، ونحدّث العدّاد نصياً كل إطار
	local parts = {}
	for _, buff in State.buffs do
		table.insert(parts, buff.id)
	end
	table.sort(parts)
	local signature = table.concat(parts, ",")
	if signature ~= buffSignature then
		buffSignature = signature
		for _, icon in buffIcons do icon:Destroy() end
		table.clear(buffIcons)
		for _, buff in State.buffs do
			local def = Buffs.get(buff.id)
			if def then
				local icon = Theme.new("Frame", {
					Name = buff.id,
					BackgroundColor3 = def.color,
					BorderSizePixel = 0,
					Size = UDim2.fromOffset(24, 24),
					ZIndex = 31,
				}, buffRow)
				Theme.corner(icon, 5)
				Theme.stroke(icon, Color3.fromRGB(10, 10, 14), 1.5)
				Theme.new("TextLabel", {
					Name = "Timer",
					BackgroundTransparency = 1,
					Font = Theme.fontBold,
					Text = "",
					TextSize = 10,
					TextColor3 = Color3.fromRGB(20, 20, 24),
					Size = UDim2.fromScale(1, 1),
					ZIndex = 32,
				}, icon)
				table.insert(buffIcons, icon)
			end
		end
	end
	for _, buff in State.buffs do
		local icon = buffRow:FindFirstChild(buff.id)
		if icon then
			local timer = icon:FindFirstChild("Timer")
			if timer and timer:IsA("TextLabel") then
				timer.Text = tostring(math.ceil(buff.t))
			end
		end
	end

	-- شريط الأدوات
	for i, slot in hotbarSlots do
		local stack = State.slots[i]
		local selected = i == State.hotbar
		slot.root.BackgroundColor3 = if selected then Theme.colors.slotActive else Theme.colors.slot
		slot.root.BackgroundTransparency = if selected then 0.05 else 0.25
		if stack then
			local item = Items.get(stack.id)
			slot.swatch.Visible = true
			slot.swatch.BackgroundColor3 = if item then item.color else Color3.fromRGB(200, 200, 200)
			slot.count.Text = if stack.n > 1 then tostring(stack.n) else ""
		else
			slot.swatch.Visible = false
			slot.count.Text = ""
		end
	end

	local held = State.heldItem()
	if held then
		local item = Items.get(held.id)
		if item then
			hotbarName.Text = item.name
			hotbarName.TextColor3 = Items.RARITY_COLORS[item.rarity] or Theme.colors.text
		else
			hotbarName.Text = held.id
		end
	else
		hotbarName.Text = ""
	end

	loadingLabel.Text = if State.pending > 0
		then string.format("جارٍ تحميل العالم… (%d)", State.pending)
		else ""

	-- الزعيم
	if State.boss and State.boss.active then
		bossFrame.Visible = true
		bossName.Text = State.boss.name or "زعيم"
		Theme.setBar(bossBar, State.boss.hp or 0, State.boss.maxHp or 1)
	else
		bossFrame.Visible = false
	end

	-- شاشة الموت
	deathFrame.Visible = State.dead
	if State.dead then
		local remaining = math.max(0, State.respawnIn)
		if remaining > 0.1 then
			respawnButton.Text = string.format("العودة خلال %.0f", remaining)
			respawnButton.AutoButtonColor = false
		else
			respawnButton.Text = "العودة للحياة"
			respawnButton.AutoButtonColor = true
		end
	end

	-- الإشعارات
	for i = #notifications, 1, -1 do
		local entry = notifications[i]
		entry.life -= dt
		if entry.life <= 0 then
			entry.frame:Destroy()
			table.remove(notifications, i)
		elseif entry.life < 0.6 then
			entry.frame.BackgroundTransparency = 1 - entry.life / 0.6 * 0.85
			for _, child in entry.frame:GetChildren() do
				if child:IsA("TextLabel") then
					child.TextTransparency = 1 - entry.life / 0.6
				end
			end
		end
	end
end

function Hud.setWallMode(enabled: boolean)
	wallModeLabel.Text = if enabled then "وضع الجدران: مُفعّل (F)" else ""
end

function Hud.notify(text: string, color: Color3?, big: boolean?)
	local frame = Theme.new("Frame", {
		BackgroundColor3 = Theme.colors.panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(if big then 460 else 380, if big then 40 else 32),
		ZIndex = 36,
	}, notifyRoot)
	Theme.corner(frame, 8)
	Theme.stroke(frame, color or Theme.colors.border, 1.5)

	Theme.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = if big then Theme.fontBold else Theme.font,
		Text = text,
		TextSize = if big then 18 else 15,
		TextColor3 = color or Theme.colors.text,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 37,
	}, frame)

	table.insert(notifications, { frame = frame, life = if big then 5 else 3.2 })
	if #notifications > 6 then
		local oldest = table.remove(notifications, 1)
		if oldest then oldest.frame:Destroy() end
	end
end

return Hud
