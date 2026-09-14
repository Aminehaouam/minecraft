--!strict
--[[ Theme — لغة بصرية موحّدة للواجهة + مساعدات إنشاء سريعة. ]]

local Theme = {}

Theme.font = Enum.Font.GothamMedium
Theme.fontBold = Enum.Font.GothamBold

Theme.colors = {
	panel = Color3.fromRGB(24, 24, 32),
	panelLight = Color3.fromRGB(38, 38, 50),
	slot = Color3.fromRGB(48, 48, 62),
	slotHover = Color3.fromRGB(70, 70, 90),
	slotActive = Color3.fromRGB(120, 150, 220),
	border = Color3.fromRGB(14, 14, 20),
	text = Color3.fromRGB(238, 238, 244),
	textDim = Color3.fromRGB(168, 168, 182),
	hp = Color3.fromRGB(226, 64, 74),
	hpBack = Color3.fromRGB(78, 26, 30),
	mana = Color3.fromRGB(86, 124, 236),
	manaBack = Color3.fromRGB(28, 38, 84),
	food = Color3.fromRGB(224, 158, 78),
	foodBack = Color3.fromRGB(78, 52, 24),
	good = Color3.fromRGB(120, 226, 140),
	bad = Color3.fromRGB(232, 96, 96),
	gold = Color3.fromRGB(246, 210, 96),
}

function Theme.new(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	if parent then instance.Parent = parent end
	return instance
end

function Theme.corner(instance: GuiObject, radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 6)
	corner.Parent = instance
	return corner
end

function Theme.stroke(instance: GuiObject, color: Color3?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.colors.border
	stroke.Thickness = thickness or 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = instance
	return stroke
end

function Theme.padding(instance: GuiObject, amount: number): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, amount)
	padding.PaddingBottom = UDim.new(0, amount)
	padding.PaddingLeft = UDim.new(0, amount)
	padding.PaddingRight = UDim.new(0, amount)
	padding.Parent = instance
	return padding
end

function Theme.panel(parent: Instance, name: string): Frame
	local frame = Theme.new("Frame", {
		Name = name,
		BackgroundColor3 = Theme.colors.panel,
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		ZIndex = 30,
	}, parent)
	Theme.corner(frame, 10)
	Theme.stroke(frame, Color3.fromRGB(8, 8, 12), 2)
	return frame
end

function Theme.label(parent: Instance, text: string, size: number, color: Color3?): TextLabel
	return Theme.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.font,
		Text = text,
		TextSize = size,
		TextColor3 = color or Theme.colors.text,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 32,
	}, parent)
end

function Theme.button(parent: Instance, text: string, size: UDim2, position: UDim2): TextButton
	local button = Theme.new("TextButton", {
		BackgroundColor3 = Theme.colors.panelLight,
		BorderSizePixel = 0,
		Font = Theme.fontBold,
		Text = text,
		TextSize = 14,
		TextColor3 = Theme.colors.text,
		Size = size,
		Position = position,
		AutoButtonColor = true,
		ZIndex = 33,
	}, parent)
	Theme.corner(button, 6)
	Theme.stroke(button, Color3.fromRGB(10, 10, 14), 1.5)
	return button
end

-- شريط تقدّم (حياة/مانا/جوع)
export type Bar = { root: Frame, fill: Frame, label: TextLabel }

function Theme.bar(parent: Instance, back: Color3, front: Color3, width: number, height: number): Bar
	local root = Theme.new("Frame", {
		BackgroundColor3 = back,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(width, height),
		ZIndex = 31,
	}, parent)
	Theme.corner(root, 4)
	Theme.stroke(root, Color3.fromRGB(10, 10, 14), 1.5)

	local fill = Theme.new("Frame", {
		BackgroundColor3 = front,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 32,
	}, root)
	Theme.corner(fill, 4)

	local label = Theme.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.fontBold,
		Text = "",
		TextSize = math.max(11, height - 6),
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextStrokeTransparency = 0.4,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 33,
	}, root)

	return { root = root, fill = fill, label = label }
end

function Theme.setBar(bar: Bar, value: number, max: number, text: string?)
	local ratio = math.clamp(value / math.max(1, max), 0, 1)
	bar.fill.Size = UDim2.fromScale(ratio, 1)
	bar.label.Text = text or string.format("%d / %d", math.floor(value), math.floor(max))
end

return Theme
