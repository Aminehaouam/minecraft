--!strict
--[[ Util — دوال رياضية وأدوات صغيرة مشتركة. ]]

local Util = {}

function Util.clamp(v: number, lo: number, hi: number): number
	if v < lo then return lo elseif v > hi then return hi end
	return v
end

function Util.sign(v: number): number
	return (v > 0 and 1) or (v < 0 and -1) or 0
end

function Util.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- تنعيم مستقل عن معدل الإطارات
function Util.damp(a: number, b: number, lambda: number, dt: number): number
	return Util.lerp(a, b, 1 - math.exp(-lambda * dt))
end

function Util.approach(v: number, target: number, delta: number): number
	if v < target then return math.min(v + delta, target) end
	return math.max(v - delta, target)
end

function Util.round(v: number): number
	return math.floor(v + 0.5)
end

-- تجزئة حتمية ثابتة عبر الخادم والعميل (32-bit)
function Util.hash2(x: number, y: number, seed: number): number
	local h = bit32.bxor(x * 374761393, y * 668265263, seed * 2147483647)
	h = bit32.band(h, 0xFFFFFFFF)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = bit32.band(h * 1274126177, 0xFFFFFFFF)
	return bit32.bxor(h, bit32.rshift(h, 16))
end

-- عشوائي حتمي [0,1)
function Util.rand2(x: number, y: number, seed: number): number
	return Util.hash2(x, y, seed) % 1000000 / 1000000
end

function Util.rand1(x: number, seed: number): number
	return Util.rand2(x, 0, seed)
end

-- قيمتان عشوائيتان من تجزئة واحدة (نصفا الكلمة) — يوفّر نصف الحسابات
-- في الضوضاء الخلوية التي تحتاج إحداثيين لكل خلية.
function Util.rand2pair(x: number, y: number, seed: number): (number, number)
	local h = Util.hash2(x, y, seed)
	return (h % 65536) / 65536, ((h // 65536) % 65536) / 65536
end

-- اختيار موزون: list = {{weight = n, ...}, ...}
function Util.weightedPick<T>(list: { T & { weight: number } }, rng: number): T?
	local total = 0
	for _, v in list do total += v.weight end
	if total <= 0 then return nil end
	local r = rng * total
	for _, v in list do
		r -= v.weight
		if r <= 0 then return v end
	end
	return list[#list]
end

function Util.dist(ax: number, ay: number, bx: number, by: number): number
	local dx, dy = bx - ax, by - ay
	return math.sqrt(dx * dx + dy * dy)
end

function Util.dist2(ax: number, ay: number, bx: number, by: number): number
	local dx, dy = bx - ax, by - ay
	return dx * dx + dy * dy
end

-- تحويل ثوانٍ إلى "س:د"
function Util.clock(t: number): string
	local hours = math.floor(t * 24)
	local minutes = math.floor((t * 24 % 1) * 60)
	local suffix = hours < 12 and "ص" or "م"
	local h12 = hours % 12
	if h12 == 0 then h12 = 12 end
	return string.format("%d:%02d %s", h12, minutes, suffix)
end

function Util.shuffle<T>(list: { T }, random: Random): { T }
	for i = #list, 2, -1 do
		local j = random:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

function Util.deepCopy<T>(tbl: T): T
	if type(tbl) ~= "table" then return tbl end
	local out = {}
	for k, v in tbl :: any do
		out[k] = if type(v) == "table" then Util.deepCopy(v) else v
	end
	return out :: any
end

return Util
