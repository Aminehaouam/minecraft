--!strict
--[[
	Minimap — خريطة مصغّرة مرسومة بكسلاً بكسلاً في EditableImage.

	كل بلاطة = بكسل واحد بلون كتلتها، والجدران الخلفية تظهر أغمق، وغير
	المحمّل يظهر أسود. هذه أرخص طريقة ممكنة: تحديث واحد للصورة كل ربع ثانية
	بدل آلاف الإطارات.
]]

local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Blocks = require(Shared.Blocks)
local Config = require(Shared.Config)
local World = require(Shared.World)

local Atlas = require(script.Parent.Atlas)
local ClientWorld = require(script.Parent.ClientWorld)
local State = require(script.Parent.State)

local Minimap = {}

local WIDTH = 176
local HEIGHT = 116
local SCALE = 2 -- بكسلات الشاشة لكل بكسل خريطة
local REFRESH = 0.25

local image: EditableImage? = nil
local pixels = buffer.create(WIDTH * HEIGHT * 4)
local frame: Frame? = nil
local display: ImageLabel? = nil
local coords: TextLabel? = nil
local timer = 0
local visible = true

local function writePixel(index: number, r: number, g: number, b: number)
	local offset = index * 4
	buffer.writeu8(pixels, offset, r)
	buffer.writeu8(pixels, offset + 1, g)
	buffer.writeu8(pixels, offset + 2, b)
	buffer.writeu8(pixels, offset + 3, 255)
end

function Minimap.build(parent: Instance)
	local Theme = require(script.Parent.UI.Theme)

	frame = Theme.panel(parent, "Minimap")
	local panel = frame :: Frame
	panel.Size = UDim2.fromOffset(WIDTH * SCALE + 12, HEIGHT * SCALE + 28)
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -16, 1, -16)
	panel.ZIndex = 28

	display = Instance.new("ImageLabel")
	local label = display :: ImageLabel
	label.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
	label.BorderSizePixel = 0
	label.Position = UDim2.fromOffset(6, 6)
	label.Size = UDim2.fromOffset(WIDTH * SCALE, HEIGHT * SCALE)
	label.ZIndex = 29
	label.Parent = panel

	image = Atlas.createDynamic("minimap", WIDTH, HEIGHT)
	if image then
		Atlas.apply(label, "minimap")
	end

	coords = Theme.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.fontNumber,
		Text = "",
		TextSize = 12,
		TextColor3 = Theme.colors.textDim,
		Position = UDim2.fromOffset(6, HEIGHT * SCALE + 8),
		Size = UDim2.fromOffset(WIDTH * SCALE, 16),
		ZIndex = 31,
	}, panel)
end

function Minimap.toggle()
	visible = not visible
	if frame then (frame :: Frame).Visible = visible end
end

function Minimap.isVisible(): boolean
	return visible
end

function Minimap.update(dt: number)
	if not visible or not image or not ClientWorld.isReady() then return end
	timer -= dt
	if timer > 0 then return end
	timer = REFRESH

	local world = ClientWorld.get()
	local originX = math.floor(State.body.x) - WIDTH // 2
	local originY = math.floor(State.body.y) - HEIGHT // 2

	for py = 0, HEIGHT - 1 do
		local ty = originY + py
		local rowBase = py * WIDTH
		for px = 0, WIDTH - 1 do
			local tx = originX + px
			local index = rowBase + px

			if not World.inBounds(tx, ty) then
				writePixel(index, 6, 6, 9)
			else
				local fgId = World.fgRaw(world, tx, ty)
				if fgId == nil then
					writePixel(index, 10, 10, 14) -- غير مستكشف
				elseif fgId ~= 0 then
					local block = Blocks.get(fgId)
					local shade = if block.liquid then 0.9 else 1
					writePixel(index,
						block.color.R * 255 * shade,
						block.color.G * 255 * shade,
						block.color.B * 255 * shade)
				else
					local bgId = World.bgRaw(world, tx, ty) or 0
					if bgId ~= 0 then
						local wall = Blocks.get(bgId)
						writePixel(index, wall.color.R * 90, wall.color.G * 90, wall.color.B * 90)
					elseif ty < Config.SURFACE - 10 then
						writePixel(index, 40, 58, 82) -- سماء
					else
						writePixel(index, 16, 16, 22) -- فراغ تحت الأرض
					end
				end
			end
		end
	end

	-- علامة اللاعب: صليب أبيض في المنتصف
	local cx, cy = WIDTH // 2, HEIGHT // 2
	for d = -2, 2 do
		writePixel(cy * WIDTH + math.clamp(cx + d, 0, WIDTH - 1), 255, 255, 255)
		writePixel(math.clamp(cy + d, 0, HEIGHT - 1) * WIDTH + cx, 255, 255, 255)
	end

	-- علامات اللاعبين الآخرين
	for userId, peer in State.peers do
		if userId ~= State.userId then
			local px = math.floor((peer.rx or peer.x) - originX)
			local py = math.floor((peer.ry or peer.y) - originY)
			if px >= 0 and py >= 0 and px < WIDTH and py < HEIGHT then
				writePixel(py * WIDTH + px, 120, 220, 255)
			end
		end
	end

	pcall(function()
		(image :: EditableImage):WritePixelsBuffer(Vector2.zero, Vector2.new(WIDTH, HEIGHT), pixels)
	end)

	if coords then
		(coords :: TextLabel).Text = string.format("X %d   Y %d",
			math.floor(State.body.x), math.floor(State.body.y - Config.SURFACE))
	end
end

function Minimap.start()
	UserInputService.InputBegan:Connect(function(io, processed)
		if processed then return end
		if io.KeyCode == Enum.KeyCode.M then
			Minimap.toggle()
		end
	end)
end

return Minimap
