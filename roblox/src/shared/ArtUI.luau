--!strict
--[[
	ArtUI — إطارات الواجهة بأسلوب بكسل (9-slice).

	نرسم إطاراً صغيراً بحواف مشطوفة ثم نمدّده بـ ScaleType.Slice، فيبقى
	السُّمك ثابتاً والزوايا حادة مهما كبر العنصر — هذا سرّ مظهر واجهات
	الألعاب البكسلية.
]]

local Pixels = require(script.Parent.Pixels)

local ArtUI = {}

ArtUI.PANEL = 24 -- إطار 24×24، مركز الشريحة 8..16
ArtUI.SLICE = 8

local function bevel(canvas: Pixels.Canvas, size: number, fill: { number }, light: { number }, dark: { number }, edge: { number })
	-- الحشوة
	Pixels.fill(canvas, 0, 0, size, size, fill[1], fill[2], fill[3], fill[4] or 255)
	-- حدّ خارجي داكن
	Pixels.rectOutline(canvas, 0, 0, size, size, edge[1], edge[2], edge[3], 255)
	-- شطف داخلي: فاتح أعلى/يسار، داكن أسفل/يمين
	Pixels.fill(canvas, 1, 1, size - 2, 2, light[1], light[2], light[3], 255)
	Pixels.fill(canvas, 1, 1, 2, size - 2, light[1], light[2], light[3], 255)
	Pixels.fill(canvas, 1, size - 3, size - 2, 2, dark[1], dark[2], dark[3], 255)
	Pixels.fill(canvas, size - 3, 1, 2, size - 2, dark[1], dark[2], dark[3], 255)
	-- ظلّ داخلي ممزوج: يعمّق الحافة بلا أن يمحو الشطف تحته
	Pixels.blendRectOutline(canvas, 1, 1, size - 2, size - 2, edge[1], edge[2], edge[3], 70)
end

-- لوحة رئيسية (نوافذ المخزون والمحطات)
function ArtUI.panel(): Pixels.Canvas
	local size = ArtUI.PANEL
	local canvas = Pixels.new(size, size)
	bevel(canvas, size,
		{ 34, 32, 44, 245 },
		{ 66, 62, 84 },
		{ 18, 16, 24 },
		{ 10, 9, 14 })
	return canvas
end

-- خانة مخزون (غائرة)
function ArtUI.slot(): Pixels.Canvas
	local size = ArtUI.PANEL
	local canvas = Pixels.new(size, size)
	bevel(canvas, size,
		{ 52, 50, 66, 255 },
		{ 24, 22, 32 },
		{ 82, 78, 102 },
		{ 12, 11, 16 })
	return canvas
end

-- خانة مختارة (متوهجة)
function ArtUI.slotActive(): Pixels.Canvas
	local size = ArtUI.PANEL
	local canvas = Pixels.new(size, size)
	bevel(canvas, size,
		{ 78, 96, 148, 255 },
		{ 150, 180, 240 },
		{ 40, 52, 90 },
		{ 14, 18, 30 })
	return canvas
end

-- زر بارز
function ArtUI.button(): Pixels.Canvas
	local size = ArtUI.PANEL
	local canvas = Pixels.new(size, size)
	bevel(canvas, size,
		{ 62, 60, 78, 255 },
		{ 104, 100, 128 },
		{ 26, 24, 34 },
		{ 12, 11, 16 })
	return canvas
end

-- إطار شريط (حياة/مانا/تقدّم)
function ArtUI.barFrame(): Pixels.Canvas
	local size = ArtUI.PANEL
	local canvas = Pixels.new(size, size)
	Pixels.fill(canvas, 0, 0, size, size, 18, 16, 24, 255)
	Pixels.rectOutline(canvas, 0, 0, size, size, 8, 7, 12, 255)
	Pixels.fill(canvas, 1, 1, size - 2, 1, 48, 44, 60, 255)
	Pixels.fill(canvas, 1, size - 2, size - 2, 1, 8, 7, 12, 255)
	return canvas
end

-- تعبئة شريط (تدرّج أفقي خفيف يُلوَّن بـ ImageColor3)
function ArtUI.barFill(): Pixels.Canvas
	local size = ArtUI.PANEL
	local canvas = Pixels.new(size, size)
	Pixels.fill(canvas, 0, 0, size, size, 255, 255, 255, 255)
	Pixels.fill(canvas, 0, 0, size, 2, 255, 255, 255, 255)
	Pixels.fill(canvas, 0, 2, size, 3, 216, 216, 216, 255)
	Pixels.fill(canvas, 0, size - 3, size, 3, 176, 176, 176, 255)
	return canvas
end

-- مراحل تشقّق البلاطة أثناء التعدين (شفافة، تُرسم فوق البلاطة)
function ArtUI.crack(stage: number): Pixels.Canvas
	local size = 16
	local canvas = Pixels.new(size, size)
	local density = stage / 4

	-- شقّان رئيسيان يمتدّان مع التقدّم
	local mainLength = math.floor(3 + density * 12)
	Pixels.line(canvas, 8, 2, 8 - math.floor(density * 4), 2 + mainLength, 20, 18, 24, 235)
	Pixels.line(canvas, 7, 3, 7 + math.floor(density * 5), 3 + mainLength, 20, 18, 24, 200)

	-- تفرّعات تظهر تدريجياً
	local branches = stage * 2
	for i = 1, branches do
		local t = i / (branches + 1)
		local y = math.floor(3 + t * mainLength)
		local dir = if i % 2 == 0 then 1 else -1
		local length = 2 + math.floor(density * 4)
		Pixels.line(canvas, 8, y, 8 + dir * length, y + dir, 20, 18, 24, 215)
	end

	-- شظايا متناثرة في المراحل الأخيرة
	if stage >= 3 then
		for i = 0, 5 do
			local x = math.floor(Pixels.noise(i, stage, 31) * size)
			local y = math.floor(Pixels.noise(i, stage + 7, 31) * size)
			Pixels.set(canvas, x, y, 20, 18, 24, 190)
		end
	end
	return canvas
end

ArtUI.pieces = {
	panel = ArtUI.panel,
	slot = ArtUI.slot,
	slot_active = ArtUI.slotActive,
	button = ArtUI.button,
	bar_frame = ArtUI.barFrame,
	bar_fill = ArtUI.barFill,
	crack1 = function() return ArtUI.crack(1) end,
	crack2 = function() return ArtUI.crack(2) end,
	crack3 = function() return ArtUI.crack(3) end,
	crack4 = function() return ArtUI.crack(4) end,
}

return ArtUI
