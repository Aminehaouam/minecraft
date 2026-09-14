--!strict
--[[
	ArtItems — أيقونات العناصر بكسل آرت.

	لا نرسم 119 أيقونة يدوياً: نرسم *أشكالاً* (سيف، معول، قارورة، سبيكة…)
	ونلوّنها بلون العنصر من السجل. النتيجة أيقونة مميّزة لكل عنصر، وأي عنصر
	جديد يحصل على أيقونة تلقائياً بلا عمل فني إضافي.

	عناصر البلاطات تستعمل نقش البلاطة نفسه — كما في تيراريا.
]]

local ArtBlocks = require(script.Parent.ArtBlocks)
local Items = require(script.Parent.Items)
local Pixels = require(script.Parent.Pixels)

local ArtItems = {}

local BLACK = Color3.fromRGB(0, 0, 0)
local WHITE = Color3.fromRGB(255, 255, 255)
local WOOD = Color3.fromRGB(126, 92, 54)

local function rgb(color: Color3): (number, number, number)
	return Pixels.rgb(color)
end

local function mix(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, t)
end

type Shape = (canvas: Pixels.Canvas, size: number, item: Items.Item) -> ()

local shapes: { [string]: Shape } = {}

-- مقبض خشبي قطري مشترك بين الأدوات
local function handle(canvas: Pixels.Canvas, size: number, fromX: number, fromY: number, toX: number, toY: number)
	local r, g, b = rgb(WOOD)
	local dr, dg, db = rgb(mix(WOOD, BLACK, 0.35))
	Pixels.line(canvas, fromX, fromY, toX, toY, r, g, b, 255)
	Pixels.line(canvas, fromX + 1, fromY, toX + 1, toY, dr, dg, db, 255)
end

shapes.sword = function(canvas, size, item)
	local blade = item.color
	local light = mix(blade, WHITE, 0.45)
	local dark = mix(blade, BLACK, 0.4)
	local r, g, b = rgb(blade)
	local lr, lg, lb = rgb(light)
	local dr, dg, db = rgb(dark)

	-- نصل قطري من أسفل اليسار إلى أعلى اليمين
	for i = 0, 9 do
		local x = 4 + i
		local y = 11 - i
		Pixels.set(canvas, x, y, r, g, b, 255)
		Pixels.set(canvas, x, y - 1, lr, lg, lb, 255)
		Pixels.set(canvas, x + 1, y, dr, dg, db, 255)
	end
	Pixels.set(canvas, 14, 1, lr, lg, lb, 255)
	-- الحارس والمقبض
	local guard = mix(blade, Color3.fromRGB(180, 150, 70), 0.55)
	local gr, gg, gb = rgb(guard)
	Pixels.line(canvas, 2, 10, 6, 14, gr, gg, gb, 255)
	Pixels.line(canvas, 2, 13, 5, 10, gr, gg, gb, 255)
	handle(canvas, size, 1, 14, 4, 11)
end

shapes.pickaxe = function(canvas, size, item)
	local head = item.color
	local light = mix(head, WHITE, 0.4)
	local dark = mix(head, BLACK, 0.4)
	local r, g, b = rgb(head)
	local lr, lg, lb = rgb(light)
	local dr, dg, db = rgb(dark)

	handle(canvas, size, 5, 14, 10, 4)
	-- رأس مقوّس
	for i = 0, 5 do
		Pixels.set(canvas, 3 + i, 5 - math.floor(i * 0.4), r, g, b, 255)
		Pixels.set(canvas, 3 + i, 4 - math.floor(i * 0.4), lr, lg, lb, 255)
		Pixels.set(canvas, 12 - i, 5 - math.floor(i * 0.4), r, g, b, 255)
		Pixels.set(canvas, 12 - i, 6 - math.floor(i * 0.4), dr, dg, db, 255)
	end
	Pixels.fill(canvas, 7, 3, 2, 3, lr, lg, lb, 255)
end

shapes.axe = function(canvas, size, item)
	local head = item.color
	local light = mix(head, WHITE, 0.4)
	local dark = mix(head, BLACK, 0.4)
	local r, g, b = rgb(head)
	local lr, lg, lb = rgb(light)
	local dr, dg, db = rgb(dark)

	handle(canvas, size, 5, 14, 9, 4)
	-- شفرة على شكل هلال
	for y = 2, 8 do
		local width = 5 - math.abs(y - 5)
		for x = 0, width do
			Pixels.set(canvas, 9 + x, y, r, g, b, 255)
		end
		Pixels.set(canvas, 9, y, lr, lg, lb, 255)
		Pixels.set(canvas, 9 + width, y, dr, dg, db, 255)
	end
end

shapes.hammer = function(canvas, size, item)
	local head = item.color
	local r, g, b = rgb(head)
	local lr, lg, lb = rgb(mix(head, WHITE, 0.35))
	local dr, dg, db = rgb(mix(head, BLACK, 0.4))
	handle(canvas, size, 6, 14, 8, 6)
	Pixels.fill(canvas, 3, 2, 10, 5, r, g, b, 255)
	Pixels.fill(canvas, 3, 2, 10, 1, lr, lg, lb, 255)
	Pixels.fill(canvas, 3, 6, 10, 1, dr, dg, db, 255)
end

shapes.bow = function(canvas, size, item)
	local wood = item.color
	local r, g, b = rgb(wood)
	local dr, dg, db = rgb(mix(wood, BLACK, 0.35))
	-- قوس منحنٍ
	for y = 2, 13 do
		local bend = math.floor(math.sin((y - 2) / 11 * math.pi) * 4)
		Pixels.set(canvas, 4 + bend, y, r, g, b, 255)
		Pixels.set(canvas, 5 + bend, y, dr, dg, db, 255)
	end
	-- الوتر
	Pixels.line(canvas, 4, 2, 4, 13, 225, 225, 215, 220)
	Pixels.set(canvas, 3, 7, 225, 225, 215, 255)
end

shapes.staff = function(canvas, size, item)
	local gem = item.color
	handle(canvas, size, 4, 15, 10, 5)
	local r, g, b = rgb(gem)
	local lr, lg, lb = rgb(mix(gem, WHITE, 0.55))
	Pixels.disc(canvas, 11, 4, 3.2, r, g, b, 255)
	Pixels.disc(canvas, 11, 4, 1.6, lr, lg, lb, 255)
	Pixels.set(canvas, 10, 3, 255, 255, 255, 255)
	-- شرر
	Pixels.set(canvas, 14, 1, lr, lg, lb, 200)
	Pixels.set(canvas, 8, 1, lr, lg, lb, 160)
end

shapes.arrow = function(canvas, size, item)
	local shaft = Color3.fromRGB(150, 120, 84)
	local r, g, b = rgb(shaft)
	Pixels.line(canvas, 3, 12, 12, 3, r, g, b, 255)
	local tipR, tipG, tipB = rgb(item.color)
	Pixels.fill(canvas, 11, 2, 3, 3, tipR, tipG, tipB, 255)
	Pixels.set(canvas, 13, 2, 255, 255, 255, 220)
	-- الريش
	Pixels.set(canvas, 3, 11, 230, 230, 230, 255)
	Pixels.set(canvas, 2, 12, 230, 230, 230, 255)
	Pixels.set(canvas, 4, 13, 230, 230, 230, 255)
end

local function armorPiece(canvas: Pixels.Canvas, item: Items.Item, kind: string)
	local metal = item.color
	local r, g, b = rgb(metal)
	local lr, lg, lb = rgb(mix(metal, WHITE, 0.35))
	local dr, dg, db = rgb(mix(metal, BLACK, 0.4))

	if kind == "head" then
		Pixels.ellipse(canvas, 8, 7, 5, 4.6, r, g, b, 255)
		Pixels.fill(canvas, 3, 7, 10, 4, r, g, b, 255)
		Pixels.fill(canvas, 4, 8, 8, 2, 30, 26, 34, 255) -- فتحة العينين
		Pixels.ellipse(canvas, 8, 5, 4.4, 3, lr, lg, lb, 255)
		Pixels.fill(canvas, 3, 11, 10, 1, dr, dg, db, 255)
	elseif kind == "chest" then
		Pixels.fill(canvas, 3, 3, 10, 10, r, g, b, 255)
		Pixels.fill(canvas, 3, 3, 10, 2, lr, lg, lb, 255)
		Pixels.fill(canvas, 3, 12, 10, 1, dr, dg, db, 255)
		Pixels.fill(canvas, 1, 4, 2, 5, r, g, b, 255) -- الكتفان
		Pixels.fill(canvas, 13, 4, 2, 5, r, g, b, 255)
		Pixels.fill(canvas, 7, 5, 2, 7, dr, dg, db, 255)
	else
		Pixels.fill(canvas, 2, 7, 5, 6, r, g, b, 255)
		Pixels.fill(canvas, 9, 7, 5, 6, r, g, b, 255)
		Pixels.fill(canvas, 2, 7, 5, 1, lr, lg, lb, 255)
		Pixels.fill(canvas, 9, 7, 5, 1, lr, lg, lb, 255)
		Pixels.fill(canvas, 1, 12, 6, 2, dr, dg, db, 255)
		Pixels.fill(canvas, 9, 12, 6, 2, dr, dg, db, 255)
	end
end

shapes.armor_head = function(canvas, size, item) armorPiece(canvas, item, "head") end
shapes.armor_chest = function(canvas, size, item) armorPiece(canvas, item, "chest") end
shapes.armor_feet = function(canvas, size, item) armorPiece(canvas, item, "feet") end

shapes.potion = function(canvas, size, item)
	local liquid = item.color
	local r, g, b = rgb(liquid)
	local lr, lg, lb = rgb(mix(liquid, WHITE, 0.45))
	-- زجاجة
	Pixels.fill(canvas, 6, 2, 4, 3, 210, 220, 230, 235)
	Pixels.fill(canvas, 6, 1, 4, 1, 150, 120, 80, 255) -- سدادة
	Pixels.ellipse(canvas, 8, 10, 4.6, 4.6, 205, 218, 232, 190)
	Pixels.ellipse(canvas, 8, 11, 3.6, 3.4, r, g, b, 255)
	Pixels.ellipse(canvas, 7, 10, 1.2, 1.2, lr, lg, lb, 255)
	Pixels.set(canvas, 5, 8, 255, 255, 255, 220)
end

shapes.food = function(canvas, size, item)
	local base = item.color
	local r, g, b = rgb(base)
	local lr, lg, lb = rgb(mix(base, WHITE, 0.4))
	local dr, dg, db = rgb(mix(base, BLACK, 0.3))
	Pixels.ellipse(canvas, 8, 9, 5, 4.6, r, g, b, 255)
	Pixels.ellipse(canvas, 6, 7, 1.8, 1.6, lr, lg, lb, 255)
	Pixels.ellipse(canvas, 10, 11, 2, 1.6, dr, dg, db, 255)
	if item.id == "apple" then
		Pixels.fill(canvas, 8, 3, 1, 3, 90, 140, 60, 255)
		Pixels.ellipse(canvas, 10, 4, 2, 1.2, 110, 180, 80, 255)
	end
end

shapes.bar = function(canvas, size, item)
	local metal = item.color
	local r, g, b = rgb(metal)
	local lr, lg, lb = rgb(mix(metal, WHITE, 0.4))
	local dr, dg, db = rgb(mix(metal, BLACK, 0.4))
	-- سبيكة شبه منحرفة
	for y = 0, 4 do
		local inset = 4 - y
		Pixels.fill(canvas, 2 + inset, 6 + y, 12 - inset * 2, 1, r, g, b, 255)
	end
	Pixels.fill(canvas, 6, 6, 4, 1, lr, lg, lb, 255)
	Pixels.fill(canvas, 2, 10, 12, 2, dr, dg, db, 255)
	Pixels.set(canvas, 5, 7, 255, 255, 255, 210)
end

shapes.ore_chunk = function(canvas, size, item)
	local host = Color3.fromRGB(120, 120, 128)
	local hr, hg, hb = rgb(host)
	Pixels.ellipse(canvas, 8, 9, 5.4, 4.6, hr, hg, hb, 255)
	Pixels.ellipse(canvas, 6, 7, 2, 1.6, rgb(mix(host, WHITE, 0.3)))
	local gem = item.color
	local r, g, b = rgb(gem)
	local lr, lg, lb = rgb(mix(gem, WHITE, 0.45))
	for i = 0, 2 do
		local cx = 6 + i * 2
		local cy = 8 + (i % 2) * 2
		Pixels.disc(canvas, cx, cy, 1.4, r, g, b, 255)
		Pixels.set(canvas, cx - 1, cy - 1, lr, lg, lb, 255)
	end
end

shapes.gem = function(canvas, size, item)
	local gem = item.color
	local r, g, b = rgb(gem)
	local lr, lg, lb = rgb(mix(gem, WHITE, 0.5))
	local dr, dg, db = rgb(mix(gem, BLACK, 0.35))
	for y = 3, 12 do
		local spread = if y < 7 then y - 2 else 13 - y
		for x = 8 - spread, 8 + spread do
			local tone = if x < 8 then lr elseif x > 8 then dr else r
			local tg = if x < 8 then lg elseif x > 8 then dg else g
			local tb = if x < 8 then lb elseif x > 8 then db else b
			Pixels.set(canvas, x, y, tone, tg, tb, 255)
		end
	end
	Pixels.set(canvas, 6, 5, 255, 255, 255, 235)
end

shapes.dust = function(canvas, size, item)
	local color = item.color
	local r, g, b = rgb(color)
	local lr, lg, lb = rgb(mix(color, WHITE, 0.5))
	for i = 0, 7 do
		local x = 3 + math.floor(Pixels.noise(i, 3, 77) * 10)
		local y = 3 + math.floor(Pixels.noise(i, 7, 77) * 10)
		Pixels.disc(canvas, x, y, 1.2, r, g, b, 230)
		Pixels.set(canvas, x, y, lr, lg, lb, 255)
	end
	-- بريق رباعي في الوسط
	Pixels.line(canvas, 8, 3, 8, 12, lr, lg, lb, 210)
	Pixels.line(canvas, 3, 8, 12, 8, lr, lg, lb, 210)
end

shapes.coin = function(canvas, size, item)
	local gold = item.color
	local r, g, b = rgb(gold)
	Pixels.disc(canvas, 8, 8, 5, rgb(mix(gold, BLACK, 0.35)))
	Pixels.disc(canvas, 8, 8, 4.2, r, g, b, 255)
	Pixels.disc(canvas, 6.5, 6.5, 1.4, rgb(mix(gold, WHITE, 0.6)))
	Pixels.fill(canvas, 7, 6, 2, 5, rgb(mix(gold, BLACK, 0.2)))
end

shapes.blob = function(canvas, size, item)
	local color = item.color
	local r, g, b = rgb(color)
	Pixels.ellipse(canvas, 8, 10, 5.2, 4, r, g, b, 225)
	Pixels.ellipse(canvas, 6.5, 8.5, 1.6, 1.2, 255, 255, 255, 200)
	Pixels.ellipse(canvas, 8, 12, 4, 1.6, rgb(mix(color, BLACK, 0.3)))
end

shapes.fiber = function(canvas, size, item)
	local color = item.color
	local r, g, b = rgb(color)
	for i = 0, 3 do
		local y = 4 + i * 3
		Pixels.line(canvas, 2, y, 13, y + (if i % 2 == 0 then 2 else -2), r, g, b, 255)
	end
	Pixels.disc(canvas, 8, 8, 2, rgb(mix(color, Color3.fromRGB(255, 255, 255), 0.3)))
end

shapes.bone = function(canvas, size, item)
	local r, g, b = rgb(item.color)
	Pixels.line(canvas, 4, 12, 12, 4, r, g, b, 255)
	Pixels.line(canvas, 5, 12, 13, 4, r, g, b, 255)
	Pixels.disc(canvas, 4, 12, 2, r, g, b, 255)
	Pixels.disc(canvas, 12, 4, 2, r, g, b, 255)
	Pixels.set(canvas, 4, 11, 255, 255, 255, 200)
end

shapes.leaf = function(canvas, size, item)
	local color = item.color
	local r, g, b = rgb(color)
	Pixels.ellipse(canvas, 8, 8, 5, 3.2, r, g, b, 255)
	Pixels.line(canvas, 3, 9, 13, 7, rgb(mix(color, BLACK, 0.35)))
	Pixels.line(canvas, 8, 11, 10, 14, 110, 84, 50, 255)
end

shapes.shard = function(canvas, size, item)
	local color = item.color
	local r, g, b = rgb(color)
	local lr, lg, lb = rgb(mix(color, WHITE, 0.5))
	Pixels.line(canvas, 8, 2, 4, 9, r, g, b, 255)
	Pixels.line(canvas, 8, 2, 12, 9, r, g, b, 255)
	Pixels.line(canvas, 4, 9, 8, 14, r, g, b, 255)
	Pixels.line(canvas, 12, 9, 8, 14, r, g, b, 255)
	for y = 4, 12 do
		local spread = if y < 9 then math.floor((y - 2) * 0.55) else math.floor((14 - y) * 0.75)
		for x = 8 - spread, 8 + spread do
			Pixels.set(canvas, x, y, r, g, b, 210)
		end
	end
	Pixels.line(canvas, 8, 3, 8, 13, lr, lg, lb, 240)
end

shapes.core = function(canvas, size, item)
	local color = item.color
	local r, g, b = rgb(color)
	Pixels.rectOutline(canvas, 3, 3, 10, 10, rgb(mix(color, Color3.fromRGB(0, 0, 0), 0.4)))
	Pixels.fill(canvas, 4, 4, 8, 8, r, g, b, 255)
	Pixels.ellipse(canvas, 8, 8, 2.4, 2.4, rgb(mix(color, WHITE, 0.6)))
	for i = 0, 3 do
		local x = if i % 2 == 0 then 2 else 13
		local y = if i < 2 then 2 else 13
		Pixels.set(canvas, x, y, rgb(mix(color, WHITE, 0.4)))
	end
end

shapes.mirror = function(canvas, size, item)
	local frame = Color3.fromRGB(190, 160, 90)
	Pixels.ellipse(canvas, 8, 6, 5, 5, rgb(frame))
	Pixels.ellipse(canvas, 8, 6, 3.6, 3.6, rgb(item.color))
	Pixels.ellipse(canvas, 6.6, 4.8, 1.2, 1.2, 255, 255, 255, 230)
	Pixels.fill(canvas, 7, 11, 2, 4, rgb(frame))
end

shapes.totem = function(canvas, size, item)
	local color = item.color
	Pixels.ellipse(canvas, 8, 8, 5.6, 5.2, 232, 228, 222, 255)
	Pixels.ellipse(canvas, 8, 8, 3, 3, rgb(color))
	Pixels.ellipse(canvas, 8, 8, 1.4, 1.4, 24, 18, 22, 255)
	Pixels.set(canvas, 6, 6, 255, 255, 255, 240)
	for i = 0, 3 do
		local angle = i * math.pi / 2 + 0.6
		Pixels.set(canvas, math.floor(8 + math.cos(angle) * 7), math.floor(8 + math.sin(angle) * 7), rgb(color))
	end
end

shapes.stone_rune = function(canvas, size, item)
	local color = item.color
	Pixels.ellipse(canvas, 8, 9, 5, 4.4, rgb(color))
	Pixels.ellipse(canvas, 6.4, 7.4, 1.6, 1.2, rgb(mix(color, WHITE, 0.35)))
	Pixels.line(canvas, 6, 10, 10, 6, 150, 220, 255, 235)
	Pixels.line(canvas, 6, 7, 10, 11, 150, 220, 255, 235)
end

shapes.logs = function(canvas, size, item)
	local wood = item.color
	local r, g, b = rgb(wood)
	local dark = mix(wood, BLACK, 0.35)
	local light = mix(wood, WHITE, 0.25)
	-- ثلاثة جذوع مكدّسة مع حلقات في المقطع
	for i = 0, 2 do
		local y = 4 + i * 4
		local x = 2 + (i % 2) * 2
		Pixels.fill(canvas, x, y, 11, 3, r, g, b, 255)
		Pixels.fill(canvas, x, y, 11, 1, rgb(light))
		Pixels.fill(canvas, x, y + 2, 11, 1, rgb(dark))
		Pixels.set(canvas, x + 1, y + 1, rgb(dark))
	end
end

shapes.hide = function(canvas, size, item)
	local base = item.color
	local r, g, b = rgb(base)
	local dark = mix(base, BLACK, 0.3)
	-- جلد ممدود بأطراف غير منتظمة
	Pixels.ellipse(canvas, 8, 8, 5.4, 4.4, r, g, b, 255)
	Pixels.fill(canvas, 1, 4, 3, 2, r, g, b, 255)
	Pixels.fill(canvas, 12, 4, 3, 2, r, g, b, 255)
	Pixels.fill(canvas, 1, 11, 3, 2, r, g, b, 255)
	Pixels.fill(canvas, 12, 11, 3, 2, r, g, b, 255)
	Pixels.ellipse(canvas, 6.5, 6.5, 1.8, 1.4, rgb(mix(base, WHITE, 0.3)))
	Pixels.line(canvas, 4, 11, 12, 10, rgb(dark))
end

shapes.generic = function(canvas, size, item)
	local color = item.color
	Pixels.ellipse(canvas, 8, 8, 5, 5, rgb(color))
	Pixels.ellipse(canvas, 6.4, 6.4, 1.8, 1.8, rgb(mix(color, WHITE, 0.45)))
	Pixels.ellipse(canvas, 9.5, 10, 2, 1.6, rgb(mix(color, BLACK, 0.3)))
end

-- ===== اختيار الشكل =====

local EXPLICIT: { [string]: string } = {
	coin = "coin", gel = "blob", string = "fiber", leather = "hide", bone = "bone",
	herb = "leaf", glow_dust = "dust", magic_essence = "dust", shadow_scale = "shard",
	soul_fragment = "shard", upgrade_core = "core", coal = "ore_chunk", wood = "logs",
	diamond = "gem", magic_mirror = "mirror", eye_totem = "totem", recall_stone = "stone_rune",
	life_crystal = "gem", mana_crystal = "gem",
}

function ArtItems.shapeOf(itemId: string): string
	local explicit = EXPLICIT[itemId]
	if explicit then return explicit end

	local item = Items.get(itemId)
	if not item then return "generic" end

	if item.cat == "armor" then
		return "armor_" .. (item.slot or "chest")
	end
	if item.cat == "ammo" then return "arrow" end
	if item.cat == "tool" then
		if item.tool == "pickaxe" then return "pickaxe" end
		if item.tool == "axe" then return "axe" end
		if item.tool == "hammer" then return "hammer" end
		return "pickaxe"
	end
	if item.cat == "weapon" then
		if item.ranged then return "bow" end
		if item.magic then return "staff" end
		return "sword"
	end
	if item.cat == "consumable" then
		if item.food and not item.heal and not item.buff then return "food" end
		if item.id == "apple" or item.id == "bread" or item.id == "cooked_meat" or item.id == "mushroom" then
			return "food"
		end
		return "potion"
	end
	if item.cat == "material" then
		if string.find(itemId, "_bar", 1, true) then return "bar" end
		if string.find(itemId, "_ore", 1, true) then return "ore_chunk" end
		return "generic"
	end
	return "generic"
end

-- يرسم أيقونة عنصر (16×16). عناصر البلاطات تستعمل نقش البلاطة نفسه.
function ArtItems.paint(itemId: string, size: number): Pixels.Canvas
	local item = Items.get(itemId)
	if not item then
		local canvas = Pixels.new(size, size)
		Pixels.rectOutline(canvas, 2, 2, size - 4, size - 4, 220, 60, 60, 255)
		return canvas
	end

	if item.place then
		return ArtBlocks.paint(item.place, size)
	end

	local canvas = Pixels.new(size, size)
	local shape = shapes[ArtItems.shapeOf(itemId)] or shapes.generic
	shape(canvas, size, item)
	return canvas
end

ArtItems.shapes = shapes

return ArtItems
