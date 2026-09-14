--!strict
--[[
	ArtBlocks — رسّامو نقوش البلاطات.

	لكل نمط نقش دالة ترسم بلاطة 16×16 بكسلاً بكسلاً. لا صور خارجية:
	الحجر يُرشّ حبيباً، والخشب يُخطّ عروقاً، والطوب يُبنى صفوفاً مزاحة،
	والخامات تُنثر عناقيدَ داخل صخر مضيف.

	وحدة نقية (بلا واجهة روبلوكس) — تُختبر خارج المحرّك.
]]

local Blocks = require(script.Parent.Blocks)
local Pixels = require(script.Parent.Pixels)

local B = Blocks.ID
local ArtBlocks = {}

export type Canvas = Pixels.Canvas

local function rgb(color: Color3): (number, number, number)
	return Pixels.rgb(color)
end

local function mix(color: Color3, other: Color3, t: number): Color3
	return color:Lerp(other, t)
end

local BLACK = Color3.fromRGB(0, 0, 0)
local WHITE = Color3.fromRGB(255, 255, 255)
local STONE_HOST = Color3.fromRGB(122, 122, 130)
local ASH_HOST = Color3.fromRGB(78, 70, 68)

-- ===== لبنات أساسية =====

local function fillBase(canvas: Canvas, size: number, color: Color3)
	local r, g, b = rgb(color)
	Pixels.fill(canvas, 0, 0, size, size, r, g, b, 255)
end

-- صخر حبيبي: أساس + رشّ + شقوق قصيرة
local function rockTexture(canvas: Canvas, size: number, color: Color3, seed: number, grain: number)
	fillBase(canvas, size, color)
	Pixels.speckle(canvas, 0, 0, size, size, seed, grain, 0.34)

	-- شقّان قصيران يكسران الرتابة
	local dark = mix(color, BLACK, 0.35)
	local dr, dg, db = rgb(dark)
	for i = 0, 1 do
		local sx = math.floor(Pixels.noise(seed + i, 11, seed) * size)
		local sy = math.floor(Pixels.noise(seed + i, 23, seed) * size)
		local length = 2 + math.floor(Pixels.noise(seed + i, 37, seed) * 3)
		local horizontal = Pixels.noise(seed + i, 41, seed) > 0.5
		for k = 0, length do
			if horizontal then
				Pixels.set(canvas, sx + k, sy, dr, dg, db, 255)
			else
				Pixels.set(canvas, sx, sy + k, dr, dg, db, 255)
			end
		end
	end
end

-- تربة: حبيبات أخشن + حصيّات صغيرة
local function soilTexture(canvas: Canvas, size: number, color: Color3, seed: number)
	fillBase(canvas, size, color)
	Pixels.speckle(canvas, 0, 0, size, size, seed, 0.26, 0.4)

	local pebble = mix(color, BLACK, 0.28)
	local pr, pg, pb = rgb(pebble)
	for i = 0, 3 do
		local px = math.floor(Pixels.noise(seed + i * 7, 3, seed) * (size - 2))
		local py = math.floor(Pixels.noise(seed + i * 7, 5, seed) * (size - 2))
		Pixels.fill(canvas, px, py, 2, 1, pr, pg, pb, 255)
		Pixels.set(canvas, px, py + 1, pr, pg, pb, 255)
	end
end

-- ===== الرسّامون =====

type Painter = (canvas: Canvas, size: number, block: Blocks.Block, seed: number) -> ()

local painters: { [string]: Painter } = {}

painters.rock = function(canvas, size, block, seed)
	rockTexture(canvas, size, block.color, seed, 0.22)
end

painters.soil = function(canvas, size, block, seed)
	soilTexture(canvas, size, block.color, seed)
end

painters.grass = function(canvas, size, block, seed)
	-- تراب تحت، وغطاء عشبي متعرّج فوقه
	soilTexture(canvas, size, Color3.fromRGB(120, 85, 58), seed)
	local top = block.color
	local tr, tg, tb = rgb(top)
	local shade = mix(top, BLACK, 0.3)
	local sr, sg, sb = rgb(shade)

	for x = 0, size - 1 do
		local depth = 4 + math.floor(Pixels.noise(x, 1, seed) * 3)
		for y = 0, depth - 1 do
			local tone = if y == depth - 1 then 0.55 else 0
			Pixels.set(canvas, x, y,
				tr * (1 - tone) + sr * tone,
				tg * (1 - tone) + sg * tone,
				tb * (1 - tone) + sb * tone, 255)
		end
		-- بريق على السطح
		if Pixels.noise(x, 9, seed) > 0.72 then
			local lr, lg, lb = rgb(mix(top, WHITE, 0.3))
			Pixels.set(canvas, x, 0, lr, lg, lb, 255)
		end
	end
end

painters.sand = function(canvas, size, block, seed)
	fillBase(canvas, size, block.color)
	Pixels.speckle(canvas, 0, 0, size, size, seed, 0.16, 0.45)
	-- طبقات أفقية خفيفة
	local band = mix(block.color, BLACK, 0.12)
	local br, bg, bb = rgb(band)
	for y = 3, size - 1, 5 do
		for x = 0, size - 1 do
			if Pixels.noise(x, y, seed) > 0.35 then
				Pixels.set(canvas, x, y, br, bg, bb, 255)
			end
		end
	end
end

painters.layered = function(canvas, size, block, seed)
	fillBase(canvas, size, block.color)
	local dark = mix(block.color, BLACK, 0.22)
	local light = mix(block.color, WHITE, 0.16)
	local dr, dg, db = rgb(dark)
	local lr, lg, lb = rgb(light)
	for y = 0, size - 1 do
		if y % 4 == 0 then
			Pixels.fill(canvas, 0, y, size, 1, dr, dg, db, 255)
		elseif y % 4 == 1 then
			Pixels.fill(canvas, 0, y, size, 1, lr, lg, lb, 255)
		end
	end
	Pixels.speckle(canvas, 0, 0, size, size, seed, 0.12, 0.3)
end

painters.log = function(canvas, size, block, seed)
	fillBase(canvas, size, block.color)
	local dark = mix(block.color, BLACK, 0.34)
	local light = mix(block.color, WHITE, 0.18)
	local dr, dg, db = rgb(dark)
	local lr, lg, lb = rgb(light)

	-- عروق رأسية بعرض متغيّر
	for x = 0, size - 1 do
		local n = Pixels.noise(x, 2, seed)
		if n > 0.74 then
			Pixels.fill(canvas, x, 0, 1, size, dr, dg, db, 255)
		elseif n < 0.18 then
			Pixels.fill(canvas, x, 0, 1, size, lr, lg, lb, 255)
		end
	end
	-- حافتا اللحاء
	Pixels.fill(canvas, 0, 0, 1, size, dr, dg, db, 255)
	Pixels.fill(canvas, size - 1, 0, 1, size, dr, dg, db, 255)
	-- عقدة
	local kx = 4 + math.floor(Pixels.noise(seed, 7, seed) * 6)
	local ky = 4 + math.floor(Pixels.noise(seed, 13, seed) * 7)
	Pixels.ellipse(canvas, kx, ky, 2, 1.6, dr, dg, db, 255)
	Pixels.set(canvas, kx, ky, lr, lg, lb, 255)
end

painters.plank = function(canvas, size, block, seed)
	fillBase(canvas, size, block.color)
	local seam = mix(block.color, BLACK, 0.45)
	local light = mix(block.color, WHITE, 0.16)
	local grain = mix(block.color, BLACK, 0.2)
	local sr, sg, sb = rgb(seam)
	local lr, lg, lb = rgb(light)
	local grainR, grainG, grainB = rgb(grain)

	-- ثلاثة ألواح أفقية طويلة: فاصل غائر ثم حافة مضاءة
	for _, y in { 0, 5, 10 } do
		Pixels.fill(canvas, 0, y, size, 1, sr, sg, sb, 255)
		Pixels.fill(canvas, 0, y + 1, size, 1, lr, lg, lb, 255)
	end

	-- عروق طولية داخل كل لوح (شرطات، لا فواصل كاملة)
	for _, y in { 2, 7, 12 } do
		for x = 0, size - 1 do
			if Pixels.noise(x, y, seed) > 0.66 then
				Pixels.set(canvas, x, y, grainR, grainG, grainB, 255)
			end
		end
	end

	-- مسمار واحد في كل لوح
	local nail = mix(block.color, BLACK, 0.6)
	local nr, ng, nb = rgb(nail)
	Pixels.set(canvas, 2, 3, nr, ng, nb, 255)
	Pixels.set(canvas, size - 3, 8, nr, ng, nb, 255)
	Pixels.set(canvas, 3, 13, nr, ng, nb, 255)
	Pixels.speckle(canvas, 0, 0, size, size, seed, 0.08, 0.22)
end

painters.brick = function(canvas, size, block, seed)
	fillBase(canvas, size, block.color)
	local mortar = mix(block.color, BLACK, 0.45)
	local light = mix(block.color, WHITE, 0.16)
	local mr, mg, mb = rgb(mortar)
	local lr, lg, lb = rgb(light)

	local rowHeight = 4
	for row = 0, math.floor(size / rowHeight) - 1 do
		local y = row * rowHeight
		Pixels.fill(canvas, 0, y, size, 1, mr, mg, mb, 255)
		Pixels.fill(canvas, 0, y + 1, size, 1, lr, lg, lb, 255)
		-- فواصل رأسية مزاحة بين الصفوف
		local offset = if row % 2 == 0 then 0 else math.floor(size / 4)
		for x = offset, size - 1, math.floor(size / 2) do
			Pixels.fill(canvas, x, y, 1, rowHeight, mr, mg, mb, 255)
		end
	end
	Pixels.speckle(canvas, 0, 0, size, size, seed, 0.08, 0.25)
end

painters.ore = function(canvas, size, block, seed)
	local host = if block.id == B.HELLSTONE_ORE then ASH_HOST else STONE_HOST
	rockTexture(canvas, size, host, seed, 0.2)

	local gem = block.color
	local gr, gg, gb = rgb(gem)
	local bright = mix(gem, WHITE, 0.45)
	local br, bg, bb = rgb(bright)
	local edge = mix(gem, BLACK, 0.35)
	local er, eg, eb = rgb(edge)

	-- ثلاثة عناقيد بأحجام مختلفة
	for i = 0, 2 do
		local cx = 3 + math.floor(Pixels.noise(seed + i * 13, 3, seed) * (size - 6))
		local cy = 3 + math.floor(Pixels.noise(seed + i * 13, 9, seed) * (size - 6))
		local radius = 1.4 + Pixels.noise(seed + i, 17, seed) * 1.3
		Pixels.disc(canvas, cx, cy, radius + 0.6, er, eg, eb, 255)
		Pixels.disc(canvas, cx, cy, radius, gr, gg, gb, 255)
		Pixels.set(canvas, cx - 1, cy - 1, br, bg, bb, 255)
	end
end

painters.crystal = function(canvas, size, block, seed)
	rockTexture(canvas, size, mix(STONE_HOST, BLACK, 0.35), seed, 0.18)
	local gem = block.color
	local bright = mix(gem, WHITE, 0.5)
	local br, bg, bb = rgb(bright)
	local dark = mix(gem, BLACK, 0.4)

	-- بلّورة معيّنية الشكل
	local cx, cy = size // 2, size // 2
	for y = 0, size - 1 do
		local spread = 6 - math.floor(math.abs(y - cy) * 0.85)
		if spread > 0 then
			for x = cx - spread, cx + spread do
				local tone = if x < cx then bright elseif x > cx + 1 then dark else gem
				local r, g, b = rgb(tone)
				Pixels.set(canvas, x, y, r, g, b, 255)
			end
		end
	end
	Pixels.line(canvas, cx, 2, cx, size - 3, br, bg, bb, 255)
	Pixels.set(canvas, cx - 2, cy - 2, br, bg, bb, 255)
end

painters.leaves = function(canvas, size, block, seed)
	local base = block.color
	local dark = mix(base, BLACK, 0.32)
	local light = mix(base, WHITE, 0.22)

	Pixels.clear(canvas)
	-- كتل ورقية متداخلة مع فجوات شفافة
	for i = 0, 5 do
		local cx = 2 + math.floor(Pixels.noise(seed + i * 19, 3, seed) * (size - 4))
		local cy = 2 + math.floor(Pixels.noise(seed + i * 19, 11, seed) * (size - 4))
		local radius = 2.2 + Pixels.noise(seed + i, 29, seed) * 1.8
		local tone = if i % 3 == 0 then light elseif i % 3 == 1 then base else dark
		local r, g, b = rgb(tone)
		Pixels.disc(canvas, cx, cy, radius, r, g, b, 255)
	end
	-- املأ الحواف قليلاً حتى لا تبدو البلاطة ممزقة
	local r, g, b = rgb(base)
	for y = 0, size - 1 do
		for x = 0, size - 1 do
			local _, _, _, a = Pixels.get(canvas, x, y)
			if a == 0 and Pixels.noise(x, y, seed + 3) > 0.45 then
				Pixels.set(canvas, x, y, r, g, b, 255)
			end
		end
	end
	Pixels.speckle(canvas, 0, 0, size, size, seed, 0.18, 0.3)
end

painters.glass = function(canvas, size, block, seed)
	Pixels.clear(canvas)
	local tint = block.color
	local r, g, b = rgb(tint)
	-- زجاج شبه شفاف
	Pixels.fill(canvas, 0, 0, size, size, r, g, b, 42)
	-- إطار
	local frame = mix(tint, WHITE, 0.5)
	local fr, fg, fb = rgb(frame)
	Pixels.rectOutline(canvas, 0, 0, size, size, fr, fg, fb, 190)
	-- وميض قطري
	for i = 0, 5 do
		Pixels.set(canvas, 3 + i, 3 + i, 255, 255, 255, 150)
		Pixels.set(canvas, 4 + i, 3 + i, 255, 255, 255, 90)
	end
end

painters.liquid = function(canvas, size, block, seed)
	local base = block.color
	local light = mix(base, WHITE, 0.28)
	local dark = mix(base, BLACK, 0.22)
	local r, g, b = rgb(base)
	local alpha = if block.id == B.LAVA then 255 else 205
	Pixels.fill(canvas, 0, 0, size, size, r, g, b, alpha)

	local lr, lg, lb = rgb(light)
	local dr, dg, db = rgb(dark)
	for y = 0, size - 1 do
		for x = 0, size - 1 do
			local wave = math.sin((x + y * 0.6) * 0.9 + y) * 0.5 + 0.5
			if wave > 0.78 then
				Pixels.set(canvas, x, y, lr, lg, lb, alpha)
			elseif wave < 0.16 then
				Pixels.set(canvas, x, y, dr, dg, db, alpha)
			end
		end
	end
	if block.id == B.LAVA then
		-- عروق متوهجة
		local hot = mix(base, Color3.fromRGB(255, 240, 140), 0.7)
		local hr, hg, hb = rgb(hot)
		for i = 0, 2 do
			local y = 2 + i * 5
			Pixels.line(canvas, 0, y, size - 1, y + (if i % 2 == 0 then 2 else -2), hr, hg, hb, 255)
		end
	end
end

painters.snow = function(canvas, size, block, seed)
	fillBase(canvas, size, block.color)
	local shadow = mix(block.color, Color3.fromRGB(150, 180, 220), 0.4)
	local sr, sg, sb = rgb(shadow)
	for y = 0, size - 1 do
		for x = 0, size - 1 do
			if Pixels.noise(x, y, seed) > 0.82 then
				Pixels.set(canvas, x, y, sr, sg, sb, 255)
			elseif Pixels.noise(x, y, seed + 5) > 0.95 then
				Pixels.set(canvas, x, y, 255, 255, 255, 255)
			end
		end
	end
end

painters.ice = function(canvas, size, block, seed)
	local base = block.color
	local r, g, b = rgb(base)
	Pixels.fill(canvas, 0, 0, size, size, r, g, b, 225)
	local light = mix(base, WHITE, 0.55)
	local lr, lg, lb = rgb(light)
	for i = 0, 3 do
		local x = i * 4 + math.floor(Pixels.noise(i, 7, seed) * 3)
		Pixels.line(canvas, x, 0, x + 5, size - 1, lr, lg, lb, 200)
	end
	Pixels.speckle(canvas, 0, 0, size, size, seed, 0.12, 0.25)
end

painters.obsidian = function(canvas, size, block, seed)
	fillBase(canvas, size, block.color)
	local facet = mix(block.color, Color3.fromRGB(150, 120, 220), 0.35)
	local fr, fg, fb = rgb(facet)
	for i = 0, 4 do
		local x0 = math.floor(Pixels.noise(seed + i, 3, seed) * size)
		local y0 = math.floor(Pixels.noise(seed + i, 5, seed) * size)
		Pixels.line(canvas, x0, y0, x0 + 4, y0 + 4, fr, fg, fb, 255)
	end
	Pixels.speckle(canvas, 0, 0, size, size, seed, 0.22, 0.3)
end

painters.bedrock = function(canvas, size, block, seed)
	fillBase(canvas, size, block.color)
	local light = mix(block.color, WHITE, 0.22)
	local dark = mix(block.color, BLACK, 0.6)
	local lr, lg, lb = rgb(light)
	local dr, dg, db = rgb(dark)
	for y = 0, size - 1, 2 do
		for x = 0, size - 1, 2 do
			local n = Pixels.noise(x, y, seed)
			if n > 0.6 then
				Pixels.fill(canvas, x, y, 2, 2, lr, lg, lb, 255)
			elseif n < 0.3 then
				Pixels.fill(canvas, x, y, 2, 2, dr, dg, db, 255)
			end
		end
	end
end

painters.gravel = function(canvas, size, block, seed)
	-- أرضية داكنة بين الحصيّات حتى تبرز كل حصاة بحدّها
	fillBase(canvas, size, mix(block.color, BLACK, 0.42))
	local outline = mix(block.color, BLACK, 0.62)
	local orr, og, ob = rgb(outline)

	for i = 0, 13 do
		local cx = math.floor(Pixels.noise(seed + i * 3, 3, seed) * size)
		local cy = math.floor(Pixels.noise(seed + i * 3, 7, seed) * size)
		local radius = 1.4 + Pixels.noise(seed + i, 11, seed) * 1.1
		local tint = Pixels.noise(seed + i, 17, seed)
		local tone = mix(block.color, if tint > 0.6 then WHITE else BLACK, 0.16 * math.abs(tint - 0.5) * 2)
		local r, g, b = rgb(tone)
		Pixels.disc(canvas, cx, cy, radius + 0.5, orr, og, ob, 255)
		Pixels.disc(canvas, cx, cy, radius, r, g, b, 255)
		-- بريق علوي صغير يعطي استدارة
		Pixels.set(canvas, cx - 1, cy - 1, rgb(mix(tone, WHITE, 0.35)))
	end
end

painters.ash = function(canvas, size, block, seed)
	soilTexture(canvas, size, block.color, seed)
	-- جمرات خافتة
	for i = 0, 2 do
		local x = math.floor(Pixels.noise(seed + i, 19, seed) * size)
		local y = math.floor(Pixels.noise(seed + i, 23, seed) * size)
		Pixels.set(canvas, x, y, 220, 110, 60, 210)
	end
end

painters.cactus = function(canvas, size, block, seed)
	Pixels.clear(canvas)
	local base = block.color
	local dark = mix(base, BLACK, 0.3)
	local light = mix(base, WHITE, 0.25)
	local r, g, b = rgb(base)
	local dr, dg, db = rgb(dark)
	local lr, lg, lb = rgb(light)

	Pixels.fill(canvas, 2, 0, size - 4, size, r, g, b, 255)
	Pixels.fill(canvas, 2, 0, 1, size, dr, dg, db, 255)
	Pixels.fill(canvas, size - 3, 0, 1, size, dr, dg, db, 255)
	Pixels.fill(canvas, 5, 0, 1, size, lr, lg, lb, 255)
	Pixels.fill(canvas, 9, 0, 1, size, dr, dg, db, 255)
	-- أشواك
	for y = 1, size - 2, 4 do
		Pixels.set(canvas, 1, y, 240, 240, 220, 255)
		Pixels.set(canvas, size - 2, y + 2, 240, 240, 220, 255)
	end
end

painters.torch = function(canvas, size, block, seed)
	Pixels.clear(canvas)
	local stick = Color3.fromRGB(112, 78, 44)
	local sr, sg, sb = rgb(stick)
	local cx = size // 2
	Pixels.fill(canvas, cx - 1, 6, 2, size - 7, sr, sg, sb, 255)
	Pixels.fill(canvas, cx - 1, 6, 1, size - 7, rgb(mix(stick, BLACK, 0.3)))

	-- لهب: نواة بيضاء ثم صفراء ثم برتقالية
	Pixels.ellipse(canvas, cx, 4, 2.6, 3.2, 236, 120, 40, 255)
	Pixels.ellipse(canvas, cx, 4, 1.8, 2.4, 252, 196, 64, 255)
	Pixels.ellipse(canvas, cx, 4, 0.9, 1.4, 255, 246, 200, 255)
end

painters.lantern = function(canvas, size, block, seed)
	Pixels.clear(canvas)
	local metal = Color3.fromRGB(120, 110, 96)
	local mr, mg, mb = rgb(metal)
	local cx = size // 2
	Pixels.fill(canvas, cx - 1, 0, 2, 3, mr, mg, mb, 255)
	Pixels.rectOutline(canvas, cx - 4, 3, 9, 10, mr, mg, mb, 255)
	Pixels.fill(canvas, cx - 3, 4, 7, 8, 255, 224, 140, 255)
	Pixels.ellipse(canvas, cx, 8, 2, 3, 255, 250, 210, 255)
	Pixels.fill(canvas, cx - 4, 13, 9, 2, mr, mg, mb, 255)
end

painters.workbench = function(canvas, size, block, seed)
	Pixels.clear(canvas)
	local wood = block.color
	local dark = mix(wood, BLACK, 0.35)
	local light = mix(wood, WHITE, 0.2)
	local r, g, b = rgb(wood)
	local dr, dg, db = rgb(dark)
	local lr, lg, lb = rgb(light)

	Pixels.fill(canvas, 0, 3, size, 4, r, g, b, 255) -- السطح
	Pixels.fill(canvas, 0, 3, size, 1, lr, lg, lb, 255)
	Pixels.fill(canvas, 0, 6, size, 1, dr, dg, db, 255)
	Pixels.fill(canvas, 1, 7, 3, size - 7, r, g, b, 255) -- الأرجل
	Pixels.fill(canvas, size - 4, 7, 3, size - 7, r, g, b, 255)
	Pixels.fill(canvas, 1, 7, 1, size - 7, dr, dg, db, 255)
	Pixels.fill(canvas, size - 4, 7, 1, size - 7, dr, dg, db, 255)
	-- منشار ومطرقة صغيران على السطح
	Pixels.line(canvas, 4, 2, 9, 2, 200, 200, 210, 255)
	Pixels.fill(canvas, 11, 1, 3, 2, 150, 150, 160, 255)
end

painters.furnace = function(canvas, size, block, seed)
	rockTexture(canvas, size, block.color, seed, 0.2)
	local dark = mix(block.color, BLACK, 0.65)
	local dr, dg, db = rgb(dark)
	-- فتحة
	Pixels.fill(canvas, 3, 6, size - 6, 7, dr, dg, db, 255)
	Pixels.rectOutline(canvas, 3, 6, size - 6, 7, rgb(mix(block.color, BLACK, 0.35)))
	-- جمر متوهج
	for x = 4, size - 5 do
		local heat = Pixels.noise(x, 3, seed)
		if heat > 0.35 then
			Pixels.set(canvas, x, 11, 240, 140, 50, 255)
			Pixels.set(canvas, x, 12, 220, 90, 40, 255)
		end
	end
	Pixels.fill(canvas, 2, 2, size - 4, 2, rgb(mix(block.color, WHITE, 0.2)))
end

painters.anvil = function(canvas, size, block, seed)
	Pixels.clear(canvas)
	local metal = block.color
	local dark = mix(metal, BLACK, 0.4)
	local light = mix(metal, WHITE, 0.28)
	local r, g, b = rgb(metal)
	local dr, dg, db = rgb(dark)
	local lr, lg, lb = rgb(light)

	-- السطح العريض
	Pixels.fill(canvas, 2, 4, size - 4, 3, r, g, b, 255)
	Pixels.fill(canvas, 2, 4, size - 4, 1, lr, lg, lb, 255)
	Pixels.fill(canvas, 2, 6, size - 4, 1, dr, dg, db, 255)
	-- البوق المدبّب يساراً
	Pixels.fill(canvas, 0, 5, 2, 2, r, g, b, 255)
	Pixels.set(canvas, 0, 5, lr, lg, lb, 255)
	-- الخصر الضيّق
	Pixels.fill(canvas, 6, 7, 4, 4, dr, dg, db, 255)
	Pixels.fill(canvas, 6, 7, 1, 4, r, g, b, 255)
	-- القاعدة المتدرّجة
	Pixels.fill(canvas, 3, 11, size - 6, 2, r, g, b, 255)
	Pixels.fill(canvas, 2, 13, size - 4, 2, r, g, b, 255)
	Pixels.fill(canvas, 2, 14, size - 4, 1, dr, dg, db, 255)
end

painters.chest = function(canvas, size, block, seed)
	Pixels.clear(canvas)
	local wood = block.color
	local dark = mix(wood, BLACK, 0.38)
	local light = mix(wood, WHITE, 0.2)
	local r, g, b = rgb(wood)
	local dr, dg, db = rgb(dark)
	local lr, lg, lb = rgb(light)

	Pixels.fill(canvas, 1, 3, size - 2, size - 4, r, g, b, 255)
	Pixels.rectOutline(canvas, 1, 3, size - 2, size - 4, dr, dg, db, 255)
	Pixels.fill(canvas, 1, 3, size - 2, 1, lr, lg, lb, 255)
	Pixels.fill(canvas, 1, 7, size - 2, 1, dr, dg, db, 255) -- خط الغطاء
	-- الأحزمة المعدنية والقفل
	local metal = Color3.fromRGB(180, 150, 90)
	local mr, mg, mb = rgb(metal)
	Pixels.fill(canvas, 3, 3, 2, size - 4, mr, mg, mb, 255)
	Pixels.fill(canvas, size - 5, 3, 2, size - 4, mr, mg, mb, 255)
	Pixels.fill(canvas, size // 2 - 1, 6, 3, 4, mr, mg, mb, 255)
	Pixels.set(canvas, size // 2, 8, 40, 30, 20, 255)
end

painters.alchemy = function(canvas, size, block, seed)
	painters.workbench(canvas, size, block, seed)
	-- قوارير ملوّنة على السطح
	Pixels.fill(canvas, 3, 0, 2, 3, 120, 220, 150, 255)
	Pixels.fill(canvas, 7, 0, 2, 3, 220, 110, 150, 255)
	Pixels.fill(canvas, 11, 0, 2, 3, 130, 150, 240, 255)
end

painters.enchant = function(canvas, size, block, seed)
	Pixels.clear(canvas)
	local stone = block.color
	local r, g, b = rgb(stone)
	local dark = mix(stone, BLACK, 0.4)
	local dr, dg, db = rgb(dark)

	Pixels.fill(canvas, 1, 6, size - 2, size - 7, r, g, b, 255)
	Pixels.rectOutline(canvas, 1, 6, size - 2, size - 7, dr, dg, db, 255)
	Pixels.fill(canvas, 0, 5, size, 2, rgb(mix(stone, WHITE, 0.25)))
	-- جوهرة معلّقة متوهجة
	Pixels.ellipse(canvas, size // 2, 3, 2.6, 2.6, 200, 160, 255, 220)
	Pixels.ellipse(canvas, size // 2, 3, 1.4, 1.4, 245, 230, 255, 255)
	-- رموز
	for i = 0, 3 do
		Pixels.set(canvas, 3 + i * 3, 9, 210, 180, 255, 210)
		Pixels.set(canvas, 3 + i * 3, 12, 180, 150, 240, 170)
	end
end

painters.platform = function(canvas, size, block, seed)
	Pixels.clear(canvas)
	local wood = block.color
	local r, g, b = rgb(wood)
	local dark = mix(wood, BLACK, 0.4)
	local light = mix(wood, WHITE, 0.22)
	Pixels.fill(canvas, 0, 0, size, 4, r, g, b, 255)
	Pixels.fill(canvas, 0, 0, size, 1, rgb(light))
	Pixels.fill(canvas, 0, 3, size, 1, rgb(dark))
	for x = 3, size - 1, 5 do
		Pixels.fill(canvas, x, 0, 1, 4, rgb(dark))
	end
end

painters.ladder = function(canvas, size, block, seed)
	Pixels.clear(canvas)
	local wood = block.color
	local r, g, b = rgb(wood)
	local dark = mix(wood, BLACK, 0.38)
	local light = mix(wood, WHITE, 0.28)

	-- القائمان: ظلّ على اليسار وإضاءة على اليمين يعطيان استدارة
	for _, x in { 2, size - 4 } do
		Pixels.fill(canvas, x, 0, 3, size, r, g, b, 255)
		Pixels.fill(canvas, x, 0, 1, size, rgb(dark))
		Pixels.fill(canvas, x + 2, 0, 1, size, rgb(light))
	end

	-- الدرجات: حافة مضاءة أعلى وظلّ أسفل
	for y = 2, size - 1, 5 do
		Pixels.fill(canvas, 3, y, size - 6, 3, r, g, b, 255)
		Pixels.fill(canvas, 3, y, size - 6, 1, rgb(light))
		Pixels.fill(canvas, 3, y + 2, size - 6, 1, rgb(dark))
	end
end

painters.cobweb = function(canvas, size, block, seed)
	Pixels.clear(canvas)
	local cx, cy = size // 2, size // 2

	-- خيوط شعاعية بدرجات مختلفة: الأقرب للمركز أنصع
	for i = 0, 7 do
		local angle = i * math.pi / 4
		local bright = if i % 2 == 0 then 248 else 206
		Pixels.line(canvas, cx, cy,
			math.floor(cx + math.cos(angle) * 8),
			math.floor(cy + math.sin(angle) * 8),
			bright, bright, math.min(255, bright + 6), 190)
	end

	-- حلقات لولبية أخفت
	for ring = 3, 7, 2 do
		local tone = 232 - ring * 10
		for i = 0, 15 do
			local angle = i * math.pi / 8
			Pixels.set(canvas,
				math.floor(cx + math.cos(angle) * ring),
				math.floor(cy + math.sin(angle) * ring),
				tone, tone, tone + 6, 170)
		end
	end

	-- عقدة المركز
	Pixels.set(canvas, cx, cy, 255, 255, 255, 230)
end

-- نباتات صغيرة على خلفية شفافة
painters.plant = function(canvas, size, block, seed)
	Pixels.clear(canvas)
	local base = block.color
	local dark = mix(base, BLACK, 0.3)
	local r, g, b = rgb(base)
	local dr, dg, db = rgb(dark)
	local cx = size // 2

	if block.id == B.FLOWER then
		Pixels.fill(canvas, cx, 8, 1, size - 8, 80, 150, 70, 255)
		Pixels.disc(canvas, cx, 6, 2.6, r, g, b, 255)
		Pixels.disc(canvas, cx, 6, 1.1, 255, 236, 150, 255)
		Pixels.set(canvas, cx - 2, 10, 80, 150, 70, 255)
	elseif block.id == B.MUSHROOM or block.id == B.GLOW_MUSHROOM then
		Pixels.fill(canvas, cx - 1, 9, 3, size - 9, 232, 222, 200, 255)
		Pixels.ellipse(canvas, cx, 8, 4, 2.6, r, g, b, 255)
		Pixels.set(canvas, cx - 2, 7, 255, 255, 255, 220)
		Pixels.set(canvas, cx + 2, 8, 255, 255, 255, 200)
	elseif block.id == B.SAPLING then
		Pixels.fill(canvas, cx, 9, 1, size - 9, 120, 88, 52, 255)
		Pixels.disc(canvas, cx, 7, 3, r, g, b, 255)
		Pixels.disc(canvas, cx - 2, 9, 1.6, dr, dg, db, 255)
	elseif block.id == B.VINE then
		local light = mix(base, WHITE, 0.3)
		local lr, lg, lb = rgb(light)
		for y = 0, size - 1 do
			local sway = math.floor(math.sin(y * 0.6) * 1.6)
			Pixels.set(canvas, cx + sway - 1, y, lr, lg, lb, 255) -- حافة مضاءة
			Pixels.set(canvas, cx + sway, y, r, g, b, 255)
			Pixels.set(canvas, cx + sway + 1, y, dr, dg, db, 255) -- ظلّ
			-- ورقة صغيرة كل بضع بكسلات
			if y % 5 == 2 then
				Pixels.set(canvas, cx + sway - 2, y, r, g, b, 255)
				Pixels.set(canvas, cx + sway - 3, y + 1, lr, lg, lb, 255)
			elseif y % 5 == 4 then
				Pixels.set(canvas, cx + sway + 2, y, r, g, b, 255)
			end
		end
	else -- حشائش: شفرات عريضة عند القاعدة تدقّ نحو الطرف وتنحني
		local light = mix(base, WHITE, 0.3)
		for i = 0, 3 do
			local rootX = 2 + i * 4 + math.floor(Pixels.noise(i, 5, seed) * 2)
			local height = 7 + math.floor(Pixels.noise(rootX, 3, seed) * 6)
			local dir = if i % 2 == 0 then 1 else -1
			for y = 0, height - 1 do
				local t = y / math.max(1, height - 1)
				local lean = math.floor(t * t * 3) * dir
				local width = if t < 0.35 then 2 elseif t < 0.75 then 1 else 1
				local tone = if t < 0.25 then dark elseif t > 0.8 then light else base
				local tr, tg, tb = rgb(tone)
				for k = 0, width - 1 do
					Pixels.set(canvas, rootX + lean + k, size - 1 - y, tr, tg, tb, 255)
				end
			end
		end
	end
end

-- ===== توزيع الأنماط على البلاطات =====

local styles: { [number]: string } = {
	[B.STONE] = "rock", [B.CLAY] = "rock", [B.MUD] = "soil",
	[B.DIRT] = "soil", [B.GRASS] = "grass", [B.JUNGLE_GRASS] = "grass",
	[B.SAND] = "sand", [B.SANDSTONE] = "layered", [B.SNOW] = "snow", [B.ICE] = "ice",
	[B.GRAVEL] = "gravel", [B.ASH] = "ash",
	[B.LOG] = "log", [B.LEAVES] = "leaves", [B.PLANK] = "plank",
	[B.STONE_BRICK] = "brick", [B.SAND_BRICK] = "brick", [B.BRICK] = "brick",
	[B.ICE_BRICK] = "brick", [B.HELLSTONE_BRICK] = "brick",
	[B.GLASS] = "glass", [B.OBSIDIAN] = "obsidian", [B.BEDROCK] = "bedrock",
	[B.COAL_ORE] = "ore", [B.COPPER_ORE] = "ore", [B.IRON_ORE] = "ore",
	[B.SILVER_ORE] = "ore", [B.GOLD_ORE] = "ore", [B.DIAMOND_ORE] = "ore",
	[B.MYTHRIL_ORE] = "ore", [B.HELLSTONE_ORE] = "ore", [B.CRYSTAL] = "crystal",
	[B.WATER] = "liquid", [B.LAVA] = "liquid",
	[B.TORCH] = "torch", [B.LANTERN] = "lantern",
	[B.WORKBENCH] = "workbench", [B.FURNACE] = "furnace", [B.ANVIL] = "anvil",
	[B.CHEST] = "chest", [B.ALCHEMY] = "alchemy", [B.ENCHANT_TABLE] = "enchant",
	[B.PLATFORM] = "platform", [B.LADDER] = "ladder", [B.CACTUS] = "cactus",
	[B.COBWEB] = "cobweb",
	[B.GRASS_TUFT] = "plant", [B.FLOWER] = "plant", [B.MUSHROOM] = "plant",
	[B.GLOW_MUSHROOM] = "plant", [B.SAPLING] = "plant", [B.VINE] = "plant",
}

ArtBlocks.painters = painters
ArtBlocks.styles = styles

function ArtBlocks.styleOf(blockId: number): string
	local explicit = styles[blockId]
	if explicit then return explicit end
	-- افتراضي معقول لأي بلاطة جديدة تُضاف لاحقاً بلا نمط
	local block = Blocks.get(blockId)
	if block.liquid then return "liquid" end
	if block.fragile then return "plant" end
	if block.solid then return "rock" end
	return "plant"
end

-- يرسم بلاطة واحدة بلا إضاءة حواف
function ArtBlocks.paint(blockId: number, size: number): Canvas
	local canvas = Pixels.new(size, size)
	local block = Blocks.get(blockId)
	local painter = painters[ArtBlocks.styleOf(blockId)] or painters.rock
	painter(canvas, size, block, blockId * 7919 + 13)
	return canvas
end

-- هل يستفيد هذا النمط من إضاءة الحواف؟ (النباتات والمشاعل لا)
function ArtBlocks.usesEdges(blockId: number): boolean
	local style = ArtBlocks.styleOf(blockId)
	return style ~= "plant" and style ~= "torch" and style ~= "lantern"
		and style ~= "cobweb" and style ~= "ladder" and style ~= "platform"
		and style ~= "liquid" and style ~= "anvil" and style ~= "chest"
		and style ~= "workbench" and style ~= "alchemy" and style ~= "enchant"
end

return ArtBlocks
