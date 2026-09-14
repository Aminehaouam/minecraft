--!strict
--[[
	Items — سجل العناصر (كل ما يمكن حمله في المخزون).
	معرّف العنصر نص قصير ثابت (يُحفظ في DataStore) — لا تُغيّر المعرّفات بعد النشر.
]]

local Blocks = require(script.Parent.Blocks)
local B = Blocks.ID

local Items = {}

export type Item = {
	id: string,
	name: string,
	cat: string, -- block | tool | weapon | armor | material | consumable | ammo | misc
	max: number, -- أقصى تكديس
	color: Color3,
	rarity: number, -- 0 أبيض .. 5 أسطوري
	value: number, -- سعر البيع بالعملة

	place: number?, -- معرّف البلاطة عند الوضع
	wall: boolean?, -- يمكن وضعه كخلفية

	tool: string?, -- pickaxe | axe | hammer
	pick: number?, -- قوة المعول
	axe: number?, -- قوة الفأس
	speed: number?, -- مضاعف سرعة الاستخدام (1 = عادي)
	damage: number?,
	knockback: number?,
	useTime: number?, -- ثواني بين الاستخدامات
	crit: number?,
	ranged: string?, -- نوع الذخيرة المطلوبة
	shootSpeed: number?,
	mana: number?, -- كلفة المانا
	magic: string?, -- نوع التعويذة

	defense: number?,
	slot: string?, -- head | chest | feet
	setBonus: string?,

	heal: number?,
	restoreMana: number?,
	food: number?,
	buff: string?,
	buffTime: number?,

	ammo: string?,
	summon: string?, -- استدعاء زعيم
	nightOnly: boolean?,
	desc: string?,
}

local defs: { [string]: Item } = {}
local order: { string } = {}
local byBlock: { [number]: string } = {}

local function C(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function def(item: Item)
	defs[item.id] = item
	table.insert(order, item.id)
	if item.place then byBlock[item.place] = item.id end
end

-- عنصر بلاطة: يرث اللون والاسم من سجل البلاطات
local function blockItem(id: string, blockId: number, value: number, wall: boolean?)
	local b = Blocks.get(blockId)
	def({
		id = id,
		name = b.name,
		cat = "block",
		max = 999,
		color = b.color,
		rarity = 0,
		value = value,
		place = blockId,
		wall = wall,
	})
end

-- ===== بلاطات =====
blockItem("dirt", B.DIRT, 1, true)
blockItem("grass", B.GRASS, 1, true)
blockItem("stone", B.STONE, 1, true)
blockItem("clay", B.CLAY, 1, true)
blockItem("sand", B.SAND, 1, true)
blockItem("sandstone", B.SANDSTONE, 2, true)
blockItem("snow", B.SNOW, 1, true)
blockItem("ice", B.ICE, 1, true)
blockItem("mud", B.MUD, 1, true)
blockItem("jungle_grass", B.JUNGLE_GRASS, 1, true)
blockItem("gravel", B.GRAVEL, 1, true)
blockItem("ash", B.ASH, 1, true)
blockItem("log", B.LOG, 2, true)
blockItem("leaves", B.LEAVES, 1, true)
blockItem("plank", B.PLANK, 3, true)
blockItem("stone_brick", B.STONE_BRICK, 3, true)
blockItem("glass", B.GLASS, 4, true)
blockItem("sand_brick", B.SAND_BRICK, 3, true)
blockItem("ice_brick", B.ICE_BRICK, 3, true)
blockItem("hellstone_brick", B.HELLSTONE_BRICK, 12, true)
blockItem("obsidian", B.OBSIDIAN, 14, true)
blockItem("coal_ore", B.COAL_ORE, 4)
blockItem("copper_ore", B.COPPER_ORE, 5)
blockItem("iron_ore", B.IRON_ORE, 8)
blockItem("silver_ore", B.SILVER_ORE, 12)
blockItem("gold_ore", B.GOLD_ORE, 18)
blockItem("diamond_ore", B.DIAMOND_ORE, 30)
blockItem("mythril_ore", B.MYTHRIL_ORE, 40)
blockItem("hellstone_ore", B.HELLSTONE_ORE, 35)
blockItem("crystal", B.CRYSTAL, 22)
blockItem("torch", B.TORCH, 1)
blockItem("lantern", B.LANTERN, 6)
blockItem("workbench", B.WORKBENCH, 8)
blockItem("furnace", B.FURNACE, 10)
blockItem("anvil", B.ANVIL, 18)
blockItem("alchemy_table", B.ALCHEMY, 24)
blockItem("chest", B.CHEST, 12)
blockItem("platform", B.PLATFORM, 1)
blockItem("ladder", B.LADDER, 2)
blockItem("cactus", B.CACTUS, 2)
blockItem("cobweb", B.COBWEB, 1)
blockItem("sapling", B.SAPLING, 1)
blockItem("mushroom_block", B.MUSHROOM, 3)
blockItem("glow_mushroom_block", B.GLOW_MUSHROOM, 9)

-- ===== مواد =====
local function material(id: string, name: string, color: Color3, value: number, rarity: number?)
	def({ id = id, name = name, cat = "material", max = 999, color = color, rarity = rarity or 0, value = value })
end

material("wood", "خشب", C(150, 108, 64), 2)
material("coal", "فحم", C(48, 46, 50), 5)
material("copper_bar", "سبيكة نحاس", C(196, 122, 74), 14)
material("iron_bar", "سبيكة حديد", C(196, 174, 156), 22)
material("silver_bar", "سبيكة فضة", C(214, 220, 228), 34)
material("gold_bar", "سبيكة ذهب", C(238, 202, 84), 50, 1)
material("diamond", "ألماسة", C(126, 226, 234), 90, 2)
material("mythril_bar", "سبيكة ميثريل", C(102, 210, 176), 120, 3)
material("hellstone_bar", "سبيكة جهنمية", C(224, 110, 58), 110, 3)
material("string", "خيط", C(228, 228, 220), 3)
material("leather", "جلد", C(142, 98, 64), 8)
material("bone", "عظم", C(232, 228, 210), 6)
material("gel", "هلام", C(120, 170, 236), 4)
material("herb", "عشبة", C(126, 196, 96), 6)
material("glow_dust", "غبار متوهج", C(150, 242, 210), 12, 1)
material("shadow_scale", "قشرة ظلامية", C(126, 96, 170), 60, 3)
material("soul_fragment", "شظية روح", C(196, 150, 250), 80, 4)
material("coin", "عملة", C(246, 210, 96), 1)

-- ===== الأدوات =====
local function tool(id: string, name: string, kind: string, power: number, damage: number, useTime: number, color: Color3, rarity: number, value: number)
	local item: Item = {
		id = id, name = name, cat = "tool", max = 1, color = color, rarity = rarity, value = value,
		tool = kind, damage = damage, useTime = useTime, knockback = 2.5, crit = 0.04,
	}
	if kind == "pickaxe" then item.pick = power elseif kind == "axe" then item.axe = power else item.pick = power end
	def(item)
end

tool("wood_pickaxe", "معول خشبي", "pickaxe", 12, 4, 0.42, C(150, 108, 64), 0, 10)
tool("stone_pickaxe", "معول حجري", "pickaxe", 22, 6, 0.36, C(122, 122, 130), 0, 20)
tool("copper_pickaxe", "معول نحاسي", "pickaxe", 30, 7, 0.33, C(196, 122, 74), 1, 40)
tool("iron_pickaxe", "معول حديدي", "pickaxe", 42, 9, 0.30, C(196, 174, 156), 1, 80)
tool("gold_pickaxe", "معول ذهبي", "pickaxe", 52, 10, 0.26, C(238, 202, 84), 2, 160)
tool("diamond_pickaxe", "معول ألماسي", "pickaxe", 68, 13, 0.22, C(126, 226, 234), 3, 320)
tool("mythril_pickaxe", "معول ميثريل", "pickaxe", 90, 17, 0.18, C(102, 210, 176), 4, 600)

tool("wood_axe", "فأس خشبي", "axe", 14, 5, 0.5, C(150, 108, 64), 0, 10)
tool("stone_axe", "فأس حجري", "axe", 26, 7, 0.44, C(122, 122, 130), 0, 20)
tool("iron_axe", "فأس حديدي", "axe", 46, 10, 0.36, C(196, 174, 156), 1, 80)
tool("diamond_axe", "فأس ألماسي", "axe", 72, 14, 0.28, C(126, 226, 234), 3, 300)

def({
	id = "hammer", name = "مطرقة", cat = "tool", max = 1, color = C(150, 140, 130), rarity = 1, value = 45,
	tool = "hammer", pick = 0, damage = 8, useTime = 0.45, knockback = 4,
	desc = "تهدم الجدران الخلفية",
})

-- ===== الأسلحة =====
local function sword(id: string, name: string, damage: number, useTime: number, color: Color3, rarity: number, value: number, kb: number?)
	def({
		id = id, name = name, cat = "weapon", max = 1, color = color, rarity = rarity, value = value,
		damage = damage, useTime = useTime, knockback = kb or 4, crit = 0.06, tool = "sword",
	})
end

sword("wood_sword", "سيف خشبي", 7, 0.36, C(150, 108, 64), 0, 12)
sword("stone_sword", "سيف حجري", 11, 0.34, C(122, 122, 130), 0, 24)
sword("copper_sword", "سيف نحاسي", 14, 0.32, C(196, 122, 74), 1, 48)
sword("iron_sword", "سيف حديدي", 19, 0.30, C(196, 174, 156), 1, 95)
sword("silver_sword", "سيف فضي", 24, 0.28, C(214, 220, 228), 2, 150)
sword("gold_sword", "سيف ذهبي", 29, 0.26, C(238, 202, 84), 2, 220)
sword("diamond_sword", "سيف ألماسي", 38, 0.24, C(126, 226, 234), 3, 420)
sword("mythril_blade", "نصل الميثريل", 52, 0.20, C(102, 210, 176), 4, 800, 6)
sword("night_edge", "حدّ الليل", 74, 0.18, C(150, 96, 200), 5, 1600, 7)

def({
	id = "wood_bow", name = "قوس خشبي", cat = "weapon", max = 1, color = C(150, 108, 64), rarity = 0, value = 20,
	damage = 8, useTime = 0.42, knockback = 2, ranged = "arrow", shootSpeed = 34, crit = 0.06,
})
def({
	id = "iron_bow", name = "قوس حديدي", cat = "weapon", max = 1, color = C(196, 174, 156), rarity = 1, value = 90,
	damage = 14, useTime = 0.34, knockback = 2.5, ranged = "arrow", shootSpeed = 42, crit = 0.08,
})
def({
	id = "hell_bow", name = "قوس الجحيم", cat = "weapon", max = 1, color = C(224, 110, 58), rarity = 3, value = 420,
	damage = 26, useTime = 0.26, knockback = 3, ranged = "arrow", shootSpeed = 52, crit = 0.1,
})
def({
	id = "arrow", name = "سهم", cat = "ammo", max = 999, color = C(190, 170, 140), rarity = 0, value = 1,
	ammo = "arrow", damage = 4,
})
def({
	id = "fire_arrow", name = "سهم ناري", cat = "ammo", max = 999, color = C(240, 140, 60), rarity = 1, value = 3,
	ammo = "arrow", damage = 9, buff = "burn",
})

def({
	id = "spark_staff", name = "عصا الشرر", cat = "weapon", max = 1, color = C(120, 190, 250), rarity = 2, value = 200,
	damage = 18, useTime = 0.3, knockback = 2, mana = 6, magic = "spark", shootSpeed = 30, crit = 0.08,
})
def({
	id = "flame_staff", name = "عصا اللهب", cat = "weapon", max = 1, color = C(250, 130, 70), rarity = 3, value = 520,
	damage = 30, useTime = 0.36, knockback = 3, mana = 10, magic = "flame", shootSpeed = 26, crit = 0.1,
})

-- ===== الدروع =====
local function armor(id: string, name: string, slot: string, defense: number, color: Color3, rarity: number, value: number, setBonus: string?)
	def({
		id = id, name = name, cat = "armor", max = 1, color = color, rarity = rarity, value = value,
		defense = defense, slot = slot, setBonus = setBonus,
	})
end

armor("leather_helm", "خوذة جلدية", "head", 2, C(142, 98, 64), 0, 20, "leather")
armor("leather_chest", "درع جلدي", "chest", 3, C(142, 98, 64), 0, 30, "leather")
armor("leather_boots", "حذاء جلدي", "feet", 2, C(142, 98, 64), 0, 20, "leather")
armor("copper_helm", "خوذة نحاسية", "head", 3, C(196, 122, 74), 1, 45, "copper")
armor("copper_chest", "درع نحاسي", "chest", 4, C(196, 122, 74), 1, 65, "copper")
armor("copper_boots", "حذاء نحاسي", "feet", 3, C(196, 122, 74), 1, 45, "copper")
armor("iron_helm", "خوذة حديدية", "head", 5, C(196, 174, 156), 1, 90, "iron")
armor("iron_chest", "درع حديدي", "chest", 7, C(196, 174, 156), 1, 130, "iron")
armor("iron_boots", "حذاء حديدي", "feet", 5, C(196, 174, 156), 1, 90, "iron")
armor("diamond_helm", "خوذة ألماسية", "head", 9, C(126, 226, 234), 3, 300, "diamond")
armor("diamond_chest", "درع ألماسي", "chest", 12, C(126, 226, 234), 3, 420, "diamond")
armor("diamond_boots", "حذاء ألماسي", "feet", 9, C(126, 226, 234), 3, 300, "diamond")
armor("mythril_helm", "خوذة ميثريل", "head", 13, C(102, 210, 176), 4, 700, "mythril")
armor("mythril_chest", "درع ميثريل", "chest", 17, C(102, 210, 176), 4, 900, "mythril")
armor("mythril_boots", "حذاء ميثريل", "feet", 13, C(102, 210, 176), 4, 700, "mythril")

-- ===== الاستهلاكيات =====
def({ id = "apple", name = "تفاحة", cat = "consumable", max = 99, color = C(214, 72, 72), rarity = 0, value = 4, food = 22, heal = 4, useTime = 0.6 })
def({ id = "mushroom", name = "فطر", cat = "consumable", max = 99, color = C(214, 178, 152), rarity = 0, value = 3, food = 14, useTime = 0.6 })
def({ id = "cooked_meat", name = "لحم مشوي", cat = "consumable", max = 99, color = C(178, 108, 74), rarity = 0, value = 10, food = 45, heal = 10, useTime = 0.8 })
def({ id = "bread", name = "خبز", cat = "consumable", max = 99, color = C(216, 178, 112), rarity = 0, value = 8, food = 36, useTime = 0.7 })
def({ id = "health_potion", name = "جرعة حياة", cat = "consumable", max = 30, color = C(232, 72, 96), rarity = 1, value = 24, heal = 60, useTime = 0.5, buff = "potion_sickness", buffTime = 20 })
def({ id = "mana_potion", name = "جرعة مانا", cat = "consumable", max = 30, color = C(96, 128, 240), rarity = 1, value = 20, restoreMana = 40, useTime = 0.5 })
def({ id = "swift_potion", name = "جرعة سرعة", cat = "consumable", max = 30, color = C(120, 226, 140), rarity = 2, value = 40, useTime = 0.5, buff = "swift", buffTime = 180 })
def({ id = "iron_skin_potion", name = "جرعة جلد حديدي", cat = "consumable", max = 30, color = C(180, 180, 200), rarity = 2, value = 45, useTime = 0.5, buff = "iron_skin", buffTime = 180 })
def({ id = "shine_potion", name = "جرعة توهج", cat = "consumable", max = 30, color = C(250, 240, 160), rarity = 1, value = 30, useTime = 0.5, buff = "shine", buffTime = 300 })

-- ===== خاص =====
def({
	id = "life_crystal", name = "بلّورة حياة", cat = "consumable", max = 99, color = C(240, 90, 120), rarity = 2, value = 120,
	useTime = 0.8, desc = "تزيد الحياة القصوى 20 (حتى 300)",
})
def({
	id = "mana_crystal", name = "نجمة مانا", cat = "consumable", max = 99, color = C(120, 140, 250), rarity = 2, value = 100,
	useTime = 0.8, desc = "تزيد المانا القصوى 20 (حتى 200)",
})
def({
	id = "eye_totem", name = "طوطم العين", cat = "misc", max = 20, color = C(200, 60, 60), rarity = 4, value = 250,
	useTime = 1, summon = "eye_of_depths", nightOnly = true, desc = "يستدعي عين الأعماق ليلاً",
})
def({
	id = "magic_mirror", name = "المرآة السحرية", cat = "misc", max = 1, color = C(190, 200, 250), rarity = 3, value = 350,
	useTime = 1.6, desc = "تعيدك إلى نقطة الظهور",
})
def({
	id = "recall_stone", name = "حجر العودة", cat = "misc", max = 99, color = C(150, 190, 220), rarity = 1, value = 40,
	useTime = 2.2, desc = "عودة لمرة واحدة إلى نقطة الظهور",
})

Items.defs = defs
Items.order = order

function Items.get(id: string): Item?
	return defs[id]
end

function Items.name(id: string): string
	local item = defs[id]
	return if item then item.name else id
end

function Items.maxStack(id: string): number
	local item = defs[id]
	return if item then item.max else 1
end

-- العنصر المقابل لبلاطة (لإسقاطها عند الكسر)
function Items.fromBlock(blockId: number): string?
	return byBlock[blockId]
end

Items.RARITY_COLORS = {
	[0] = Color3.fromRGB(236, 236, 236),
	[1] = Color3.fromRGB(140, 230, 140),
	[2] = Color3.fromRGB(120, 180, 255),
	[3] = Color3.fromRGB(200, 130, 255),
	[4] = Color3.fromRGB(255, 180, 90),
	[5] = Color3.fromRGB(255, 100, 120),
}

return Items
