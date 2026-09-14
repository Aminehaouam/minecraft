--!strict
--[[
	Chunk — تخزين مضغوط لبيانات القطعة داخل buffer.
	كل بلاطة 4 بايت: u16 للطبقة الأمامية + u16 للجدار الخلفي.
	هذا يقلّل الذاكرة ~10 أضعاف مقارنة بجداول Lua ويجعل النسخ عبر الشبكة رخيصاً.
]]

local Config = require(script.Parent.Config)

local Chunk = {}

local SIZE = Config.CHUNK
local AREA = SIZE * SIZE
Chunk.SIZE = SIZE
Chunk.AREA = AREA
Chunk.BYTES = AREA * 4

export type Data = buffer

function Chunk.create(): Data
	return buffer.create(Chunk.BYTES)
end

-- فهرس محلي 0..AREA-1 من إحداثيات محلية
function Chunk.index(lx: number, ly: number): number
	return ly * SIZE + lx
end

function Chunk.localOf(x: number, y: number): (number, number)
	return x % SIZE, y % SIZE
end

function Chunk.keyOf(cx: number, cy: number): string
	return cx .. ":" .. cy
end

function Chunk.parseKey(key: string): (number, number)
	local a, b = string.match(key, "^(-?%d+):(-?%d+)$")
	return tonumber(a) or 0, tonumber(b) or 0
end

function Chunk.getFg(data: Data, index: number): number
	return buffer.readu16(data, index * 4)
end

function Chunk.getBg(data: Data, index: number): number
	return buffer.readu16(data, index * 4 + 2)
end

function Chunk.setFg(data: Data, index: number, id: number)
	buffer.writeu16(data, index * 4, id)
end

function Chunk.setBg(data: Data, index: number, id: number)
	buffer.writeu16(data, index * 4 + 2, id)
end

function Chunk.fill(data: Data, fg: number, bg: number)
	for i = 0, AREA - 1 do
		buffer.writeu16(data, i * 4, fg)
		buffer.writeu16(data, i * 4 + 2, bg)
	end
end

function Chunk.clone(data: Data): Data
	local out = buffer.create(Chunk.BYTES)
	buffer.copy(out, 0, data, 0, Chunk.BYTES)
	return out
end

return Chunk
