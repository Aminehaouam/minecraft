--!strict
--[[
	Lighting — إضاءة بلاطية بانتشار BFS (مثل ماين كرافت) فوق نافذة حول الكاميرا.

	مصدران: ضوء الشمس النازل من السطح (متأثر بوقت اليوم) ومصادر الضوء
	(مشاعل، حمم، بلّور). يُعاد الحساب عند تغيّر النافذة أو تعديل بلاطة،
	وبحدّ أقصى LIGHT_HZ مرة في الثانية.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Blocks = require(Shared.Blocks)
local Config = require(Shared.Config)
local World = require(Shared.World)

local Lighting = {}

local MAX = Config.MAX_LIGHT

local levels: { number } = {} -- مصفوفة مسطّحة بحجم النافذة
local originX, originY = 0, 0
local width, height = 0, 0
local dirty = true
local sunlight = 1
local extraSources: { { x: number, y: number, level: number } } = {}

function Lighting.resize(w: number, h: number)
	width = w + Config.LIGHT_PAD * 2
	height = h + Config.LIGHT_PAD * 2
	levels = table.create(width * height, 0)
	dirty = true
end

function Lighting.markDirty()
	dirty = true
end

function Lighting.setSunlight(value: number)
	if math.abs(value - sunlight) > 0.02 then
		sunlight = value
		dirty = true
	end
end

-- مصادر ضوء ديناميكية (اللاعب حامل مشعل، تعزيز التوهج…)
function Lighting.setDynamicSources(sources: { { x: number, y: number, level: number } })
	extraSources = sources
	dirty = true
end

function Lighting.get(x: number, y: number): number
	local lx, ly = x - originX, y - originY
	if lx < 0 or ly < 0 or lx >= width or ly >= height then
		return MAX
	end
	return levels[ly * width + lx + 1] or 0
end

-- شدة الإضاءة كنسبة 0..1 مع منحنى ألطف للعين
function Lighting.factor(x: number, y: number): number
	local level = Lighting.get(x, y)
	local t = level / MAX
	return 0.055 + 0.945 * (t * t * (3 - 2 * t))
end

function Lighting.recompute(world: World.World, camX: number, camY: number, viewW: number, viewH: number)
	local newOriginX = math.floor(camX - viewW / 2) - Config.LIGHT_PAD
	local newOriginY = math.floor(camY - viewH / 2) - Config.LIGHT_PAD
	if newOriginX == originX and newOriginY == originY and not dirty then
		return
	end
	originX, originY = newOriginX, newOriginY
	dirty = false

	table.clear(levels)
	local size = width * height
	for i = 1, size do
		levels[i] = 0
	end

	-- طابور BFS مسطّح (فهرس, مستوى)
	local queue = table.create(size)
	local head, tail = 1, 0
	local sunLevel = math.floor(MAX * sunlight + 0.5)

	-- 1) بذور ضوء الشمس
	for lx = 0, width - 1 do
		local worldX = originX + lx
		if worldX >= 0 and worldX < Config.WORLD_W and sunLevel > 0 then
			local surface = World.surfaceY(world, worldX)
			for ly = 0, height - 1 do
				local worldY = originY + ly
				if worldY < surface then
					local index = ly * width + lx + 1
					if levels[index] < sunLevel then
						levels[index] = sunLevel
						tail += 1
						queue[tail] = index
					end
				else
					break
				end
			end
		end
	end

	-- 2) بذور مصادر الضوء داخل النافذة
	for ly = 0, height - 1 do
		local worldY = originY + ly
		local rowBase = ly * width
		for lx = 0, width - 1 do
			local worldX = originX + lx
			local fgId = World.fgRaw(world, worldX, worldY)
			local emit = if fgId then Blocks.light(fgId) else 0
			if emit == 0 then
				local bgId = World.bgRaw(world, worldX, worldY)
				emit = if bgId then Blocks.light(bgId) else 0
			end
			if emit > 0 then
				local index = rowBase + lx + 1
				if levels[index] < emit then
					levels[index] = emit
					tail += 1
					queue[tail] = index
				end
			end
		end
	end

	-- 3) المصادر الديناميكية
	for _, source in extraSources do
		local lx, ly = math.floor(source.x) - originX, math.floor(source.y) - originY
		if lx >= 0 and ly >= 0 and lx < width and ly < height then
			local index = ly * width + lx + 1
			if levels[index] < source.level then
				levels[index] = source.level
				tail += 1
				queue[tail] = index
			end
		end
	end

	-- 4) الانتشار
	while head <= tail do
		local index = queue[head]
		head += 1
		local level = levels[index]
		if level > 1 then
			local i0 = index - 1
			local lx = i0 % width
			local ly = i0 // width

			for _, offset in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local nx, ny = lx + offset[1], ly + offset[2]
				if nx >= 0 and ny >= 0 and nx < width and ny < height then
					local nIndex = ny * width + nx + 1
					local worldX, worldY = originX + nx, originY + ny
					local neighbourFg = World.fgRaw(world, worldX, worldY)
					-- قطعة غير محمّلة بعد: عاملها كصخر معتم حتى لا يتسرّب الضوء
					local blockOpacity = if neighbourFg then Blocks.opacity(neighbourFg) else 15
					local opacity = math.max(1, blockOpacity)
					if blockOpacity < 15 then
						-- الجدار الخلفي يخفت الضوء قليلاً أيضاً
						local neighbourBg = World.bgRaw(world, worldX, worldY)
						if neighbourBg and neighbourBg ~= 0 then
							opacity = math.max(opacity, 2)
						end
					end
					local spread = level - opacity
					if spread > levels[nIndex] then
						levels[nIndex] = spread
						tail += 1
						queue[tail] = nIndex
					end
				end
			end
		end
	end
end

return Lighting
