--!strict
--[[
	Noise — ضوضاء قيمية حتمية (value noise) مبنية على تجزئة صحيحة.
	لا نستعمل math.noise لأن نتائجه غير مضمونة الثبات بين الإصدارات،
	ونحتاج تطابقاً تاماً بين توليد الخادم وتوليد العميل.
]]

local Util = require(script.Parent.Util)

local Noise = {}

local function fade(t: number): number
	return t * t * (3 - 2 * t) -- smoothstep
end

-- ضوضاء أحادية البعد في [0,1)
function Noise.value1(x: number, seed: number): number
	local x0 = math.floor(x)
	local t = fade(x - x0)
	local a = Util.rand1(x0, seed)
	local b = Util.rand1(x0 + 1, seed)
	return a + (b - a) * t
end

-- ضوضاء ثنائية البعد في [0,1)
function Noise.value2(x: number, y: number, seed: number): number
	local x0, y0 = math.floor(x), math.floor(y)
	local tx, ty = fade(x - x0), fade(y - y0)
	local a = Util.rand2(x0, y0, seed)
	local b = Util.rand2(x0 + 1, y0, seed)
	local c = Util.rand2(x0, y0 + 1, seed)
	local d = Util.rand2(x0 + 1, y0 + 1, seed)
	local top = a + (b - a) * tx
	local bottom = c + (d - c) * tx
	return top + (bottom - top) * ty
end

-- تراكب عدة طبقات (fBm) — النتيجة في [0,1)
function Noise.fbm1(x: number, seed: number, octaves: number, freq: number, persistence: number): number
	local total, amp, max = 0, 1, 0
	for i = 0, octaves - 1 do
		total += Noise.value1(x * freq, seed + i * 7919) * amp
		max += amp
		amp *= persistence
		freq *= 2
	end
	return total / max
end

function Noise.fbm2(x: number, y: number, seed: number, octaves: number, freq: number, persistence: number): number
	local total, amp, max = 0, 1, 0
	for i = 0, octaves - 1 do
		total += Noise.value2(x * freq, y * freq, seed + i * 7919) * amp
		max += amp
		amp *= persistence
		freq *= 2
	end
	return total / max
end

-- ضوضاء "حِيَد" مناسبة لأنفاق الكهوف: قمم حادة حول 0
function Noise.ridged2(x: number, y: number, seed: number, octaves: number, freq: number): number
	local total, amp, max = 0, 1, 0
	for i = 0, octaves - 1 do
		local n = math.abs(Noise.value2(x * freq, y * freq, seed + i * 104729) * 2 - 1)
		total += (1 - n) * amp
		max += amp
		amp *= 0.5
		freq *= 2
	end
	return total / max
end

-- ضوضاء خلوية مبسّطة (worley) لعروق المعادن والبقع
function Noise.cell2(x: number, y: number, seed: number, scale: number): number
	local cx, cy = math.floor(x / scale), math.floor(y / scale)
	local best = math.huge
	for oy = -1, 1 do
		for ox = -1, 1 do
			local gx, gy = cx + ox, cy + oy
			local jx, jy = Util.rand2pair(gx, gy, seed)
			local px = (gx + jx) * scale
			local py = (gy + jy) * scale
			local d = Util.dist2(x, y, px, py)
			if d < best then best = d end
		end
	end
	return math.sqrt(best) / scale
end

return Noise
