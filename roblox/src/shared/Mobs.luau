--!strict
--[[
	Mobs — تعريفات الوحوش (مشتركة: الخادم يحاكيها والعميل يرسمها).
	ai: walker | jumper | flyer | shooter | climber | boss
]]

local Mobs = {}

export type Drop = { id: string, min: number, max: number, chance: number }

export type MobDef = {
	id: string,
	name: string,
	w: number,
	h: number,
	hp: number,
	damage: number,
	defense: number,
	speed: number,
	jump: number,
	ai: string,
	color: Color3,
	accent: Color3,
	eyes: boolean,
	knockbackResist: number,
	detect: number,
	attackCd: number,
	drops: { Drop },
	coins: { min: number, max: number },
	layer: string, -- surface | underground | cavern | hell | any
	night: boolean?, -- ليلاً فقط
	biomes: { string }?,
	minDepth: number?,
	weight: number,
	boss: boolean?,
	flee: boolean?, -- يهرب من ضوء النهار
	projectile: string?,
}

local function C(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local defs: { [string]: MobDef } = {}
local list: { MobDef } = {}

local function def(m: MobDef)
	defs[m.id] = m
	table.insert(list, m)
end

def({
	id = "slime", name = "هلامة", w = 1.6, h = 1.2, hp = 30, damage = 7, defense = 0,
	speed = 3.6, jump = 12, ai = "jumper", color = C(96, 150, 226), accent = C(60, 100, 180), eyes = true,
	knockbackResist = 0.1, detect = 18, attackCd = 0.8,
	drops = { { id = "gel", min = 1, max = 3, chance = 1 } },
	coins = { min = 1, max = 4 }, layer = "any", weight = 30,
})

def({
	id = "ice_slime", name = "هلامة ثلجية", w = 1.6, h = 1.2, hp = 42, damage = 10, defense = 2,
	speed = 4.0, jump = 13, ai = "jumper", color = C(170, 220, 245), accent = C(110, 175, 215), eyes = true,
	knockbackResist = 0.15, detect = 18, attackCd = 0.8,
	drops = { { id = "gel", min = 2, max = 4, chance = 1 }, { id = "ice", min = 1, max = 3, chance = 0.5 } },
	coins = { min = 2, max = 6 }, layer = "any", biomes = { "snow" }, weight = 20,
})

def({
	id = "sand_slime", name = "هلامة رملية", w = 1.7, h = 1.2, hp = 38, damage = 9, defense = 1,
	speed = 4.4, jump = 12, ai = "jumper", color = C(220, 200, 140), accent = C(180, 160, 100), eyes = true,
	knockbackResist = 0.1, detect = 18, attackCd = 0.8,
	drops = { { id = "gel", min = 1, max = 3, chance = 1 }, { id = "sand", min = 2, max = 5, chance = 0.6 } },
	coins = { min = 2, max = 5 }, layer = "any", biomes = { "desert" }, weight = 20,
})

def({
	id = "zombie", name = "زومبي", w = 1.5, h = 2.6, hp = 55, damage = 14, defense = 2,
	speed = 4.2, jump = 11, ai = "walker", color = C(96, 132, 88), accent = C(66, 96, 62), eyes = true,
	knockbackResist = 0.25, detect = 24, attackCd = 0.9,
	drops = { { id = "leather", min = 1, max = 2, chance = 0.55 }, { id = "bone", min = 1, max = 1, chance = 0.2 } },
	coins = { min = 3, max = 8 }, layer = "surface", night = true, weight = 34, flee = true,
})

def({
	id = "demon_eye", name = "عين شيطانية", w = 1.4, h = 1.4, hp = 40, damage = 13, defense = 0,
	speed = 6.5, jump = 0, ai = "flyer", color = C(226, 226, 226), accent = C(180, 40, 40), eyes = false,
	knockbackResist = 0.05, detect = 30, attackCd = 0.7,
	drops = { { id = "shadow_scale", min = 1, max = 1, chance = 0.12 } },
	coins = { min = 3, max = 9 }, layer = "surface", night = true, weight = 26, flee = true,
})

def({
	id = "skeleton", name = "هيكل عظمي", w = 1.5, h = 2.6, hp = 70, damage = 18, defense = 5,
	speed = 4.6, jump = 12, ai = "shooter", color = C(226, 222, 206), accent = C(150, 146, 132), eyes = true,
	knockbackResist = 0.3, detect = 26, attackCd = 1.6, projectile = "bone_shot",
	drops = { { id = "bone", min = 1, max = 3, chance = 0.85 }, { id = "iron_ore", min = 1, max = 2, chance = 0.2 } },
	coins = { min = 5, max = 14 }, layer = "underground", weight = 30,
})

def({
	id = "bat", name = "خفاش", w = 1.2, h = 1.0, hp = 28, damage = 11, defense = 1,
	speed = 7.5, jump = 0, ai = "flyer", color = C(78, 66, 84), accent = C(50, 42, 56), eyes = true,
	knockbackResist = 0, detect = 22, attackCd = 0.6,
	drops = { { id = "leather", min = 1, max = 1, chance = 0.35 } },
	coins = { min = 2, max = 7 }, layer = "underground", weight = 28,
})

def({
	id = "spider", name = "عنكبوت", w = 1.8, h = 1.2, hp = 45, damage = 15, defense = 2,
	speed = 6.0, jump = 9, ai = "climber", color = C(58, 50, 66), accent = C(140, 50, 60), eyes = true,
	knockbackResist = 0.1, detect = 22, attackCd = 0.7,
	drops = { { id = "string", min = 1, max = 3, chance = 0.9 }, { id = "cobweb", min = 1, max = 2, chance = 0.4 } },
	coins = { min = 3, max = 9 }, layer = "underground", weight = 22,
})

def({
	id = "cave_wasp", name = "دبور الأدغال", w = 1.3, h = 1.1, hp = 50, damage = 17, defense = 3,
	speed = 8.0, jump = 0, ai = "flyer", color = C(220, 190, 70), accent = C(40, 36, 30), eyes = true,
	knockbackResist = 0.05, detect = 24, attackCd = 0.6,
	drops = { { id = "herb", min = 1, max = 2, chance = 0.5 } },
	coins = { min = 4, max = 11 }, layer = "underground", biomes = { "jungle" }, weight = 18,
})

def({
	id = "stone_golem", name = "غول حجري", w = 2.2, h = 3.2, hp = 180, damage = 28, defense = 12,
	speed = 3.2, jump = 10, ai = "walker", color = C(110, 108, 116), accent = C(70, 68, 76), eyes = true,
	knockbackResist = 0.75, detect = 20, attackCd = 1.4,
	drops = { { id = "stone", min = 6, max = 14, chance = 1 }, { id = "silver_ore", min = 1, max = 3, chance = 0.4 }, { id = "crystal", min = 1, max = 2, chance = 0.25 } },
	coins = { min = 12, max = 30 }, layer = "cavern", minDepth = 300, weight = 14,
})

def({
	id = "lava_imp", name = "عفريت الحمم", w = 1.4, h = 2.0, hp = 140, damage = 32, defense = 10,
	speed = 7.0, jump = 0, ai = "flyer", color = C(214, 90, 54), accent = C(120, 40, 30), eyes = true,
	knockbackResist = 0.4, detect = 28, attackCd = 1.2, projectile = "fireball",
	drops = { { id = "hellstone_ore", min = 1, max = 3, chance = 0.5 }, { id = "soul_fragment", min = 1, max = 1, chance = 0.18 } },
	coins = { min = 15, max = 40 }, layer = "hell", weight = 26,
})

def({
	id = "shadow_crawler", name = "زاحف الظل", w = 1.9, h = 1.6, hp = 160, damage = 30, defense = 9,
	speed = 7.5, jump = 13, ai = "climber", color = C(70, 52, 96), accent = C(150, 110, 210), eyes = true,
	knockbackResist = 0.3, detect = 26, attackCd = 0.8,
	drops = { { id = "shadow_scale", min = 1, max = 3, chance = 0.8 }, { id = "soul_fragment", min = 1, max = 1, chance = 0.25 } },
	coins = { min = 14, max = 34 }, layer = "cavern", minDepth = 340, weight = 16,
})

-- ===== الزعيم =====
def({
	id = "eye_of_depths", name = "عين الأعماق", w = 5.0, h = 5.0, hp = 2600, damage = 34, defense = 10,
	speed = 9.5, jump = 0, ai = "boss", color = C(236, 232, 226), accent = C(180, 40, 48), eyes = false,
	knockbackResist = 1, detect = 200, attackCd = 2.4, projectile = "blood_shot",
	drops = {
		{ id = "soul_fragment", min = 8, max = 16, chance = 1 },
		{ id = "shadow_scale", min = 10, max = 22, chance = 1 },
		{ id = "diamond", min = 2, max = 5, chance = 0.7 },
		{ id = "life_crystal", min = 1, max = 2, chance = 0.5 },
	},
	coins = { min = 300, max = 600 }, layer = "any", weight = 0, boss = true,
})

Mobs.defs = defs
Mobs.list = list

function Mobs.get(id: string): MobDef?
	return defs[id]
end

-- ===== المقذوفات =====
export type ProjectileDef = {
	id: string,
	w: number,
	h: number,
	color: Color3,
	gravity: number,
	life: number,
	damage: number,
	pierce: number,
	trail: string?,
	fromPlayer: boolean?,
}

Mobs.projectiles = {
	arrow = { id = "arrow", w = 0.8, h = 0.18, color = C(200, 180, 150), gravity = 26, life = 4, damage = 0, pierce = 0, fromPlayer = true },
	fire_arrow = { id = "fire_arrow", w = 0.9, h = 0.2, color = C(250, 150, 70), gravity = 24, life = 4, damage = 0, pierce = 0, trail = "fire", fromPlayer = true },
	spark = { id = "spark", w = 0.6, h = 0.6, color = C(140, 210, 255), gravity = 0, life = 1.6, damage = 0, pierce = 1, trail = "spark", fromPlayer = true },
	flame = { id = "flame", w = 0.9, h = 0.9, color = C(255, 140, 60), gravity = 2, life = 1.8, damage = 0, pierce = 2, trail = "fire", fromPlayer = true },
	bone_shot = { id = "bone_shot", w = 0.7, h = 0.3, color = C(226, 222, 206), gravity = 18, life = 5, damage = 0, pierce = 0 },
	fireball = { id = "fireball", w = 1.0, h = 1.0, color = C(250, 120, 50), gravity = 0, life = 4, damage = 0, pierce = 0, trail = "fire" },
	blood_shot = { id = "blood_shot", w = 1.2, h = 1.2, color = C(200, 50, 60), gravity = 0, life = 6, damage = 0, pierce = 0, trail = "blood" },
} :: { [string]: ProjectileDef }

return Mobs
