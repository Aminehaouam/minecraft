--!strict
--[[
	Recipes — وصفات التصنيع.
	station = nil يعني التصنيع باليد من أي مكان.
	وصفات الفرن تستهلك الفحم كوقود ضمن المكوّنات (تبسيط مقصود بدل محاكاة فرن بحالة).
]]

local Recipes = {}

export type Stack = { id: string, n: number }
export type Recipe = {
	key: string,
	out: Stack,
	ins: { Stack },
	station: string?,
}

local list: { Recipe } = {}

local function R(out: string, n: number, ins: { Stack }, station: string?)
	table.insert(list, {
		key = out .. "#" .. tostring(#list + 1),
		out = { id = out, n = n },
		ins = ins,
		station = station,
	})
end

-- ===== باليد =====
R("plank", 4, { { id = "wood", n = 1 } })
R("workbench", 1, { { id = "plank", n = 8 } })
R("torch", 4, { { id = "wood", n = 1 }, { id = "coal", n = 1 } })
R("platform", 4, { { id = "plank", n = 1 } })

-- ===== طاولة العمل =====
R("furnace", 1, { { id = "stone", n = 20 }, { id = "wood", n = 4 } }, "workbench")
R("chest", 1, { { id = "plank", n = 8 }, { id = "iron_bar", n = 1 } }, "workbench")
R("ladder", 6, { { id = "plank", n = 2 } }, "workbench")
R("lantern", 1, { { id = "iron_bar", n = 1 }, { id = "torch", n = 1 } }, "workbench")
R("anvil", 1, { { id = "iron_bar", n = 5 } }, "workbench")
R("alchemy_table", 1, { { id = "plank", n = 10 }, { id = "crystal", n = 3 }, { id = "glow_dust", n = 2 } }, "workbench")

R("wood_pickaxe", 1, { { id = "wood", n = 3 }, { id = "plank", n = 5 } }, "workbench")
R("wood_axe", 1, { { id = "wood", n = 3 }, { id = "plank", n = 4 } }, "workbench")
R("wood_sword", 1, { { id = "wood", n = 2 }, { id = "plank", n = 5 } }, "workbench")
R("wood_bow", 1, { { id = "wood", n = 8 }, { id = "string", n = 3 } }, "workbench")
R("stone_pickaxe", 1, { { id = "stone", n = 12 }, { id = "wood", n = 3 } }, "workbench")
R("stone_axe", 1, { { id = "stone", n = 10 }, { id = "wood", n = 3 } }, "workbench")
R("stone_sword", 1, { { id = "stone", n = 10 }, { id = "wood", n = 2 } }, "workbench")
R("hammer", 1, { { id = "stone", n = 14 }, { id = "wood", n = 4 } }, "workbench")
R("arrow", 10, { { id = "wood", n = 1 }, { id = "stone", n = 1 }, { id = "string", n = 1 } }, "workbench")

R("leather_helm", 1, { { id = "leather", n = 5 } }, "workbench")
R("leather_chest", 1, { { id = "leather", n = 8 } }, "workbench")
R("leather_boots", 1, { { id = "leather", n = 5 } }, "workbench")

-- ===== الفرن (يستهلك فحماً) =====
R("copper_bar", 1, { { id = "copper_ore", n = 3 }, { id = "coal", n = 1 } }, "furnace")
R("iron_bar", 1, { { id = "iron_ore", n = 3 }, { id = "coal", n = 1 } }, "furnace")
R("silver_bar", 1, { { id = "silver_ore", n = 3 }, { id = "coal", n = 1 } }, "furnace")
R("gold_bar", 1, { { id = "gold_ore", n = 4 }, { id = "coal", n = 1 } }, "furnace")
R("mythril_bar", 1, { { id = "mythril_ore", n = 4 }, { id = "coal", n = 2 } }, "furnace")
R("hellstone_bar", 1, { { id = "hellstone_ore", n = 3 }, { id = "obsidian", n = 1 }, { id = "coal", n = 2 } }, "furnace")
R("glass", 2, { { id = "sand", n = 2 }, { id = "coal", n = 1 } }, "furnace")
R("stone_brick", 4, { { id = "stone", n = 4 }, { id = "coal", n = 1 } }, "furnace")
R("sand_brick", 4, { { id = "sandstone", n = 4 }, { id = "coal", n = 1 } }, "furnace")
R("ice_brick", 4, { { id = "ice", n = 4 } }, "furnace")
R("hellstone_brick", 4, { { id = "hellstone_ore", n = 2 }, { id = "ash", n = 2 } }, "furnace")
R("cooked_meat", 1, { { id = "leather", n = 1 }, { id = "coal", n = 1 } }, "furnace")
R("bread", 1, { { id = "herb", n = 3 }, { id = "coal", n = 1 } }, "furnace")

-- ===== السندان =====
R("copper_pickaxe", 1, { { id = "copper_bar", n = 8 }, { id = "wood", n = 3 } }, "anvil")
R("copper_sword", 1, { { id = "copper_bar", n = 7 }, { id = "wood", n = 2 } }, "anvil")
R("iron_pickaxe", 1, { { id = "iron_bar", n = 10 }, { id = "wood", n = 3 } }, "anvil")
R("iron_axe", 1, { { id = "iron_bar", n = 9 }, { id = "wood", n = 3 } }, "anvil")
R("iron_sword", 1, { { id = "iron_bar", n = 9 }, { id = "wood", n = 2 } }, "anvil")
R("iron_bow", 1, { { id = "iron_bar", n = 8 }, { id = "string", n = 4 } }, "anvil")
R("silver_sword", 1, { { id = "silver_bar", n = 10 }, { id = "wood", n = 2 } }, "anvil")
R("gold_pickaxe", 1, { { id = "gold_bar", n = 12 }, { id = "wood", n = 3 } }, "anvil")
R("gold_sword", 1, { { id = "gold_bar", n = 11 }, { id = "wood", n = 2 } }, "anvil")
R("diamond_pickaxe", 1, { { id = "diamond", n = 8 }, { id = "gold_bar", n = 4 } }, "anvil")
R("diamond_axe", 1, { { id = "diamond", n = 7 }, { id = "gold_bar", n = 3 } }, "anvil")
R("diamond_sword", 1, { { id = "diamond", n = 9 }, { id = "gold_bar", n = 3 } }, "anvil")
R("mythril_pickaxe", 1, { { id = "mythril_bar", n = 14 }, { id = "diamond", n = 4 } }, "anvil")
R("mythril_blade", 1, { { id = "mythril_bar", n = 16 }, { id = "soul_fragment", n = 3 } }, "anvil")
R("night_edge", 1, { { id = "mythril_blade", n = 1 }, { id = "hellstone_bar", n = 12 }, { id = "shadow_scale", n = 8 }, { id = "soul_fragment", n = 10 } }, "anvil")
R("hell_bow", 1, { { id = "hellstone_bar", n = 10 }, { id = "string", n = 5 } }, "anvil")
R("fire_arrow", 20, { { id = "arrow", n = 20 }, { id = "hellstone_ore", n = 1 } }, "anvil")

R("copper_helm", 1, { { id = "copper_bar", n = 10 } }, "anvil")
R("copper_chest", 1, { { id = "copper_bar", n = 14 } }, "anvil")
R("copper_boots", 1, { { id = "copper_bar", n = 10 } }, "anvil")
R("iron_helm", 1, { { id = "iron_bar", n = 12 } }, "anvil")
R("iron_chest", 1, { { id = "iron_bar", n = 18 } }, "anvil")
R("iron_boots", 1, { { id = "iron_bar", n = 12 } }, "anvil")
R("diamond_helm", 1, { { id = "diamond", n = 10 }, { id = "iron_bar", n = 6 } }, "anvil")
R("diamond_chest", 1, { { id = "diamond", n = 15 }, { id = "iron_bar", n = 8 } }, "anvil")
R("diamond_boots", 1, { { id = "diamond", n = 10 }, { id = "iron_bar", n = 6 } }, "anvil")
R("mythril_helm", 1, { { id = "mythril_bar", n = 14 } }, "anvil")
R("mythril_chest", 1, { { id = "mythril_bar", n = 20 } }, "anvil")
R("mythril_boots", 1, { { id = "mythril_bar", n = 14 } }, "anvil")

R("eye_totem", 1, { { id = "bone", n = 12 }, { id = "gel", n = 20 }, { id = "coal", n = 6 } }, "anvil")

-- ===== طاولة الخيمياء =====
R("health_potion", 2, { { id = "herb", n = 2 }, { id = "mushroom", n = 1 }, { id = "glass", n = 1 } }, "alchemy")
R("mana_potion", 2, { { id = "crystal", n = 1 }, { id = "herb", n = 1 }, { id = "glass", n = 1 } }, "alchemy")
R("swift_potion", 1, { { id = "herb", n = 3 }, { id = "gel", n = 4 }, { id = "glass", n = 1 } }, "alchemy")
R("iron_skin_potion", 1, { { id = "iron_bar", n = 2 }, { id = "herb", n = 2 }, { id = "glass", n = 1 } }, "alchemy")
R("shine_potion", 1, { { id = "glow_dust", n = 3 }, { id = "glass", n = 1 } }, "alchemy")
R("spark_staff", 1, { { id = "crystal", n = 12 }, { id = "silver_bar", n = 6 }, { id = "wood", n = 8 } }, "alchemy")
R("flame_staff", 1, { { id = "spark_staff", n = 1 }, { id = "hellstone_bar", n = 8 }, { id = "soul_fragment", n = 4 } }, "alchemy")
R("magic_mirror", 1, { { id = "glass", n = 6 }, { id = "silver_bar", n = 6 }, { id = "crystal", n = 4 } }, "alchemy")
R("recall_stone", 3, { { id = "stone", n = 10 }, { id = "glow_dust", n = 1 } }, "alchemy")
R("mana_crystal", 1, { { id = "crystal", n = 8 }, { id = "glow_dust", n = 4 } }, "alchemy")

Recipes.list = list

local byKey: { [string]: Recipe } = {}
for _, r in list do
	byKey[r.key] = r
end
Recipes.byKey = byKey

-- الوصفات المتاحة لمجموعة محطات مفتوحة
function Recipes.available(stations: { [string]: boolean }): { Recipe }
	local out = {}
	for _, r in list do
		if r.station == nil or stations[r.station] then
			table.insert(out, r)
		end
	end
	return out
end

return Recipes
