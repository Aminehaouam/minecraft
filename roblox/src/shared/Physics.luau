--!strict
--[[
	Physics — فيزياء AABB على شبكة بلاطات.
	تُستخدم *نفس* الدالة على العميل (تنبؤ) وعلى الخادم (تحقق ومحاكاة الوحوش)،
	فتتطابق النتائج ويقل الارتداد (rubber-banding).

	نظام الإحداثيات: الوحدة = بلاطة واحدة، المحور Y يزداد للأسفل،
	و (body.x, body.y) هو *مركز* الصندوق.
]]

local Blocks = require(script.Parent.Blocks)
local Config = require(script.Parent.Config)
local World = require(script.Parent.World)

local Physics = {}

local EPS = 1e-3

export type Body = {
	x: number,
	y: number,
	w: number,
	h: number,
	vx: number,
	vy: number,
	onGround: boolean,
	inLiquid: number, -- 0 = لا شيء، وإلا معرّف السائل
	headUnder: boolean,
	dropThrough: number, -- مؤقت تجاهل المنصات
	stepUp: boolean,
}

export type Options = {
	gravity: number?,
	maxFall: number?,
	ignorePlatforms: boolean?,
	noGravity: boolean?,
}

function Physics.newBody(x: number, y: number, w: number, h: number): Body
	return {
		x = x, y = y, w = w, h = h,
		vx = 0, vy = 0,
		onGround = false,
		inLiquid = 0,
		headUnder = false,
		dropThrough = 0,
		stepUp = true,
	}
end

local function tileBlocks(world: World.World, tx: number, ty: number): boolean
	return Blocks.isSolid(World.fg(world, tx, ty))
end

-- هل تعترض هذه البلاطة الحركة الرأسية للأسفل فقط؟ (منصات)
local function tilePlatform(world: World.World, tx: number, ty: number): boolean
	return Blocks.isPlatform(World.fg(world, tx, ty))
end

function Physics.boxOverlapsSolid(world: World.World, x: number, y: number, w: number, h: number): boolean
	local left, right = x - w / 2, x + w / 2
	local top, bottom = y - h / 2, y + h / 2
	for ty = math.floor(top), math.ceil(bottom) - 1 do
		for tx = math.floor(left), math.ceil(right) - 1 do
			if tileBlocks(world, tx, ty) then return true end
		end
	end
	return false
end

-- إيجاد أقرب موضع آمن للأسفل من نقطة معينة
function Physics.findGround(world: World.World, x: number, y: number, w: number, h: number, maxScan: number?): number
	local scan = maxScan or 200
	local ty = math.floor(y)
	for i = 0, scan do
		local py = ty + i
		if not Physics.boxOverlapsSolid(world, x, py - h / 2 - 0.02, w, h) then
			if tileBlocks(world, math.floor(x), py) then
				return py - h / 2 - 0.02
			end
		end
	end
	return y
end

-- ===== الخطوة الرئيسية =====
-- ملاحظة مهمة: نقسّم الخطوة إن تجاوز الإزاحة نصف بلاطة، وإلا لأمكن لجسم سريع
-- (سقوط حر أو مقذوف) أن يعبر أرضية بسمك بلاطة واحدة بين إطارين.
local function stepOnce(world: World.World, body: Body, dt: number, opts: Options?)
	local options: Options = opts or {}
	local gravity = options.gravity or Config.GRAVITY
	local maxFall = options.maxFall or Config.MAX_FALL

	-- حالة السوائل (تُقاس عند المركز والرأس)
	local centerLiquid = World.fg(world, math.floor(body.x), math.floor(body.y))
	local headLiquidId = World.fg(world, math.floor(body.x), math.floor(body.y - body.h / 2 + 0.3))
	body.inLiquid = if Blocks.isLiquid(centerLiquid) then centerLiquid else 0
	body.headUnder = Blocks.isLiquid(headLiquidId)

	-- الجاذبية
	if not options.noGravity then
		local g = gravity
		if body.inLiquid ~= 0 then g *= 0.32 end
		body.vy += g * dt
	end

	local fallCap = if body.inLiquid ~= 0 then maxFall * 0.28 else maxFall
	if body.vy > fallCap then body.vy = fallCap end

	-- مقاومة السائل
	if body.inLiquid ~= 0 then
		local drag = math.pow(Config.WATER_DRAG, dt * 60)
		body.vx *= drag
		body.vy *= drag
	end

	if body.dropThrough > 0 then
		body.dropThrough -= dt
	end

	local prevBottom = body.y + body.h / 2

	-- ===== الحركة الأفقية =====
	local dx = body.vx * dt
	if dx ~= 0 then
		body.x += dx
		local left, right = body.x - body.w / 2, body.x + body.w / 2
		local top, bottom = body.y - body.h / 2, body.y + body.h / 2
		local hit = false
		local hitTileX = 0

		local ty0, ty1 = math.floor(top), math.ceil(bottom) - 1
		if dx > 0 then
			local tx = math.ceil(right) - 1
			for ty = ty0, ty1 do
				if tileBlocks(world, tx, ty) then hit = true; hitTileX = tx; break end
			end
			if hit then body.x = hitTileX - body.w / 2 - EPS end
		else
			local tx = math.floor(left)
			for ty = ty0, ty1 do
				if tileBlocks(world, tx, ty) then hit = true; hitTileX = tx; break end
			end
			if hit then body.x = hitTileX + 1 + body.w / 2 + EPS end
		end

		-- صعود تلقائي لبلاطة واحدة (يمنع التعثر بكل حافة كما في تيراريا)
		if hit and body.stepUp and (body.onGround or body.inLiquid ~= 0) then
			local tryX = body.x + (if dx > 0 then body.w / 2 + 0.05 else -body.w / 2 - 0.05)
			local tryY = body.y - Config.STEP_UP
			if not Physics.boxOverlapsSolid(world, tryX, tryY, body.w, body.h)
				and not Physics.boxOverlapsSolid(world, body.x, tryY, body.w, body.h) then
				body.y = tryY
				body.x += (if dx > 0 then 0.06 else -0.06)
				hit = false
			end
		end

		if hit then body.vx = 0 end
	end

	-- ===== الحركة الرأسية =====
	body.onGround = false
	local dy = body.vy * dt
	if dy ~= 0 then
		body.y += dy
		local left, right = body.x - body.w / 2, body.x + body.w / 2
		local tx0, tx1 = math.floor(left), math.ceil(right) - 1

		if dy > 0 then -- هبوط
			local ty = math.ceil(body.y + body.h / 2) - 1
			local landed = false
			for tx = tx0, tx1 do
				if tileBlocks(world, tx, ty) then
					landed = true
					break
				end
				if not options.ignorePlatforms and body.dropThrough <= 0 and tilePlatform(world, tx, ty) then
					-- المنصة تُصدّ فقط إن كنا فوقها قبل الحركة
					if prevBottom <= ty + 0.05 then
						landed = true
						break
					end
				end
			end
			if landed then
				body.y = ty - body.h / 2 - EPS
				body.vy = 0
				body.onGround = true
			end
		else -- صعود
			local ty = math.floor(body.y - body.h / 2)
			for tx = tx0, tx1 do
				if tileBlocks(world, tx, ty) then
					body.y = ty + 1 + body.h / 2 + EPS
					body.vy = 0
					break
				end
			end
		end
	end

	-- فحص إضافي: هل نلامس الأرض بلا حركة رأسية؟
	if not body.onGround and math.abs(body.vy) < 1e-4 then
		local checkY = body.y + 0.02
		if Physics.boxOverlapsSolid(world, body.x, checkY, body.w, body.h) then
			body.onGround = true
		end
	end

	-- حدود العالم
	if body.x < body.w / 2 then body.x = body.w / 2; body.vx = 0 end
	if body.x > Config.WORLD_W - body.w / 2 then body.x = Config.WORLD_W - body.w / 2; body.vx = 0 end
	if body.y < body.h / 2 then body.y = body.h / 2; body.vy = 0 end
end

local MAX_SUBSTEP_TILES = 0.5

function Physics.step(world: World.World, body: Body, dt: number, opts: Options?)
	if dt <= 0 then return end
	local travel = math.max(math.abs(body.vx), math.abs(body.vy)) * dt
	local steps = math.clamp(math.ceil(travel / MAX_SUBSTEP_TILES), 1, 12)
	if steps == 1 then
		stepOnce(world, body, dt, opts)
		return
	end

	local slice = dt / steps
	local grounded = false
	for _ = 1, steps do
		stepOnce(world, body, slice, opts)
		if body.onGround then grounded = true end
	end
	body.onGround = grounded
end

-- تسلّق (سلالم/لبلاب)
function Physics.canClimb(world: World.World, body: Body): boolean
	local tx = math.floor(body.x)
	for ty = math.floor(body.y - body.h / 2), math.ceil(body.y + body.h / 2) - 1 do
		if Blocks.isClimb(World.fg(world, tx, ty)) then return true end
	end
	return false
end

-- ضرر اللمس (حمم، صبّار…) — يُعيد أعلى قيمة ضرر ملامسة
function Physics.contactDamage(world: World.World, body: Body): number
	local worst = 0
	local left, right = body.x - body.w / 2, body.x + body.w / 2
	local top, bottom = body.y - body.h / 2, body.y + body.h / 2
	for ty = math.floor(top), math.ceil(bottom) - 1 do
		for tx = math.floor(left), math.ceil(right) - 1 do
			local block = Blocks.get(World.fg(world, tx, ty))
			if block.burn and block.burn > worst then worst = block.burn end
		end
	end
	return worst
end

-- خط رؤية بسيط بخوارزمية Bresenham على البلاطات
function Physics.lineOfSight(world: World.World, ax: number, ay: number, bx: number, by: number): boolean
	local x0, y0 = math.floor(ax), math.floor(ay)
	local x1, y1 = math.floor(bx), math.floor(by)
	local dx = math.abs(x1 - x0)
	local dy = -math.abs(y1 - y0)
	local sx = if x0 < x1 then 1 else -1
	local sy = if y0 < y1 then 1 else -1
	local err = dx + dy
	local guard = 0

	while guard < 400 do
		guard += 1
		if x0 == x1 and y0 == y1 then return true end
		if tileBlocks(world, x0, y0) then return false end
		local e2 = 2 * err
		if e2 >= dy then err += dy; x0 += sx end
		if e2 <= dx then err += dx; y0 += sy end
	end
	return false
end

return Physics
