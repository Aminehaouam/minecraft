--!strict
--[[
	Renderer — محرك الرسم ثنائي الأبعاد.

	الفكرة الأساسية للأداء: شبكة ثابتة من الإطارات تُعاد تدويرها (torus mapping).
	الإطار في الموضع (tx % cols, ty % rows) يرسم دائماً البلاطة (tx, ty)،
	وتُحرَّك الحاوية كلها مع الكاميرا. النتيجة: تمرير سلس بلا إنشاء/حذف إطارات،
	وتحديث خصائص فقط عند تغيّر المحتوى أو الإضاءة.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Blocks = require(Shared.Blocks)
local Config = require(Shared.Config)
local Mobs = require(Shared.Mobs)
local Util = require(Shared.Util)
local World = require(Shared.World)
local WorldGen = require(Shared.WorldGen)

local ClientWorld = require(script.Parent.ClientWorld)
local Lighting = require(script.Parent.Lighting)
local Sprites = require(script.Parent.Sprites)
local State = require(script.Parent.State)

local Renderer = {}

local player = Players.LocalPlayer

local gui: ScreenGui
local skyFrame: Frame
local skyGradient: UIGradient
local starsFolder: Frame
local celestial: Frame
local cloudFolder: Frame
local hillsFar: Frame
local hillsNear: Frame
local worldRoot: Frame
local tileContainer: Frame
local entityContainer: Frame
local fxContainer: Frame

type Slot = {
	wall: Frame,
	fg: Frame,
	tx: number,
	ty: number,
	lastFg: number,
	lastBg: number,
	lastLight: number,
}

local slots: { Slot } = {}
local cols, rows = 0, 0
local tilePx = 40
local viewW, viewH = 0, 0
local shakeTime, shakeMagnitude = 0, 0

local stars: { Frame } = {}
local clouds: { Frame } = {}
local hillBarsFar: { Frame } = {}
local hillBarsNear: { Frame } = {}

-- تجمّعات الكيانات
local charSprites: { [number]: Sprites.Character } = {}
local mobSprites: { [number]: Sprites.MobSprite } = {}
local itemSprites: { [number]: Sprites.ItemSprite } = {}
local projSprites: { [number]: Sprites.ProjSprite } = {}
local localCharacter: Sprites.Character
local miningOverlay: Frame
local selectionBox: Frame

-- ===== إنشاء الواجهة =====

local function makeFrame(parent: Instance, name: string, zindex: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = zindex
	f.Parent = parent
	return f
end

local function buildSky(parent: Instance)
	skyFrame = Instance.new("Frame")
	skyFrame.Name = "Sky"
	skyFrame.Size = UDim2.fromScale(1, 1)
	skyFrame.BorderSizePixel = 0
	skyFrame.BackgroundColor3 = Color3.fromRGB(120, 180, 235)
	skyFrame.ZIndex = 1
	skyFrame.Parent = parent

	skyGradient = Instance.new("UIGradient")
	skyGradient.Rotation = 90
	skyGradient.Color = ColorSequence.new(Color3.fromRGB(96, 160, 230), Color3.fromRGB(186, 218, 240))
	skyGradient.Parent = skyFrame

	starsFolder = makeFrame(parent, "Stars", 2)
	for i = 1, 90 do
		local star = Instance.new("Frame")
		star.BorderSizePixel = 0
		star.BackgroundColor3 = Color3.fromRGB(255, 255, 245)
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Size = UDim2.fromOffset(2, 2)
		star.Position = UDim2.fromScale(math.random(), math.random() * 0.65)
		star.ZIndex = 2
		star.Parent = starsFolder
		table.insert(stars, star)
	end

	celestial = Instance.new("Frame")
	celestial.Name = "Sun"
	celestial.BorderSizePixel = 0
	celestial.AnchorPoint = Vector2.new(0.5, 0.5)
	celestial.Size = UDim2.fromOffset(74, 74)
	celestial.BackgroundColor3 = Color3.fromRGB(255, 240, 190)
	celestial.ZIndex = 3
	celestial.Parent = parent
	local sunCorner = Instance.new("UICorner")
	sunCorner.CornerRadius = UDim.new(0.5, 0)
	sunCorner.Parent = celestial

	hillsFar = makeFrame(parent, "HillsFar", 4)
	for i = 1, 40 do
		local bar = Instance.new("Frame")
		bar.BorderSizePixel = 0
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.BackgroundColor3 = Color3.fromRGB(56, 78, 96)
		bar.ZIndex = 4
		bar.Parent = hillsFar
		table.insert(hillBarsFar, bar)
	end

	hillsNear = makeFrame(parent, "HillsNear", 5)
	for i = 1, 40 do
		local bar = Instance.new("Frame")
		bar.BorderSizePixel = 0
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.BackgroundColor3 = Color3.fromRGB(40, 60, 70)
		bar.ZIndex = 5
		bar.Parent = hillsNear
		table.insert(hillBarsNear, bar)
	end

	cloudFolder = makeFrame(parent, "Clouds", 6)
	for i = 1, 16 do
		local cloud = Instance.new("Frame")
		cloud.BorderSizePixel = 0
		cloud.AnchorPoint = Vector2.new(0.5, 0.5)
		cloud.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		cloud.BackgroundTransparency = 0.15
		cloud.ZIndex = 6
		cloud.Parent = cloudFolder
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = cloud
		table.insert(clouds, cloud)
	end
end

local function buildTileGrid()
	for _, slot in slots do
		slot.wall:Destroy()
		slot.fg:Destroy()
	end
	table.clear(slots)

	tilePx = math.max(16, math.floor(viewH / Config.TILES_ON_SCREEN_Y))
	State.tilePx = tilePx
	cols = math.ceil(viewW / tilePx) + Config.RENDER_PAD * 2
	rows = Config.TILES_ON_SCREEN_Y + Config.RENDER_PAD * 2

	for i = 1, cols * rows do
		local wall = Instance.new("Frame")
		wall.BorderSizePixel = 0
		wall.Size = UDim2.fromOffset(tilePx + 1, tilePx + 1)
		wall.BackgroundColor3 = Color3.new(0, 0, 0)
		wall.BackgroundTransparency = 1
		wall.ZIndex = 2
		wall.Parent = tileContainer

		local fg = Instance.new("Frame")
		fg.BorderSizePixel = 0
		fg.Size = UDim2.fromOffset(tilePx + 1, tilePx + 1)
		fg.BackgroundColor3 = Color3.new(0, 0, 0)
		fg.BackgroundTransparency = 1
		fg.ZIndex = 3
		fg.Parent = tileContainer

		-- تدرّج خفيف يعطي إحساس الإضاءة العلوية (بلا أي صور)
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.18, Color3.fromRGB(238, 238, 238)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(188, 188, 188)),
		})
		gradient.Parent = fg

		table.insert(slots, {
			wall = wall, fg = fg,
			tx = -99999, ty = -99999,
			lastFg = -1, lastBg = -1, lastLight = -1,
		})
	end

	Lighting.resize(cols, rows)
end

function Renderer.init()
	local playerGui = player:WaitForChild("PlayerGui")

	gui = Instance.new("ScreenGui")
	gui.Name = "TerraCraft"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	-- خاصية حديثة نسبياً: نتجاهلها بهدوء على الإصدارات الأقدم من المحرّك
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.None
	end)
	gui.Parent = playerGui

	buildSky(gui)

	worldRoot = Instance.new("Frame")
	worldRoot.Name = "World"
	worldRoot.BackgroundTransparency = 1
	worldRoot.Size = UDim2.fromScale(1, 1)
	worldRoot.ClipsDescendants = true
	worldRoot.ZIndex = 7
	worldRoot.Parent = gui

	tileContainer = Instance.new("Frame")
	tileContainer.Name = "Tiles"
	tileContainer.BackgroundTransparency = 1
	tileContainer.Size = UDim2.fromOffset(0, 0)
	tileContainer.ZIndex = 2
	tileContainer.Parent = worldRoot

	entityContainer = Instance.new("Frame")
	entityContainer.Name = "Entities"
	entityContainer.BackgroundTransparency = 1
	entityContainer.Size = UDim2.fromOffset(0, 0)
	entityContainer.ZIndex = 5
	entityContainer.Parent = worldRoot

	fxContainer = Instance.new("Frame")
	fxContainer.Name = "Fx"
	fxContainer.BackgroundTransparency = 1
	fxContainer.Size = UDim2.fromOffset(0, 0)
	fxContainer.ZIndex = 9
	fxContainer.Parent = worldRoot

	-- مؤشر البلاطة المستهدفة
	selectionBox = Instance.new("Frame")
	selectionBox.BackgroundTransparency = 1
	selectionBox.BorderSizePixel = 0
	selectionBox.AnchorPoint = Vector2.new(0, 0)
	selectionBox.ZIndex = 8
	selectionBox.Visible = false
	selectionBox.Parent = tileContainer
	local selStroke = Instance.new("UIStroke")
	selStroke.Color = Color3.fromRGB(255, 255, 255)
	selStroke.Thickness = 2
	selStroke.Transparency = 0.25
	selStroke.Parent = selectionBox

	-- تراكب تقدّم التعدين
	miningOverlay = Instance.new("Frame")
	miningOverlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	miningOverlay.BackgroundTransparency = 0.55
	miningOverlay.BorderSizePixel = 0
	miningOverlay.AnchorPoint = Vector2.new(0, 1)
	miningOverlay.ZIndex = 8
	miningOverlay.Visible = false
	miningOverlay.Parent = tileContainer

	localCharacter = Sprites.newCharacter(entityContainer, false)

	local camera = workspace.CurrentCamera
	while not camera do
		task.wait()
		camera = workspace.CurrentCamera
	end
	viewW, viewH = camera.ViewportSize.X, camera.ViewportSize.Y
	buildTileGrid()

	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		viewW, viewH = camera.ViewportSize.X, camera.ViewportSize.Y
		buildTileGrid()
	end)

	-- كاميرا Roblox معطّلة تماماً: اللعبة كلها واجهة
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.new(0, 5000, 0)
end

function Renderer.gui(): ScreenGui
	return gui
end

function Renderer.fxLayer(): Frame
	return fxContainer
end

function Renderer.tileSize(): number
	return tilePx
end

function Renderer.shake(magnitude: number, duration: number)
	shakeMagnitude = math.max(shakeMagnitude, magnitude)
	shakeTime = math.max(shakeTime, duration)
end

-- ===== تحويل الإحداثيات =====

function Renderer.worldToScreen(x: number, y: number): (number, number)
	return (x - State.camX) * tilePx + viewW / 2, (y - State.camY) * tilePx + viewH / 2
end

function Renderer.screenToWorld(px: number, py: number): (number, number)
	return (px - viewW / 2) / tilePx + State.camX, (py - viewH / 2) / tilePx + State.camY
end

-- ===== السماء =====

local DAY_TOP = Color3.fromRGB(78, 148, 226)
local DAY_BOTTOM = Color3.fromRGB(186, 218, 240)
local NIGHT_TOP = Color3.fromRGB(8, 10, 28)
local NIGHT_BOTTOM = Color3.fromRGB(30, 34, 68)
local DUSK_TOP = Color3.fromRGB(48, 46, 96)
local DUSK_BOTTOM = Color3.fromRGB(232, 140, 88)
local BLOOD_TOP = Color3.fromRGB(52, 6, 10)
local BLOOD_BOTTOM = Color3.fromRGB(150, 32, 34)

local function updateSky()
	local t = State.time
	local topColor, bottomColor

	local sun = 0
	if t >= 0.27 and t <= 0.73 then
		sun = 1
	elseif t > 0.73 and t < Config.NIGHT_FROM then
		sun = 1 - (t - 0.73) / (Config.NIGHT_FROM - 0.73)
	elseif t > Config.NIGHT_TO and t < 0.27 then
		sun = (t - Config.NIGHT_TO) / (0.27 - Config.NIGHT_TO)
	end

	local duskness = 1 - math.abs(sun * 2 - 1)
	if sun >= 0.999 then duskness = 0 end

	topColor = NIGHT_TOP:Lerp(DAY_TOP, sun)
	bottomColor = NIGHT_BOTTOM:Lerp(DAY_BOTTOM, sun)
	topColor = topColor:Lerp(DUSK_TOP, duskness * 0.7)
	bottomColor = bottomColor:Lerp(DUSK_BOTTOM, duskness * 0.8)

	if State.bloodMoon then
		topColor = topColor:Lerp(BLOOD_TOP, 0.75)
		bottomColor = bottomColor:Lerp(BLOOD_BOTTOM, 0.65)
	end

	-- تحت الأرض: خلفية كهفية تعتم مع العمق
	local depth = State.camY - Config.SURFACE
	if depth > 0 then
		local blend = math.clamp(depth / 90, 0, 1)
		local caveTop = Color3.fromRGB(26, 22, 28)
		local caveBottom = Color3.fromRGB(14, 12, 16)
		if State.camY >= Config.HELL_Y - 40 then
			caveTop = Color3.fromRGB(48, 16, 12)
			caveBottom = Color3.fromRGB(22, 8, 8)
		end
		topColor = topColor:Lerp(caveTop, blend)
		bottomColor = bottomColor:Lerp(caveBottom, blend)
	end

	skyGradient.Color = ColorSequence.new(topColor, bottomColor)

	-- النجوم
	local starAlpha = math.clamp(1 - sun * 1.6, 0, 1) * math.clamp(1 - math.max(0, depth) / 40, 0, 1)
	starsFolder.Visible = starAlpha > 0.02
	if starsFolder.Visible then
		for i, star in stars do
			local twinkle = 0.3 + 0.7 * math.abs(math.sin(os.clock() * 1.4 + i))
			star.BackgroundTransparency = 1 - starAlpha * twinkle
		end
	end

	-- الشمس/القمر على قوس
	local aboveGround = depth < 30
	celestial.Visible = aboveGround
	if aboveGround then
		local angle = (t - 0.25) * math.pi * 2
		local cx = 0.5 + math.cos(angle - math.pi / 2) * 0.42
		local cy = 0.62 - math.sin(angle) * 0.5
		celestial.Position = UDim2.fromScale(cx, cy)
		if sun > 0.35 then
			celestial.BackgroundColor3 = Color3.fromRGB(255, 242, 196)
			celestial.Size = UDim2.fromOffset(78, 78)
		else
			celestial.BackgroundColor3 = if State.bloodMoon
				then Color3.fromRGB(228, 70, 64)
				else Color3.fromRGB(226, 230, 240)
			celestial.Size = UDim2.fromOffset(58, 58)
		end
		celestial.BackgroundTransparency = math.clamp(math.max(0, depth) / 30, 0, 1)
	end

	-- السحب (منظور متحرك)
	cloudFolder.Visible = aboveGround
	if aboveGround then
		local drift = os.clock() * 6
		for i, cloud in clouds do
			local seedX = i * 137.5
			local baseX = ((seedX + drift - State.camX * tilePx * 0.12) % (viewW + 600)) - 300
			local sizeX = 90 + (i % 5) * 55
			local sizeY = 26 + (i % 3) * 12
			cloud.Size = UDim2.fromOffset(sizeX, sizeY)
			cloud.Position = UDim2.fromOffset(baseX, 60 + (i % 6) * 46 - State.camY * tilePx * 0.06 + Config.SURFACE * tilePx * 0.06)
			cloud.BackgroundTransparency = 0.15 + math.clamp(math.max(0, depth) / 30, 0, 0.85)
			cloud.BackgroundColor3 = Color3.fromRGB(255, 255, 255):Lerp(bottomColor, 1 - sun * 0.8)
		end
	end

	-- التلال البعيدة
	local showHills = depth < 24
	hillsFar.Visible = showHills
	hillsNear.Visible = showHills
	if showHills then
		local seed = State.seed
		for i, bar in hillBarsFar do
			local worldX = State.camX * 0.35 + (i - 20) * 7
			local h = WorldGen.surfaceHeight(seed, math.floor(worldX) % Config.WORLD_W)
			local screenY = viewH / 2 + (h - State.camY) * tilePx * 0.35 + 60
			bar.Size = UDim2.fromOffset(viewW / 18 + 4, math.max(10, viewH - screenY + 200))
			bar.Position = UDim2.fromOffset((i - 1) * (viewW / 18) - (State.camX * tilePx * 0.12) % (viewW / 18) * 2, screenY + 200)
			bar.BackgroundColor3 = Color3.fromRGB(56, 78, 96):Lerp(bottomColor, 0.55)
			bar.BackgroundTransparency = math.clamp(math.max(0, depth) / 24, 0, 1)
		end
		for i, bar in hillBarsNear do
			local worldX = State.camX * 0.6 + (i - 20) * 5
			local h = WorldGen.surfaceHeight(seed, math.floor(worldX) % Config.WORLD_W)
			local screenY = viewH / 2 + (h - State.camY) * tilePx * 0.6 + 30
			bar.Size = UDim2.fromOffset(viewW / 24 + 4, math.max(10, viewH - screenY + 200))
			bar.Position = UDim2.fromOffset((i - 1) * (viewW / 24) - (State.camX * tilePx * 0.28) % (viewW / 24) * 2, screenY + 200)
			bar.BackgroundColor3 = Color3.fromRGB(38, 58, 68):Lerp(bottomColor, 0.35)
			bar.BackgroundTransparency = math.clamp(math.max(0, depth) / 24, 0, 1)
		end
	end
end

-- ===== البلاطات =====

local UNLOADED = -1
local UNLOADED_COLOR = Color3.fromRGB(12, 12, 16)

local function applyTile(slot: Slot, tx: number, ty: number, fgId: number, bgId: number, light: number)
	local fgFrame = slot.fg
	local wallFrame = slot.wall

	-- قطعة لم تُولَّد بعد: ارسمها كظلام صلب بدل ثقب في العالم
	if fgId == UNLOADED then
		wallFrame.BackgroundTransparency = 0
		wallFrame.BackgroundColor3 = UNLOADED_COLOR
		fgFrame.Visible = false
		return
	end

	-- الجدار الخلفي / الظلمة
	if bgId ~= 0 then
		local wallBlock = Blocks.get(bgId)
		local variation = (Util.rand2(tx, ty, 77) - 0.5) * (wallBlock.shade / 255) * 0.7
		local base = wallBlock.color
		local factor = light * 0.5
		wallFrame.BackgroundTransparency = 0
		wallFrame.BackgroundColor3 = Color3.new(
			math.clamp((base.R + variation) * factor, 0, 1),
			math.clamp((base.G + variation) * factor, 0, 1),
			math.clamp((base.B + variation) * factor, 0, 1)
		)
	else
		-- هواء بلا جدار: ارسم الظلمة فقط
		if light >= 0.985 then
			wallFrame.BackgroundTransparency = 1
		else
			wallFrame.BackgroundColor3 = Color3.new(0, 0, 0)
			wallFrame.BackgroundTransparency = light
		end
	end

	-- الطبقة الأمامية
	if fgId == 0 then
		fgFrame.Visible = false
		return
	end

	local block = Blocks.get(fgId)
	fgFrame.Visible = true

	local variation = (Util.rand2(tx, ty, 33) - 0.5) * (block.shade / 255) * 2
	local emissive = block.light / Config.MAX_LIGHT
	local factor = math.min(1, light + emissive * 0.8)
	local base = block.color
	fgFrame.BackgroundColor3 = Color3.new(
		math.clamp((base.R + variation) * factor, 0, 1),
		math.clamp((base.G + variation) * factor, 0, 1),
		math.clamp((base.B + variation) * factor, 0, 1)
	)

	-- أشكال خاصة
	if block.liquid then
		fgFrame.Size = UDim2.fromOffset(tilePx + 1, tilePx * 0.92)
		fgFrame.Position = UDim2.fromOffset(tx * tilePx, ty * tilePx + tilePx * 0.08)
		fgFrame.BackgroundTransparency = 0.28
	elseif block.platform then
		fgFrame.Size = UDim2.fromOffset(tilePx + 1, math.max(3, tilePx * 0.22))
		fgFrame.Position = UDim2.fromOffset(tx * tilePx, ty * tilePx)
		fgFrame.BackgroundTransparency = 0
	elseif fgId == Blocks.ID.TORCH or fgId == Blocks.ID.LANTERN then
		fgFrame.Size = UDim2.fromOffset(math.max(4, tilePx * 0.24), tilePx * 0.62)
		fgFrame.Position = UDim2.fromOffset(tx * tilePx + tilePx * 0.38, ty * tilePx + tilePx * 0.2)
		fgFrame.BackgroundTransparency = 0
	elseif block.fragile or fgId == Blocks.ID.VINE then
		fgFrame.Size = UDim2.fromOffset(tilePx * 0.7, tilePx * 0.7)
		fgFrame.Position = UDim2.fromOffset(tx * tilePx + tilePx * 0.15, ty * tilePx + tilePx * 0.3)
		fgFrame.BackgroundTransparency = 0.05
	elseif block.station or block.container then
		fgFrame.Size = UDim2.fromOffset(tilePx + 1, tilePx * 0.85)
		fgFrame.Position = UDim2.fromOffset(tx * tilePx, ty * tilePx + tilePx * 0.15)
		fgFrame.BackgroundTransparency = 0
	else
		fgFrame.Size = UDim2.fromOffset(tilePx + 1, tilePx + 1)
		fgFrame.Position = UDim2.fromOffset(tx * tilePx, ty * tilePx)
		fgFrame.BackgroundTransparency = 0
	end
end

local tileAccumulator = 1 -- يفرض حساب إضاءة في أول إطار

local function renderTiles(force: boolean)
	local world = ClientWorld.get()
	local halfW = viewW / tilePx / 2
	local halfH = viewH / tilePx / 2
	local left = math.floor(State.camX - halfW) - Config.RENDER_PAD
	local top = math.floor(State.camY - halfH) - Config.RENDER_PAD

	for row = 0, rows - 1 do
		local ty = top + row
		local slotRow = ((ty % rows) + rows) % rows
		for col = 0, cols - 1 do
			local tx = left + col
			local slotCol = ((tx % cols) + cols) % cols
			local slot = slots[slotRow * cols + slotCol + 1]
			if slot then
				local fgId, bgId
				if World.inBounds(tx, ty) then
					fgId = World.fgRaw(world, tx, ty) or UNLOADED
					bgId = World.bgRaw(world, tx, ty) or Blocks.ID.AIR
				else
					fgId, bgId = Blocks.ID.BEDROCK, Blocks.ID.BEDROCK
				end
				local light = if fgId == UNLOADED then 0 else Lighting.factor(tx, ty)
				local quantized = math.floor(light * 48)

				local moved = slot.tx ~= tx or slot.ty ~= ty
				if moved or force or slot.lastFg ~= fgId or slot.lastBg ~= bgId or slot.lastLight ~= quantized then
					slot.tx, slot.ty = tx, ty
					slot.lastFg, slot.lastBg, slot.lastLight = fgId, bgId, quantized
					if moved then
						slot.wall.Position = UDim2.fromOffset(tx * tilePx, ty * tilePx)
					end
					applyTile(slot, tx, ty, fgId, bgId, light)
				end
			end
		end
	end
end

-- ===== الكيانات =====

local function releaseSprites(seen: { [number]: boolean })
	for id, sprite in charSprites do
		if not seen[id] then
			sprite.root:Destroy()
			charSprites[id] = nil
		end
	end
	for id, sprite in mobSprites do
		if not seen[id] then
			sprite.root:Destroy()
			mobSprites[id] = nil
		end
	end
	for id, sprite in itemSprites do
		if not seen[id] then
			sprite.root:Destroy()
			itemSprites[id] = nil
		end
	end
	for id, sprite in projSprites do
		if not seen[id] then
			sprite.root:Destroy()
			projSprites[id] = nil
		end
	end
end

local function renderEntities()
	local seen: { [number]: boolean } = {}
	local now = os.clock()

	for id, entity in State.entities do
		seen[id] = true
		local x = entity.rx or entity.x
		local y = entity.ry or entity.y

		if entity.k == 1 then -- وحش
			local sprite = mobSprites[id]
			if not sprite then
				sprite = Sprites.newMob(entityContainer)
				mobSprites[id] = sprite
			end
			local def = Mobs.get(entity.t)
			local w = if def then def.w else 1
			local h = if def then def.h else 1
			sprite.root.Position = UDim2.fromOffset(x * tilePx, y * tilePx)
			Sprites.updateMob(sprite, entity.t, w * tilePx, h * tilePx, entity.f or 1, entity.a or "idle", now, entity.h or 100)

		elseif entity.k == 2 then -- غرض
			local sprite = itemSprites[id]
			if not sprite then
				sprite = Sprites.newItem(entityContainer)
				itemSprites[id] = sprite
			end
			sprite.root.Position = UDim2.fromOffset(x * tilePx, y * tilePx)
			Sprites.updateItem(sprite, entity.t, entity.n or 1, tilePx * 0.8, now + id)

		elseif entity.k == 3 then -- مقذوف
			local sprite = projSprites[id]
			if not sprite then
				sprite = Sprites.newProjectile(entityContainer)
				projSprites[id] = sprite
			end
			local def = Mobs.projectiles[entity.t]
			local w = if def then def.w else 0.5
			local h = if def then def.h else 0.5
			local angle = math.deg(math.atan2(entity.vy or 0, entity.vx or 1))
			sprite.root.Position = UDim2.fromOffset(x * tilePx, y * tilePx)
			Sprites.updateProjectile(sprite, entity.t, w * tilePx, math.max(3, h * tilePx), angle, now)
		end
	end

	-- اللاعبون الآخرون
	for userId, peer in State.peers do
		if userId ~= State.userId then
			seen[-userId] = true
			local sprite = charSprites[-userId]
			if not sprite then
				sprite = Sprites.newCharacter(entityContainer, true)
				charSprites[-userId] = sprite
			end
			local px = peer.rx or peer.x
			local py = peer.ry or peer.y
			sprite.root.Position = UDim2.fromOffset(px * tilePx, py * tilePx)
			sprite.root.Visible = not peer.d
			sprite.nameTag.Text = peer.n or "لاعب"
			sprite.nameTag.Position = UDim2.fromOffset(Config.PLAYER_W * tilePx / 2, -6)
			sprite.nameTag.Size = UDim2.fromOffset(180, 18)
			Sprites.updateCharacter(
				sprite, Config.PLAYER_W * tilePx, Config.PLAYER_H * tilePx,
				peer.f or 1, if math.abs((peer.vx or 0)) > 0.5 then "walk" else "idle",
				now, peer.hd, peer.ch, peer.it, 0
			)
		end
	end

	releaseSprites(seen)
end

-- ===== اللاعب المحلي =====

local function renderLocalPlayer()
	local body = State.body
	localCharacter.root.Visible = not State.dead
	localCharacter.root.Position = UDim2.fromOffset(body.x * tilePx, body.y * tilePx)

	local swing = 0
	local lastSwing = State.lastSwing or 0
	local since = os.clock() - lastSwing
	if since < 0.22 then
		swing = math.sin(since / 0.22 * math.pi)
	end

	local held = State.heldItem()
	Sprites.updateCharacter(
		localCharacter,
		Config.PLAYER_W * tilePx,
		Config.PLAYER_H * tilePx,
		State.facing,
		State.anim,
		State.animTime,
		if State.armor.head then (State.armor.head :: any).id else nil,
		if State.armor.chest then (State.armor.chest :: any).id else nil,
		if held then held.id else nil,
		swing
	)
end

-- ===== مؤشر الاستهداف =====

function Renderer.setSelection(tx: number?, ty: number?, valid: boolean)
	if not tx or not ty then
		selectionBox.Visible = false
		return
	end
	selectionBox.Visible = true
	selectionBox.Size = UDim2.fromOffset(tilePx, tilePx)
	selectionBox.Position = UDim2.fromOffset(tx * tilePx, ty * tilePx)
	local stroke = selectionBox:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if valid then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(235, 90, 80)
	end
end

function Renderer.setMiningProgress(tx: number?, ty: number?, progress: number)
	if not tx or not ty or progress <= 0 then
		miningOverlay.Visible = false
		return
	end
	miningOverlay.Visible = true
	miningOverlay.Size = UDim2.fromOffset(tilePx, tilePx * math.clamp(progress, 0, 1))
	miningOverlay.Position = UDim2.fromOffset(tx * tilePx, (ty + 1) * tilePx)
end

-- ===== الكاميرا والحلقة =====

local function updateCamera(dt: number)
	local body = State.body
	local targetX = body.x
	local targetY = body.y - 1

	-- ابقَ داخل حدود العالم
	local halfW = viewW / tilePx / 2
	local halfH = viewH / tilePx / 2
	targetX = math.clamp(targetX, halfW, Config.WORLD_W - halfW)
	targetY = math.clamp(targetY, halfH, Config.WORLD_H - halfH)

	State.camX = Util.damp(State.camX, targetX, Config.CAMERA_SMOOTH, dt)
	State.camY = Util.damp(State.camY, targetY, Config.CAMERA_SMOOTH, dt)
end

function Renderer.render(dt: number)
	if not ClientWorld.isReady() then return end

	updateCamera(dt)
	updateSky()

	-- اهتزاز الشاشة
	local shakeX, shakeY = 0, 0
	if shakeTime > 0 then
		shakeTime -= dt
		local strength = shakeMagnitude * math.min(1, shakeTime * 4)
		shakeX = (math.random() - 0.5) * strength
		shakeY = (math.random() - 0.5) * strength
		if shakeTime <= 0 then shakeMagnitude = 0 end
	end

	local offsetX = math.floor(-State.camX * tilePx + viewW / 2 + shakeX)
	local offsetY = math.floor(-State.camY * tilePx + viewH / 2 + shakeY)
	local offset = UDim2.fromOffset(offsetX, offsetY)
	tileContainer.Position = offset
	entityContainer.Position = offset
	fxContainer.Position = offset

	-- الإضاءة (بمعدل محدود)
	tileAccumulator += dt
	local lightStep = 1 / Config.LIGHT_HZ
	if tileAccumulator >= lightStep then
		tileAccumulator -= lightStep
		local world = ClientWorld.get()
		Lighting.recompute(world, State.camX, State.camY, cols, rows)
	end

	renderTiles(false)
	renderEntities()
	renderLocalPlayer()
end

return Renderer
