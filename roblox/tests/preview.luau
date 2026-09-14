-- يبني أوراق معاينة للفن ويطبعها بصيغة سداسية ليحوّلها preview.py إلى PNG.
local Pixels = __req("Pixels")
local ArtBlocks = __req("ArtBlocks")
local ArtItems = __req("ArtItems")
local ArtSprites = __req("ArtSprites")
local ArtUI = __req("ArtUI")
local Blocks = __req("Blocks")
local Items = __req("Items")
local Mobs = __req("Mobs")

local SCALE = 3

local function upscale(src, scale)
	local out = Pixels.new(src.w * scale, src.h * scale)
	for y = 0, src.h - 1 do
		for x = 0, src.w - 1 do
			local r, g, b, a = Pixels.get(src, x, y)
			if a > 0 then
				Pixels.fill(out, x * scale, y * scale, scale, scale, r, g, b, a)
			end
		end
	end
	return out
end

local function checker(canvas)
	-- خلفية شطرنجية لإظهار الشفافية
	for y = 0, canvas.h - 1 do
		for x = 0, canvas.w - 1 do
			local on = ((x // 8) + (y // 8)) % 2 == 0
			local v = if on then 58 else 44
			Pixels.set(canvas, x, y, v, v, v + 6, 255)
		end
	end
end

local function emit(name, canvas)
	print("@SHEET " .. name .. " " .. canvas.w .. " " .. canvas.h)
	local parts = {}
	local total = canvas.w * canvas.h * 4
	for i = 0, total - 1, 1 do
		parts[#parts + 1] = string.format("%02x", buffer.readu8(canvas.data, i))
		if #parts >= 4096 then
			print(table.concat(parts))
			parts = {}
		end
	end
	if #parts > 0 then print(table.concat(parts)) end
	print("@END")
end

-- ===== ورقة البلاطات =====
do
	local ids = {}
	for id in Blocks.defs do
		if id ~= Blocks.ID.AIR then table.insert(ids, id) end
	end
	table.sort(ids)

	local cell = 32 * SCALE + 6
	local cols = 9
	local rows = math.ceil(#ids / cols)
	local sheet = Pixels.new(cols * cell + 6, rows * cell + 6)
	checker(sheet)

	local names = {}
	for i, id in ids do
		local block = Blocks.get(id)
		table.insert(names, string.format("%d=%s", id, block.name))

		-- رقعة 2×2 بأقنعة حواف واقعية لإظهار التجانب
		local patch = Pixels.new(32, 32)
		local masks = { Pixels.EDGE_UP + Pixels.EDGE_LEFT, Pixels.EDGE_UP + Pixels.EDGE_RIGHT,
			Pixels.EDGE_DOWN + Pixels.EDGE_LEFT, Pixels.EDGE_DOWN + Pixels.EDGE_RIGHT }
		local base = ArtBlocks.paint(id, 16)
		for k = 0, 3 do
			local tile = Pixels.clone(base)
			if ArtBlocks.usesEdges(id) then
				Pixels.applyEdges(tile, masks[k + 1], 16)
			end
			Pixels.blit(patch, tile, (k % 2) * 16, (k // 2) * 16)
		end

		local scaled = upscale(patch, SCALE)
		local col = (i - 1) % cols
		local row = (i - 1) // cols
		Pixels.blit(sheet, scaled, 6 + col * cell, 6 + row * cell)
	end
	print("@NAMES blocks " .. table.concat(names, " | "))
	emit("blocks", sheet)
end

-- ===== ورقة العناصر =====
do
	local cell = 16 * SCALE + 4
	local cols = 16
	local rows = math.ceil(#Items.order / cols)
	local sheet = Pixels.new(cols * cell + 4, rows * cell + 4)
	checker(sheet)

	for i, itemId in Items.order do
		local icon = upscale(ArtItems.paint(itemId, 16), SCALE)
		local col = (i - 1) % cols
		local row = (i - 1) // cols
		Pixels.blit(sheet, icon, 4 + col * cell, 4 + row * cell)
	end
	print("@NAMES items " .. table.concat(Items.order, " | "))
	emit("items", sheet)
end

-- ===== ورقة الكائنات =====
do
	local entries = {}
	for _, frame in ArtSprites.PLAYER_FRAMES do
		table.insert(entries, { "player:" .. frame, ArtSprites.paintPlayer(frame) })
	end
	table.insert(entries, { "helm", ArtSprites.paintHelmet("idle") })
	table.insert(entries, { "chest", ArtSprites.paintChestplate("idle") })

	local mobIds = {}
	for id in Mobs.defs do table.insert(mobIds, id) end
	table.sort(mobIds)
	for _, id in mobIds do
		for frame = 1, ArtSprites.mobFrames(id) do
			table.insert(entries, { "mob:" .. id .. ":" .. frame, ArtSprites.paintMob(id, frame) })
		end
	end
	for id in Mobs.projectiles do
		table.insert(entries, { "proj:" .. id, ArtSprites.paintProjectile(id) })
	end
	for name, painter in ArtUI.pieces do
		table.insert(entries, { "ui:" .. name, painter() })
	end

	local cellW, cellH = 0, 0
	for _, entry in entries do
		cellW = math.max(cellW, entry[2].w * SCALE)
		cellH = math.max(cellH, entry[2].h * SCALE)
	end
	cellW += 6
	cellH += 6

	local cols = 10
	local rows = math.ceil(#entries / cols)
	local sheet = Pixels.new(cols * cellW + 6, rows * cellH + 6)
	checker(sheet)

	local names = {}
	for i, entry in entries do
		table.insert(names, entry[1])
		local scaled = upscale(entry[2], SCALE)
		local col = (i - 1) % cols
		local row = (i - 1) // cols
		-- محاذاة للأسفل داخل الخلية
		Pixels.blit(sheet, scaled, 6 + col * cellW, 6 + row * cellH + (cellH - 6 - scaled.h))
	end
	print("@NAMES sprites " .. table.concat(names, " | "))
	emit("sprites", sheet)
end
