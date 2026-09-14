--!strict
--[[
	ArtSprites — كائنات اللعبة كنقوش بكسل.

	اللاعب والوحوش والمقذوفات كلها مرسومة بكسلاً بكسلاً، بإطارات حركة حقيقية
	(مشي، رفرفة، انضغاط) بدل تحريك مستطيلات. الدروع تُرسم بالرمادي كطبقات
	منفصلة ليُلوّنها ImageColor3 بلون المعدن مع بقاء التظليل.
]]

local Mobs = require(script.Parent.Mobs)
local Pixels = require(script.Parent.Pixels)

local ArtSprites = {}

local BLACK = Color3.fromRGB(0, 0, 0)
local WHITE = Color3.fromRGB(255, 255, 255)

local function rgb(color: Color3): (number, number, number)
	return Pixels.rgb(color)
end

local function mix(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, t)
end

-- ===== اللاعب =====

ArtSprites.PLAYER_W = 26
ArtSprites.PLAYER_H = 45
ArtSprites.PLAYER_FRAMES = { "idle", "walk1", "walk2", "walk3", "walk4", "jump" }

local SKIN = Color3.fromRGB(236, 194, 158)
local SKIN_SHADE = Color3.fromRGB(198, 154, 120)
local HAIR = Color3.fromRGB(92, 58, 38)
local SHIRT = Color3.fromRGB(86, 126, 196)
local SHIRT_SHADE = Color3.fromRGB(58, 92, 152)
local PANTS = Color3.fromRGB(58, 62, 96)
local PANTS_SHADE = Color3.fromRGB(40, 44, 72)
local BOOT = Color3.fromRGB(84, 60, 40)

-- إزاحات الأرجل والذراع لكل إطار (مشي رباعي الإطارات)
-- stride = إزاحة أفقية للقدم، lift = رفع القدم — معاً يعطيان خطوة مقروءة
local PLAYER_POSE: { [string]: { strideFront: number, strideBack: number, liftFront: number, liftBack: number, arm: number, bob: number } } = {
	idle = { strideFront = 0, strideBack = 0, liftFront = 0, liftBack = 0, arm = 0, bob = 0 },
	walk1 = { strideFront = 3, strideBack = -3, liftFront = 0, liftBack = 3, arm = -3, bob = 0 },
	walk2 = { strideFront = 1, strideBack = -1, liftFront = 0, liftBack = 0, arm = -1, bob = 1 },
	walk3 = { strideFront = -3, strideBack = 3, liftFront = 3, liftBack = 0, arm = 3, bob = 0 },
	walk4 = { strideFront = -1, strideBack = 1, liftFront = 0, liftBack = 0, arm = 1, bob = 1 },
	jump = { strideFront = -3, strideBack = 3, liftFront = 4, liftBack = 1, arm = -5, bob = -1 },
}

function ArtSprites.paintPlayer(frame: string): Pixels.Canvas
	local canvas = Pixels.new(ArtSprites.PLAYER_W, ArtSprites.PLAYER_H)
	local pose = PLAYER_POSE[frame] or PLAYER_POSE.idle
	local cx = ArtSprites.PLAYER_W // 2
	local bob = pose.bob

	local sr, sg, sb = rgb(SKIN)
	local ssr, ssg, ssb = rgb(SKIN_SHADE)
	local hr, hg, hb = rgb(HAIR)
	local tr, tg, tb = rgb(SHIRT)
	local tsr, tsg, tsb = rgb(SHIRT_SHADE)
	local pr, pg, pb = rgb(PANTS)
	local psr, psg, psb = rgb(PANTS_SHADE)
	local br, bg, bb = rgb(BOOT)

	-- ===== الأرجل =====
	-- كل رجل: فخذ ثابت من الحوض، ثم ساق تُزاح أفقياً وتُرفع، وحذاء عند طرفها
	local hipY = 30 + bob
	local function drawLeg(baseX: number, stride: number, lift: number, thighR: number, thighG: number, thighB: number)
		local footX = baseX + stride
		local footY = hipY + 10 - lift
		-- الفخذ يصل الحوض بالساق
		for step = 0, 5 do
			local t = step / 5
			local x = math.floor(baseX + stride * t * 0.6)
			Pixels.fill(canvas, x, hipY + step, 4, 2, thighR, thighG, thighB, 255)
		end
		-- الساق
		Pixels.fill(canvas, footX, hipY + 5, 4, math.max(2, 6 - lift), thighR, thighG, thighB, 255)
		-- الحذاء
		Pixels.fill(canvas, footX - 1, footY, 6, 4, br, bg, bb, 255)
		Pixels.fill(canvas, footX - 1, footY + 3, 6, 1, rgb(mix(BOOT, BLACK, 0.35)))
	end

	drawLeg(cx - 5, pose.strideBack, pose.liftBack, psr, psg, psb)
	drawLeg(cx + 1, pose.strideFront, pose.liftFront, pr, pg, pb)

	-- ===== الجذع =====
	local torsoTop = 17 + bob
	Pixels.fill(canvas, cx - 6, torsoTop, 12, 14, tr, tg, tb, 255)
	Pixels.fill(canvas, cx - 6, torsoTop, 12, 2, rgb(mix(SHIRT, WHITE, 0.25)))
	Pixels.fill(canvas, cx + 3, torsoTop, 3, 14, tsr, tsg, tsb, 255)
	Pixels.fill(canvas, cx - 6, torsoTop + 12, 12, 2, tsr, tsg, tsb, 255)
	-- حزام
	Pixels.fill(canvas, cx - 6, torsoTop + 13, 12, 2, rgb(mix(BOOT, BLACK, 0.2)))

	-- ===== الذراع الأمامية =====
	local armTop = torsoTop + 2 + pose.arm
	Pixels.fill(canvas, cx + 5, armTop, 4, 11, tsr, tsg, tsb, 255)
	Pixels.fill(canvas, cx + 5, armTop + 9, 4, 4, sr, sg, sb, 255)

	-- ===== الرأس =====
	local headTop = 4 + bob
	Pixels.fill(canvas, cx - 6, headTop, 12, 12, sr, sg, sb, 255)
	Pixels.fill(canvas, cx + 4, headTop + 1, 2, 11, ssr, ssg, ssb, 255)
	Pixels.fill(canvas, cx - 6, headTop + 11, 12, 1, ssr, ssg, ssb, 255)
	-- شعر
	Pixels.fill(canvas, cx - 7, headTop - 2, 14, 4, hr, hg, hb, 255)
	Pixels.fill(canvas, cx - 7, headTop - 2, 14, 1, rgb(mix(HAIR, WHITE, 0.2)))
	Pixels.fill(canvas, cx - 7, headTop, 2, 6, hr, hg, hb, 255)
	-- عين (باتجاه اليمين)
	Pixels.fill(canvas, cx + 1, headTop + 5, 2, 3, 32, 28, 38, 255)
	Pixels.set(canvas, cx + 1, headTop + 5, 255, 255, 255, 220)
	-- فم
	Pixels.fill(canvas, cx + 2, headTop + 9, 2, 1, ssr, ssg, ssb, 255)
	-- رقبة
	Pixels.fill(canvas, cx - 3, headTop + 12, 6, 2, ssr, ssg, ssb, 255)

	return canvas
end

-- طبقة خوذة رمادية (تُلوَّن لاحقاً بلون المعدن)
function ArtSprites.paintHelmet(frame: string): Pixels.Canvas
	local canvas = Pixels.new(ArtSprites.PLAYER_W, ArtSprites.PLAYER_H)
	local pose = PLAYER_POSE[frame] or PLAYER_POSE.idle
	local cx = ArtSprites.PLAYER_W // 2
	local headTop = 4 + pose.bob

	Pixels.fill(canvas, cx - 7, headTop - 3, 14, 7, 200, 200, 200, 255)
	Pixels.fill(canvas, cx - 7, headTop - 3, 14, 2, 245, 245, 245, 255)
	Pixels.fill(canvas, cx - 7, headTop + 4, 3, 7, 170, 170, 170, 255)
	Pixels.fill(canvas, cx + 4, headTop + 4, 3, 7, 140, 140, 140, 255)
	-- قمة الخوذة
	Pixels.fill(canvas, cx - 1, headTop - 5, 3, 3, 225, 225, 225, 255)
	return canvas
end

function ArtSprites.paintChestplate(frame: string): Pixels.Canvas
	local canvas = Pixels.new(ArtSprites.PLAYER_W, ArtSprites.PLAYER_H)
	local pose = PLAYER_POSE[frame] or PLAYER_POSE.idle
	local cx = ArtSprites.PLAYER_W // 2
	local torsoTop = 17 + pose.bob

	Pixels.fill(canvas, cx - 7, torsoTop - 1, 14, 13, 200, 200, 200, 255)
	Pixels.fill(canvas, cx - 7, torsoTop - 1, 14, 2, 245, 245, 245, 255)
	Pixels.fill(canvas, cx + 3, torsoTop - 1, 4, 13, 150, 150, 150, 255)
	Pixels.fill(canvas, cx - 7, torsoTop + 10, 14, 2, 130, 130, 130, 255)
	-- كتفان
	Pixels.fill(canvas, cx - 9, torsoTop, 3, 5, 215, 215, 215, 255)
	Pixels.fill(canvas, cx + 6, torsoTop, 3, 5, 175, 175, 175, 255)
	return canvas
end

-- ===== الوحوش =====

local MOB_SHAPE: { [string]: string } = {
	slime = "blob", ice_slime = "blob", sand_slime = "blob",
	zombie = "humanoid", skeleton = "humanoid", stone_golem = "humanoid",
	bat = "flyer", cave_wasp = "flyer", lava_imp = "flyer",
	demon_eye = "eye", eye_of_depths = "eye",
	spider = "crawler", shadow_crawler = "crawler",
}

function ArtSprites.shapeOf(mobId: string): string
	return MOB_SHAPE[mobId] or "humanoid"
end

function ArtSprites.mobFrames(mobId: string): number
	local shape = ArtSprites.shapeOf(mobId)
	if shape == "humanoid" then return 4 end
	return 2
end

function ArtSprites.mobSize(mobId: string): (number, number)
	local def = Mobs.get(mobId)
	if not def then return 16, 16 end
	return math.max(8, math.floor(def.w * 16 + 0.5)), math.max(8, math.floor(def.h * 16 + 0.5))
end

local function drawBlob(canvas: Pixels.Canvas, w: number, h: number, def: Mobs.MobDef, frame: number)
	local squash = if frame == 1 then 1.0 else 0.86
	local bodyH = math.floor(h * squash)
	local top = h - bodyH
	local cx = w / 2 - 0.5
	local cy = top + bodyH / 2

	local r, g, b = rgb(def.color)
	local dark = mix(def.color, BLACK, 0.3)
	local light = mix(def.color, WHITE, 0.35)

	Pixels.ellipse(canvas, cx, cy, w / 2 - 0.5, bodyH / 2 - 0.5, r, g, b, 232)
	Pixels.ellipse(canvas, cx, cy + bodyH * 0.22, w / 2 - 1.5, bodyH * 0.26, rgb(dark))
	Pixels.ellipse(canvas, cx - w * 0.2, cy - bodyH * 0.22, w * 0.16, bodyH * 0.18, rgb(light))

	-- عينان
	local eyeY = math.floor(cy - bodyH * 0.05)
	local eyeDx = math.floor(w * 0.17)
	for _, dx in { -eyeDx, eyeDx } do
		Pixels.fill(canvas, math.floor(cx + dx) - 1, eyeY - 1, 3, 3, 22, 20, 28, 255)
		Pixels.set(canvas, math.floor(cx + dx) - 1, eyeY - 1, 255, 255, 255, 220)
	end
	-- فم
	Pixels.fill(canvas, math.floor(cx) - 1, eyeY + 3, 3, 1, 22, 20, 28, 200)
end

local function drawHumanoid(canvas: Pixels.Canvas, w: number, h: number, def: Mobs.MobDef, frame: number)
	local swing = ({ 0, 3, 0, -3 })[frame] or 0
	local cx = w // 2
	local r, g, b = rgb(def.color)
	local ar, ag, ab = rgb(def.accent)
	local dark = mix(def.color, BLACK, 0.32)
	local light = mix(def.color, WHITE, 0.22)

	local headH = math.floor(h * 0.26)
	local torsoH = math.floor(h * 0.36)
	local legH = h - headH - torsoH - 1

	-- أرجل
	local legTop = headH + torsoH
	Pixels.fill(canvas, cx - math.floor(w * 0.26), legTop + math.max(0, swing), math.floor(w * 0.2), legH - math.abs(swing) // 2, ar, ag, ab, 255)
	Pixels.fill(canvas, cx + math.floor(w * 0.06), legTop + math.max(0, -swing), math.floor(w * 0.2), legH - math.abs(swing) // 2, ar, ag, ab, 255)

	-- جذع
	Pixels.fill(canvas, cx - math.floor(w * 0.3), headH, math.floor(w * 0.6), torsoH, r, g, b, 255)
	Pixels.fill(canvas, cx - math.floor(w * 0.3), headH, math.floor(w * 0.6), 2, rgb(light))
	Pixels.fill(canvas, cx + math.floor(w * 0.14), headH, math.floor(w * 0.16), torsoH, rgb(dark))

	-- ذراع ممدودة أمامها (مشية الزومبي)
	Pixels.fill(canvas, cx + math.floor(w * 0.24), headH + 2 - swing, math.floor(w * 0.24), math.floor(torsoH * 0.45), r, g, b, 255)

	-- رأس
	Pixels.fill(canvas, cx - math.floor(w * 0.26), 1, math.floor(w * 0.52), headH - 1, r, g, b, 255)
	Pixels.fill(canvas, cx - math.floor(w * 0.26), 1, math.floor(w * 0.52), 1, rgb(light))
	Pixels.fill(canvas, cx + math.floor(w * 0.12), 1, math.floor(w * 0.14), headH - 1, rgb(dark))

	-- عينان متوهجتان
	local eyeY = math.floor(headH * 0.5)
	Pixels.fill(canvas, cx - math.floor(w * 0.16), eyeY, 2, 2, 226, 62, 62, 255)
	Pixels.fill(canvas, cx + math.floor(w * 0.06), eyeY, 2, 2, 226, 62, 62, 255)
end

local function drawFlyer(canvas: Pixels.Canvas, w: number, h: number, def: Mobs.MobDef, frame: number)
	local cx = w / 2 - 0.5
	local cy = h / 2
	local r, g, b = rgb(def.color)
	local ar, ag, ab = rgb(def.accent)
	local light = mix(def.color, WHITE, 0.3)

	-- جناحان غشائيان: مثلّثان متصلان بالجسم، أعلى في إطار وأسفل في الآخر
	local up = frame == 1
	local tipY = if up then cy - h * 0.42 else cy + h * 0.3
	local membrane = mix(def.accent, BLACK, 0.15)
	local mr, mg, mb = rgb(membrane)

	for side = -1, 1, 2 do
		local rootX = cx + side * w * 0.16
		local tipX = cx + side * w * 0.48
		-- املأ الغشاء بخطوط من الجذر إلى الحافة
		for k = 0, 6 do
			local t = k / 6
			Pixels.line(canvas,
				math.floor(rootX), math.floor(cy - h * 0.06),
				math.floor(rootX + (tipX - rootX) * (0.45 + t * 0.55)),
				math.floor(cy + (tipY - cy) * t),
				mr, mg, mb, 245)
		end
		-- عظام الجناح أغمق
		Pixels.line(canvas, math.floor(rootX), math.floor(cy - h * 0.06),
			math.floor(tipX), math.floor(tipY), ar, ag, ab, 255)
	end

	-- جسم بيضاوي وأذنان صغيرتان
	Pixels.ellipse(canvas, cx, cy, w * 0.2, h * 0.3, r, g, b, 255)
	Pixels.ellipse(canvas, cx - w * 0.06, cy - h * 0.12, w * 0.08, h * 0.1, rgb(light))
	Pixels.set(canvas, math.floor(cx - w * 0.12), math.floor(cy - h * 0.3), ar, ag, ab, 255)
	Pixels.set(canvas, math.floor(cx + w * 0.12), math.floor(cy - h * 0.3), ar, ag, ab, 255)

	-- عينان
	Pixels.set(canvas, math.floor(cx - w * 0.08), math.floor(cy - h * 0.06), 250, 226, 96, 255)
	Pixels.set(canvas, math.floor(cx + w * 0.08), math.floor(cy - h * 0.06), 250, 226, 96, 255)
end

local function drawCrawler(canvas: Pixels.Canvas, w: number, h: number, def: Mobs.MobDef, frame: number)
	local cx = w / 2 - 0.5
	local cy = h * 0.45
	local r, g, b = rgb(def.color)
	local ar, ag, ab = rgb(def.accent)
	local light = mix(def.color, WHITE, 0.25)

	-- أرجل (أربع لكل جانب بزوايا متبادلة)
	local phase = if frame == 1 then 1 else -1
	for i = 0, 3 do
		local offset = (i - 1.5) * (w * 0.16)
		local drop = h * (0.28 + (i % 2) * 0.12) * (if i % 2 == 0 then 1 else phase * 0.8)
		Pixels.line(canvas,
			math.floor(cx - w * 0.16), math.floor(cy),
			math.floor(cx - w * 0.42 + offset * 0.3), math.floor(cy + drop),
			ar, ag, ab, 255)
		Pixels.line(canvas,
			math.floor(cx + w * 0.16), math.floor(cy),
			math.floor(cx + w * 0.42 + offset * 0.3), math.floor(cy + drop),
			ar, ag, ab, 255)
	end

	-- بطن ورأس
	Pixels.ellipse(canvas, cx - w * 0.1, cy, w * 0.26, h * 0.3, r, g, b, 255)
	Pixels.ellipse(canvas, cx + w * 0.22, cy - h * 0.04, w * 0.16, h * 0.2, rgb(light))
	-- عيون حمراء
	Pixels.set(canvas, math.floor(cx + w * 0.26), math.floor(cy - h * 0.1), 230, 70, 70, 255)
	Pixels.set(canvas, math.floor(cx + w * 0.3), math.floor(cy), 230, 70, 70, 255)
end

local function drawEye(canvas: Pixels.Canvas, w: number, h: number, def: Mobs.MobDef, frame: number)
	local cx = w / 2 - 0.5
	local cy = h / 2 - 0.5
	local radius = math.min(w, h) * 0.42
	local pulse = if frame == 1 then 1 else 0.93

	local r, g, b = rgb(def.color)
	local ar, ag, ab = rgb(def.accent)

	-- أهداب/زوائد حول العين (للزعيم)
	if w >= 40 then
		for i = 0, 7 do
			local angle = i * math.pi / 4 + (if frame == 1 then 0 else 0.2)
			Pixels.line(canvas,
				math.floor(cx + math.cos(angle) * radius * 0.9),
				math.floor(cy + math.sin(angle) * radius * 0.9),
				math.floor(cx + math.cos(angle) * radius * 1.35),
				math.floor(cy + math.sin(angle) * radius * 1.35),
				ar, ag, ab, 255)
		end
	end

	-- مقلة
	Pixels.ellipse(canvas, cx, cy, radius, radius * pulse, r, g, b, 255)
	Pixels.ellipse(canvas, cx, cy, radius * 0.92, radius * pulse * 0.92, 245, 242, 238, 255)
	-- عروق
	for i = 0, 4 do
		local angle = i * 1.25 + 0.4
		Pixels.line(canvas,
			math.floor(cx + math.cos(angle) * radius * 0.4),
			math.floor(cy + math.sin(angle) * radius * 0.4),
			math.floor(cx + math.cos(angle) * radius * 0.88),
			math.floor(cy + math.sin(angle) * radius * 0.88),
			220, 120, 120, 190)
	end
	-- قزحية وبؤبؤ (تنظر لليمين)
	local irisX = cx + radius * 0.28
	Pixels.ellipse(canvas, irisX, cy, radius * 0.42, radius * 0.42, ar, ag, ab, 255)
	Pixels.ellipse(canvas, irisX, cy, radius * 0.2, radius * 0.24, 18, 14, 20, 255)
	Pixels.ellipse(canvas, irisX - radius * 0.16, cy - radius * 0.16, radius * 0.1, radius * 0.1, 255, 255, 255, 235)
end

function ArtSprites.paintMob(mobId: string, frame: number): Pixels.Canvas
	local def = Mobs.get(mobId)
	local w, h = ArtSprites.mobSize(mobId)
	local canvas = Pixels.new(w, h)
	if not def then return canvas end

	local shape = ArtSprites.shapeOf(mobId)
	if shape == "blob" then
		drawBlob(canvas, w, h, def, frame)
	elseif shape == "flyer" then
		drawFlyer(canvas, w, h, def, frame)
	elseif shape == "crawler" then
		drawCrawler(canvas, w, h, def, frame)
	elseif shape == "eye" then
		drawEye(canvas, w, h, def, frame)
	else
		drawHumanoid(canvas, w, h, def, frame)
	end
	return canvas
end

-- ===== المقذوفات =====

ArtSprites.PROJECTILE_SIZE = 16

function ArtSprites.paintProjectile(projId: string): Pixels.Canvas
	local size = ArtSprites.PROJECTILE_SIZE
	local canvas = Pixels.new(size, size)
	local def = Mobs.projectiles[projId]
	local color = if def then def.color else Color3.fromRGB(230, 230, 230)
	local r, g, b = rgb(color)
	local light = mix(color, WHITE, 0.5)
	local lr, lg, lb = rgb(light)
	local cy = size // 2

	if projId == "arrow" or projId == "fire_arrow" or projId == "bone_shot" then
		-- سهم أفقي يتجه لليمين
		Pixels.fill(canvas, 2, cy - 1, 10, 2, r, g, b, 255)
		Pixels.fill(canvas, 11, cy - 2, 4, 4, lr, lg, lb, 255)
		Pixels.set(canvas, 14, cy, 255, 255, 255, 255)
		Pixels.fill(canvas, 1, cy - 3, 3, 2, 235, 235, 235, 235)
		Pixels.fill(canvas, 1, cy + 1, 3, 2, 235, 235, 235, 235)
		if projId == "fire_arrow" then
			Pixels.ellipse(canvas, 4, cy, 3, 2.4, 250, 150, 60, 170)
		end
	else
		-- كرة طاقة متوهّجة
		Pixels.disc(canvas, size / 2, cy, 5.4, r, g, b, 120)
		Pixels.disc(canvas, size / 2, cy, 4, r, g, b, 220)
		Pixels.disc(canvas, size / 2, cy, 2.4, lr, lg, lb, 255)
		Pixels.disc(canvas, size / 2 - 1, cy - 1, 1.2, 255, 255, 255, 255)
	end
	return canvas
end

return ArtSprites
