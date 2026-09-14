-- ===== إطار اختبار مصغّر =====
local passed, failed = 0, 0
local failures = {}

local function ok(condition: boolean, label: string)
	if condition then
		passed += 1
	else
		failed += 1
		table.insert(failures, label)
	end
end

local function eq(a: any, b: any, label: string)
	if a == b then
		passed += 1
	else
		failed += 1
		table.insert(failures, string.format("%s (توقعنا %s، وجدنا %s)", label, tostring(b), tostring(a)))
	end
end

local function near(a: number, b: number, tolerance: number, label: string)
	if math.abs(a - b) <= tolerance then
		passed += 1
	else
		failed += 1
		table.insert(failures, string.format("%s (توقعنا ~%.3f، وجدنا %.3f)", label, b, a))
	end
end

local Util = __req("Util")
local Noise = __req("Noise")
local Config = __req("Config")
local Blocks = __req("Blocks")
local Items = __req("Items")
local Recipes = __req("Recipes")
local Chunk = __req("Chunk")
local WorldGen = __req("WorldGen")
local World = __req("World")
local Physics = __req("Physics")
local Mining = __req("Mining")
local Inventory = __req("Inventory")
local Mobs = __req("Mobs")
local Smelting = __req("Smelting")
local Upgrades = __req("Upgrades")

local B = Blocks.ID
local SEED = 123456

-- ===== Util =====
eq(Util.clamp(5, 0, 3), 3, "clamp يقصّ الحد الأعلى")
eq(Util.clamp(-2, 0, 3), 0, "clamp يقصّ الحد الأدنى")
eq(Util.sign(-4), -1, "sign سالب")
eq(Util.approach(0, 10, 3), 3, "approach يتقدّم بخطوة")
eq(Util.approach(9, 10, 3), 10, "approach لا يتجاوز الهدف")
eq(Util.hash2(5, 9, SEED), Util.hash2(5, 9, SEED), "hash2 حتمي")
ok(Util.hash2(5, 9, SEED) ~= Util.hash2(9, 5, SEED), "hash2 غير متماثل")
do
	local value = Util.rand2(3, 7, SEED)
	ok(value >= 0 and value < 1, "rand2 داخل [0,1)")
end

-- ===== Noise =====
do
	local a = Noise.fbm2(12.5, 8.25, SEED, 4, 0.02, 0.5)
	local b = Noise.fbm2(12.5, 8.25, SEED, 4, 0.02, 0.5)
	eq(a, b, "الضوضاء حتمية")
	ok(a >= 0 and a <= 1, "الضوضاء داخل [0,1]")
	local ridged = Noise.ridged2(4, 9, SEED, 2, 0.02)
	ok(ridged >= 0 and ridged <= 1, "ridged داخل [0,1]")
	local cell = Noise.cell2(10, 20, SEED, 8)
	ok(cell >= 0, "cell موجبة")
end

-- ===== سلامة السجلات =====
do
	local missingDrop = 0
	local badBlock = 0
	for id, block in Blocks.defs do
		if block.drop and not Items.fromBlock(block.drop) then
			missingDrop += 1
		end
		if block.id ~= id then badBlock += 1 end
	end
	eq(missingDrop, 0, "كل ما تُسقطه البلاطات له عنصر مقابل")
	eq(badBlock, 0, "معرّفات البلاطات متسقة مع مفاتيحها")

	local badPlace = 0
	for id, item in Items.defs do
		if item.id ~= id then badPlace += 1 end
		if item.place and not Blocks.defs[item.place] then badPlace += 1 end
		if item.rarity < 0 or item.rarity > 5 then badPlace += 1 end
		if item.max < 1 then badPlace += 1 end
	end
	eq(badPlace, 0, "كل العناصر صالحة (معرّف، بلاطة، ندرة، تكديس)")
end

-- ===== الوصفات =====
do
	local unknown = 0
	local badStation = 0
	local stations = { workbench = true, furnace = true, anvil = true, alchemy = true }
	for _, recipe in Recipes.list do
		if not Items.get(recipe.out.id) then unknown += 1 end
		if recipe.station and not stations[recipe.station] then badStation += 1 end
		for _, ingredient in recipe.ins do
			if not Items.get(ingredient.id) then
				unknown += 1
			end
			if ingredient.n <= 0 then unknown += 1 end
		end
	end
	eq(unknown, 0, "كل مكوّنات ونواتج الوصفات معرّفة")
	eq(badStation, 0, "كل الوصفات تشير إلى محطات معروفة")

	local handOnly = Recipes.available({})
	ok(#handOnly > 0, "توجد وصفات تُصنع باليد")
	local withBench = Recipes.available({ workbench = true })
	ok(#withBench > #handOnly, "طاولة العمل تفتح وصفات إضافية")
end

-- ===== الوحوش =====
do
	local bad = 0
	for id, def in Mobs.defs do
		if def.id ~= id then bad += 1 end
		if def.projectile and not Mobs.projectiles[def.projectile] then bad += 1 end
		for _, drop in def.drops do
			if not Items.get(drop.id) then bad += 1 end
			if drop.min > drop.max then bad += 1 end
		end
		if def.hp <= 0 or def.w <= 0 or def.h <= 0 then bad += 1 end
	end
	eq(bad, 0, "تعريفات الوحوش سليمة")
end

-- ===== Chunk =====
do
	local data = Chunk.create()
	Chunk.setFg(data, 10, 4242)
	Chunk.setBg(data, 10, 77)
	eq(Chunk.getFg(data, 10), 4242, "قراءة/كتابة الطبقة الأمامية")
	eq(Chunk.getBg(data, 10), 77, "قراءة/كتابة الجدار")
	eq(Chunk.getFg(data, 11), 0, "الخانات الأخرى صفر")
	local cx, cy = Chunk.parseKey(Chunk.keyOf(-3, 7))
	eq(cx, -3, "parseKey يعيد cx")
	eq(cy, 7, "parseKey يعيد cy")
end

-- ===== حتمية التوليد =====
do
	local a = WorldGen.generateChunk(SEED, 20, 5)
	local b = WorldGen.generateChunk(SEED, 20, 5)
	local same = true
	for i = 0, Chunk.AREA - 1 do
		if Chunk.getFg(a, i) ~= Chunk.getFg(b, i) or Chunk.getBg(a, i) ~= Chunk.getBg(b, i) then
			same = false
			break
		end
	end
	ok(same, "نفس البذرة تعطي نفس القطعة بالضبط")

	local other = WorldGen.generateChunk(SEED + 1, 20, 5)
	local differs = false
	for i = 0, Chunk.AREA - 1 do
		if Chunk.getFg(a, i) ~= Chunk.getFg(other, i) then
			differs = true
			break
		end
	end
	ok(differs, "بذرة مختلفة تعطي عالماً مختلفاً")
end

-- ===== منطق العالم المولّد =====
do
	local world = World.new(SEED)
	local spawnX, spawnY = WorldGen.spawnPoint(SEED)
	local column = math.floor(spawnX)
	local surface = WorldGen.surfaceHeight(SEED, column)

	ok(Blocks.isSolid(World.fg(world, column, surface)), "بلاطة السطح صلبة")
	ok(not Blocks.isSolid(World.fg(world, column, surface - 3)), "الهواء فوق السطح")
	eq(World.fg(world, column, Config.WORLD_H - 1), B.BEDROCK, "صخر الأساس في القاع")
	ok(spawnY < surface, "نقطة الظهور فوق الأرض")

	-- إحصاء عيّنة من الطبقات العميقة
	local ores, caves, stone = 0, 0, 0
	for x = column - 40, column + 40 do
		for y = 320, 360 do
			local id = World.fg(world, x, y)
			if id == B.AIR then
				caves += 1
			elseif id == B.STONE then
				stone += 1
			elseif id == B.COAL_ORE or id == B.IRON_ORE or id == B.GOLD_ORE
				or id == B.SILVER_ORE or id == B.DIAMOND_ORE or id == B.COPPER_ORE
				or id == B.MYTHRIL_ORE then
				ores += 1
			end
		end
	end
	ok(stone > 500, "الطبقة العميقة حجرية في معظمها")
	ok(caves > 20, "توجد كهوف تحت الأرض")
	ok(ores > 10, "توجد خامات تحت الأرض")

	-- الجحيم
	local lava = 0
	for x = column - 20, column + 20 do
		for y = Config.HELL_Y + 20, Config.HELL_Y + 40 do
			if World.fg(world, x, y) == B.LAVA then lava += 1 end
		end
	end
	ok(lava > 0, "توجد حمم في طبقة الجحيم")

	-- المناطق الحيوية تتغيّر عبر العالم
	local seen = {}
	for x = 0, Config.WORLD_W - 1, 37 do
		seen[WorldGen.biomeAt(SEED, x)] = true
	end
	local biomeCount = 0
	for _ in seen do biomeCount += 1 end
	ok(biomeCount >= 3, "العالم يحوي عدة مناطق حيوية")
end

-- ===== التعديلات والمزامنة =====
do
	local server = World.new(SEED)
	local client = World.new(SEED)
	local x, y = 300, 200

	local original = World.fg(server, x, y)
	World.set(server, x, y, B.PLANK, B.DIRT)
	eq(World.fg(server, x, y), B.PLANK, "الخادم طبّق التعديل")
	ok(World.fg(client, x, y) == original, "العميل لم يتأثر قبل المزامنة")

	local cx, cy = World.chunkOf(x, y)
	local flat = World.encodeDiff(server, cx, cy)
	ok(flat ~= nil and #flat == 3, "ترميز التعديل يعطي ثلاثة أرقام لكل بلاطة")
	World.applyEncodedDiff(client, cx, cy, flat)
	eq(World.fg(client, x, y), B.PLANK, "العميل طبّق التعديل بعد المزامنة")
	eq(World.bg(client, x, y), B.DIRT, "الجدار تزامن أيضاً")

	-- التعديل يبقى بعد تفريغ القطعة وإعادة توليدها
	World.unload(client, cx, cy)
	eq(World.fg(client, x, y), B.PLANK, "التعديل ثابت بعد إعادة التوليد")
end

-- ===== surfaceY =====
do
	local world = World.new(SEED)
	local column = 700
	local surface = World.surfaceY(world, column)
	ok(Blocks.opacity(World.fg(world, column, surface)) >= 15, "surfaceY تشير إلى بلاطة معتمة")
	ok(Blocks.opacity(World.fg(world, column, surface - 1)) < 15, "ما فوق surfaceY شفاف")

	-- البناء فوق السطح يرفع القيمة
	World.set(world, column, surface - 6, B.STONE, B.AIR)
	local raised = World.surfaceY(world, column)
	eq(raised, surface - 6, "surfaceY تتبع البناء الجديد")
end

-- ===== الفيزياء =====
local function makeTestWorld()
	local world = World.new(SEED)
	-- افرغ منطقة اختبار في السماء ثم ابنِ أرضية
	for x = 100, 140 do
		for y = 20, 40 do
			World.set(world, x, y, B.AIR, B.AIR)
		end
		World.set(world, x, 40, B.STONE, B.AIR)
	end
	return world
end

do
	local world = makeTestWorld()
	local body = Physics.newBody(110, 25, 1.6, 2.8)
	for _ = 1, 240 do
		Physics.step(world, body, 1 / 60)
	end
	ok(body.onGround, "الجسم هبط على الأرض")
	near(body.y, 40 - 1.4 - 0.001, 0.05, "ارتفاع الوقوف صحيح")
	near(body.vy, 0, 0.001, "سرعة الهبوط صفر بعد الاستقرار")
end

do
	-- اختبار الاختراق: سرعة عالية جداً مع خطوة زمنية كبيرة
	local world = makeTestWorld()
	local body = Physics.newBody(112, 25, 1.6, 2.8)
	body.vy = 46
	for _ = 1, 10 do
		Physics.step(world, body, 1 / 20)
	end
	ok(body.y < 41, "جسم سريع لا يخترق أرضية بسمك بلاطة")
	ok(body.onGround, "الجسم السريع توقف على الأرض")
end

do
	-- الصعود التلقائي فوق حافة بارتفاع بلاطة
	local world = makeTestWorld()
	World.set(world, 120, 39, B.STONE, B.AIR)
	local body = Physics.newBody(116, 40 - 1.4 - 0.01, 1.6, 2.8)
	body.onGround = true
	for _ = 1, 120 do
		body.vx = 9
		Physics.step(world, body, 1 / 60)
	end
	ok(body.x > 121, "اللاعب صعد الحافة وواصل المشي")
end

do
	-- المنصات: تُعبر من الأسفل ويُوقف عليها من الأعلى
	local world = makeTestWorld()
	for x = 104, 112 do
		World.set(world, x, 32, B.PLATFORM, B.AIR)
	end

	local rising = Physics.newBody(108, 35, 1.6, 2.8)
	rising.vy = -26
	local highest = rising.y
	for _ = 1, 40 do
		Physics.step(world, rising, 1 / 60)
		highest = math.min(highest, rising.y)
	end
	ok(highest < 31.5, "الجسم عبر المنصة من الأسفل")

	local falling = Physics.newBody(108, 26, 1.6, 2.8)
	for _ = 1, 120 do
		Physics.step(world, falling, 1 / 60)
	end
	near(falling.y, 32 - 1.4 - 0.001, 0.06, "الجسم وقف فوق المنصة")
end

do
	-- خط الرؤية
	local world = makeTestWorld()
	ok(Physics.lineOfSight(world, 105, 30, 115, 30), "خط رؤية مفتوح عبر الهواء")
	ok(not Physics.lineOfSight(world, 105, 30, 115, 45), "الصخر يقطع خط الرؤية")
end

-- ===== التعدين =====
do
	eq(Mining.breakTime(B.AIR, "wood_pickaxe", 1), nil, "الهواء لا يُكسر")
	eq(Mining.breakTime(B.BEDROCK, "mythril_pickaxe", 1), nil, "صخر الأساس لا يُكسر")
	ok(Mining.breakTime(B.STONE, "wood_pickaxe", 1) ~= nil, "المعول الخشبي يكسر الحجر")
	eq(Mining.breakTime(B.MYTHRIL_ORE, "wood_pickaxe", 1), nil, "الميثريل يحتاج معولاً أقوى")
	ok(Mining.breakTime(B.MYTHRIL_ORE, "mythril_pickaxe", 1) ~= nil, "معول الميثريل يكسر الميثريل")

	local wood = Mining.breakTime(B.STONE, "wood_pickaxe", 1) :: number
	local diamond = Mining.breakTime(B.STONE, "diamond_pickaxe", 1) :: number
	ok(diamond < wood, "المعول الأفضل أسرع")

	local hand = Mining.breakTime(B.LOG, nil, 1) :: number
	local axe = Mining.breakTime(B.LOG, "iron_axe", 1) :: number
	ok(axe < hand, "الفأس أسرع من اليد على الخشب")

	local hasted = Mining.breakTime(B.STONE, "wood_pickaxe", 1.35) :: number
	ok(hasted < wood, "تعزيز الخفة يسرّع التعدين")
end

-- ===== المخزون =====
do
	local slots = Inventory.new()
	eq(Inventory.add(slots, "stone", 150), 0, "إضافة 150 حجراً تنجح")
	eq(Inventory.count(slots, "stone"), 150, "العدّ صحيح")

	-- التكديس يحترم الحد الأقصى
	eq(Inventory.add(slots, "wood_sword", 1), 0, "إضافة سيف")
	eq(Inventory.add(slots, "wood_sword", 1), 0, "السيوف لا تتكدس فتأخذ خانة أخرى")
	eq(Inventory.count(slots, "wood_sword"), 2, "سيفان في خانتين")

	ok(Inventory.remove(slots, "stone", 50), "إزالة 50 حجراً")
	eq(Inventory.count(slots, "stone"), 100, "بقي 100 حجر")
	ok(not Inventory.remove(slots, "stone", 500), "لا يمكن إزالة أكثر من الموجود")
	eq(Inventory.count(slots, "stone"), 100, "الإزالة الفاشلة لا تغيّر شيئاً")

	-- التصنيع
	local craftSlots = Inventory.new()
	Inventory.add(craftSlots, "wood", 4)
	local plankRecipe = nil
	for _, recipe in Recipes.list do
		if recipe.out.id == "plank" then plankRecipe = recipe break end
	end
	ok(plankRecipe ~= nil, "وصفة الألواح موجودة")
	ok(Inventory.canCraft(craftSlots, plankRecipe), "يمكن تصنيع الألواح")
	ok(Inventory.craft(craftSlots, plankRecipe), "التصنيع نجح")
	eq(Inventory.count(craftSlots, "wood"), 3, "استُهلك خشب واحد")
	eq(Inventory.count(craftSlots, "plank"), 4, "أُنتجت 4 ألواح")

	local empty = Inventory.new()
	ok(not Inventory.canCraft(empty, plankRecipe), "لا تصنيع بلا مواد")

	-- التبديل والدمج
	local swapSlots = Inventory.new()
	swapSlots[1] = { id = "dirt", n = 10 }
	swapSlots[2] = { id = "dirt", n = 5 }
	Inventory.swap(swapSlots, 1, 2)
	eq(swapSlots[2].n, 15, "الأكوام المتطابقة تندمج")
	eq(swapSlots[1], nil, "الخانة المصدر فرغت")

	swapSlots[1] = { id = "stone", n = 3 }
	Inventory.swap(swapSlots, 1, 2)
	eq(swapSlots[1].id, "dirt", "التبديل بين نوعين مختلفين")
	eq(swapSlots[2].id, "stone", "التبديل عكسي صحيح")

	-- الحفظ والاسترجاع
	local saveSlots = Inventory.new()
	Inventory.add(saveSlots, "iron_bar", 12)
	Inventory.add(saveSlots, "torch", 30)
	local restored = Inventory.deserialize(Inventory.serialize(saveSlots))
	eq(Inventory.count(restored, "iron_bar"), 12, "الاسترجاع يحفظ السبائك")
	eq(Inventory.count(restored, "torch"), 30, "الاسترجاع يحفظ المشاعل")

	-- البيانات التالفة لا تُسقط اللعبة
	local junk = Inventory.deserialize({ { 1, "عنصر_غير_موجود", 5 }, { 999, "stone", 1 }, "نص", { 2, "stone", -3 } })
	eq(Inventory.count(junk, "stone"), 0, "البيانات التالفة تُتجاهل بأمان")

	-- المساحة المتاحة
	local full = Inventory.new()
	for i = 1, Config.INV_SLOTS do
		full[i] = { id = "stone", n = 999 }
	end
	ok(not Inventory.hasRoom(full, "dirt", 1), "المخزون الممتلئ لا يتسع")
	ok(Inventory.hasRoom(full, "stone", 0), "لا حاجة لمساحة لكمية صفر")
end


-- ===== شجرة التقدّم: هل كل شيء قابل للوصول؟ =====
do
	-- مواد أولية تُجمع مباشرة من العالم أو تسقط من الوحوش
	local obtainable: { [string]: boolean } = {}
	for _, id in {
		"wood", "stone", "dirt", "sand", "sandstone", "clay", "gravel", "snow", "ice",
		"mud", "grass", "jungle_grass", "ash", "leaves", "sapling", "coal", "copper_ore",
		"iron_ore", "silver_ore", "gold_ore", "diamond", "mythril_ore", "hellstone_ore",
		"obsidian", "crystal", "glow_mushroom_block", "mushroom_block", "cactus", "cobweb",
		"string", "leather", "bone", "gel", "herb", "glow_dust", "shadow_scale",
		"soul_fragment", "coin", "log", "mushroom", "apple", "life_crystal",
	} do
		ok(Items.get(id) ~= nil, "المادة الأولية موجودة: " .. id)
		obtainable[id] = true
	end

	-- طبّق الوصفات *والصهر* مراراً حتى يستقر ما يمكن صنعه
	for _ = 1, 12 do
		for input, smelt in Smelting.recipes do
			if obtainable[input] then obtainable[smelt.out] = true end
		end
		for _, recipe in Recipes.list do
			local ready = true
			for _, ingredient in recipe.ins do
				if not obtainable[ingredient.id] then
					ready = false
					break
				end
			end
			if ready then obtainable[recipe.out.id] = true end
		end
	end

	-- كل ما له وصفة أو صهر يجب أن يكون قابلاً للوصول
	local unreachable = {}
	for _, recipe in Recipes.list do
		if not obtainable[recipe.out.id] then
			table.insert(unreachable, recipe.out.id)
		end
	end
	for _, smelt in Smelting.recipes do
		if not obtainable[smelt.out] then
			table.insert(unreachable, smelt.out)
		end
	end
	eq(#unreachable, 0, "كل عنصر مُصنَّع أو مصهور قابل للوصول: " .. table.concat(unreachable, ", "))

	-- أهم عناصر نهاية اللعبة
	for _, id in { "night_edge", "mythril_chest", "flame_staff", "hell_bow", "magic_mirror",
		"eye_totem", "enchant_table", "upgrade_core", "magic_essence", "hellstone_brick" } do
		ok(obtainable[id] == true, "عنصر نهاية اللعبة قابل للوصول: " .. id)
	end
end

-- ===== توازن التقدّم =====
do
	local function damageOf(id: string): number
		local item = Items.get(id)
		return (item and item.damage) or 0
	end
	ok(damageOf("wood_sword") < damageOf("iron_sword"), "السيف الحديدي أقوى من الخشبي")
	ok(damageOf("iron_sword") < damageOf("diamond_sword"), "السيف الألماسي أقوى من الحديدي")
	ok(damageOf("diamond_sword") < damageOf("night_edge"), "حدّ الليل أقوى سيف")

	local function pickOf(id: string): number
		local item = Items.get(id)
		return (item and item.pick) or 0
	end
	ok(pickOf("wood_pickaxe") < pickOf("iron_pickaxe"), "تدرّج قوة المعاول")
	ok(pickOf("iron_pickaxe") < pickOf("mythril_pickaxe"), "معول الميثريل الأقوى")

	-- كل خام له معول يستطيع كسره
	local ores = { B.COAL_ORE, B.COPPER_ORE, B.IRON_ORE, B.SILVER_ORE, B.GOLD_ORE,
		B.DIAMOND_ORE, B.MYTHRIL_ORE, B.HELLSTONE_ORE, B.OBSIDIAN }
	local unbreakable = 0
	for _, ore in ores do
		if Mining.breakTime(ore, "mythril_pickaxe", 1) == nil then unbreakable += 1 end
	end
	eq(unbreakable, 0, "معول الميثريل يكسر كل الخامات")
end

-- ===== الأداء: زمن توليد القطعة =====
do
	local start = os.clock()
	local samples = 12
	for i = 1, samples do
		WorldGen.generateChunk(SEED + i, 30 + i, 6)
	end
	local perChunk = (os.clock() - start) / samples * 1000
	print(string.format("  متوسط زمن توليد القطعة: %.2f مللي ثانية", perChunk))
	ok(perChunk < 60, string.format("توليد القطعة سريع بما يكفي (%.2f مللي ثانية)", perChunk))
end


-- ===== الصهر =====
do
	local bad = 0
	for input, recipe in Smelting.recipes do
		if not Items.get(input) then bad += 1 end
		if not Items.get(recipe.out) then bad += 1 end
		if recipe.time <= 0 or recipe.n <= 0 then bad += 1 end
	end
	eq(bad, 0, "كل وصفات الصهر تشير إلى عناصر موجودة")

	local badFuel = 0
	for id, value in Smelting.fuels do
		if not Items.get(id) then badFuel += 1 end
		if value <= 0 then badFuel += 1 end
	end
	eq(badFuel, 0, "كل أنواع الوقود صالحة")

	ok(Smelting.recipeFor("iron_ore") ~= nil, "خام الحديد يُصهر")
	eq(Smelting.recipeFor("iron_ore").out, "iron_bar", "خام الحديد يعطي سبيكة حديد")
	eq(Smelting.recipeFor("iron_bar"), nil, "السبيكة لا تُصهر مرة أخرى")
	ok(Smelting.isFuel("coal"), "الفحم وقود")
	ok(not Smelting.isFuel("iron_bar"), "السبيكة ليست وقوداً")
	ok(Smelting.fuelValue("coal") > Smelting.fuelValue("wood"), "الفحم يحترق أطول من الخشب")

	-- كل سبيكة يجب أن تكون قابلة للحصول عبر الصهر
	for _, bar in { "copper_bar", "iron_bar", "silver_bar", "gold_bar", "mythril_bar", "hellstone_bar" } do
		local found = false
		for _, recipe in Smelting.recipes do
			if recipe.out == bar then found = true break end
		end
		ok(found, "السبيكة قابلة للصهر: " .. bar)
	end
end

-- ===== التطوير والسحر =====
do
	-- الأهلية
	ok(Upgrades.canModify("iron_sword"), "السيف قابل للتطوير")
	ok(Upgrades.canModify("iron_pickaxe"), "المعول قابل للتطوير")
	ok(Upgrades.canModify("iron_chest"), "الدرع قابل للتطوير")
	ok(not Upgrades.canModify("stone"), "البلاطة غير قابلة للتطوير")
	ok(not Upgrades.canModify("health_potion"), "الجرعة غير قابلة للتطوير")
	eq(Upgrades.categoryOf("iron_sword"), "weapon", "تصنيف السلاح")
	eq(Upgrades.categoryOf("iron_pickaxe"), "tool", "تصنيف الأداة")
	eq(Upgrades.categoryOf("iron_helm"), "armor", "تصنيف الدرع")

	-- التطوير يزيد الأرقام بشكل رتيب
	local plain = { id = "iron_sword", n = 1 }
	local base = Upgrades.damage(plain)
	local previous = base
	for level = 1, Upgrades.MAX_LEVEL do
		local upgraded = { id = "iron_sword", n = 1, up = { lvl = level } }
		local value = Upgrades.damage(upgraded)
		ok(value > previous, string.format("+%d أقوى من +%d", level, level - 1))
		previous = value
	end
	ok(previous >= base * 1.5, "التطوير الكامل يزيد الضرر 50% على الأقل")

	local maxed = { id = "iron_pickaxe", n = 1, up = { lvl = 5 } }
	eq(Upgrades.powerBonus(maxed), 20, "التطوير الكامل يعطي +20 قوة معول")
	ok(Upgrades.useTime(maxed) < Upgrades.useTime({ id = "iron_pickaxe", n = 1 }), "التطوير يسرّع الاستخدام")
	ok(Upgrades.miningMultiplier(maxed) > 1, "التطوير يسرّع التعدين")

	-- المستوى مقصوص ضمن الحدود
	eq(Upgrades.levelOf({ id = "iron_sword", n = 1, up = { lvl = 99 } }), Upgrades.MAX_LEVEL, "المستوى مقصوص للأعلى")
	eq(Upgrades.levelOf({ id = "iron_sword", n = 1 }), 0, "بلا تطوير = صفر")

	-- الصفات السحرية
	local badAffix = 0
	for category, pool in Upgrades.pools do
		for _, affix in pool do
			if affix.weight <= 0 then badAffix += 1 end
			if affix.name == "" or affix.desc == "" then badAffix += 1 end
			if Upgrades.affix(affix.id) == nil then badAffix += 1 end
		end
	end
	eq(badAffix, 0, "كل الصفات السحرية معرّفة بالكامل")

	-- الرمي يعطي دائماً صفة من الفئة الصحيحة
	for _, category in { "weapon", "tool", "armor" } do
		for i = 0, 20 do
			local rolled = Upgrades.rollAffix(category, i / 21)
			local found = false
			for _, affix in Upgrades.pools[category] do
				if affix.id == rolled then found = true break end
			end
			ok(found, "الصفة المرميّة تنتمي لفئة " .. category)
		end
	end

	-- إعادة الرمي لا تعطي الصفة نفسها
	local sameCount = 0
	for i = 0, 30 do
		if Upgrades.rollAffix("weapon", i / 31, "sharp") == "sharp" then sameCount += 1 end
	end
	eq(sameCount, 0, "إعادة الرمي تستبعد الصفة الحالية")

	-- أثر الصفة على الأرقام
	local sharp = { id = "iron_sword", n = 1, up = { lvl = 0, aff = "sharp" } }
	ok(Upgrades.damage(sharp) > Upgrades.damage(plain), "صفة «حادّ» تزيد الضرر")
	local swift = { id = "iron_sword", n = 1, up = { lvl = 0, aff = "swift" } }
	ok(Upgrades.useTime(swift) < Upgrades.useTime(plain), "صفة «سريع» تقلّل زمن الاستخدام")
	eq(Upgrades.reachBonus({ id = "iron_pickaxe", n = 1, up = { lvl = 0, aff = "far" } }), 1.5, "صفة «بعيد المدى» تضيف مدى")
	eq(Upgrades.fortune({ id = "iron_pickaxe", n = 1, up = { lvl = 0, aff = "fortune" } }), 0.25, "صفة «موفّق» تضاعف الإسقاط")

	-- مكافآت الدرع تتجمّع
	local armor = {
		head = { id = "iron_helm", n = 1, up = { lvl = 2, aff = "tough" } },
		chest = { id = "iron_chest", n = 1, up = { lvl = 0, aff = "arcane" } },
		feet = { id = "iron_boots", n = 1 },
	}
	local bonus = Upgrades.armorBonus(armor)
	local plainArmor = Upgrades.armorBonus({
		head = { id = "iron_helm", n = 1 },
		chest = { id = "iron_chest", n = 1 },
		feet = { id = "iron_boots", n = 1 },
	})
	ok(bonus.defense > plainArmor.defense, "الدرع المطوّر والمسحور يعطي دفاعاً أعلى")
	eq(bonus.mana, 20, "صفة «غامض» تضيف 20 مانا")

	-- التكاليف تتصاعد وتتوقف عند الحد الأقصى
	local previousCost = 0
	for level = 0, Upgrades.MAX_LEVEL - 1 do
		local cost = Upgrades.upgradeCost("iron_sword", level)
		ok(cost ~= nil, "توجد كلفة للمستوى " .. level)
		ok(cost.amount > previousCost, "الكلفة تتصاعد مع المستوى")
		previousCost = cost.amount
	end
	eq(Upgrades.upgradeCost("iron_sword", Upgrades.MAX_LEVEL), nil, "لا كلفة بعد الحد الأقصى")
	ok(Upgrades.enchantCost("iron_sword") ~= nil, "توجد كلفة للسحر")
	ok(Upgrades.enchantCost("night_edge").coins > Upgrades.enchantCost("wood_sword").coins,
		"سحر السلاح النادر أغلى")

	-- التنظيف يرفض البيانات الفاسدة
	eq(Upgrades.normalize(nil), nil, "بيانات فارغة تُرفض")
	eq(Upgrades.normalize({ lvl = 0 }), nil, "مستوى صفر بلا صفة = بلا تطوير")
	eq(Upgrades.normalize({ lvl = 3, aff = "صفة_وهمية" }).aff, nil, "الصفة المجهولة تُحذف")
	eq(Upgrades.normalize({ lvl = 99 }).lvl, Upgrades.MAX_LEVEL, "المستوى الفاسد يُقصّ")

	-- التعدين يستفيد من قوة التطوير
	local plainPick = Mining.breakTime(B.MYTHRIL_ORE, "diamond_pickaxe", 1, 0)
	local boostedPick = Mining.breakTime(B.MYTHRIL_ORE, "diamond_pickaxe", 1, Upgrades.powerBonus(maxed))
	ok(plainPick ~= nil and boostedPick ~= nil, "معول الألماس يكسر الميثريل")
	ok(boostedPick < plainPick, "المعول المطوّر أسرع")

	-- معول حجري مطوّر بالكامل ما زال عاجزاً عن الميثريل (التقدّم محفوظ)
	eq(Mining.breakTime(B.MYTHRIL_ORE, "stone_pickaxe", 1, 20), nil,
		"التطوير لا يكسر تسلسل التقدّم")
end

-- ===== المخزون يحافظ على التطوير =====
do
	local slots = Inventory.new()
	slots[1] = { id = "iron_sword", n = 1, up = { lvl = 3, aff = "sharp" } }
	slots[2] = { id = "iron_sword", n = 1 }

	-- الأغراض المطوّرة لا تندمج مع العادية
	Inventory.swap(slots, 1, 2)
	ok(slots[1] ~= nil and slots[2] ~= nil, "السيفان بقيا منفصلين بعد التبديل")

	local restored = Inventory.deserialize(Inventory.serialize(slots))
	local found = nil
	for i = 1, Config.INV_SLOTS do
		local stack = restored[i]
		if stack and stack.up then found = stack break end
	end
	ok(found ~= nil, "التطوير نجا من الحفظ والاسترجاع")
	eq(found.up.lvl, 3, "مستوى التطوير محفوظ")
	eq(found.up.aff, "sharp", "الصفة السحرية محفوظة")

	-- الشبكة تنقل التطوير أيضاً
	local net = Inventory.toNetwork(slots)
	local networked = nil
	for _, entry in net do
		if entry[3] ~= nil then networked = entry break end
	end
	ok(networked ~= nil, "التطوير يُرسل عبر الشبكة")

	-- addStack يحافظ على النسخة
	local target = Inventory.new()
	ok(Inventory.addStack(target, { id = "iron_helm", n = 1, up = { lvl = 2, aff = "tough" } }), "addStack نجح")
	eq(target[1].up.lvl, 2, "addStack حافظ على المستوى")

	-- بيانات تطوير فاسدة لا تُسقط اللعبة
	local junk = Inventory.deserialize({ { 1, "iron_sword", 1, "نص", 5 }, { 2, "stone", 4, 3, "sharp" } })
	ok(junk[1] ~= nil, "السيف نجا رغم بيانات التطوير الفاسدة")
	eq(junk[1].up, nil, "التطوير الفاسد أُهمل")
	eq(junk[2].up, nil, "البلاطات لا تحمل تطويراً")
end

-- ===== النتيجة =====
print(string.format("\n%d اختبار ناجح، %d فاشل", passed, failed))
for _, failure in failures do
	print("  ✗ " .. failure)
end
if failed > 0 then
	error(string.format("فشل %d اختبار", failed), 0)
end
print("كل الاختبارات نجحت ✓")
