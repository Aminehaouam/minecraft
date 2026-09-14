--!strict
--[[
	Upgrades — نظام تطوير الأدوات والدروع وسِحرها.

	لكل غرض قابل للتطوير حقل `up` صغير داخل كومته:
		{ lvl = 0..5, aff = "sharp" }

	* **التطوير (+N)** على السندان: زيادة خطية مضمونة النجاح — لا كسر ولا عشوائية.
	* **السحر (صفة)** على طاولة السحر: صفة واحدة عشوائية، يمكن إعادة رميها
	  كما في تيراريا. العشوائية هنا مقبولة لأنها قابلة للإعادة دائماً.

	كل الأغراض القابلة للتطوير حدّ تكديسها 1، فلا مشكلة اندماج أكوام مختلفة.
]]

local Items = require(script.Parent.Items)

local Upgrades = {}

export type Upgrade = { lvl: number, aff: string? }
export type Stack = { id: string, n: number, up: Upgrade? }

Upgrades.MAX_LEVEL = 5

-- ===== الصفات (السحر) =====

export type Affix = {
	id: string,
	name: string,
	color: Color3,
	desc: string,
	weight: number,
	damage: number?, -- مضاعف
	useTime: number?, -- مضاعف (أقل = أسرع)
	knockback: number?, -- مضاعف
	crit: number?, -- إضافة مطلقة
	lifesteal: number?, -- نسبة الضرر التي تُشفى
	mining: number?, -- مضاعف سرعة التعدين
	fortune: number?, -- احتمال إسقاط مضاعف
	reach: number?, -- بلاطات إضافية
	defense: number?, -- إضافة مطلقة
	speed: number?, -- مضاعف سرعة الحركة
	thorns: number?, -- نسبة الضرر المرتد
	regen: number?, -- حياة/ثانية
	mana: number?, -- مانا قصوى إضافية
}

local function C(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local WEAPON_AFFIXES: { Affix } = {
	{ id = "sharp", name = "حادّ", color = C(240, 120, 110), desc = "+15% ضرر", weight = 26, damage = 1.15 },
	{ id = "swift", name = "سريع", color = C(140, 220, 240), desc = "-14% زمن الاستخدام", weight = 24, useTime = 0.86 },
	{ id = "deadly", name = "فتّاك", color = C(250, 200, 90), desc = "+12% فرصة ضربة حرجة", weight = 18, crit = 0.12 },
	{ id = "brutal", name = "عنيف", color = C(230, 150, 90), desc = "+60% ارتداد و+6% ضرر", weight = 18, knockback = 1.6, damage = 1.06 },
	{ id = "vampiric", name = "مصّاص", color = C(200, 110, 200), desc = "يشفيك 8% من الضرر", weight = 14, lifesteal = 0.08 },
}

local TOOL_AFFIXES: { Affix } = {
	{ id = "efficient", name = "كفؤ", color = C(150, 230, 160), desc = "+28% سرعة تعدين", weight = 28, mining = 1.28 },
	{ id = "fortune", name = "موفّق", color = C(250, 210, 110), desc = "25% فرصة إسقاط مضاعف", weight = 20, fortune = 0.25 },
	{ id = "far", name = "بعيد المدى", color = C(160, 200, 250), desc = "+1.5 بلاطة مدى", weight = 20, reach = 1.5 },
	{ id = "keen", name = "ماضٍ", color = C(240, 140, 120), desc = "+18% ضرر", weight = 18, damage = 1.18 },
	{ id = "tireless", name = "لا يكلّ", color = C(200, 220, 240), desc = "+14% سرعة تعدين و-8% زمن استخدام", weight = 14, mining = 1.14, useTime = 0.92 },
}

local ARMOR_AFFIXES: { Affix } = {
	{ id = "tough", name = "صلب", color = C(190, 195, 210), desc = "+3 دفاع", weight = 28, defense = 3 },
	{ id = "agile", name = "رشيق", color = C(140, 230, 170), desc = "+8% سرعة حركة", weight = 22, speed = 1.08 },
	{ id = "thorny", name = "شائك", color = C(230, 140, 140), desc = "يرتدّ 25% من الضرر", weight = 18, thorns = 0.25 },
	{ id = "vital", name = "حيويّ", color = C(240, 130, 170), desc = "+1 حياة/ثانية", weight = 18, regen = 1 },
	{ id = "arcane", name = "غامض", color = C(150, 160, 250), desc = "+20 مانا قصوى", weight = 14, mana = 20 },
}

local byId: { [string]: Affix } = {}
for _, pool in { WEAPON_AFFIXES, TOOL_AFFIXES, ARMOR_AFFIXES } do
	for _, affix in pool do
		byId[affix.id] = affix
	end
end

Upgrades.pools = { weapon = WEAPON_AFFIXES, tool = TOOL_AFFIXES, armor = ARMOR_AFFIXES }

function Upgrades.affix(id: string?): Affix?
	if not id then return nil end
	return byId[id]
end

-- ===== الأهلية =====

-- فئة التطوير التي ينتمي إليها العنصر (أو nil إن كان غير قابل للتطوير)
function Upgrades.categoryOf(itemId: string?): string?
	if not itemId then return nil end
	local item = Items.get(itemId)
	if not item then return nil end
	if item.cat == "weapon" then return "weapon" end
	if item.cat == "tool" then return "tool" end
	if item.cat == "armor" then return "armor" end
	return nil
end

function Upgrades.canModify(itemId: string?): boolean
	return Upgrades.categoryOf(itemId) ~= nil
end

function Upgrades.levelOf(stack: Stack?): number
	if stack and stack.up then return math.clamp(stack.up.lvl or 0, 0, Upgrades.MAX_LEVEL) end
	return 0
end

function Upgrades.affixOf(stack: Stack?): Affix?
	if stack and stack.up then return Upgrades.affix(stack.up.aff) end
	return nil
end

-- ===== حساب الإحصاءات =====

-- كل مستوى تطوير يضيف 12% للأرقام النسبية
local function levelScale(level: number): number
	return 1 + 0.12 * level
end
Upgrades.levelScale = levelScale

function Upgrades.damage(stack: Stack?): number
	if not stack then return 0 end
	local item = Items.get(stack.id)
	if not item or not item.damage then return 0 end
	local value = item.damage * levelScale(Upgrades.levelOf(stack))
	local affix = Upgrades.affixOf(stack)
	if affix and affix.damage then value *= affix.damage end
	return math.floor(value + 0.5)
end

function Upgrades.useTime(stack: Stack?): number
	if not stack then return 0.35 end
	local item = Items.get(stack.id)
	local base = (item and item.useTime) or 0.35
	local affix = Upgrades.affixOf(stack)
	if affix and affix.useTime then base *= affix.useTime end
	-- التطوير يسرّع قليلاً أيضاً
	base *= 1 - 0.03 * Upgrades.levelOf(stack)
	return math.max(0.08, base)
end

function Upgrades.knockback(stack: Stack?): number
	if not stack then return 3 end
	local item = Items.get(stack.id)
	local base = (item and item.knockback) or 3
	local affix = Upgrades.affixOf(stack)
	if affix and affix.knockback then base *= affix.knockback end
	return base
end

function Upgrades.crit(stack: Stack?): number
	if not stack then return 0.03 end
	local item = Items.get(stack.id)
	local base = (item and item.crit) or 0.03
	local affix = Upgrades.affixOf(stack)
	if affix and affix.crit then base += affix.crit end
	return math.clamp(base, 0, 0.95)
end

function Upgrades.lifesteal(stack: Stack?): number
	local affix = Upgrades.affixOf(stack)
	return if affix and affix.lifesteal then affix.lifesteal else 0
end

-- قوة معول/فأس إضافية من التطوير
function Upgrades.powerBonus(stack: Stack?): number
	return 4 * Upgrades.levelOf(stack)
end

function Upgrades.miningMultiplier(stack: Stack?): number
	local value = 1 + 0.05 * Upgrades.levelOf(stack)
	local affix = Upgrades.affixOf(stack)
	if affix and affix.mining then value *= affix.mining end
	return value
end

function Upgrades.fortune(stack: Stack?): number
	local affix = Upgrades.affixOf(stack)
	return if affix and affix.fortune then affix.fortune else 0
end

function Upgrades.reachBonus(stack: Stack?): number
	local affix = Upgrades.affixOf(stack)
	return if affix and affix.reach then affix.reach else 0
end

function Upgrades.defense(stack: Stack?): number
	if not stack then return 0 end
	local item = Items.get(stack.id)
	if not item or not item.defense then return 0 end
	local value = item.defense * levelScale(Upgrades.levelOf(stack))
	local affix = Upgrades.affixOf(stack)
	if affix and affix.defense then value += affix.defense end
	return math.floor(value + 0.5)
end

-- مجموع تأثيرات الدرع الملبوس
export type ArmorBonus = { defense: number, speed: number, thorns: number, regen: number, mana: number }

function Upgrades.armorBonus(armor: { [string]: Stack? }): ArmorBonus
	local bonus: ArmorBonus = { defense = 0, speed = 1, thorns = 0, regen = 0, mana = 0 }
	for _, stack in armor do
		if stack then
			bonus.defense += Upgrades.defense(stack)
			local affix = Upgrades.affixOf(stack)
			if affix then
				if affix.speed then bonus.speed *= affix.speed end
				if affix.thorns then bonus.thorns += affix.thorns end
				if affix.regen then bonus.regen += affix.regen end
				if affix.mana then bonus.mana += affix.mana end
			end
		end
	end
	return bonus
end

-- ===== التكاليف =====

export type Cost = { material: string, amount: number, coins: number }

function Upgrades.upgradeCost(itemId: string, level: number): Cost?
	local item = Items.get(itemId)
	if not item then return nil end
	if level >= Upgrades.MAX_LEVEL then return nil end
	local target = level + 1
	return {
		material = "upgrade_core",
		amount = target,
		coins = 40 * target * (1 + item.rarity),
	}
end

function Upgrades.enchantCost(itemId: string): Cost?
	local item = Items.get(itemId)
	if not item then return nil end
	return {
		material = "magic_essence",
		amount = 2 + item.rarity,
		coins = 60 * (1 + item.rarity),
	}
end

-- اختيار صفة عشوائية موزونة (تُمرَّر قيمة عشوائية 0..1 لتبقى الدالة نقية)
function Upgrades.rollAffix(category: string, roll: number, exclude: string?): string?
	local pool = Upgrades.pools[category]
	if not pool then return nil end

	local total = 0
	for _, affix in pool do
		if affix.id ~= exclude then total += affix.weight end
	end
	if total <= 0 then
		return pool[1].id
	end

	local pick = roll * total
	for _, affix in pool do
		if affix.id ~= exclude then
			pick -= affix.weight
			if pick <= 0 then return affix.id end
		end
	end
	return pool[#pool].id
end

-- ===== العرض =====

function Upgrades.displayName(stack: Stack?): string
	if not stack then return "" end
	local item = Items.get(stack.id)
	local name = if item then item.name else stack.id
	local affix = Upgrades.affixOf(stack)
	if affix then
		name = affix.name .. " " .. name
	end
	local level = Upgrades.levelOf(stack)
	if level > 0 then
		name ..= " +" .. level
	end
	return name
end

function Upgrades.displayColor(stack: Stack?): Color3
	local affix = Upgrades.affixOf(stack)
	if affix then return affix.color end
	local item = if stack then Items.get(stack.id) else nil
	if item then
		return Items.RARITY_COLORS[item.rarity] or Color3.fromRGB(236, 236, 236)
	end
	return Color3.fromRGB(236, 236, 236)
end

-- هل هذه الكومة مطوّرة أو مسحورة؟ (لإظهار توهج في الواجهة)
function Upgrades.isModified(stack: Stack?): boolean
	return Upgrades.levelOf(stack) > 0 or Upgrades.affixOf(stack) ~= nil
end

-- تنظيف حقل التطوير قبل الحفظ/الإرسال (يُعيد nil إن كان بلا معنى)
function Upgrades.normalize(up: any): Upgrade?
	if type(up) ~= "table" then return nil end
	local level = tonumber(up.lvl) or 0
	level = math.clamp(math.floor(level), 0, Upgrades.MAX_LEVEL)
	local affixId = if type(up.aff) == "string" and byId[up.aff] then up.aff else nil
	if level == 0 and affixId == nil then return nil end
	return { lvl = level, aff = affixId }
end

return Upgrades
