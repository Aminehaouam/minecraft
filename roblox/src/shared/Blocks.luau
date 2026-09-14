--!strict
--[[
	Blocks — سجل البلاطات.
	كل بلاطة لها: لون، صلابة، الأداة المطلوبة، قوة المعول اللازمة، الضوء المنبعث،
	مقدار حجب الضوء، وما تُسقطه عند الكسر.

	ملاحظات:
	* `pick` = قوة المعول المطلوبة؛ إن كانت قوة معول اللاعب أقل فلن يكسر البلاطة.
	* `opacity` = كم نقطة ضوء تُفقد عند مرور الضوء خلال البلاطة (0..15).
	* `hard`   = زمن الكسر الأساسي بالثواني (يُقسم على كفاءة الأداة).
]]

local Blocks = {}

export type Block = {
	id: number,
	name: string,
	color: Color3,
	shade: number, -- مقدار التنويع العشوائي للون بين البلاطات
	solid: boolean,
	opacity: number,
	light: number,
	hard: number,
	tool: string?, -- "pickaxe" | "axe" | "hammer"
	pick: number,
	drop: number?, -- معرّف العنصر الساقط (افتراضياً عنصر البلاطة نفسها)
	dropChance: number?,
	liquid: boolean?,
	platform: boolean?, -- منصة: تُعبر من الأسفل ويُقف عليها
	climb: boolean?,
	attach: boolean?, -- تحتاج بلاطة مجاورة صلبة لتبقى
	station: string?, -- محطة تصنيع
	container: boolean?,
	fragile: boolean?, -- تُكسر فوراً (أعشاب، زهور)
	burn: number?, -- ضرر لمس (الحمم)
	sound: string?,
}

local function C(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- ===== المعرّفات =====
local ID = {
	AIR = 0,
	DIRT = 1,
	GRASS = 2,
	STONE = 3,
	CLAY = 4,
	SAND = 5,
	SANDSTONE = 6,
	SNOW = 7,
	ICE = 8,
	MUD = 9,
	JUNGLE_GRASS = 10,
	GRAVEL = 11,
	ASH = 12,

	LOG = 20,
	LEAVES = 21,
	PLANK = 22,
	STONE_BRICK = 23,
	GLASS = 24,
	SAND_BRICK = 25,
	BRICK = 30,
	ICE_BRICK = 26,
	HELLSTONE_BRICK = 27,
	OBSIDIAN = 28,
	BEDROCK = 29,

	COAL_ORE = 40,
	COPPER_ORE = 41,
	IRON_ORE = 42,
	SILVER_ORE = 43,
	GOLD_ORE = 44,
	DIAMOND_ORE = 45,
	MYTHRIL_ORE = 46,
	HELLSTONE_ORE = 47,
	CRYSTAL = 48,

	TORCH = 60,
	WORKBENCH = 61,
	FURNACE = 62,
	ANVIL = 63,
	CHEST = 64,
	PLATFORM = 65,
	LADDER = 66,
	LANTERN = 67,
	ALCHEMY = 68,
	ENCHANT_TABLE = 69,

	GRASS_TUFT = 80,
	FLOWER = 81,
	MUSHROOM = 82,
	GLOW_MUSHROOM = 83,
	CACTUS = 84,
	VINE = 85,
	COBWEB = 86,
	SAPLING = 87,

	WATER = 100,
	LAVA = 101,
}
Blocks.ID = ID

local defs: { Block } = {}

local function def(block: Block)
	defs[block.id] = block
end

-- ===== التربة والحجر =====
def({ id = ID.AIR, name = "هواء", color = C(0, 0, 0), shade = 0, solid = false, opacity = 1, light = 0, hard = 0, pick = 0 })
def({ id = ID.DIRT, name = "تراب", color = C(120, 85, 58), shade = 10, solid = true, opacity = 15, light = 0, hard = 0.5, tool = "pickaxe", pick = 0, sound = "soft" })
def({ id = ID.GRASS, name = "عشب", color = C(94, 152, 70), shade = 12, solid = true, opacity = 15, light = 0, hard = 0.55, tool = "pickaxe", pick = 0, drop = ID.DIRT, sound = "soft" })
def({ id = ID.STONE, name = "حجر", color = C(122, 122, 130), shade = 12, solid = true, opacity = 15, light = 0, hard = 1.1, tool = "pickaxe", pick = 0, sound = "hard" })
def({ id = ID.CLAY, name = "طين", color = C(150, 108, 96), shade = 8, solid = true, opacity = 15, light = 0, hard = 0.7, tool = "pickaxe", pick = 0, sound = "soft" })
def({ id = ID.SAND, name = "رمل", color = C(214, 198, 132), shade = 9, solid = true, opacity = 15, light = 0, hard = 0.4, tool = "pickaxe", pick = 0, sound = "soft" })
def({ id = ID.SANDSTONE, name = "حجر رملي", color = C(190, 165, 110), shade = 9, solid = true, opacity = 15, light = 0, hard = 1.0, tool = "pickaxe", pick = 0, sound = "hard" })
def({ id = ID.SNOW, name = "ثلج", color = C(232, 240, 248), shade = 6, solid = true, opacity = 15, light = 0, hard = 0.35, tool = "pickaxe", pick = 0, sound = "soft" })
def({ id = ID.ICE, name = "جليد", color = C(168, 214, 238), shade = 8, solid = true, opacity = 6, light = 0, hard = 0.6, tool = "pickaxe", pick = 0, sound = "hard" })
def({ id = ID.MUD, name = "وحل", color = C(88, 68, 48), shade = 8, solid = true, opacity = 15, light = 0, hard = 0.5, tool = "pickaxe", pick = 0, sound = "soft" })
def({ id = ID.JUNGLE_GRASS, name = "عشب أدغال", color = C(62, 140, 58), shade = 12, solid = true, opacity = 15, light = 0, hard = 0.6, tool = "pickaxe", pick = 0, drop = ID.MUD, sound = "soft" })
def({ id = ID.GRAVEL, name = "حصى", color = C(132, 126, 118), shade = 14, solid = true, opacity = 15, light = 0, hard = 0.6, tool = "pickaxe", pick = 0, sound = "soft" })
def({ id = ID.ASH, name = "رماد", color = C(78, 70, 68), shade = 10, solid = true, opacity = 15, light = 0, hard = 0.6, tool = "pickaxe", pick = 0, sound = "soft" })

-- ===== الخشب ومواد البناء =====
def({ id = ID.LOG, name = "جذع", color = C(112, 78, 44), shade = 8, solid = true, opacity = 15, light = 0, hard = 0.9, tool = "axe", pick = 0, sound = "wood" })
def({ id = ID.LEAVES, name = "أوراق", color = C(72, 132, 58), shade = 14, solid = true, opacity = 4, light = 0, hard = 0.25, tool = "axe", pick = 0, drop = ID.SAPLING, dropChance = 0.18, sound = "soft" })
def({ id = ID.PLANK, name = "ألواح", color = C(160, 116, 70), shade = 7, solid = true, opacity = 15, light = 0, hard = 0.8, tool = "axe", pick = 0, sound = "wood" })
def({ id = ID.STONE_BRICK, name = "طوب حجري", color = C(104, 104, 112), shade = 6, solid = true, opacity = 15, light = 0, hard = 1.3, tool = "pickaxe", pick = 0, sound = "hard" })
def({ id = ID.GLASS, name = "زجاج", color = C(198, 232, 240), shade = 3, solid = true, opacity = 1, light = 0, hard = 0.3, tool = "pickaxe", pick = 0, sound = "hard" })
def({ id = ID.SAND_BRICK, name = "طوب رملي", color = C(204, 178, 118), shade = 6, solid = true, opacity = 15, light = 0, hard = 1.2, tool = "pickaxe", pick = 0, sound = "hard" })
def({ id = ID.BRICK, name = "طوب طيني", color = C(170, 96, 78), shade = 6, solid = true, opacity = 15, light = 0, hard = 1.3, tool = "pickaxe", pick = 0, sound = "hard" })
def({ id = ID.ICE_BRICK, name = "طوب جليدي", color = C(186, 226, 246), shade = 5, solid = true, opacity = 8, light = 1, hard = 1.0, tool = "pickaxe", pick = 0, sound = "hard" })
def({ id = ID.HELLSTONE_BRICK, name = "طوب جهنمي", color = C(126, 56, 44), shade = 8, solid = true, opacity = 15, light = 3, hard = 1.8, tool = "pickaxe", pick = 55, sound = "hard" })
def({ id = ID.OBSIDIAN, name = "سبج", color = C(48, 36, 66), shade = 6, solid = true, opacity = 15, light = 0, hard = 4.0, tool = "pickaxe", pick = 65, sound = "hard" })
def({ id = ID.BEDROCK, name = "صخر الأساس", color = C(26, 24, 30), shade = 8, solid = true, opacity = 15, light = 0, hard = math.huge, tool = "pickaxe", pick = 9999, sound = "hard" })

-- ===== الخامات =====
def({ id = ID.COAL_ORE, name = "خام فحم", color = C(64, 62, 66), shade = 8, solid = true, opacity = 15, light = 0, hard = 1.4, tool = "pickaxe", pick = 0, sound = "hard" })
def({ id = ID.COPPER_ORE, name = "خام نحاس", color = C(180, 112, 68), shade = 8, solid = true, opacity = 15, light = 0, hard = 1.5, tool = "pickaxe", pick = 0, sound = "hard" })
def({ id = ID.IRON_ORE, name = "خام حديد", color = C(186, 160, 140), shade = 8, solid = true, opacity = 15, light = 0, hard = 1.8, tool = "pickaxe", pick = 20, sound = "hard" })
def({ id = ID.SILVER_ORE, name = "خام فضة", color = C(206, 212, 220), shade = 8, solid = true, opacity = 15, light = 0, hard = 2.0, tool = "pickaxe", pick = 30, sound = "hard" })
def({ id = ID.GOLD_ORE, name = "خام ذهب", color = C(226, 192, 76), shade = 8, solid = true, opacity = 15, light = 0, hard = 2.2, tool = "pickaxe", pick = 35, sound = "hard" })
def({ id = ID.DIAMOND_ORE, name = "خام ألماس", color = C(118, 218, 226), shade = 8, solid = true, opacity = 15, light = 1, hard = 2.8, tool = "pickaxe", pick = 45, sound = "hard" })
def({ id = ID.MYTHRIL_ORE, name = "خام ميثريل", color = C(96, 200, 168), shade = 8, solid = true, opacity = 15, light = 2, hard = 3.2, tool = "pickaxe", pick = 60, sound = "hard" })
def({ id = ID.HELLSTONE_ORE, name = "حجر جهنمي", color = C(214, 96, 52), shade = 10, solid = true, opacity = 15, light = 6, hard = 3.4, tool = "pickaxe", pick = 65, burn = 4, sound = "hard" })
def({ id = ID.CRYSTAL, name = "بلّور", color = C(180, 128, 236), shade = 10, solid = true, opacity = 2, light = 11, hard = 1.0, tool = "pickaxe", pick = 25, sound = "hard" })

-- ===== الأثاث والمحطات =====
def({ id = ID.TORCH, name = "مشعل", color = C(252, 202, 92), shade = 0, solid = false, opacity = 0, light = 14, hard = 0.05, pick = 0, attach = true, fragile = true, sound = "wood" })
def({ id = ID.LANTERN, name = "فانوس", color = C(255, 224, 140), shade = 0, solid = false, opacity = 0, light = 15, hard = 0.2, pick = 0, attach = true, sound = "hard" })
def({ id = ID.WORKBENCH, name = "طاولة عمل", color = C(150, 104, 62), shade = 4, solid = false, opacity = 2, light = 0, hard = 0.6, tool = "axe", pick = 0, station = "workbench", sound = "wood" })
def({ id = ID.FURNACE, name = "فرن", color = C(96, 92, 96), shade = 5, solid = false, opacity = 2, light = 8, hard = 1.4, tool = "pickaxe", pick = 0, station = "furnace", sound = "hard" })
def({ id = ID.ANVIL, name = "سندان", color = C(76, 78, 86), shade = 4, solid = false, opacity = 2, light = 0, hard = 1.8, tool = "pickaxe", pick = 0, station = "anvil", sound = "hard" })
def({ id = ID.ALCHEMY, name = "طاولة خيمياء", color = C(108, 78, 150), shade = 5, solid = false, opacity = 2, light = 4, hard = 1.0, tool = "axe", pick = 0, station = "alchemy", sound = "wood" })
def({ id = ID.ENCHANT_TABLE, name = "طاولة السحر", color = C(86, 66, 156), shade = 6, solid = false, opacity = 2, light = 7, hard = 2.2, tool = "pickaxe", pick = 25, station = "enchant", sound = "hard" })
def({ id = ID.CHEST, name = "صندوق", color = C(172, 124, 62), shade = 4, solid = false, opacity = 2, light = 0, hard = 0.8, tool = "axe", pick = 0, container = true, sound = "wood" })
def({ id = ID.PLATFORM, name = "منصة", color = C(164, 122, 76), shade = 5, solid = false, opacity = 1, light = 0, hard = 0.3, tool = "axe", pick = 0, platform = true, sound = "wood" })
def({ id = ID.LADDER, name = "سلّم", color = C(178, 138, 84), shade = 4, solid = false, opacity = 1, light = 0, hard = 0.3, tool = "axe", pick = 0, climb = true, attach = true, sound = "wood" })

-- ===== النباتات =====
def({ id = ID.GRASS_TUFT, name = "حشائش", color = C(104, 168, 76), shade = 12, solid = false, opacity = 0, light = 0, hard = 0.02, pick = 0, attach = true, fragile = true, drop = ID.SAPLING, dropChance = 0.1, sound = "soft" })
def({ id = ID.FLOWER, name = "زهرة", color = C(226, 122, 156), shade = 30, solid = false, opacity = 0, light = 0, hard = 0.02, pick = 0, attach = true, fragile = true, sound = "soft" })
def({ id = ID.MUSHROOM, name = "فطر", color = C(214, 178, 152), shade = 8, solid = false, opacity = 0, light = 0, hard = 0.02, pick = 0, attach = true, fragile = true, sound = "soft" })
def({ id = ID.GLOW_MUSHROOM, name = "فطر متوهج", color = C(126, 226, 196), shade = 8, solid = false, opacity = 0, light = 9, hard = 0.02, pick = 0, attach = true, fragile = true, sound = "soft" })
def({ id = ID.CACTUS, name = "صبّار", color = C(74, 138, 82), shade = 6, solid = true, opacity = 6, light = 0, hard = 0.5, tool = "axe", pick = 0, burn = 2, sound = "soft" })
def({ id = ID.VINE, name = "لبلاب", color = C(58, 118, 52), shade = 10, solid = false, opacity = 2, light = 0, hard = 0.05, pick = 0, climb = true, attach = true, fragile = true, sound = "soft" })
def({ id = ID.COBWEB, name = "خيوط عنكبوت", color = C(224, 228, 232), shade = 4, solid = false, opacity = 1, light = 0, hard = 0.35, pick = 0, fragile = true, sound = "soft" })
def({ id = ID.SAPLING, name = "شتلة", color = C(96, 160, 66), shade = 8, solid = false, opacity = 0, light = 0, hard = 0.02, pick = 0, attach = true, fragile = true, sound = "soft" })

-- ===== السوائل =====
def({ id = ID.WATER, name = "ماء", color = C(52, 104, 208), shade = 4, solid = false, opacity = 2, light = 0, hard = math.huge, pick = 9999, liquid = true })
def({ id = ID.LAVA, name = "حمم", color = C(226, 104, 34), shade = 8, solid = false, opacity = 1, light = 12, hard = math.huge, pick = 9999, liquid = true, burn = 26 })

Blocks.defs = defs

local AIR = defs[ID.AIR]

function Blocks.get(id: number): Block
	return defs[id] or AIR
end

function Blocks.isSolid(id: number): boolean
	local b = defs[id]
	return b ~= nil and b.solid
end

function Blocks.isPlatform(id: number): boolean
	local b = defs[id]
	return b ~= nil and b.platform == true
end

function Blocks.isLiquid(id: number): boolean
	local b = defs[id]
	return b ~= nil and b.liquid == true
end

function Blocks.isClimb(id: number): boolean
	local b = defs[id]
	return b ~= nil and b.climb == true
end

function Blocks.opacity(id: number): number
	local b = defs[id]
	return if b then b.opacity else 1
end

function Blocks.light(id: number): number
	local b = defs[id]
	return if b then b.light else 0
end

-- البلاطات التي يمكن استبدالها مباشرة بالبناء
function Blocks.isReplaceable(id: number): boolean
	if id == ID.AIR then return true end
	local b = defs[id]
	return b ~= nil and (b.liquid == true or b.fragile == true)
end

-- هل يحتاج هذا الصنف سنداً؟ (يسقط إن أزيل ما حوله)
function Blocks.needsSupport(id: number): boolean
	local b = defs[id]
	return b ~= nil and b.attach == true
end

return Blocks
