--!strict
--[[
	Inventory — منطق المخزون كدوال نقية (يُستعمل على الخادم كمصدر للحقيقة،
	وعلى العميل كنسخة معروضة).
]]

local Config = require(script.Parent.Config)
local Items = require(script.Parent.Items)
local Recipes = require(script.Parent.Recipes)
local Upgrades = require(script.Parent.Upgrades)

local Inventory = {}

-- `up` يحمل مستوى التطوير والصفة السحرية. الأغراض القابلة للتطوير حدّ تكديسها 1،
-- لذا لا يلتقي كومان مختلفان في الدمج أبداً — لكننا نحرس ذلك صراحة على أي حال.
export type Stack = { id: string, n: number, up: Upgrades.Upgrade? }
export type Slots = { [number]: Stack? }

function Inventory.new(): Slots
	return {}
end

function Inventory.copyStack(stack: Stack?): Stack?
	if not stack then return nil end
	local copy: Stack = { id = stack.id, n = stack.n }
	if stack.up then
		copy.up = { lvl = stack.up.lvl, aff = stack.up.aff }
	end
	return copy
end

-- إضافة عناصر؛ تُعيد الكمية المتبقية التي لم تتسع
function Inventory.add(slots: Slots, id: string, n: number, limit: number?): number
	local item = Items.get(id)
	if not item or n <= 0 then return n end
	local max = item.max
	local slotCount = limit or Config.INV_SLOTS

	-- أولاً: أكمل الأكوام الموجودة (لا ندمج في كومة مطوّرة أو مسحورة)
	for i = 1, slotCount do
		local stack = slots[i]
		if stack and stack.id == id and stack.n < max and stack.up == nil then
			local space = max - stack.n
			local take = math.min(space, n)
			stack.n += take
			n -= take
			if n <= 0 then return 0 end
		end
	end

	-- ثانياً: خانات فارغة
	for i = 1, slotCount do
		if not slots[i] then
			local take = math.min(max, n)
			slots[i] = { id = id, n = take }
			n -= take
			if n <= 0 then return 0 end
		end
	end

	return n
end

-- إضافة كومة كما هي (مع تطويرها) — تُستعمل لإعادة غرض مطوّر إلى اللاعب
function Inventory.addStack(slots: Slots, stack: Stack, limit: number?): boolean
	if not stack.up then
		return Inventory.add(slots, stack.id, stack.n, limit) == 0
	end
	local slotCount = limit or Config.INV_SLOTS
	for i = 1, slotCount do
		if not slots[i] then
			slots[i] = Inventory.copyStack(stack)
			return true
		end
	end
	return false
end

function Inventory.count(slots: Slots, id: string): number
	local total = 0
	for i = 1, Config.INV_SLOTS do
		local stack = slots[i]
		if stack and stack.id == id then total += stack.n end
	end
	return total
end

-- إزالة كمية؛ تُعيد false إن لم تكن متوفرة (ولا تُزيل شيئاً)
function Inventory.remove(slots: Slots, id: string, n: number): boolean
	if Inventory.count(slots, id) < n then return false end
	local left = n
	for i = 1, Config.INV_SLOTS do
		local stack = slots[i]
		if stack and stack.id == id then
			local take = math.min(stack.n, left)
			stack.n -= take
			left -= take
			if stack.n <= 0 then slots[i] = nil end
			if left <= 0 then return true end
		end
	end
	return left <= 0
end

function Inventory.removeFromSlot(slots: Slots, index: number, n: number): number
	local stack = slots[index]
	if not stack then return 0 end
	local take = math.min(stack.n, n)
	stack.n -= take
	if stack.n <= 0 then slots[index] = nil end
	return take
end

function Inventory.hasRoom(slots: Slots, id: string, n: number): boolean
	local item = Items.get(id)
	if not item then return false end
	local space = 0
	for i = 1, Config.INV_SLOTS do
		local stack = slots[i]
		if not stack then
			space += item.max
		elseif stack.id == id then
			space += item.max - stack.n
		end
		if space >= n then return true end
	end
	return space >= n
end

-- ===== التصنيع =====
function Inventory.canCraft(slots: Slots, recipe: Recipes.Recipe): boolean
	for _, ingredient in recipe.ins do
		if Inventory.count(slots, ingredient.id) < ingredient.n then return false end
	end
	return Inventory.hasRoom(slots, recipe.out.id, recipe.out.n)
end

function Inventory.craft(slots: Slots, recipe: Recipes.Recipe): boolean
	if not Inventory.canCraft(slots, recipe) then return false end
	for _, ingredient in recipe.ins do
		Inventory.remove(slots, ingredient.id, ingredient.n)
	end
	local leftover = Inventory.add(slots, recipe.out.id, recipe.out.n)
	return leftover == 0
end

-- ===== تحريك الخانات =====
function Inventory.swap(slots: Slots, a: number, b: number)
	if a == b then return end
	local sa, sb = slots[a], slots[b]

	-- دمج الأكوام المتطابقة (الأغراض المطوّرة لا تندمج أبداً)
	if sa and sb and sa.id == sb.id and sa.up == nil and sb.up == nil then
		local max = Items.maxStack(sa.id)
		local move = math.min(max - sb.n, sa.n)
		if move > 0 then
			sb.n += move
			sa.n -= move
			if sa.n <= 0 then slots[a] = nil end
			return
		end
	end

	slots[a], slots[b] = sb, sa
end

-- ===== التسلسل للحفظ =====
function Inventory.serialize(slots: Slots): { any }
	local out: { any } = {}
	for i = 1, Config.INV_SLOTS do
		local stack = slots[i]
		if stack then
			local entry: { any } = { i, stack.id, stack.n }
			if stack.up then
				entry[4] = stack.up.lvl
				entry[5] = stack.up.aff or ""
			end
			table.insert(out, entry)
		end
	end
	return out
end

function Inventory.deserialize(data: { any }?): Slots
	local slots: Slots = {}
	if type(data) ~= "table" then return slots end
	for _, entry in data :: { any } do
		if type(entry) == "table" and #entry >= 3 then
			local index, id, n = entry[1], entry[2], entry[3]
			if type(index) == "number" and type(id) == "string" and type(n) == "number" then
				if index >= 1 and index <= Config.INV_SLOTS and Items.get(id) and n > 0 then
					local stack: Stack = { id = id, n = math.min(n, Items.maxStack(id)) }
					if type(entry[4]) == "number" and Upgrades.canModify(id) then
						stack.up = Upgrades.normalize({ lvl = entry[4], aff = entry[5] })
					end
					slots[index] = stack
				end
			end
		end
	end
	return slots
end

-- شكل مُبسّط للإرسال عبر الشبكة
function Inventory.toNetwork(slots: Slots): { [number]: any }
	local out: { [number]: any } = {}
	for i = 1, Config.INV_SLOTS do
		local stack = slots[i]
		if stack then
			local entry: { any } = { stack.id, stack.n }
			if stack.up then
				entry[3] = stack.up.lvl
				entry[4] = stack.up.aff or ""
			end
			out[i] = entry
		end
	end
	return out
end

return Inventory
