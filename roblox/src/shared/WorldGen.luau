--!strict
--[[
	WorldGen — توليد العالم الحتمي.

	القاعدة الذهبية: هذا الملف *نقي تماماً*. نفس (seed, cx, cy) يعطي نفس القطعة
	على الخادم والعميل معاً. لذلك لا نُرسل بيانات العالم عبر الشبكة إطلاقاً —
	نرسل فقط ما عدّله اللاعبون. هكذا نحصل على عالم بمليون بلاطة بلا أي كلفة شبكة.
]]

local Blocks = require(script.Parent.Blocks)
local Chunk = require(script.Parent.Chunk)
local Config = require(script.Parent.Config)
local Noise = require(script.Parent.Noise)
local Util = require(script.Parent.Util)

local B = Blocks.ID
local SIZE = Config.CHUNK

local WorldGen = {}

export type Biome = "forest" | "desert" | "snow" | "jungle" | "plains"

local heightCache: { [number]: number } = {}
local biomeCache: { [number]: Biome } = {}
local cachedSeed: number? = nil

local function ensureSeed(seed: number)
	if cachedSeed ~= seed then
		cachedSeed = seed
		heightCache = {}
		biomeCache = {}
	end
end

-- ===== المناطق الحيوية =====
function WorldGen.biomeAt(seed: number, x: number): Biome
	ensureSeed(seed)
	local cached = biomeCache[x]
	if cached then return cached :: Biome end

	local n = Noise.fbm1(x, seed + 9001, 3, 0.0016, 0.5)
	local warp = Noise.value1(x * 0.01, seed + 4242) * 0.12
	local v = n + warp
	local biome: Biome
	if v < 0.28 then
		biome = "snow"
	elseif v < 0.44 then
		biome = "forest"
	elseif v < 0.58 then
		biome = "plains"
	elseif v < 0.74 then
		biome = "jungle"
	else
		biome = "desert"
	end
	biomeCache[x] = biome
	return biome
end

-- ===== ارتفاع السطح =====
function WorldGen.surfaceHeight(seed: number, x: number): number
	ensureSeed(seed)
	local cached = heightCache[x]
	if cached then return cached end

	local base = Noise.fbm1(x, seed, 4, 0.006, 0.5) -- تلال عريضة
	local detail = Noise.fbm1(x, seed + 771, 3, 0.045, 0.45) -- تفاصيل دقيقة
	local mountain = Noise.fbm1(x, seed + 1337, 2, 0.0022, 0.5)
	mountain = math.max(0, mountain - 0.55) * 2.4 -- سلاسل جبلية متفرقة

	local h = Config.SURFACE
		- (base - 0.5) * Config.SURFACE_AMP * 2
		- (detail - 0.5) * 6
		- mountain * 48

	local biome = WorldGen.biomeAt(seed, x)
	if biome == "desert" then
		h += 6 -- كثبان منخفضة
	elseif biome == "snow" then
		h -= 10
	elseif biome == "jungle" then
		h += 3
	end

	h = math.floor(Util.clamp(h, Config.SKY_TOP + 20, Config.SURFACE + 70))
	heightCache[x] = h
	return h
end

-- ===== الكهوف =====
local function isCave(seed: number, x: number, y: number, surface: number): boolean
	if y < surface + 4 then return false end

	-- أنفاق طويلة (ridged noise)؛ كلما زاد العمق زاد الفراغ
	local depth = (y - surface) / (Config.WORLD_H - surface)
	local threshold = 0.80 - depth * 0.12
	local tunnel = Noise.ridged2(x * 0.9, y * 1.5, seed + 555, 2, 0.022)
	if tunnel > threshold then return true end

	-- الجيوب الكبيرة تُحسب فقط تحت عمق معيّن (توفير ثلث كلفة التوليد)
	if y > surface + 25 then
		local pocket = Noise.fbm2(x, y, seed + 8123, 3, 0.028, 0.5)
		if pocket > 0.72 then return true end
	end
	return false
end

-- ===== الخامات =====
-- ملاحظة أداء: نستدعي ضوضاء خلوية *واحدة* لتحديد وجود عرق، ثم نختار نوع الخام
-- بتجزئة رخيصة موزونة بالعمق. الصيغة القديمة كانت تستدعي ضوضاء لكل نوع خام
-- (سبعة استدعاءات لكل بلاطة حجرية) وكانت أبطأ بأضعاف بلا فائدة بصرية.
local oreTable = {
	{ id = B.COAL_ORE, minY = 0, maxY = 400, weight = 30 },
	{ id = B.COPPER_ORE, minY = 5, maxY = 380, weight = 26 },
	{ id = B.IRON_ORE, minY = 40, maxY = 460, weight = 20 },
	{ id = B.SILVER_ORE, minY = 140, maxY = 470, weight = 12 },
	{ id = B.GOLD_ORE, minY = 200, maxY = 480, weight = 8 },
	{ id = B.DIAMOND_ORE, minY = 290, maxY = 500, weight = 5 },
	{ id = B.MYTHRIL_ORE, minY = 370, maxY = 505, weight = 4 },
}

local VEIN_SCALE = 7
local VEIN_THRESHOLD = 0.17

local function oreAt(seed: number, x: number, y: number): number?
	local vein = Noise.cell2(x, y, seed + 3607, VEIN_SCALE)
	if vein > VEIN_THRESHOLD then return nil end

	-- نوع الخام ثابت لكل عرق تقريباً (نُجزّئ على شبكة أخشن)
	local roll = Util.rand2(x // VEIN_SCALE, y // VEIN_SCALE, seed + 9173)
	local total = 0
	for _, ore in oreTable do
		if y >= ore.minY and y <= ore.maxY then total += ore.weight end
	end
	if total <= 0 then return nil end

	local pick = roll * total
	for _, ore in oreTable do
		if y >= ore.minY and y <= ore.maxY then
			pick -= ore.weight
			if pick <= 0 then return ore.id end
		end
	end
	return nil
end

-- ===== الأشجار =====
-- تُولَّد حتمياً: العمود x يحمل شجرة إذا تحقق شرط تجزئة ثابت.
local function treeAt(seed: number, x: number): boolean
	local biome = WorldGen.biomeAt(seed, x)
	if biome == "desert" then return false end
	local r = Util.rand1(x, seed + 24601)
	local density = if biome == "jungle" then 0.34 elseif biome == "forest" then 0.24 elseif biome == "snow" then 0.13 else 0.08
	if r > density then return false end
	-- تباعد أدنى: لا شجرتان متلاصقتان
	for dx = -2, -1 do
		if Util.rand1(x + dx, seed + 24601) <= density then return false end
	end
	return true
end

local function treeHeight(seed: number, x: number): number
	local biome = WorldGen.biomeAt(seed, x)
	local base = if biome == "jungle" then 11 elseif biome == "snow" then 7 else 9
	return base + math.floor(Util.rand1(x, seed + 777) * 5)
end

-- كتابة شجرة داخل قطعة (تكتب فقط ما يقع داخل حدود القطعة)
local function writeTree(data: buffer, seed: number, x: number, chunkX0: number, chunkY0: number)
	local groundY = WorldGen.surfaceHeight(seed, x)
	local h = treeHeight(seed, x)
	local biome = WorldGen.biomeAt(seed, x)
	local leafId = B.LEAVES

	local function put(px: number, py: number, id: number, overwriteOnly: boolean?)
		local lx, ly = px - chunkX0, py - chunkY0
		if lx < 0 or lx >= SIZE or ly < 0 or ly >= SIZE then return end
		local idx = Chunk.index(lx, ly)
		if overwriteOnly and Chunk.getFg(data, idx) ~= B.AIR then return end
		Chunk.setFg(data, idx, id)
	end

	-- الجذع
	for i = 1, h do
		put(x, groundY - i, B.LOG)
	end

	-- التاج
	local top = groundY - h
	local radius = if biome == "jungle" then 3 else 2
	for dy = -radius - 1, 1 do
		for dx = -radius, radius do
			local d = math.abs(dx) + math.abs(dy)
			if d <= radius + 1 then
				put(x + dx, top + dy, leafId, true)
			end
		end
	end

	-- أغصان بسيطة
	if h > 8 then
		put(x - 1, groundY - h + 3, leafId, true)
		put(x + 1, groundY - h + 5, leafId, true)
	end
end

-- ===== توليد قطعة كاملة =====
function WorldGen.generateChunk(seed: number, cx: number, cy: number): buffer
	local data = Chunk.create()
	local x0, y0 = cx * SIZE, cy * SIZE

	for lx = 0, SIZE - 1 do
		local x = x0 + lx
		local surface = WorldGen.surfaceHeight(seed, x)
		local biome = WorldGen.biomeAt(seed, x)

		for ly = 0, SIZE - 1 do
			local y = y0 + ly
			local idx = Chunk.index(lx, ly)
			local fg, bg = B.AIR, B.AIR

			if y >= Config.BEDROCK_Y then
				fg, bg = B.BEDROCK, B.BEDROCK
			elseif y < surface then
				-- فوق السطح: هواء (قد تُضاف نباتات لاحقاً)
				fg = B.AIR
			else
				local depth = y - surface
				-- الطبقة الأساسية
				if y >= Config.HELL_Y then
					fg = B.ASH
					bg = B.ASH
				elseif depth < 1 then
					if biome == "desert" then fg = B.SAND
					elseif biome == "snow" then fg = B.SNOW
					elseif biome == "jungle" then fg = B.JUNGLE_GRASS
					else fg = B.GRASS end
					bg = if biome == "desert" then B.SAND elseif biome == "jungle" then B.MUD else B.DIRT
				elseif depth < Config.DIRT_DEPTH then
					if biome == "desert" then
						fg = if depth < 10 then B.SAND else B.SANDSTONE
					elseif biome == "jungle" then
						fg = B.MUD
					elseif biome == "snow" and depth < 5 then
						fg = B.SNOW
					else
						fg = B.DIRT
					end
					bg = fg
					-- جيوب طين وحصى من ضوضاء خلوية واحدة (بعتبتين) بدل استدعاءين
					local pocket = Noise.cell2(x, y, seed + 4404, 9)
					if pocket < 0.10 then
						fg = if depth > 6 then B.CLAY else B.GRAVEL
					elseif pocket < 0.17 then
						fg = B.GRAVEL
					end
				else
					fg = B.STONE
					bg = B.STONE
					if depth < Config.DIRT_DEPTH + 14 and Noise.value2(x * 0.1, y * 0.1, seed + 11) > 0.6 then
						fg = B.DIRT -- تداخل طبيعي بين التراب والحجر
					end
				end

				-- الجحيم: حجر جهنمي وبحيرات حمم
				if y >= Config.HELL_Y then
					if Noise.cell2(x, y, seed + 6606, 7) < 0.14 then fg = B.HELLSTONE_ORE end
					if y > Config.HELL_Y + 18 and Noise.fbm2(x, y, seed + 909, 2, 0.03, 0.5) > 0.62 then
						fg = B.LAVA
					end
				end

				-- نحت الكهوف
				if fg ~= B.BEDROCK and isCave(seed, x, y, surface) then
					fg = B.AIR
					-- بحيرات جوفية
					if y > Config.CAVERN_Y and y < Config.HELL_Y and Noise.value2(x * 0.02, y * 0.05, seed + 313) > 0.80 then
						fg = B.WATER
					elseif y >= Config.HELL_Y then
						fg = B.LAVA
					end
				end

				-- الخامات (لا تُزرع في الفراغ)
				if fg == B.STONE or fg == B.DIRT or fg == B.ASH then
					local ore = oreAt(seed, x, y)
					if ore then
						fg = ore
					elseif y > Config.CAVERN_Y and Noise.cell2(x, y, seed + 7707, 12) < 0.05 then
						fg = B.CRYSTAL
					end
				end
			end

			Chunk.setFg(data, idx, fg)
			Chunk.setBg(data, idx, bg)
		end
	end

	-- ===== زخرفة السطح: نباتات وأشجار =====
	for lx = -4, SIZE + 3 do -- نتجاوز الحدود لأن الأشجار تتعدى القطعة
		local x = x0 + lx
		if x >= 0 and x < Config.WORLD_W then
			local surface = WorldGen.surfaceHeight(seed, x)
			local biome = WorldGen.biomeAt(seed, x)

			if treeAt(seed, x) then
				writeTree(data, seed, x, x0, y0)
			end

			-- نباتات صغيرة فوق السطح مباشرة
			if lx >= 0 and lx < SIZE then
				local py = surface - 1
				local ly = py - y0
				if ly >= 0 and ly < SIZE then
					local idx = Chunk.index(lx, ly)
					if Chunk.getFg(data, idx) == B.AIR then
						local r = Util.rand1(x, seed + 3131)
						if biome == "desert" then
							if r > 0.96 then
								-- صبّار بارتفاع 2-4
								for i = 0, math.floor(r * 10) % 3 + 1 do
									local cy2 = py - i - y0
									if cy2 >= 0 and cy2 < SIZE then
										Chunk.setFg(data, Chunk.index(lx, cy2), B.CACTUS)
									end
								end
							end
						elseif biome ~= "snow" then
							if r > 0.88 then
								Chunk.setFg(data, idx, B.FLOWER)
							elseif r > 0.45 then
								Chunk.setFg(data, idx, B.GRASS_TUFT)
							elseif r > 0.40 then
								Chunk.setFg(data, idx, B.MUSHROOM)
							end
						end
					end
				end
			end
		end
	end

	-- ===== زخرفة الكهوف: فطر متوهج، خيوط، لبلاب =====
	for lx = 0, SIZE - 1 do
		local x = x0 + lx
		for ly = 0, SIZE - 1 do
			local y = y0 + ly
			local idx = Chunk.index(lx, ly)
			if Chunk.getFg(data, idx) == B.AIR and y > Config.SURFACE + 30 then
				local below = if ly + 1 < SIZE then Chunk.getFg(data, Chunk.index(lx, ly + 1)) else B.AIR
				local above = if ly > 0 then Chunk.getFg(data, Chunk.index(lx, ly - 1)) else B.AIR
				local r = Util.rand2(x, y, seed + 8484)
				if Blocks.isSolid(below) and r > 0.965 then
					Chunk.setFg(data, idx, if r > 0.985 then B.GLOW_MUSHROOM else B.MUSHROOM)
				elseif Blocks.isSolid(above) and r < 0.02 then
					Chunk.setFg(data, idx, if y > Config.CAVERN_Y then B.COBWEB else B.VINE)
				end
			end
		end
	end

	return data
end

-- نقطة ظهور آمنة عند منتصف العالم
function WorldGen.spawnPoint(seed: number): (number, number)
	local x = Config.WORLD_W // 2
	for i = 0, 60 do
		local candidate = x + i
		local biome = WorldGen.biomeAt(seed, candidate)
		if biome ~= "desert" and not treeAt(seed, candidate) then
			return candidate + 0.5, WorldGen.surfaceHeight(seed, candidate) - 2
		end
	end
	return x + 0.5, WorldGen.surfaceHeight(seed, x) - 2
end

return WorldGen
