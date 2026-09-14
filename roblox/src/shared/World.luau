--!strict
--[[
	World — حاوية العالم المشتركة بين الخادم والعميل.

	القطعة = (توليد حتمي من البذرة) + (تعديلات اللاعبين).
	الخادم يحفظ التعديلات ويبثّها؛ العميل يولّد نفس القطعة محلياً ثم يطبّق التعديلات.
]]

local Blocks = require(script.Parent.Blocks)
local Chunk = require(script.Parent.Chunk)
local Config = require(script.Parent.Config)
local WorldGen = require(script.Parent.WorldGen)

local SIZE = Config.CHUNK
local B = Blocks.ID

local World = {}
World.__index = World

--[[
	مستوى السائل يُخزَّن في البتّات العليا من نفس الحقل u16:
	    القيمة = معرّف البلاطة | (المستوى << 12)
	معرّفات البلاطات أقل من 4096 بكثير، فالبتّات 12..15 فارغة.
	الفائدة: ماء بمستويات حقيقية بلا توسيع صيغة التخزين ولا صيغة الحفظ.
]]
World.BLOCK_MASK = 0xFFF
World.LIQUID_SHIFT = 12
World.LIQUID_FULL = 8

export type Diff = { [number]: number } -- index -> fg + bg*65536
export type World = typeof(setmetatable({} :: {
	seed: number,
	chunks: { [string]: buffer },
	diffs: { [string]: Diff },
	dirty: { [string]: boolean },
	loadOrder: { string },
	maxChunks: number,
	surfaceCache: { [number]: number },
	memoCx: number,
	memoCy: number,
	memoChunk: buffer?,
	onChange: ((x: number, y: number, fg: number, bg: number) -> ())?,
}, World))

function World.new(seed: number, maxChunks: number?): World
	return setmetatable({
		seed = seed,
		chunks = {},
		diffs = {},
		dirty = {},
		loadOrder = {},
		maxChunks = maxChunks or 400,
		surfaceCache = {},
		memoCx = -1,
		memoCy = -1,
		memoChunk = nil,
		onChange = nil,
	}, World)
end

function World.pack(fg: number, bg: number): number
	return fg + bg * 65536
end

function World.unpack(v: number): (number, number)
	return v % 65536, v // 65536
end

function World.inBounds(x: number, y: number): boolean
	return x >= 0 and x < Config.WORLD_W and y >= 0 and y < Config.WORLD_H
end

function World.chunkOf(x: number, y: number): (number, number)
	return x // SIZE, y // SIZE
end

-- ===== إدارة القطع =====

function World.getChunk(self: World, cx: number, cy: number, create: boolean?): buffer?
	if cx < 0 or cy < 0 or cx >= Config.CHUNKS_X or cy >= Config.CHUNKS_Y then
		return nil
	end
	-- ذاكرة صغيرة لآخر قطعة: الرسم يمرّ صفاً صفاً فتتكرر القطعة 32 مرة،
	-- وهذا يوفّر بناء مفتاح نصي لكل بلاطة (فرق أداء كبير في حلقة الرسم).
	if cx == self.memoCx and cy == self.memoCy and self.memoChunk then
		return self.memoChunk
	end

	local key = Chunk.keyOf(cx, cy)
	local data = self.chunks[key]
	if data then
		self.memoCx, self.memoCy, self.memoChunk = cx, cy, data
		return data
	end
	if create == false then return nil end

	data = WorldGen.generateChunk(self.seed, cx, cy)
	-- تطبيق تعديلات اللاعبين فوق التوليد
	local diff = self.diffs[key]
	if diff then
		for index, packed in diff do
			local fg, bg = World.unpack(packed)
			Chunk.setFg(data, index, fg)
			Chunk.setBg(data, index, bg)
		end
	end

	self.chunks[key] = data
	self.memoCx, self.memoCy, self.memoChunk = cx, cy, data
	table.insert(self.loadOrder, key)
	if #self.loadOrder > self.maxChunks then
		local oldest = table.remove(self.loadOrder, 1)
		if oldest and oldest ~= key then
			self.chunks[oldest] = nil -- آمن: التعديلات محفوظة منفصلة
			local ocx, ocy = Chunk.parseKey(oldest)
			if self.memoCx == ocx and self.memoCy == ocy then
				self.memoChunk = nil
				self.memoCx, self.memoCy = -1, -1
			end
		end
	end
	return data
end

function World.isLoaded(self: World, cx: number, cy: number): boolean
	return self.chunks[Chunk.keyOf(cx, cy)] ~= nil
end

function World.unload(self: World, cx: number, cy: number)
	local key = Chunk.keyOf(cx, cy)
	self.chunks[key] = nil
	if self.memoCx == cx and self.memoCy == cy then
		self.memoChunk = nil
		self.memoCx, self.memoCy = -1, -1
	end
	local i = table.find(self.loadOrder, key)
	if i then table.remove(self.loadOrder, i) end
end

-- ===== قراءة/كتابة البلاطات =====

-- قراءة بلا إجبار على التوليد: تُعيد nil إن لم تكن القطعة محمّلة.
-- يستعملها الرسم والإضاءة حتى لا يحدث توليد مفاجئ داخل حلقة الإطار.
function World.fgRaw(self: World, x: number, y: number): number?
	if not World.inBounds(x, y) then return B.BEDROCK end
	local data = World.getChunk(self, x // SIZE, y // SIZE, false)
	if not data then return nil end
	return bit32.band(Chunk.getFg(data, Chunk.index(x % SIZE, y % SIZE)), World.BLOCK_MASK)
end

-- مستوى السائل بلا إجبار على التوليد (للرسم)
function World.liquidLevelRaw(self: World, x: number, y: number): number
	if not World.inBounds(x, y) then return 0 end
	local data = World.getChunk(self, x // SIZE, y // SIZE, false)
	if not data then return 0 end
	local packed = Chunk.getFg(data, Chunk.index(x % SIZE, y % SIZE))
	local id = bit32.band(packed, World.BLOCK_MASK)
	if not Blocks.isLiquid(id) then return 0 end
	local level = bit32.rshift(packed, World.LIQUID_SHIFT)
	return if level == 0 then World.LIQUID_FULL else math.min(level, World.LIQUID_FULL)
end

function World.bgRaw(self: World, x: number, y: number): number?
	if not World.inBounds(x, y) then return B.AIR end
	local data = World.getChunk(self, x // SIZE, y // SIZE, false)
	if not data then return nil end
	return Chunk.getBg(data, Chunk.index(x % SIZE, y % SIZE))
end

function World.fg(self: World, x: number, y: number): number
	if not World.inBounds(x, y) then return B.BEDROCK end
	local data = World.getChunk(self, x // SIZE, y // SIZE)
	if not data then return B.BEDROCK end
	return bit32.band(Chunk.getFg(data, Chunk.index(x % SIZE, y % SIZE)), World.BLOCK_MASK)
end

-- القيمة الخام بما فيها مستوى السائل
function World.fgPacked(self: World, x: number, y: number): number
	if not World.inBounds(x, y) then return B.BEDROCK end
	local data = World.getChunk(self, x // SIZE, y // SIZE)
	if not data then return B.BEDROCK end
	return Chunk.getFg(data, Chunk.index(x % SIZE, y % SIZE))
end

-- مستوى السائل 0..8 (8 = بلاطة ممتلئة). غير السوائل تُعيد 0.
function World.liquidLevel(self: World, x: number, y: number): number
	local packed = World.fgPacked(self, x, y)
	local id = bit32.band(packed, World.BLOCK_MASK)
	if not Blocks.isLiquid(id) then return 0 end
	local level = bit32.rshift(packed, World.LIQUID_SHIFT)
	-- المستوى 0 يعني «مولَّد من التضاريس» أي ممتلئ
	return if level == 0 then World.LIQUID_FULL else math.min(level, World.LIQUID_FULL)
end

-- كتابة سائل بمستوى محدّد؛ المستوى 0 يزيل السائل
function World.setLiquid(self: World, x: number, y: number, id: number, level: number)
	local bg = World.bg(self, x, y)
	if level <= 0 then
		World.set(self, x, y, B.AIR, bg)
		return
	end
	local clamped = math.min(math.floor(level), World.LIQUID_FULL)
	World.set(self, x, y, id + bit32.lshift(clamped, World.LIQUID_SHIFT), bg)
end

function World.bg(self: World, x: number, y: number): number
	if not World.inBounds(x, y) then return B.AIR end
	local data = World.getChunk(self, x // SIZE, y // SIZE)
	if not data then return B.AIR end
	return Chunk.getBg(data, Chunk.index(x % SIZE, y % SIZE))
end

-- كتابة بلاطة وتسجيلها كتعديل
function World.set(self: World, x: number, y: number, fg: number, bg: number)
	if not World.inBounds(x, y) then return end
	local cx, cy = x // SIZE, y // SIZE
	local data = World.getChunk(self, cx, cy)
	if not data then return end
	local index = Chunk.index(x % SIZE, y % SIZE)

	Chunk.setFg(data, index, fg)
	Chunk.setBg(data, index, bg)

	local key = Chunk.keyOf(cx, cy)
	local diff = self.diffs[key]
	if not diff then
		diff = {}
		self.diffs[key] = diff
	end
	diff[index] = World.pack(fg, bg)
	self.dirty[key] = true
	self.surfaceCache[x] = nil

	if self.onChange then
		self.onChange(x, y, fg, bg)
	end
end

function World.setFg(self: World, x: number, y: number, id: number)
	World.set(self, x, y, id, World.bg(self, x, y))
end

-- الكتلة الإجمالية للسائل في بلاطة (تُستعمل في اختبارات الحفاظ على الكتلة)
function World.liquidMass(self: World, x0: number, y0: number, x1: number, y1: number): number
	local total = 0
	for y = y0, y1 do
		for x = x0, x1 do
			total += World.liquidLevel(self, x, y)
		end
	end
	return total
end

function World.setBg(self: World, x: number, y: number, id: number)
	World.set(self, x, y, World.fg(self, x, y), id)
end

-- ===== استعلامات مساعدة =====

function World.solid(self: World, x: number, y: number): boolean
	return Blocks.isSolid(World.fg(self, x, y))
end

function World.platform(self: World, x: number, y: number): boolean
	return Blocks.isPlatform(World.fg(self, x, y))
end

function World.liquid(self: World, x: number, y: number): number
	local id = World.fg(self, x, y)
	return if Blocks.isLiquid(id) then id else 0
end

-- أول بلاطة صلبة من الأعلى في هذا العمود (لحساب ضوء الشمس).
-- تعتمد قراءات بلا توليد: إن لم تكن القطعة محمّلة بعد نُرجع ارتفاع التضاريس
-- المولّد رياضياً، وهو تقدير صحيح تماماً للعالم البكر.
function World.surfaceY(self: World, x: number): number
	local cached = self.surfaceCache[x]
	if cached then return cached end
	if x < 0 or x >= Config.WORLD_W then return 0 end

	local base = WorldGen.surfaceHeight(self.seed, x)
	local y = math.max(Config.SKY_TOP, base - 48)

	-- انزل حتى أول بلاطة معتمة.
	-- القطع غير المحمّلة تساوي حتماً ناتج التوليد، فنقفز فوقها ونثق بارتفاع
	-- التضاريس المحسوب رياضياً إن وقع داخلها.
	while y < Config.WORLD_H do
		local id = World.fgRaw(self, x, y)
		if id == nil then
			local chunkEnd = (y // SIZE + 1) * SIZE
			if base >= y and base < chunkEnd then
				self.surfaceCache[x] = base
				return base
			end
			y = chunkEnd
		elseif Blocks.opacity(id) >= 15 then
			break
		else
			y += 1
		end
	end

	-- اصعد إن كان اللاعب قد بنى فوق نقطة البداية
	while y > Config.SKY_TOP do
		local above = World.fgRaw(self, x, y - 1)
		if above == nil or Blocks.opacity(above) < 15 then break end
		y -= 1
	end

	self.surfaceCache[x] = y
	return y
end

-- ===== التعديلات (للشبكة والحفظ) =====

-- يحوّل تعديلات قطعة إلى مصفوفة مسطّحة: {index, fg, bg, index, fg, bg, ...}
function World.encodeDiff(self: World, cx: number, cy: number): { number }?
	local diff = self.diffs[Chunk.keyOf(cx, cy)]
	if not diff then return nil end
	local out = {}
	for index, packed in diff do
		local fg, bg = World.unpack(packed)
		table.insert(out, index)
		table.insert(out, fg)
		table.insert(out, bg)
	end
	return out
end

function World.applyEncodedDiff(self: World, cx: number, cy: number, flat: { number })
	local key = Chunk.keyOf(cx, cy)
	local diff = self.diffs[key]
	if not diff then
		diff = {}
		self.diffs[key] = diff
	end
	for i = 1, #flat, 3 do
		local index, fg, bg = flat[i], flat[i + 1], flat[i + 2]
		diff[index] = World.pack(fg, bg)
	end
	-- إن كانت القطعة محمّلة، أعد بناءها لتضمين التعديلات
	local data = self.chunks[key]
	if data then
		for i = 1, #flat, 3 do
			local index, fg, bg = flat[i], flat[i + 1], flat[i + 2]
			Chunk.setFg(data, index, fg)
			Chunk.setBg(data, index, bg)
		end
		local x0 = cx * SIZE
		for i = 1, #flat, 3 do
			local index = flat[i]
			self.surfaceCache[x0 + (index % SIZE)] = nil
		end
	end
end

function World.clearDirty(self: World, key: string)
	self.dirty[key] = nil
end

return World
