--!strict
--[[
	EntitySprites — رسم اللاعبين والوحوش والأغراض والمقذوفات من أطلس البكسل.

	كل كائن صار ImageLabel واحداً (أو ثلاثة للشخصية: جسد + خوذة + درع) يشير
	إلى مستطيل داخل الأطلس. تغيير إطار الحركة = تغيير ImageRectOffset فقط،
	بلا إنشاء أو حذف أي كائن.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ArtSprites = require(Shared.ArtSprites)
local Items = require(Shared.Items)
local Mobs = require(Shared.Mobs)

local Atlas = require(script.Parent.Atlas)

local EntitySprites = {}

local function newImage(parent: Instance, zindex: number, atlas: string): ImageLabel
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Size = UDim2.fromScale(1, 1)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.ZIndex = zindex
	image.Parent = parent
	Atlas.apply(image, atlas)
	return image
end

-- ===== الشخصية =====

export type Character = {
	root: Frame,
	body: ImageLabel,
	helm: ImageLabel,
	chest: ImageLabel,
	held: ImageLabel,
	nameTag: TextLabel,
	hpBack: Frame,
	hpFill: Frame,
}

function EntitySprites.newCharacter(parent: Instance, showName: boolean): Character
	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.ZIndex = 6
	root.Parent = parent

	local body = newImage(root, 6, "sprites")
	local chest = newImage(root, 7, "sprites")
	local helm = newImage(root, 8, "sprites")

	local held = Instance.new("ImageLabel")
	held.BackgroundTransparency = 1
	held.BorderSizePixel = 0
	held.AnchorPoint = Vector2.new(0.5, 0.9)
	held.ZIndex = 9
	held.Visible = false
	held.Parent = root
	Atlas.apply(held, "items")

	local nameTag = Instance.new("TextLabel")
	nameTag.BackgroundTransparency = 1
	nameTag.AnchorPoint = Vector2.new(0.5, 1)
	nameTag.Font = Enum.Font.GothamMedium
	nameTag.TextSize = 13
	nameTag.TextColor3 = Color3.fromRGB(240, 240, 240)
	nameTag.TextStrokeTransparency = 0.3
	nameTag.ZIndex = 11
	nameTag.Visible = showName
	nameTag.Parent = root

	local hpBack = Instance.new("Frame")
	hpBack.BackgroundColor3 = Color3.fromRGB(16, 14, 20)
	hpBack.BorderSizePixel = 0
	hpBack.AnchorPoint = Vector2.new(0.5, 1)
	hpBack.ZIndex = 11
	hpBack.Visible = false
	hpBack.Parent = root

	local hpFill = Instance.new("Frame")
	hpFill.BackgroundColor3 = Color3.fromRGB(226, 64, 74)
	hpFill.BorderSizePixel = 0
	hpFill.ZIndex = 12
	hpFill.Parent = hpBack

	return { root = root, body = body, helm = helm, chest = chest, held = held,
		nameTag = nameTag, hpBack = hpBack, hpFill = hpFill }
end

-- اختيار إطار المشي من زمن الحركة
local WALK_CYCLE = { "walk1", "walk2", "walk3", "walk4" }

function EntitySprites.playerFrame(anim: string, animTime: number): string
	if anim == "jump" or anim == "fall" then return "jump" end
	if anim == "walk" then
		local index = math.floor(animTime * 7) % 4 + 1
		return WALK_CYCLE[index]
	end
	return "idle"
end

function EntitySprites.updateCharacter(
	character: Character,
	pxWidth: number,
	pxHeight: number,
	facing: number,
	anim: string,
	animTime: number,
	helmet: string?,
	chestPiece: string?,
	heldItem: string?,
	swing: number,
	heldModified: boolean?
)
	local root = character.root
	root.Size = UDim2.fromOffset(pxWidth, pxHeight)

	local frame = EntitySprites.playerFrame(anim, animTime)
	Atlas.setRect(character.body, Atlas.spriteRect("player:" .. frame, facing))

	character.helm.Visible = helmet ~= nil and helmet ~= ""
	if character.helm.Visible then
		Atlas.setRect(character.helm, Atlas.spriteRect("helm:" .. frame, facing))
		local item = Items.get(helmet :: string)
		character.helm.ImageColor3 = if item then item.color else Color3.fromRGB(190, 190, 200)
	end

	character.chest.Visible = chestPiece ~= nil and chestPiece ~= ""
	if character.chest.Visible then
		Atlas.setRect(character.chest, Atlas.spriteRect("chest:" .. frame, facing))
		local item = Items.get(chestPiece :: string)
		character.chest.ImageColor3 = if item then item.color else Color3.fromRGB(190, 190, 200)
	end

	-- العنصر المحمول: يتأرجح مع الضربة
	local hasHeld = heldItem ~= nil and heldItem ~= "" and Items.get(heldItem :: string) ~= nil
	character.held.Visible = hasHeld
	if hasHeld then
		Atlas.setRect(character.held, Atlas.itemRect(heldItem :: string))
		local iconSize = pxHeight * 0.42
		character.held.Size = UDim2.fromOffset(iconSize, iconSize)
		character.held.Position = UDim2.fromOffset(
			pxWidth / 2 + facing * pxWidth * 0.42,
			pxHeight * 0.56
		)
		character.held.Rotation = facing * (-20 + swing * 120)
		character.held.ImageColor3 = if heldModified
			then Color3.fromRGB(255, 245, 210)
			else Color3.fromRGB(255, 255, 255)
	end
end

function EntitySprites.setCharacterHealth(character: Character, pxWidth: number, pxHeight: number, percent: number)
	local show = percent < 99
	character.hpBack.Visible = show
	if not show then return end
	character.hpBack.Size = UDim2.fromOffset(pxWidth * 0.9, math.max(3, pxHeight * 0.05))
	character.hpBack.Position = UDim2.fromOffset(pxWidth / 2, -4)
	character.hpFill.Size = UDim2.new(math.clamp(percent / 100, 0, 1), -2, 1, -2)
	character.hpFill.Position = UDim2.fromOffset(1, 1)
end

-- ===== الوحوش =====

export type MobSprite = {
	root: Frame,
	image: ImageLabel,
	hpBack: Frame,
	hpFill: Frame,
}

function EntitySprites.newMob(parent: Instance): MobSprite
	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.ZIndex = 5
	root.Parent = parent

	local image = newImage(root, 5, "sprites")

	local hpBack = Instance.new("Frame")
	hpBack.BackgroundColor3 = Color3.fromRGB(16, 14, 20)
	hpBack.BorderSizePixel = 0
	hpBack.AnchorPoint = Vector2.new(0.5, 1)
	hpBack.ZIndex = 9
	hpBack.Visible = false
	hpBack.Parent = root

	local hpFill = Instance.new("Frame")
	hpFill.BackgroundColor3 = Color3.fromRGB(226, 64, 74)
	hpFill.BorderSizePixel = 0
	hpFill.ZIndex = 10
	hpFill.Parent = hpBack

	return { root = root, image = image, hpBack = hpBack, hpFill = hpFill }
end

function EntitySprites.updateMob(
	sprite: MobSprite,
	mobId: string,
	pxW: number,
	pxH: number,
	facing: number,
	anim: string,
	age: number,
	hpPercent: number
)
	sprite.root.Size = UDim2.fromOffset(pxW, pxH)

	local frames = ArtSprites.mobFrames(mobId)
	local speed = if anim == "walk" or anim == "fly" then 7 else 3
	local frame = math.floor(age * speed) % frames + 1
	Atlas.setRect(sprite.image, Atlas.spriteRect("mob:" .. mobId .. ":" .. frame, facing))

	local def = Mobs.get(mobId)
	local isBoss = def ~= nil and def.boss == true
	local show = hpPercent < 99 and not isBoss
	sprite.hpBack.Visible = show
	if show then
		sprite.hpBack.Size = UDim2.fromOffset(pxW * 0.9, math.max(3, pxH * 0.07))
		sprite.hpBack.Position = UDim2.fromOffset(pxW / 2, -3)
		sprite.hpFill.Size = UDim2.new(math.clamp(hpPercent / 100, 0, 1), -2, 1, -2)
		sprite.hpFill.Position = UDim2.fromOffset(1, 1)
	end
end

-- ===== الأغراض الساقطة =====

export type ItemSprite = { root: Frame, image: ImageLabel, count: TextLabel }

function EntitySprites.newItem(parent: Instance): ItemSprite
	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.ZIndex = 5
	root.Parent = parent

	local image = newImage(root, 5, "items")

	local count = Instance.new("TextLabel")
	count.BackgroundTransparency = 1
	count.AnchorPoint = Vector2.new(0.5, 0)
	count.Font = Enum.Font.Arcade
	count.TextSize = 12
	count.TextColor3 = Color3.fromRGB(255, 255, 255)
	count.TextStrokeTransparency = 0.1
	count.ZIndex = 7
	count.Parent = root

	return { root = root, image = image, count = count }
end

function EntitySprites.updateItem(sprite: ItemSprite, itemId: string, count: number, pxSize: number, age: number)
	local bob = math.sin(age * 3.4) * pxSize * 0.2
	sprite.root.Size = UDim2.fromOffset(pxSize, pxSize)
	Atlas.setRect(sprite.image, Atlas.itemRect(itemId))
	sprite.image.Position = UDim2.fromOffset(pxSize / 2, pxSize / 2 + bob)

	sprite.count.Visible = count > 1
	if sprite.count.Visible then
		sprite.count.Text = tostring(count)
		sprite.count.Size = UDim2.fromOffset(pxSize * 2, pxSize * 0.55)
		sprite.count.Position = UDim2.fromOffset(pxSize / 2, pxSize * 0.8 + bob)
	end
end

-- ===== المقذوفات =====

export type ProjSprite = { root: Frame, image: ImageLabel }

function EntitySprites.newProjectile(parent: Instance): ProjSprite
	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.ZIndex = 6
	root.Parent = parent
	local image = newImage(root, 6, "sprites")
	return { root = root, image = image }
end

function EntitySprites.updateProjectile(sprite: ProjSprite, projId: string, pxSize: number, angle: number)
	sprite.root.Size = UDim2.fromOffset(pxSize, pxSize)
	Atlas.setRect(sprite.image, Atlas.spriteRect("proj:" .. projId, 1))
	sprite.image.Rotation = angle
end

return EntitySprites
