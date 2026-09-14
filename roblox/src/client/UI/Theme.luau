--!strict
--[[
	Theme — لغة الواجهة البكسلية.

	كل لوحة وزر وخانة تُرسم بإطار تسعي (9-slice) مولّد بكسلاً بكسلاً: حافة
	مشطوفة فاتحة أعلى/يسار وداكنة أسفل/يمين، فتبقى الحواف حادّة وسُمكها ثابت
	مهما تمدّد العنصر.

	ملاحظة عن الخطوط: النص العربي يحتاج خطاً يدعم العربية، وخطوط روبلوكس
	البكسلية (Arcade) لا تدعمها. لذلك: أرقام الواجهة بخط بكسلي، والنصوص
	العربية بخط واضح — وهو حلّ وسط مقصود لا إهمال.
]]

local Atlas = require(script.Parent.Parent.Atlas)

local Theme = {}

Theme.font = Enum.Font.GothamMedium
Theme.fontBold = Enum.Font.GothamBold
Theme.fontNumber = Enum.Font.Arcade -- للأرقام فقط (لا يدعم العربية)

Theme.colors = {
	panel = Color3.fromRGB(34, 32, 44),
	panelLight = Color3.fromRGB(62, 60, 78),
	slot = Color3.fromRGB(52, 50, 66),
	slotHover = Color3.fromRGB(74, 72, 94),
	slotActive = Color3.fromRGB(120, 150, 220),
	border = Color3.fromRGB(10, 9, 14),
	text = Color3.fromRGB(238, 238, 244),
	textDim = Color3.fromRGB(166, 166, 182),
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

-- خلفية تسعية تملأ العنصر الأب
function Theme.slice(parent: GuiObject, piece: string, zindex: number): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = "Skin"
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Size = UDim2.fromScale(1, 1)
	image.ZIndex = zindex
	image.Parent = parent
	Atlas.applySlice(image, piece)
	return image
end

-- متوافقة مع النداءات القديمة: لا زوايا دائرية في أسلوب البكسل
function Theme.corner(_instance: GuiObject, _radius: number?) end

function Theme.stroke(instance: GuiObject, color: Color3?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.colors.border
	stroke.Thickness = thickness or 2
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

-- لوحة: إطار شفاف تملؤه خلفية تسعية، فتبقى الأبناء كما هي
function Theme.panel(parent: Instance, name: string): Frame
	local frame = Theme.new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 30,
	}, parent)
	Theme.slice(frame, "panel", 29)
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

-- تسمية رقمية بخط بكسلي
function Theme.number(parent: Instance, text: string, size: number, color: Color3?): TextLabel
	return Theme.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.fontNumber,
		Text = text,
		TextSize = size,
		TextColor3 = color or Theme.colors.text,
		TextStrokeTransparency = 0.2,
		ZIndex = 33,
	}, parent)
end

function Theme.button(parent: Instance, text: string, size: UDim2, position: UDim2): TextButton
	local button = Theme.new("TextButton", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Theme.fontBold,
		Text = text,
		TextSize = 14,
		TextColor3 = Theme.colors.text,
		Size = size,
		Position = position,
		AutoButtonColor = false,
		ZIndex = 33,
	}, parent)
	local skin = Theme.slice(button, "button", 32)

	button.MouseEnter:Connect(function()
		skin.ImageColor3 = Color3.fromRGB(150, 150, 170)
	end)
	button.MouseLeave:Connect(function()
		skin.ImageColor3 = Color3.fromRGB(255, 255, 255)
	end)
	return button
end

-- خانة مخزون بكسلية
export type Slot = { button: TextButton, skin: ImageLabel }

function Theme.slotButton(parent: Instance, size: number, position: UDim2): Slot
	local button = Theme.new("TextButton", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(size, size),
		Position = position,
		ZIndex = 32,
	}, parent)
	local skin = Theme.slice(button, "slot", 31)
	return { button = button, skin = skin }
end

function Theme.setSlotState(slot: Slot, state: string)
	if state == "active" then
		Atlas.applySlice(slot.skin, "slot_active")
		slot.skin.ImageColor3 = Color3.fromRGB(255, 255, 255)
	else
		Atlas.applySlice(slot.skin, "slot")
		slot.skin.ImageColor3 = if state == "hover"
			then Color3.fromRGB(190, 190, 210)
			else Color3.fromRGB(255, 255, 255)
	end
end

-- ===== الأشرطة =====

export type Bar = { root: Frame, fill: ImageLabel, label: TextLabel }

function Theme.bar(parent: Instance, back: Color3, front: Color3, width: number, height: number): Bar
	local root = Theme.new("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(width, height),
		ZIndex = 31,
	}, parent)

	local frame = Theme.slice(root, "bar_frame", 31)
	frame.ImageColor3 = back

	local fill = Theme.new("ImageLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		ImageColor3 = front,
		ZIndex = 32,
	}, root)
	Atlas.applyUI(fill, "bar_fill")
	fill.ScaleType = Enum.ScaleType.Stretch

	local label = Theme.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.fontNumber,
		Text = "",
		TextSize = math.max(10, height - 6),
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextStrokeTransparency = 0.25,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 34,
	}, root)

	return { root = root, fill = fill, label = label }
end

function Theme.setBar(bar: Bar, value: number, max: number, text: string?)
	local ratio = math.clamp(value / math.max(1, max), 0, 1)
	bar.fill.Size = UDim2.new(ratio, -4, 1, -4)
	bar.label.Text = text or string.format("%d / %d", math.floor(value), math.floor(max))
end

-- ===== أيقونة عنصر من الأطلس =====

function Theme.itemIcon(parent: Instance, size: number, zindex: number): ImageLabel
	local icon = Theme.new("ImageLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromOffset(size, size),
		Visible = false,
		ZIndex = zindex,
	}, parent)
	Atlas.apply(icon, "items")
	return icon
end

function Theme.setItemIcon(icon: ImageLabel, itemId: string?)
	if not itemId then
		icon.Visible = false
		return
	end
	icon.Visible = true
	Atlas.setRect(icon, Atlas.itemRect(itemId))
end

return Theme
