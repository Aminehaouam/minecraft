--!strict
--[[
	Pixels — لوحة رسم نقطية فوق buffer بصيغة RGBA8.

	هذه أساس كل فنّ اللعبة: نرسم كل نقش وكل كائن بكسلاً بكسلاً في الذاكرة،
	ثم نرفعه مرة واحدة إلى EditableImage. لا نحتاج رفع أي صورة إلى روبلوكس،
	والنتيجة بكسل آرت حقيقي حادّ الحواف (ResamplerMode.Pixelated).

	الوحدة نقية تماماً (بلا أي واجهة روبلوكس) لتبقى قابلة للاختبار خارج المحرّك.
]]

local Util = require(script.Parent.Util)

local Pixels = {}

export type Canvas = {
	w: number,
	h: number,
	data: buffer,
}

function Pixels.new(w: number, h: number): Canvas
	return { w = w, h = h, data = buffer.create(w * h * 4) }
end

local function index(canvas: Canvas, x: number, y: number): number
	return (y * canvas.w + x) * 4
end

-- كتابة بكسل (بلا مزج) — الإحداثيات خارج الحدود تُتجاهل بصمت
function Pixels.set(canvas: Canvas, x: number, y: number, r: number, g: number, b: number, a: number?)
	if x < 0 or y < 0 or x >= canvas.w or y >= canvas.h then return end
	local i = index(canvas, x, y)
	buffer.writeu8(canvas.data, i, math.clamp(math.floor(r), 0, 255))
	buffer.writeu8(canvas.data, i + 1, math.clamp(math.floor(g), 0, 255))
	buffer.writeu8(canvas.data, i + 2, math.clamp(math.floor(b), 0, 255))
	buffer.writeu8(canvas.data, i + 3, math.clamp(math.floor(a or 255), 0, 255))
end

function Pixels.get(canvas: Canvas, x: number, y: number): (number, number, number, number)
	if x < 0 or y < 0 or x >= canvas.w or y >= canvas.h then return 0, 0, 0, 0 end
	local i = index(canvas, x, y)
	return buffer.readu8(canvas.data, i),
		buffer.readu8(canvas.data, i + 1),
		buffer.readu8(canvas.data, i + 2),
		buffer.readu8(canvas.data, i + 3)
end

-- مزج ألفا: يرسم لوناً شبه شفاف فوق الموجود
function Pixels.blend(canvas: Canvas, x: number, y: number, r: number, g: number, b: number, a: number)
	if a >= 255 then
		Pixels.set(canvas, x, y, r, g, b, 255)
		return
	end
	if a <= 0 then return end
	local dr, dg, db, da = Pixels.get(canvas, x, y)
	local alpha = a / 255
	local outA = alpha + (da / 255) * (1 - alpha)
	if outA <= 0 then return end
	Pixels.set(canvas, x, y,
		(r * alpha + dr * (da / 255) * (1 - alpha)) / outA,
		(g * alpha + dg * (da / 255) * (1 - alpha)) / outA,
		(b * alpha + db * (da / 255) * (1 - alpha)) / outA,
		outA * 255)
end

function Pixels.fill(canvas: Canvas, x: number, y: number, w: number, h: number, r: number, g: number, b: number, a: number?)
	for py = y, y + h - 1 do
		for px = x, x + w - 1 do
			Pixels.set(canvas, px, py, r, g, b, a)
		end
	end
end

function Pixels.clear(canvas: Canvas)
	buffer.fill(canvas.data, 0, 0, canvas.w * canvas.h * 4)
end

-- تحويل Color3 (0..1) إلى ثلاثية 0..255
function Pixels.rgb(color: Color3): (number, number, number)
	return color.R * 255, color.G * 255, color.B * 255
end

-- تفتيح/تعتيم نسبي لبكسل واحد
function Pixels.shadePixel(canvas: Canvas, x: number, y: number, amount: number)
	local r, g, b, a = Pixels.get(canvas, x, y)
	if a == 0 then return end
	Pixels.set(canvas, x, y, r * amount, g * amount, b * amount, a)
end

function Pixels.shadeRect(canvas: Canvas, x: number, y: number, w: number, h: number, amount: number)
	for py = y, y + h - 1 do
		for px = x, x + w - 1 do
			Pixels.shadePixel(canvas, px, py, amount)
		end
	end
end

-- نسخ لوحة داخل أخرى مع احترام الشفافية
function Pixels.blit(dst: Canvas, src: Canvas, dx: number, dy: number)
	for y = 0, src.h - 1 do
		for x = 0, src.w - 1 do
			local r, g, b, a = Pixels.get(src, x, y)
			if a > 0 then
				Pixels.set(dst, dx + x, dy + y, r, g, b, a)
			end
		end
	end
end

-- نسخ مقلوب أفقياً (لاتجاه الكائنات: نخبز الاتجاهين بدل قلبها وقت التشغيل)
function Pixels.blitMirrored(dst: Canvas, src: Canvas, dx: number, dy: number)
	for y = 0, src.h - 1 do
		for x = 0, src.w - 1 do
			local r, g, b, a = Pixels.get(src, x, y)
			if a > 0 then
				Pixels.set(dst, dx + (src.w - 1 - x), dy + y, r, g, b, a)
			end
		end
	end
end

-- نسخ سريع بلا مزج (صفّاً صفّاً عبر buffer.copy) — يُستعمل لرصف الأطلس،
-- حيث لا تتداخل الخلايا فلا حاجة لحساب الشفافية لكل بكسل.
function Pixels.blitFast(dst: Canvas, src: Canvas, dx: number, dy: number)
	local rowBytes = src.w * 4
	for y = 0, src.h - 1 do
		local targetY = dy + y
		if targetY >= 0 and targetY < dst.h and dx >= 0 and dx + src.w <= dst.w then
			buffer.copy(dst.data, (targetY * dst.w + dx) * 4, src.data, y * rowBytes, rowBytes)
		end
	end
end

function Pixels.clone(src: Canvas): Canvas
	local out = Pixels.new(src.w, src.h)
	buffer.copy(out.data, 0, src.data, 0, src.w * src.h * 4)
	return out
end

-- ===== أشكال =====

function Pixels.rect(canvas: Canvas, x: number, y: number, w: number, h: number, r: number, g: number, b: number, a: number?)
	Pixels.fill(canvas, x, y, w, h, r, g, b, a)
end

function Pixels.rectOutline(canvas: Canvas, x: number, y: number, w: number, h: number, r: number, g: number, b: number, a: number?)
	for px = x, x + w - 1 do
		Pixels.set(canvas, px, y, r, g, b, a)
		Pixels.set(canvas, px, y + h - 1, r, g, b, a)
	end
	for py = y, y + h - 1 do
		Pixels.set(canvas, x, py, r, g, b, a)
		Pixels.set(canvas, x + w - 1, py, r, g, b, a)
	end
end

-- حدّ خارجي ممزوج (لا يمسح ما تحته) — مهم لشطف إطارات الواجهة
function Pixels.blendRectOutline(canvas: Canvas, x: number, y: number, w: number, h: number, r: number, g: number, b: number, a: number)
	for px = x, x + w - 1 do
		Pixels.blend(canvas, px, y, r, g, b, a)
		Pixels.blend(canvas, px, y + h - 1, r, g, b, a)
	end
	for py = y + 1, y + h - 2 do
		Pixels.blend(canvas, x, py, r, g, b, a)
		Pixels.blend(canvas, x + w - 1, py, r, g, b, a)
	end
end

function Pixels.line(canvas: Canvas, x0: number, y0: number, x1: number, y1: number, r: number, g: number, b: number, a: number?)
	local dx = math.abs(x1 - x0)
	local dy = -math.abs(y1 - y0)
	local sx = if x0 < x1 then 1 else -1
	local sy = if y0 < y1 then 1 else -1
	local err = dx + dy
	local guard = 0
	while guard < 512 do
		guard += 1
		Pixels.set(canvas, x0, y0, r, g, b, a)
		if x0 == x1 and y0 == y1 then break end
		local e2 = 2 * err
		if e2 >= dy then err += dy; x0 += sx end
		if e2 <= dx then err += dx; y0 += sy end
	end
end

function Pixels.disc(canvas: Canvas, cx: number, cy: number, radius: number, r: number, g: number, b: number, a: number?)
	local rr = radius * radius
	for y = math.floor(cy - radius), math.ceil(cy + radius) do
		for x = math.floor(cx - radius), math.ceil(cx + radius) do
			local dx, dy = x - cx, y - cy
			if dx * dx + dy * dy <= rr then
				Pixels.set(canvas, x, y, r, g, b, a)
			end
		end
	end
end

-- بيضاوي مملوء (مفيد لأجسام الكائنات)
function Pixels.ellipse(canvas: Canvas, cx: number, cy: number, rx: number, ry: number, r: number, g: number, b: number, a: number?)
	for y = math.floor(cy - ry), math.ceil(cy + ry) do
		for x = math.floor(cx - rx), math.ceil(cx + rx) do
			local dx = (x - cx) / math.max(0.001, rx)
			local dy = (y - cy) / math.max(0.001, ry)
			if dx * dx + dy * dy <= 1 then
				Pixels.set(canvas, x, y, r, g, b, a)
			end
		end
	end
end

-- ===== ضوضاء حتمية للنقوش =====

-- قيمة ضوضاء ثابتة لكل (x, y) — نفس النقش في كل جلسة وعلى كل جهاز
function Pixels.noise(x: number, y: number, seed: number): number
	return Util.rand2(x, y, seed)
end

-- يرشّ بكسلات أفتح/أغمق فوق منطقة لإعطاء ملمس حبيبي
function Pixels.speckle(canvas: Canvas, x: number, y: number, w: number, h: number, seed: number, strength: number, density: number)
	for py = y, y + h - 1 do
		for px = x, x + w - 1 do
			local n = Pixels.noise(px, py, seed)
			if n < density then
				local amount = 1 - strength * (1 - n / density)
				Pixels.shadePixel(canvas, px, py, amount)
			elseif n > 1 - density then
				local amount = 1 + strength * ((n - (1 - density)) / density)
				Pixels.shadePixel(canvas, px, py, amount)
			end
		end
	end
end

-- ===== إضاءة الحواف (auto-tiling) =====
-- قناع البتّات: 1=أعلى مكشوف، 2=يمين، 4=أسفل، 8=يسار
Pixels.EDGE_UP = 1
Pixels.EDGE_RIGHT = 2
Pixels.EDGE_DOWN = 4
Pixels.EDGE_LEFT = 8

--[[
	يطبّق إضاءة الحواف على نسخة من البلاطة:
	الحافة العلوية المكشوفة تُضاء (ضوء من فوق)، السفلية تُعتم، والجانبية تُظلَّل
	قليلاً — وهذا بالضبط ما يعطي الإحساس المجسّم في تيراريا وماين كرافت.
]]
function Pixels.applyEdges(canvas: Canvas, mask: number, size: number)
	local light = 1.30
	local dark = 0.62
	local side = 0.82

	if bit32.band(mask, Pixels.EDGE_UP) ~= 0 then
		Pixels.shadeRect(canvas, 0, 0, size, 1, light + 0.12)
		Pixels.shadeRect(canvas, 0, 1, size, 1, light)
		Pixels.shadeRect(canvas, 0, 2, size, 1, 1 + (light - 1) * 0.45)
	end
	if bit32.band(mask, Pixels.EDGE_DOWN) ~= 0 then
		Pixels.shadeRect(canvas, 0, size - 1, size, 1, dark - 0.1)
		Pixels.shadeRect(canvas, 0, size - 2, size, 1, dark)
		Pixels.shadeRect(canvas, 0, size - 3, size, 1, 1 - (1 - dark) * 0.45)
	end
	if bit32.band(mask, Pixels.EDGE_LEFT) ~= 0 then
		Pixels.shadeRect(canvas, 0, 0, 1, size, side - 0.08)
		Pixels.shadeRect(canvas, 1, 0, 1, size, side + 0.08)
	end
	if bit32.band(mask, Pixels.EDGE_RIGHT) ~= 0 then
		Pixels.shadeRect(canvas, size - 1, 0, 1, size, side - 0.12)
		Pixels.shadeRect(canvas, size - 2, 0, 1, size, side + 0.06)
	end
end

return Pixels
