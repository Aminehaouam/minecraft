--!strict
--[[
	Sprites — بناء الأشكال ثنائية الأبعاد من إطارات Frame بسيطة.
	لا نستخدم أي صور خارجية: كل شيء أشكال ملوّنة تُركّب برمجياً،
	فتعمل اللعبة فوراً بلا رفع أصول، وتبقى الهوية البصرية موحّدة.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Mobs = require(Shared.Mobs)

local Sprites = {}

local function frame(parent: Instance, color: Color3, zindex: number?): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.ZIndex = zindex or 2
	f.Parent = parent
	return f
end

local function round(instance: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = instance
end

-- ===== شخصية (اللاعب والأقران) =====

export type Character = {
	root: Frame,
	head: Frame,
	torso: Frame,
	legL: Frame,
	legR: Frame,
	arm: Frame,
	held: Frame,
	helm: Frame,
	nameTag: TextLabel,
	hpBar: Frame,
	hpFill: Frame,
}

function Sprites.newCharacter(parent: Instance, showName: boolean): Character
	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.ZIndex = 6
	root.Parent = parent

	local legL = frame(root, Color3.fromRGB(58, 72, 120), 5)
	local legR = frame(root, Color3.fromRGB(48, 60, 104), 5)
	local torso = frame(root, Color3.fromRGB(96, 132, 196), 6)
	round(torso, 0.22)
	local arm = frame(root, Color3.fromRGB(226, 184, 150), 8)
	round(arm, 0.35)
	local head = frame(root, Color3.fromRGB(236, 194, 158), 7)
	round(head, 0.28)
	local helm = frame(root, Color3.fromRGB(120, 120, 130), 8)
	round(helm, 0.3)
	helm.Visible = false

	local held = frame(root, Color3.fromRGB(200, 200, 200), 9)
	round(held, 0.15)
	held.Visible = false

	local nameTag = Instance.new("TextLabel")
	nameTag.BackgroundTransparency = 1
	nameTag.AnchorPoint = Vector2.new(0.5, 1)
	nameTag.Font = Enum.Font.GothamMedium
	nameTag.TextSize = 13
	nameTag.TextColor3 = Color3.fromRGB(240, 240, 240)
	nameTag.TextStrokeTransparency = 0.35
	nameTag.ZIndex = 10
	nameTag.Visible = showName
	nameTag.Parent = root

	local hpBar = frame(root, Color3.fromRGB(20, 20, 24), 10)
	hpBar.Visible = false
	local hpFill = frame(hpBar, Color3.fromRGB(220, 70, 70), 11)
	hpFill.AnchorPoint = Vector2.new(0, 0.5)

	return {
		root = root, head = head, torso = torso, legL = legL, legR = legR,
		arm = arm, held = held, helm = helm, nameTag = nameTag,
		hpBar = hpBar, hpFill = hpFill,
	}
end

-- ألوان الدرع تُغيّر مظهر الشخصية
local function armorColor(itemId: string?, fallback: Color3): Color3
	if not itemId or itemId == "" then return fallback end
	local item = Items.get(itemId)
	return if item then item.color else fallback
end

function Sprites.updateCharacter(
	character: Character,
	pxWidth: number,
	pxHeight: number,
	facing: number,
	anim: string,
	animTime: number,
	helmet: string?,
	chest: string?,
	held: string?,
	swing: number
)
	local root = character.root
	root.Size = UDim2.fromOffset(pxWidth, pxHeight)

	local unit = pxHeight / 2.8 -- بكسل لكل بلاطة

	-- الرأس
	local headSize = unit * 0.95
	character.head.Size = UDim2.fromOffset(headSize, headSize * 0.92)
	character.head.Position = UDim2.fromOffset(pxWidth / 2 + facing * unit * 0.06, unit * 0.52)

	character.helm.Visible = helmet ~= nil and helmet ~= ""
	if character.helm.Visible then
		character.helm.BackgroundColor3 = armorColor(helmet, Color3.fromRGB(120, 120, 130))
		character.helm.Size = UDim2.fromOffset(headSize * 1.12, headSize * 0.58)
		character.helm.Position = UDim2.fromOffset(pxWidth / 2 + facing * unit * 0.06, unit * 0.34)
	end

	-- الجذع
	local torsoW, torsoH = unit * 0.95, unit * 0.95
	character.torso.Size = UDim2.fromOffset(torsoW, torsoH)
	character.torso.Position = UDim2.fromOffset(pxWidth / 2, unit * 1.48)
	character.torso.BackgroundColor3 = armorColor(chest, Color3.fromRGB(96, 132, 196))

	-- الأرجل مع حركة المشي
	local swingAngle = 0
	if anim == "walk" then
		swingAngle = math.sin(animTime * 11) * 26
	elseif anim == "jump" or anim == "fall" then
		swingAngle = 14
	end
	local legW, legH = unit * 0.34, unit * 0.85
	character.legL.Size = UDim2.fromOffset(legW, legH)
	character.legR.Size = UDim2.fromOffset(legW, legH)
	character.legL.Position = UDim2.fromOffset(pxWidth / 2 - legW * 0.7, unit * 2.36)
	character.legR.Position = UDim2.fromOffset(pxWidth / 2 + legW * 0.7, unit * 2.36)
	character.legL.Rotation = swingAngle
	character.legR.Rotation = -swingAngle

	-- الذراع تتبع اتجاه الضربة
	local armW, armH = unit * 0.3, unit * 0.9
	character.arm.Size = UDim2.fromOffset(armW, armH)
	character.arm.Position = UDim2.fromOffset(pxWidth / 2 + facing * unit * 0.42, unit * 1.5)
	character.arm.Rotation = facing * (18 + swing * 90) - (if anim == "walk" then swingAngle * 0.5 else 0)

	-- العنصر المحمول
	local heldItem = if held and held ~= "" then Items.get(held) else nil
	character.held.Visible = heldItem ~= nil
	if heldItem then
		local isTool = heldItem.cat == "tool" or heldItem.cat == "weapon"
		local w = if isTool then unit * 0.22 else unit * 0.55
		local h = if isTool then unit * 1.15 else unit * 0.55
		character.held.Size = UDim2.fromOffset(w, h)
		character.held.BackgroundColor3 = heldItem.color
		character.held.Position = UDim2.fromOffset(
			pxWidth / 2 + facing * unit * 0.72,
			unit * (if isTool then 1.15 else 1.5)
		)
		character.held.Rotation = facing * (30 + swing * 110)
	end
end

-- ===== الوحوش =====

export type MobSprite = {
	root: Frame,
	parts: { Frame },
	body: Frame,
	eyeL: Frame,
	eyeR: Frame,
	detail: Frame,
	hpBar: Frame,
	hpFill: Frame,
	kind: string,
}

function Sprites.newMob(parent: Instance): MobSprite
	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.ZIndex = 5
	root.Parent = parent

	local parts: { Frame } = {}
	for i = 1, 4 do
		local part = frame(root, Color3.fromRGB(60, 60, 60), 4)
		round(part, 0.3)
		table.insert(parts, part)
	end

	local body = frame(root, Color3.fromRGB(120, 120, 120), 5)
	round(body, 0.3)
	local detail = frame(root, Color3.fromRGB(90, 90, 90), 6)
	round(detail, 0.4)
	local eyeL = frame(root, Color3.fromRGB(20, 20, 24), 7)
	round(eyeL, 0.5)
	local eyeR = frame(root, Color3.fromRGB(20, 20, 24), 7)
	round(eyeR, 0.5)

	local hpBar = frame(root, Color3.fromRGB(16, 16, 20), 9)
	hpBar.Visible = false
	local hpFill = frame(hpBar, Color3.fromRGB(220, 70, 70), 10)
	hpFill.AnchorPoint = Vector2.new(0, 0.5)

	return {
		root = root, parts = parts, body = body, detail = detail,
		eyeL = eyeL, eyeR = eyeR, hpBar = hpBar, hpFill = hpFill, kind = "",
	}
end

function Sprites.updateMob(sprite: MobSprite, typeId: string, pxW: number, pxH: number, facing: number, anim: string, age: number, hpPct: number)
	local def = Mobs.get(typeId)
	if not def then return end
	local root = sprite.root
	root.Size = UDim2.fromOffset(pxW, pxH)
	sprite.kind = typeId

	sprite.body.BackgroundColor3 = def.color
	sprite.detail.BackgroundColor3 = def.accent

	local ai = def.ai
	local bob = math.sin(age * 6) * pxH * 0.03

	if ai == "jumper" then
		-- هلامة: انسحاب وتمدد
		local squash = if anim == "jump" then 1.18 else 1 + math.sin(age * 8) * 0.05
		sprite.body.Size = UDim2.fromOffset(pxW / squash, pxH * squash)
		sprite.body.Position = UDim2.fromOffset(pxW / 2, pxH - (pxH * squash) / 2)
		sprite.detail.Size = UDim2.fromOffset(pxW * 0.35, pxH * 0.3)
		sprite.detail.Position = UDim2.fromOffset(pxW / 2, pxH * 0.55)
		sprite.detail.BackgroundTransparency = 0.4
		for _, part in sprite.parts do part.Visible = false end
		sprite.eyeL.Size = UDim2.fromOffset(pxW * 0.13, pxH * 0.16)
		sprite.eyeR.Size = UDim2.fromOffset(pxW * 0.13, pxH * 0.16)
		sprite.eyeL.Position = UDim2.fromOffset(pxW * 0.36, pxH * 0.52)
		sprite.eyeR.Position = UDim2.fromOffset(pxW * 0.64, pxH * 0.52)
		sprite.eyeL.Visible, sprite.eyeR.Visible = true, true

	elseif ai == "flyer" then
		local flap = math.sin(age * 18) * pxH * 0.22
		sprite.body.Size = UDim2.fromOffset(pxW * 0.62, pxH * 0.72)
		sprite.body.Position = UDim2.fromOffset(pxW / 2, pxH / 2 + bob)
		sprite.detail.Size = UDim2.fromOffset(pxW * 0.3, pxH * 0.3)
		sprite.detail.Position = UDim2.fromOffset(pxW / 2, pxH * 0.45 + bob)
		sprite.detail.BackgroundTransparency = 0
		-- جناحان
		for i = 1, 2 do
			local wing = sprite.parts[i]
			wing.Visible = true
			wing.BackgroundColor3 = def.accent
			wing.Size = UDim2.fromOffset(pxW * 0.42, pxH * 0.24)
			wing.Position = UDim2.fromOffset(pxW / 2 + (if i == 1 then -1 else 1) * pxW * 0.42, pxH / 2 + bob)
			wing.Rotation = (if i == 1 then -1 else 1) * flap
		end
		sprite.parts[3].Visible = false
		sprite.parts[4].Visible = false
		sprite.eyeL.Visible, sprite.eyeR.Visible = false, false

	elseif ai == "climber" then
		-- عنكبوت: جسم بيضاوي وأربع أرجل
		sprite.body.Size = UDim2.fromOffset(pxW * 0.62, pxH * 0.66)
		sprite.body.Position = UDim2.fromOffset(pxW / 2, pxH * 0.45)
		sprite.detail.Size = UDim2.fromOffset(pxW * 0.26, pxH * 0.28)
		sprite.detail.Position = UDim2.fromOffset(pxW / 2 + facing * pxW * 0.24, pxH * 0.42)
		sprite.detail.BackgroundTransparency = 0
		for i, leg in sprite.parts do
			leg.Visible = true
			leg.BackgroundColor3 = def.color
			leg.Size = UDim2.fromOffset(pxW * 0.09, pxH * 0.5)
			local side = if i <= 2 then -1 else 1
			local offset = (if i % 2 == 0 then 0.22 else 0.42)
			leg.Position = UDim2.fromOffset(pxW / 2 + side * pxW * offset, pxH * 0.62)
			leg.Rotation = side * (24 + math.sin(age * 14 + i) * 12)
		end
		sprite.eyeL.Size = UDim2.fromOffset(pxW * 0.08, pxH * 0.12)
		sprite.eyeR.Size = UDim2.fromOffset(pxW * 0.08, pxH * 0.12)
		sprite.eyeL.Position = UDim2.fromOffset(pxW / 2 + facing * pxW * 0.28, pxH * 0.36)
		sprite.eyeR.Position = UDim2.fromOffset(pxW / 2 + facing * pxW * 0.34, pxH * 0.46)
		sprite.eyeL.BackgroundColor3 = def.accent
		sprite.eyeR.BackgroundColor3 = def.accent
		sprite.eyeL.Visible, sprite.eyeR.Visible = true, true

	elseif ai == "boss" then
		-- عين ضخمة
		local pulse = 1 + math.sin(age * 3) * 0.04
		sprite.body.Size = UDim2.fromOffset(pxW * pulse, pxH * pulse)
		sprite.body.Position = UDim2.fromOffset(pxW / 2, pxH / 2)
		sprite.detail.Size = UDim2.fromOffset(pxW * 0.46, pxH * 0.46)
		sprite.detail.Position = UDim2.fromOffset(pxW / 2 + facing * pxW * 0.1, pxH / 2)
		sprite.detail.BackgroundTransparency = 0
		sprite.eyeL.Size = UDim2.fromOffset(pxW * 0.2, pxH * 0.2)
		sprite.eyeL.Position = UDim2.fromOffset(pxW / 2 + facing * pxW * 0.14, pxH / 2)
		sprite.eyeL.BackgroundColor3 = Color3.fromRGB(18, 14, 20)
		sprite.eyeL.Visible = true
		sprite.eyeR.Visible = false
		for i, part in sprite.parts do
			part.Visible = true
			part.BackgroundColor3 = def.accent
			local angle = age * 1.5 + i * (math.pi / 2)
			part.Size = UDim2.fromOffset(pxW * 0.16, pxH * 0.34)
			part.Position = UDim2.fromOffset(
				pxW / 2 + math.cos(angle) * pxW * 0.52,
				pxH / 2 + math.sin(angle) * pxH * 0.52
			)
			part.Rotation = math.deg(angle)
		end

	else
		-- شكل بشري (زومبي، هيكل، غول)
		local walkSwing = if anim == "walk" then math.sin(age * 10) * 22 else 0
		sprite.body.Size = UDim2.fromOffset(pxW * 0.6, pxH * 0.42)
		sprite.body.Position = UDim2.fromOffset(pxW / 2, pxH * 0.46)
		sprite.detail.Size = UDim2.fromOffset(pxW * 0.5, pxH * 0.28)
		sprite.detail.Position = UDim2.fromOffset(pxW / 2 + facing * pxW * 0.04, pxH * 0.16)
		sprite.detail.BackgroundColor3 = def.color
		sprite.detail.BackgroundTransparency = 0

		sprite.parts[1].Visible = true
		sprite.parts[2].Visible = true
		for i = 1, 2 do
			local leg = sprite.parts[i]
			leg.BackgroundColor3 = def.accent
			leg.Size = UDim2.fromOffset(pxW * 0.2, pxH * 0.34)
			leg.Position = UDim2.fromOffset(pxW / 2 + (if i == 1 then -1 else 1) * pxW * 0.16, pxH * 0.82)
			leg.Rotation = (if i == 1 then 1 else -1) * walkSwing
		end
		sprite.parts[3].Visible = true
		sprite.parts[3].BackgroundColor3 = def.accent
		sprite.parts[3].Size = UDim2.fromOffset(pxW * 0.16, pxH * 0.36)
		sprite.parts[3].Position = UDim2.fromOffset(pxW / 2 + facing * pxW * 0.32, pxH * 0.45)
		sprite.parts[3].Rotation = facing * 70
		sprite.parts[4].Visible = false

		sprite.eyeL.Size = UDim2.fromOffset(pxW * 0.09, pxH * 0.09)
		sprite.eyeR.Size = UDim2.fromOffset(pxW * 0.09, pxH * 0.09)
		sprite.eyeL.Position = UDim2.fromOffset(pxW / 2 + facing * pxW * 0.1 - pxW * 0.1, pxH * 0.15)
		sprite.eyeR.Position = UDim2.fromOffset(pxW / 2 + facing * pxW * 0.1 + pxW * 0.1, pxH * 0.15)
		sprite.eyeL.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
		sprite.eyeR.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
		sprite.eyeL.Visible, sprite.eyeR.Visible = true, true
	end

	-- شريط الحياة يظهر عند التضرر فقط
	local showHp = hpPct < 99 and not def.boss
	sprite.hpBar.Visible = showHp
	if showHp then
		sprite.hpBar.Size = UDim2.fromOffset(pxW * 0.9, math.max(3, pxH * 0.06))
		sprite.hpBar.Position = UDim2.fromOffset(pxW / 2, -pxH * 0.12)
		sprite.hpFill.Size = UDim2.new(math.clamp(hpPct / 100, 0, 1), -2, 1, -2)
		sprite.hpFill.Position = UDim2.new(0, 1, 0.5, 0)
	end
end

-- ===== غرض ساقط =====

export type ItemSprite = { root: Frame, box: Frame, count: TextLabel }

function Sprites.newItem(parent: Instance): ItemSprite
	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.ZIndex = 5
	root.Parent = parent

	local box = frame(root, Color3.fromRGB(200, 200, 200), 5)
	round(box, 0.2)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 20, 24)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.35
	stroke.Parent = box

	local count = Instance.new("TextLabel")
	count.BackgroundTransparency = 1
	count.AnchorPoint = Vector2.new(0.5, 0)
	count.Font = Enum.Font.GothamBold
	count.TextSize = 12
	count.TextColor3 = Color3.fromRGB(255, 255, 255)
	count.TextStrokeTransparency = 0.2
	count.ZIndex = 7
	count.Parent = root

	return { root = root, box = box, count = count }
end

function Sprites.updateItem(sprite: ItemSprite, itemId: string, count: number, pxSize: number, age: number)
	local item = Items.get(itemId)
	local color = if item then item.color else Color3.fromRGB(200, 200, 200)
	local bob = math.sin(age * 3.5) * pxSize * 0.18

	sprite.root.Size = UDim2.fromOffset(pxSize, pxSize)
	sprite.box.BackgroundColor3 = color
	sprite.box.Size = UDim2.fromOffset(pxSize * 0.8, pxSize * 0.8)
	sprite.box.Position = UDim2.fromOffset(pxSize / 2, pxSize / 2 + bob)
	sprite.box.Rotation = math.sin(age * 2) * 8

	sprite.count.Visible = count > 1
	sprite.count.Text = tostring(count)
	sprite.count.Size = UDim2.fromOffset(pxSize * 2, pxSize * 0.6)
	sprite.count.Position = UDim2.fromOffset(pxSize / 2, pxSize * 0.85 + bob)
end

-- ===== مقذوف =====

export type ProjSprite = { root: Frame, body: Frame, trail: Frame }

function Sprites.newProjectile(parent: Instance): ProjSprite
	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.ZIndex = 6
	root.Parent = parent

	local body = frame(root, Color3.fromRGB(220, 220, 220), 7)
	round(body, 0.35)
	local trail = frame(root, Color3.fromRGB(255, 200, 120), 6)
	round(trail, 0.5)
	trail.BackgroundTransparency = 0.55

	return { root = root, body = body, trail = trail }
end

function Sprites.updateProjectile(sprite: ProjSprite, typeId: string, pxW: number, pxH: number, angle: number, age: number)
	local def = Mobs.projectiles[typeId]
	local color = if def then def.color else Color3.fromRGB(220, 220, 220)
	sprite.root.Size = UDim2.fromOffset(math.max(pxW, pxH) * 2, math.max(pxW, pxH) * 2)
	sprite.body.BackgroundColor3 = color
	sprite.body.Size = UDim2.fromOffset(pxW, pxH)
	sprite.body.Position = UDim2.fromScale(0.5, 0.5)
	sprite.body.Rotation = angle

	local hasTrail = def ~= nil and def.trail ~= nil
	sprite.trail.Visible = hasTrail
	if hasTrail then
		local pulse = 1 + math.sin(age * 22) * 0.2
		sprite.trail.BackgroundColor3 = color
		sprite.trail.Size = UDim2.fromOffset(pxW * 1.6 * pulse, pxH * 1.9 * pulse)
		sprite.trail.Position = UDim2.fromScale(0.5, 0.5)
		sprite.trail.Rotation = angle
	end
end

return Sprites
