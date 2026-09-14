--!strict
--[[
	Renderer — محرّك الرسم البكسلي.

	كل بلاطة صارت ImageLabel تشير إلى مستطيل داخل أطلس النقوش، مع
	ResamplerMode.Pixelated فتبقى البكسلات حادّة مهما كان الزوم.

	ثلاث أفكار تحمل الأداء كله:
	1. شبكة ثابتة من الإطارات تُعاد تدويرها (torus mapping): التمرير يحرّك
	   الحاوية ويحدّث عموداً واحداً فقط بدل إعادة بناء كل شيء.
	2. ذاكرة لكل خانة: لا نكتب أي خاصية إن لم يتغيّر شيء فعلياً.
	3. قناع الحواف (auto-tiling): نختار من 16 نسخة مخبوزة مسبقاً حسب الجيران
	   المكشوفين، فنحصل على حواف مضاءة كتيراريا بلا أي كلفة وقت تشغيل.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Blocks = require(Shared.Blocks)
local Config = require(Shared.Config)
local Mobs = require(Shared.Mobs)
local Pixels = require(Shared.Pixels)
local Upgrades = require(Shared.Upgrades)
local Util = require(Shared.Util)
local World = require(Shared.World)
local WorldGen = require(Shared.WorldGen)

local Atlas = require(script.Parent.Atlas)
local ClientWorld = require(script.Parent.ClientWorld)
local EntitySprites = require(script.Parent.EntitySprites)
local Lighting = require(script.Parent.Lighting)
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
	wall: ImageLabel,
	fg: ImageLabel,
	tx: number,
	ty: number,
	lastFg: number,
	lastBg: number,
	lastMask: number,
	lastLight: number,
	lastLevel: number,
}

local slots: { Slot } = {}
local cols, rows = 0, 0
local tilePx = 48
local viewW, viewH = 0, 0
local shakeTime, shakeMagnitude = 0, 0

local stars: { Frame } = {}
local clouds: { { Frame } } = {}
local hillBarsFar: { Frame } = {}
local hillBarsNear: { Frame } = {}

local charSprites: { [number]: EntitySprites.Character } = {}
local mobSprites: { [number]: EntitySprites.MobSprite } = {}
local itemSprites: { [number]: EntitySprites.ItemSprite } = {}
local projSprites: { [number]: EntitySprites.ProjSprite } = {}
local localCharacter: EntitySprites.Character
local crackOverlay: ImageLabel
local selectionBox: Frame
local crackStage = 0

local UNLOADED = -1
local UNLOADED_COLOR = Color3.fromRGB(10, 10, 14)

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
		star.Size = UDim2.fromOffset(if i % 5 == 0 then 3 else 2, if i % 5 == 0 then 3 else 2)
		star.Position = UDim2.fromScale(math.random(), math.random() * 0.65)
		star.ZIndex = 2
		star.Parent = starsFolder
		table.insert(stars, star)
	end

	-- الشمس/القمر: مربّع بكسلي بزوايا مقضومة بدل دائرة ناعمة
	celestial = Instance.new("Frame")
	celestial.Name = "Sun"
	celestial.BorderSizePixel = 0
	celestial.AnchorPoint = Vector2.new(0.5, 0.5)
	celestial.Size = UDim2.fromOffset(64, 64)
	celestial.BackgroundColor3 = Color3.fromRGB(255, 240, 190)
	celestial.ZIndex = 3
	celestial.Parent = parent
	for _, corner in { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) } do
		local notch = Instance.new("Frame")
		notch.BorderSizePixel = 0
		notch.BackgroundTransparency = 1
		notch.Size = UDim2.fromScale(0.18, 0.18)
		notch.AnchorPoint = corner
		notch.Position = UDim2.fromScale(corner.X, corner.Y)
		notch.ZIndex = 4
		notch.Parent = celestial
	end

	hillsFar = makeFrame(parent, "HillsFar", 4)
	for _ = 1, 40 do
		local bar = Instance.new("Frame")
		bar.BorderSizePixel = 0
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.BackgroundColor3 = Color3.fromRGB(56, 78, 96)
		bar.ZIndex = 4
		bar.Parent = hillsFar
		table.insert(hillBarsFar, bar)
	end

	hillsNear = makeFrame(parent, "HillsNear", 5)
	for _ = 1, 40 do
		local bar = Instance.new("Frame")
		bar.BorderSizePixel = 0
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.BackgroundColor3 = Color3.fromRGB(40, 60, 70)
		bar.ZIndex = 5
		bar.Parent = hillsNear
		table.insert(hillBarsNear, bar)
	end

	-- سحب بكسلية: ثلاث كتل متداخلة لكل سحابة (بلا زوايا دائرية)
	cloudFolder = makeFrame(parent, "Clouds", 6)
	for _ = 1, 14 do
		local parts: { Frame } = {}
		for k = 1, 3 do
			local part = Instance.new("Frame")
			part.BorderSizePixel = 0
			part.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			part.BackgroundTransparency = 0.12
			part.AnchorPoint = Vector2.new(0.5, 0.5)
			part.ZIndex = 6
			part.Parent = cloudFolder
			table.insert(parts, part)
		end
		table.insert(clouds, parts)
	end
end

local function buildTileGrid()
	for _, slot in slots do
		slot.wall:Destroy()
		slot.fg:Destroy()
	end
	table.clear(slots)

	-- حجم البلاطة مضاعف صحيح لدقة الفن (16) فتبقى البكسلات مربّعة تماماً
	local raw = viewH / Config.TILES_ON_SCREEN_Y
	local scale = math.max(2, math.floor(raw / Atlas.TILE + 0.5))
	tilePx = scale * Atlas.TILE
	State.tilePx = tilePx

	cols = math.ceil(viewW / tilePx) + Config.RENDER_PAD * 2
	rows = math.ceil(viewH / tilePx) + Config.RENDER_PAD * 2

	for _ = 1, cols * rows do
		local wall = Instance.new("ImageLabel")
		wall.BorderSizePixel = 0
		wall.BackgroundColor3 = Color3.new(0, 0, 0)
		wall.BackgroundTransparency = 1
		wall.ImageTransparency = 1
		wall.Size = UDim2.fromOffset(tilePx, tilePx)
		wall.ZIndex = 2
		wall.Parent = tileContainer
		Atlas.apply(wall, "tiles")

		local fg = Instance.new("ImageLabel")
		fg.BorderSizePixel = 0
		fg.BackgroundTransparency = 1
		fg.Size = UDim2.fromOffset(tilePx, tilePx)
		fg.Visible = false
		fg.ZIndex = 3
		fg.Parent = tileContainer
		Atlas.apply(fg, "tiles")

		table.insert(slots, {
			wall = wall, fg = fg,
			tx = -99999, ty = -99999,
			lastFg = -2, lastBg = -2, lastMask = -1, lastLight = -1, lastLevel = -1,
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
	gui.Parent = playerGui
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.None
	end)

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

	selectionBox = Instance.new("Frame")
	selectionBox.BackgroundTransparency = 1
	selectionBox.BorderSizePixel = 0
	selectionBox.ZIndex = 8
	selectionBox.Visible = false
	selectionBox.Parent = tileContainer
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 2
	stroke.Transparency = 0.25
	stroke.Parent = selectionBox

	crackOverlay = Instance.new("ImageLabel")
	crackOverlay.BackgroundTransparency = 1
	crackOverlay.BorderSizePixel = 0
	crackOverlay.ZIndex = 8
	crackOverlay.Visible = false
	crackOverlay.Parent = tileContainer
	Atlas.applyUI(crackOverlay, "crack1")

	localCharacter = EntitySprites.newCharacter(entityContainer, false)

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

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.new(0, 5000, 0)
end

function Renderer.gui(): ScreenGui return gui end
function Renderer.fxLayer(): Frame return fxContainer end
function Renderer.tileSize(): number return tilePx end

function Renderer.shake(magnitude: number, duration: number)
	shakeMagnitude = math.max(shakeMagnitude, magnitude)
	shakeTime = math.max(shakeTime, duration)
end

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

local function sunAmount(t: number): number
	if t >= 0.27 and t <= 0.73 then return 1 end
	if t > 0.73 and t < Config.NIGHT_FROM then
		return 1 - (t - 0.73) / (Config.NIGHT_FROM - 0.73)
	end
	if t > Config.NIGHT_TO and t < 0.27 then
		return (t - Config.NIGHT_TO) / (0.27 - Config.NIGHT_TO)
	end
	return 0
end
Renderer.sunAmount = sunAmount

local function updateSky()
	local t = State.time
	local sun = sunAmount(t)
	local duskness = 1 - math.abs(sun * 2 - 1)
	if sun >= 0.999 then duskness = 0 end

	local topColor = NIGHT_TOP:Lerp(DAY_TOP, sun):Lerp(DUSK_TOP, duskness * 0.7)
	local bottomColor = NIGHT_BOTTOM:Lerp(DAY_BOTTOM, sun):Lerp(DUSK_BOTTOM, duskness * 0.8)

	if State.bloodMoon then
		topColor = topColor:Lerp(BLOOD_TOP, 0.75)
		bottomColor = bottomColor:Lerp(BLOOD_BOTTOM, 0.65)
	end

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

	local starAlpha = math.clamp(1 - sun * 1.6, 0, 1) * math.clamp(1 - math.max(0, depth) / 40, 0, 1)
	starsFolder.Visible = starAlpha > 0.02
	if starsFolder.Visible then
		for i, star in stars do
			local twinkle = 0.35 + 0.65 * math.abs(math.sin(os.clock() * 1.3 + i))
			star.BackgroundTransparency = 1 - starAlpha * twinkle
		end
	end

	local aboveGround = depth < 30
	celestial.Visible = aboveGround
	if aboveGround then
		local angle = (t - 0.25) * math.pi * 2
		celestial.Position = UDim2.fromScale(
			0.5 + math.cos(angle - math.pi / 2) * 0.42,
			0.62 - math.sin(angle) * 0.5)
		if sun > 0.35 then
			celestial.BackgroundColor3 = Color3.fromRGB(255, 242, 196)
			celestial.Size = UDim2.fromOffset(72, 72)
		else
			celestial.BackgroundColor3 = if State.bloodMoon
				then Color3.fromRGB(228, 70, 64)
				else Color3.fromRGB(226, 230, 240)
			celestial.Size = UDim2.fromOffset(56, 56)
		end
		celestial.BackgroundTransparency = math.clamp(math.max(0, depth) / 30, 0, 1)
	end

	cloudFolder.Visible = aboveGround
	if aboveGround then
		local drift = os.clock() * 5
		local fade = 0.12 + math.clamp(math.max(0, depth) / 30, 0, 0.88)
		local tint = Color3.fromRGB(255, 255, 255):Lerp(bottomColor, 1 - sun * 0.75)
		for i, parts in clouds do
			local seedX = i * 151.3
			local baseX = ((seedX + drift - State.camX * tilePx * 0.1) % (viewW + 520)) - 260
			local baseY = 54 + (i % 5) * 52 - State.camY * tilePx * 0.05 + Config.SURFACE * tilePx * 0.05
			local unit = 18 + (i % 3) * 8
			-- ثلاث كتل مستطيلة تكوّن سحابة بكسلية
			local layout = {
				{ dx = 0, dy = 0, w = unit * 3, h = unit },
				{ dx = -unit * 0.6, dy = -unit * 0.6, w = unit * 1.6, h = unit * 0.9 },
				{ dx = unit * 0.8, dy = -unit * 0.45, w = unit * 1.3, h = unit * 0.8 },
			}
			for k, part in parts do
				local spec = layout[k]
				part.Size = UDim2.fromOffset(spec.w, spec.h)
				part.Position = UDim2.fromOffset(baseX + spec.dx, baseY + spec.dy)
				part.BackgroundTransparency = fade
				part.BackgroundColor3 = tint
			end
		end
	end

	local showHills = depth < 24
	hillsFar.Visible = showHills
	hillsNear.Visible = showHills
	if showHills then
		local seed = State.seed
		local fade = math.clamp(math.max(0, depth) / 24, 0, 1)
		for i, bar in hillBarsFar do
			local worldX = State.camX * 0.35 + (i - 20) * 7
			local h = WorldGen.surfaceHeight(seed, math.floor(worldX) % Config.WORLD_W)
			local screenY = viewH / 2 + (h - State.camY) * tilePx * 0.35 + 60
			bar.Size = UDim2.fromOffset(viewW / 18 + 4, math.max(10, viewH - screenY + 240))
			bar.Position = UDim2.fromOffset((i - 1) * (viewW / 18), screenY + 240)
			bar.BackgroundColor3 = Color3.fromRGB(56, 78, 96):Lerp(bottomColor, 0.55)
			bar.BackgroundTransparency = fade
		end
		for i, bar in hillBarsNear do
			local worldX = State.camX * 0.6 + (i - 20) * 5
			local h = WorldGen.surfaceHeight(seed, math.floor(worldX) % Config.WORLD_W)
			local screenY = viewH / 2 + (h - State.camY) * tilePx * 0.6 + 30
			bar.Size = UDim2.fromOffset(viewW / 24 + 4, math.max(10, viewH - screenY + 240))
			bar.Position = UDim2.fromOffset((i - 1) * (viewW / 24), screenY + 240)
			bar.BackgroundColor3 = Color3.fromRGB(38, 58, 68):Lerp(bottomColor, 0.35)
			bar.BackgroundTransparency = fade
		end
	end
end

-- ===== البلاطات =====

-- قناع الجيران المكشوفين: يحدّد أي نسخة من النقش نستعمل
local function edgeMask(world: World.World, tx: number, ty: number, blockId: number): number
	local mask = 0
	local function exposed(nx: number, ny: number): boolean
		local neighbour = World.fgRaw(world, nx, ny)
		if neighbour == nil then return false end
		if neighbour == blockId then return false end
		return not Blocks.isSolid(neighbour)
	end
	if exposed(tx, ty - 1) then mask += Pixels.EDGE_UP end
	if exposed(tx + 1, ty) then mask += Pixels.EDGE_RIGHT end
	if exposed(tx, ty + 1) then mask += Pixels.EDGE_DOWN end
	if exposed(tx - 1, ty) then mask += Pixels.EDGE_LEFT end
	return mask
end

local function applyTile(slot: Slot, tx: number, ty: number, fgId: number, bgId: number, mask: number, light: number, level: number)
	local wall = slot.wall
	local fg = slot.fg

	if fgId == UNLOADED then
		wall.ImageTransparency = 1
		wall.BackgroundTransparency = 0
		wall.BackgroundColor3 = UNLOADED_COLOR
		fg.Visible = false
		return
	end

	-- تنويع خفيف في السطوع لكسر تكرار الشبكة
	local jitter = 0.94 + Util.rand2(tx, ty, 917) * 0.12

	-- ===== الجدار الخلفي أو الظلمة =====
	if bgId ~= 0 then
		wall.BackgroundTransparency = 1
		wall.ImageTransparency = 0
		Atlas.setRect(wall, Atlas.tileRect(bgId, 0))
		local shade = light * 0.46 * jitter
		wall.ImageColor3 = Color3.new(shade, shade, shade)
	else
		wall.ImageTransparency = 1
		if light >= 0.985 then
			wall.BackgroundTransparency = 1
		else
			wall.BackgroundColor3 = Color3.new(0, 0, 0)
			wall.BackgroundTransparency = light
		end
	end

	-- ===== الطبقة الأمامية =====
	if fgId == 0 then
		fg.Visible = false
		return
	end

	local block = Blocks.get(fgId)
	fg.Visible = true
	Atlas.setRect(fg, Atlas.tileRect(fgId, mask))

	local emissive = block.light / Config.MAX_LIGHT
	local tint = math.min(1, light + emissive * 0.85) * jitter
	fg.ImageColor3 = Color3.new(tint, tint, tint)

	-- أشكال خاصة: سائل بارتفاع جزئي حسب مستواه، منصة رقيقة، نباتات
	if block.liquid then
		-- نقصّ النقش من أسفله بقدر المستوى فيبدو سطح السائل في مكانه الصحيح
		local rows = math.clamp(math.floor(level / 8 * Atlas.TILE + 0.5), 2, Atlas.TILE)
		local scale = tilePx // Atlas.TILE
		local rect = Atlas.tileRect(fgId, 0)
		fg.ImageRectOffset = Vector2.new(rect.x, rect.y + (Atlas.TILE - rows))
		fg.ImageRectSize = Vector2.new(Atlas.TILE, rows)
		fg.Size = UDim2.fromOffset(tilePx, rows * scale)
		fg.Position = UDim2.fromOffset(tx * tilePx, ty * tilePx + (Atlas.TILE - rows) * scale)
		fg.ImageTransparency = if fgId == Blocks.ID.LAVA then 0 else 0.12
	elseif block.platform then
		fg.Size = UDim2.fromOffset(tilePx, tilePx // 4)
		fg.Position = UDim2.fromOffset(tx * tilePx, ty * tilePx)
		fg.ImageRectSize = Vector2.new(Atlas.TILE, Atlas.TILE // 4)
		fg.ImageTransparency = 0
	else
		fg.Size = UDim2.fromOffset(tilePx, tilePx)
		fg.Position = UDim2.fromOffset(tx * tilePx, ty * tilePx)
		fg.ImageTransparency = 0
	end
end

local function renderTiles()
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
					bgId = World.bgRaw(world, tx, ty) or 0
				else
					fgId, bgId = Blocks.ID.BEDROCK, Blocks.ID.BEDROCK
				end

				local mask = 0
				if fgId > 0 and fgId ~= UNLOADED and Blocks.isSolid(fgId) then
					mask = edgeMask(world, tx, ty, fgId)
				end

				local level = 0
				if fgId ~= UNLOADED and Blocks.isLiquid(fgId) then
					level = World.liquidLevelRaw(world, tx, ty)
				end

				local light = if fgId == UNLOADED then 0 else Lighting.factor(tx, ty)
				local quantized = math.floor(light * 40)

				local moved = slot.tx ~= tx or slot.ty ~= ty
				if moved or slot.lastFg ~= fgId or slot.lastBg ~= bgId
					or slot.lastMask ~= mask or slot.lastLight ~= quantized
					or slot.lastLevel ~= level then
					slot.tx, slot.ty = tx, ty
					slot.lastFg, slot.lastBg = fgId, bgId
					slot.lastMask, slot.lastLight, slot.lastLevel = mask, quantized, level
					if moved then
						slot.wall.Position = UDim2.fromOffset(tx * tilePx, ty * tilePx)
					end
					applyTile(slot, tx, ty, fgId, bgId, mask, light, level)
				end
			end
		end
	end
end

-- ===== الكيانات =====

local function releaseSprites(seen: { [number]: boolean })
	for id, sprite in charSprites do
		if not seen[id] then sprite.root:Destroy(); charSprites[id] = nil end
	end
	for id, sprite in mobSprites do
		if not seen[id] then sprite.root:Destroy(); mobSprites[id] = nil end
	end
	for id, sprite in itemSprites do
		if not seen[id] then sprite.root:Destroy(); itemSprites[id] = nil end
	end
	for id, sprite in projSprites do
		if not seen[id] then sprite.root:Destroy(); projSprites[id] = nil end
	end
end

local function renderEntities()
	local seen: { [number]: boolean } = {}
	local now = os.clock()

	for id, entity in State.entities do
		seen[id] = true
		local x = entity.rx or entity.x
		local y = entity.ry or entity.y

		if entity.k == 1 then
			local sprite = mobSprites[id]
			if not sprite then
				sprite = EntitySprites.newMob(entityContainer)
				mobSprites[id] = sprite
			end
			local def = Mobs.get(entity.t)
			local w = if def then def.w else 1
			local h = if def then def.h else 1
			sprite.root.Position = UDim2.fromOffset(x * tilePx, y * tilePx)
			EntitySprites.updateMob(sprite, entity.t, w * tilePx, h * tilePx,
				entity.f or 1, entity.a or "idle", now + id * 0.37, entity.h or 100)

		elseif entity.k == 2 then
			local sprite = itemSprites[id]
			if not sprite then
				sprite = EntitySprites.newItem(entityContainer)
				itemSprites[id] = sprite
			end
			sprite.root.Position = UDim2.fromOffset(x * tilePx, y * tilePx)
			EntitySprites.updateItem(sprite, entity.t, entity.n or 1, tilePx * 0.85, now + id)

		elseif entity.k == 3 then
			local sprite = projSprites[id]
			if not sprite then
				sprite = EntitySprites.newProjectile(entityContainer)
				projSprites[id] = sprite
			end
			local def = Mobs.projectiles[entity.t]
			local scale = if def then math.max(def.w, def.h) else 0.6
			local angle = math.deg(math.atan2(entity.vy or 0, entity.vx or 1))
			sprite.root.Position = UDim2.fromOffset(x * tilePx, y * tilePx)
			EntitySprites.updateProjectile(sprite, entity.t, math.max(12, scale * tilePx * 1.6), angle)
		end
	end

	for userId, peer in State.peers do
		if userId ~= State.userId then
			seen[-userId] = true
			local sprite = charSprites[-userId]
			if not sprite then
				sprite = EntitySprites.newCharacter(entityContainer, true)
				charSprites[-userId] = sprite
			end
			local px = peer.rx or peer.x
			local py = peer.ry or peer.y
			local pxW = Config.PLAYER_W * tilePx
			local pxH = Config.PLAYER_H * tilePx
			sprite.root.Position = UDim2.fromOffset(px * tilePx, py * tilePx)
			sprite.root.Visible = not peer.d
			sprite.nameTag.Text = peer.n or "لاعب"
			sprite.nameTag.Position = UDim2.fromOffset(pxW / 2, -14)
			sprite.nameTag.Size = UDim2.fromOffset(180, 18)
			EntitySprites.updateCharacter(sprite, pxW, pxH, peer.f or 1,
				if math.abs(peer.vx or 0) > 0.5 then "walk" else "idle",
				now, peer.hd, peer.ch, peer.it, 0, peer.iu)
			EntitySprites.setCharacterHealth(sprite, pxW, pxH, peer.hp or 100)
		end
	end

	releaseSprites(seen)
end

local function renderLocalPlayer()
	local body = State.body
	localCharacter.root.Visible = not State.dead
	localCharacter.root.Position = UDim2.fromOffset(body.x * tilePx, body.y * tilePx)

	local swing = 0
	local since = os.clock() - (State.lastSwing or 0)
	if since < 0.22 then
		swing = math.sin(since / 0.22 * math.pi)
	end

	local held = State.heldItem()
	EntitySprites.updateCharacter(
		localCharacter,
		Config.PLAYER_W * tilePx,
		Config.PLAYER_H * tilePx,
		State.facing,
		State.anim,
		State.animTime,
		if State.armor.head then (State.armor.head :: any).id else nil,
		if State.armor.chest then (State.armor.chest :: any).id else nil,
		if held then held.id else nil,
		swing,
		Upgrades.isModified(held)
	)
end

-- ===== المؤشرات =====

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

-- تقدّم التعدين يُعرض كتشقّق متنامٍ فوق البلاطة (بدل شريط)
function Renderer.setMiningProgress(tx: number?, ty: number?, progress: number)
	if not tx or not ty or progress <= 0.02 then
		crackOverlay.Visible = false
		return
	end
	local stage = math.clamp(math.ceil(progress * 4), 1, 4)
	crackOverlay.Visible = true
	crackOverlay.Size = UDim2.fromOffset(tilePx, tilePx)
	crackOverlay.Position = UDim2.fromOffset(tx * tilePx, ty * tilePx)
	if crackStage ~= stage then
		crackStage = stage
		Atlas.applyUI(crackOverlay, "crack" .. stage)
	end
end

-- ===== الكاميرا والحلقة =====

local function updateCamera(dt: number)
	local body = State.body
	local halfW = viewW / tilePx / 2
	local halfH = viewH / tilePx / 2
	local targetX = math.clamp(body.x, halfW, Config.WORLD_W - halfW)
	local targetY = math.clamp(body.y - 1, halfH, Config.WORLD_H - halfH)

	State.camX = Util.damp(State.camX, targetX, Config.CAMERA_SMOOTH, dt)
	State.camY = Util.damp(State.camY, targetY, Config.CAMERA_SMOOTH, dt)
end

local lightAccumulator = 1

function Renderer.render(dt: number)
	if not ClientWorld.isReady() or not Atlas.isReady() then return end

	updateCamera(dt)
	updateSky()

	local shakeX, shakeY = 0, 0
	if shakeTime > 0 then
		shakeTime -= dt
		local strength = shakeMagnitude * math.min(1, shakeTime * 4)
		shakeX = (math.random() - 0.5) * strength
		shakeY = (math.random() - 0.5) * strength
		if shakeTime <= 0 then shakeMagnitude = 0 end
	end

	-- تثبيت الإزاحة على بكسلات صحيحة يمنع اهتزاز النقوش
	local offsetX = math.floor(-State.camX * tilePx + viewW / 2 + shakeX)
	local offsetY = math.floor(-State.camY * tilePx + viewH / 2 + shakeY)
	local offset = UDim2.fromOffset(offsetX, offsetY)
	tileContainer.Position = offset
	entityContainer.Position = offset
	fxContainer.Position = offset

	lightAccumulator += dt
	local lightStep = 1 / Config.LIGHT_HZ
	if lightAccumulator >= lightStep then
		lightAccumulator = 0
		Lighting.recompute(ClientWorld.get(), State.camX, State.camY, cols, rows)
	end

	renderTiles()
	renderEntities()
	renderLocalPlayer()
end

return Renderer
