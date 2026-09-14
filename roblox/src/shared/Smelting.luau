--!strict
--[[
	Smelting — وصفات الفرن ووقوده.

	الفرن ليس وصفة تصنيع عادية: له حالة مستمرة (وقود يحترق، وشريط تقدّم)
	تعيش في العالم حتى وأنت بعيد عنه. لذلك وصفاته منفصلة عن Recipes.luau.
]]

local Items = require(script.Parent.Items)

local Smelting = {}

export type SmeltRecipe = { out: string, n: number, time: number }

-- المُدخل -> الناتج. الزمن بالثواني وقوداً محترقاً.
local recipes: { [string]: SmeltRecipe } = {
	copper_ore = { out = "copper_bar", n = 1, time = 5 },
	iron_ore = { out = "iron_bar", n = 1, time = 6 },
	silver_ore = { out = "silver_bar", n = 1, time = 7 },
	gold_ore = { out = "gold_bar", n = 1, time = 8 },
	mythril_ore = { out = "mythril_bar", n = 1, time = 12 },
	hellstone_ore = { out = "hellstone_bar", n = 1, time = 11 },

	sand = { out = "glass", n = 1, time = 3 },
	stone = { out = "stone_brick", n = 1, time = 3 },
	sandstone = { out = "sand_brick", n = 1, time = 3 },
	ice = { out = "ice_brick", n = 1, time = 3 },
	clay = { out = "brick", n = 1, time = 4 },

	leather = { out = "cooked_meat", n = 1, time = 7 },
	herb = { out = "bread", n = 1, time = 6 },
	mushroom = { out = "cooked_meat", n = 1, time = 7 },
}

-- الوقود: العنصر -> ثواني احتراق
local fuels: { [string]: number } = {
	coal = 60,
	wood = 10,
	plank = 8,
	log = 12,
	sapling = 2,
	cactus = 5,
	hellstone_ore = 90, -- يحترق طويلاً لكنه ثمين
	torch = 3,
}

Smelting.recipes = recipes
Smelting.fuels = fuels

function Smelting.recipeFor(itemId: string?): SmeltRecipe?
	if not itemId then return nil end
	return recipes[itemId]
end

function Smelting.fuelValue(itemId: string?): number
	if not itemId then return 0 end
	return fuels[itemId] or 0
end

function Smelting.isFuel(itemId: string?): boolean
	return Smelting.fuelValue(itemId) > 0
end

-- قائمة مرتّبة للعرض في الواجهة
function Smelting.list(): { { input: string, out: string, n: number, time: number } }
	local out = {}
	for input, recipe in recipes do
		if Items.get(input) and Items.get(recipe.out) then
			table.insert(out, { input = input, out = recipe.out, n = recipe.n, time = recipe.time })
		end
	end
	table.sort(out, function(a, b)
		if a.time ~= b.time then return a.time < b.time end
		return a.input < b.input
	end)
	return out
end

return Smelting
