--!strict
--[[ Buffs — التعزيزات والتأثيرات المؤقتة. ]]

local Buffs = {}

export type BuffDef = {
	id: string,
	name: string,
	color: Color3,
	good: boolean,
	speed: number?, -- مضاعف سرعة المشي
	jump: number?,
	defense: number?,
	regen: number?, -- حياة/ثانية
	light: number?, -- توهج حول اللاعب
	dps: number?, -- ضرر مستمر
	mining: number?, -- مضاعف سرعة التعدين
	blockPotion: boolean?,
}

local defs: { [string]: BuffDef } = {
	swift = { id = "swift", name = "سرعة", color = Color3.fromRGB(120, 226, 140), good = true, speed = 1.28, jump = 1.08 },
	iron_skin = { id = "iron_skin", name = "جلد حديدي", color = Color3.fromRGB(180, 180, 200), good = true, defense = 8 },
	shine = { id = "shine", name = "توهج", color = Color3.fromRGB(250, 240, 160), good = true, light = 9 },
	regeneration = { id = "regeneration", name = "تجدد", color = Color3.fromRGB(240, 120, 160), good = true, regen = 2.5 },
	haste = { id = "haste", name = "خفة", color = Color3.fromRGB(240, 200, 120), good = true, mining = 1.35 },
	potion_sickness = { id = "potion_sickness", name = "إجهاد الجرعات", color = Color3.fromRGB(150, 120, 160), good = false, blockPotion = true },
	burn = { id = "burn", name = "احتراق", color = Color3.fromRGB(250, 120, 60), good = false, dps = 4 },
	slow = { id = "slow", name = "تباطؤ", color = Color3.fromRGB(120, 140, 170), good = false, speed = 0.6 },
	poison = { id = "poison", name = "تسمم", color = Color3.fromRGB(140, 200, 90), good = false, dps = 2.5 },
	well_fed = { id = "well_fed", name = "شبع", color = Color3.fromRGB(230, 180, 120), good = true, regen = 0.8, speed = 1.05 },
}

Buffs.defs = defs

function Buffs.get(id: string): BuffDef?
	return defs[id]
end

-- يجمع تأثيرات مجموعة تعزيزات نشطة
export type Aggregate = {
	speed: number,
	jump: number,
	defense: number,
	regen: number,
	light: number,
	dps: number,
	mining: number,
	blockPotion: boolean,
}

function Buffs.aggregate(active: { [string]: number }): Aggregate
	local agg: Aggregate = {
		speed = 1, jump = 1, defense = 0, regen = 0,
		light = 0, dps = 0, mining = 1, blockPotion = false,
	}
	for id, remaining in active do
		if remaining > 0 then
			local buff = defs[id]
			if buff then
				if buff.speed then agg.speed *= buff.speed end
				if buff.jump then agg.jump *= buff.jump end
				if buff.defense then agg.defense += buff.defense end
				if buff.regen then agg.regen += buff.regen end
				if buff.light then agg.light = math.max(agg.light, buff.light) end
				if buff.dps then agg.dps += buff.dps end
				if buff.mining then agg.mining *= buff.mining end
				if buff.blockPotion then agg.blockPotion = true end
			end
		end
	end
	return agg
end

return Buffs
