--!strict
--[[
	Atlas — يبني أطالس النقوش في الذاكرة ثم يرفعها إلى EditableImage.

	لماذا أطلس واحد لا صورة لكل بلاطة؟ لأن آلاف الـ ImageLabel التي تشترك في
	صورة واحدة أرخص بكثير على المحرّك: نغيّر ImageRectOffset فقط لاختيار البلاطة.
	هذه هي الطريقة التي تعمل بها محرّكات البلاطات الحقيقية.

	كل شيء يُولَّد وقت التشغيل — لا نرفع أي أصل إلى روبلوكس.
]]

local AssetService = game:GetService("AssetService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ArtBlocks = require(Shared.ArtBlocks)
local ArtItems = require(Shared.ArtItems)
local ArtSprites = require(Shared.ArtSprites)
local ArtUI = require(Shared.ArtUI)
local Blocks = require(Shared.Blocks)
local Items = require(Shared.Items)
local Mobs = require(Shared.Mobs)
local Pixels = require(Shared.Pixels)

local Atlas = {}

Atlas.TILE = 16 -- بكسلات النقش الواحد (دقة الفن، لا حجم العرض)

export type Rect = { x: number, y: number, w: number, h: number }

local images: { [string]: EditableImage } = {}
local contents: { [string]: any } = {}

local tileRects: { [number]: { [number]: Rect } } = {}
local itemRects: { [string]: Rect } = {}
local spriteRects: { [string]: Rect } = {}

local ready = false
local warnedNoContent = false
local progress = 0

function Atlas.isReady(): boolean
	return ready
end

function Atlas.progress(): number
	return progress
end

-- ===== رفع لوحة إلى EditableImage =====

local function upload(name: string, canvas: Pixels.Canvas): boolean
	local ok, image = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(canvas.w, canvas.h) })
	end)
	if not ok or not image then
		warn("[Atlas] تعذّر إنشاء EditableImage: " .. tostring(image))
		return false
	end

	local wrote = pcall(function()
		image:WritePixelsBuffer(Vector2.zero, Vector2.new(canvas.w, canvas.h), canvas.data)
	end)
	if not wrote then
		warn("[Atlas] تعذّرت كتابة البكسلات في " .. name)
		return false
	end

	images[name] = image

	-- الطريقة الحديثة: ImageContent. نحتفظ بالكائن نفسه كبديل للإصدارات الأقدم.
	local madeContent = pcall(function()
		contents[name] = (Content :: any).fromObject(image)
	end)
	if not madeContent then
		contents[name] = nil
	end
	return true
end

-- يربط ImageLabel/ImageButton بأطلس معيّن
function Atlas.apply(label: ImageLabel | ImageButton, name: string)
	local content = contents[name]
	if content then
		local ok = pcall(function()
			(label :: any).ImageContent = content
		end)
		if ok then
			label.ResampleMode = Enum.ResamplerMode.Pixelated
			return
		end
	end
	-- لا بديل عملي: EditableImage واحد لا يمكن مشاركته بين آلاف العناصر
	-- إلا عبر Content. نُحذّر مرة واحدة بدل إغراق السجلّ.
	if not warnedNoContent then
		warnedNoContent = true
		warn("[Atlas] هذا الإصدار من روبلوكس لا يدعم ImageContent — النقوش لن تظهر. حدّث Studio.")
	end
	label.ResampleMode = Enum.ResamplerMode.Pixelated
end

-- صورة ديناميكية يملؤها المستدعي وقت التشغيل (الخريطة المصغّرة مثلاً)
function Atlas.createDynamic(name: string, width: number, height: number): EditableImage?
	local ok, image = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(width, height) })
	end)
	if not ok or not image then
		warn("[Atlas] تعذّر إنشاء صورة ديناميكية: " .. name)
		return nil
	end
	images[name] = image
	pcall(function()
		contents[name] = (Content :: any).fromObject(image)
	end)
	return image
end

-- ===== رصف الأطلس =====

type Shelf = { x: number, y: number, rowHeight: number }

local function packInto(canvas: Pixels.Canvas, shelf: Shelf, cell: Pixels.Canvas): Rect
	if shelf.x + cell.w > canvas.w then
		shelf.x = 0
		shelf.y += shelf.rowHeight + 1
		shelf.rowHeight = 0
	end
	local rect: Rect = { x = shelf.x, y = shelf.y, w = cell.w, h = cell.h }
	if shelf.y + cell.h <= canvas.h then
		Pixels.blitFast(canvas, cell, shelf.x, shelf.y)
	else
		warn("[Atlas] امتلأ الأطلس — بعض النقوش لن تظهر")
	end
	shelf.x += cell.w + 1
	if cell.h > shelf.rowHeight then shelf.rowHeight = cell.h end
	return rect
end

-- ===== بناء أطلس البلاطات =====

local function buildTiles(): Pixels.Canvas
	local size = Atlas.TILE
	local canvas = Pixels.new(1024, 1024)
	local shelf: Shelf = { x = 0, y = 0, rowHeight = 0 }
	local count = 0

	for blockId in Blocks.defs do
		if blockId ~= Blocks.ID.AIR then
			local base = ArtBlocks.paint(blockId, size)
			local masks: { [number]: Rect } = {}

			if ArtBlocks.usesEdges(blockId) then
				-- 16 نسخة: واحدة لكل تركيبة جيران مكشوفين
				for mask = 0, 15 do
					local variant = Pixels.clone(base)
					Pixels.applyEdges(variant, mask, size)
					masks[mask] = packInto(canvas, shelf, variant)
				end
			else
				local rect = packInto(canvas, shelf, base)
				for mask = 0, 15 do
					masks[mask] = rect
				end
			end

			tileRects[blockId] = masks
			count += 1
			if count % 8 == 0 then
				progress = count / 60 * 0.5
				task.wait()
			end
		end
	end

	return canvas
end

-- ===== بناء أطلس العناصر =====

local function buildItems(): Pixels.Canvas
	local size = Atlas.TILE
	local canvas = Pixels.new(256, 256)
	local shelf: Shelf = { x = 0, y = 0, rowHeight = 0 }
	local count = 0

	for _, itemId in Items.order do
		local cell = ArtItems.paint(itemId, size)
		itemRects[itemId] = packInto(canvas, shelf, cell)
		count += 1
		if count % 24 == 0 then task.wait() end
	end

	return canvas
end

-- ===== بناء أطلس الكائنات =====

local function addSprite(canvas: Pixels.Canvas, shelf: Shelf, key: string, cell: Pixels.Canvas)
	spriteRects[key] = packInto(canvas, shelf, cell)
	-- النسخة المعكوسة للاتجاه المعاكس (نخبزها بدل قلبها وقت التشغيل)
	local mirrored = Pixels.new(cell.w, cell.h)
	Pixels.blitMirrored(mirrored, cell, 0, 0)
	spriteRects[key .. ":L"] = packInto(canvas, shelf, mirrored)
end

local function buildSprites(): Pixels.Canvas
	local canvas = Pixels.new(512, 512)
	local shelf: Shelf = { x = 0, y = 0, rowHeight = 0 }

	for _, frame in ArtSprites.PLAYER_FRAMES do
		addSprite(canvas, shelf, "player:" .. frame, ArtSprites.paintPlayer(frame))
		addSprite(canvas, shelf, "helm:" .. frame, ArtSprites.paintHelmet(frame))
		addSprite(canvas, shelf, "chest:" .. frame, ArtSprites.paintChestplate(frame))
	end
	task.wait()

	for mobId in Mobs.defs do
		local frames = ArtSprites.mobFrames(mobId)
		for frame = 1, frames do
			addSprite(canvas, shelf, "mob:" .. mobId .. ":" .. frame, ArtSprites.paintMob(mobId, frame))
		end
		task.wait()
	end

	for projId in Mobs.projectiles do
		addSprite(canvas, shelf, "proj:" .. projId, ArtSprites.paintProjectile(projId))
	end

	return canvas
end

-- ===== قطع الواجهة =====
-- كل قطعة صورة مستقلة لا خلية في أطلس: التقطيع التسعي (ScaleType.Slice)
-- يقيس SliceCenter على الصورة كاملة، فالفصل يجنّبنا التباساً حقيقياً.
local function buildUI()
	for name, painter in ArtUI.pieces do
		upload("ui:" .. name, painter())
	end
end

-- ===== الواجهة العامة =====

function Atlas.build()
	if ready then return end

	local startTime = os.clock()

	local tiles = buildTiles()
	progress = 0.55
	upload("tiles", tiles)
	task.wait()

	local items = buildItems()
	progress = 0.75
	upload("items", items)
	task.wait()

	local sprites = buildSprites()
	progress = 0.92
	upload("sprites", sprites)
	task.wait()

	buildUI()

	progress = 1
	ready = true
	print(string.format("[Atlas] بُنيت النقوش في %.0f مللي ثانية", (os.clock() - startTime) * 1000))
end

local EMPTY: Rect = { x = 0, y = 0, w = 1, h = 1 }

function Atlas.tileRect(blockId: number, mask: number): Rect
	local masks = tileRects[blockId]
	if not masks then return EMPTY end
	return masks[mask] or masks[0] or EMPTY
end

function Atlas.itemRect(itemId: string): Rect
	return itemRects[itemId] or EMPTY
end

function Atlas.spriteRect(key: string, facing: number?): Rect
	local suffix = if facing == -1 then ":L" else ""
	return spriteRects[key .. suffix] or spriteRects[key] or EMPTY
end

-- يضبط ImageLabel على قطعة واجهة كاملة (بلا مستطيل جزئي)
function Atlas.applyUI(label: ImageLabel | ImageButton, name: string)
	Atlas.apply(label, "ui:" .. name)
	label.ImageRectOffset = Vector2.zero
	label.ImageRectSize = Vector2.zero
end

-- إطار تسعي: يبقى سُمك الحافة ثابتاً مهما تمدّد العنصر
function Atlas.applySlice(label: ImageLabel | ImageButton, name: string)
	Atlas.applyUI(label, name)
	label.ScaleType = Enum.ScaleType.Slice
	label.SliceCenter = Rect.new(ArtUI.SLICE, ArtUI.SLICE, ArtUI.PANEL - ArtUI.SLICE, ArtUI.PANEL - ArtUI.SLICE)
end

-- مساعدات لضبط ImageLabel على مستطيل من الأطلس
function Atlas.setRect(label: ImageLabel | ImageButton, rect: Rect)
	label.ImageRectOffset = Vector2.new(rect.x, rect.y)
	label.ImageRectSize = Vector2.new(rect.w, rect.h)
end

function Atlas.bind(label: ImageLabel | ImageButton, name: string, rect: Rect?)
	Atlas.apply(label, name)
	if rect then Atlas.setRect(label, rect) end
end

return Atlas
