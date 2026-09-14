--!strict
--[[ Fx — الجسيمات وأرقام الضرر والمؤثرات اللحظية. ]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Blocks = require(Shared.Blocks)
local Items = require(Shared.Items)

local Renderer = require(script.Parent.Renderer)
local State = require(script.Parent.State)

local Fx = {}

type Particle = {
	frame: Frame,
	x: number,
	y: number,
	vx: number,
	vy: number,
	life: number,
	maxLife: number,
	gravity: number,
	size: number,
	fade: boolean,
}

type FloatText = {
	label: TextLabel,
	x: number,
	y: number,
	vy: number,
	life: number,
	maxLife: number,
}

local particles: { Particle } = {}
local texts: { FloatText } = {}
local particlePool: { Frame } = {}
local textPool: { TextLabel } = {}

local MAX_PARTICLES = 220
local MAX_TEXTS = 40

local function acquireParticle(): Frame
	local frame = table.remove(particlePool)
	if frame then
		frame.Visible = true
		return frame
	end
	frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.ZIndex = 9
	frame.Parent = Renderer.fxLayer()
	return frame
end

local function releaseParticle(frame: Frame)
	frame.Visible = false
	table.insert(particlePool, frame)
end

local function acquireText(): TextLabel
	local label = table.remove(textPool)
	if label then
		label.Visible = true
		return label
	end
	label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Font = Enum.Font.Arcade -- أرقام بخط بكسلي يطابق أسلوب اللعبة
	label.TextStrokeTransparency = 0.15
	label.ZIndex = 12
	label.Size = UDim2.fromOffset(140, 26)
	label.Parent = Renderer.fxLayer()
	return label
end

local function releaseText(label: TextLabel)
	label.Visible = false
	table.insert(textPool, label)
end

-- ===== الإنشاء =====

function Fx.particle(x: number, y: number, vx: number, vy: number, color: Color3, size: number, life: number, gravity: number?)
	if #particles >= MAX_PARTICLES then return end
	local frame = acquireParticle()
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 0
	frame.Rotation = math.random(0, 90)
	table.insert(particles, {
		frame = frame, x = x, y = y, vx = vx, vy = vy,
		life = life, maxLife = life, gravity = gravity or 30,
		size = size, fade = true,
	})
end

function Fx.blockBurst(tx: number, ty: number, blockId: number, amount: number?)
	local block = Blocks.get(blockId)
	if blockId == 0 then return end
	local count = amount or 7
	for _ = 1, count do
		Fx.particle(
			tx + 0.2 + math.random() * 0.6,
			ty + 0.2 + math.random() * 0.6,
			(math.random() - 0.5) * 7,
			-math.random() * 6 - 1,
			block.color,
			0.18 + math.random() * 0.14,
			0.45 + math.random() * 0.35
		)
	end
end

function Fx.burst(x: number, y: number, color: Color3, count: number, power: number, life: number?, gravity: number?)
	for _ = 1, count do
		local angle = math.random() * math.pi * 2
		local speed = power * (0.35 + math.random() * 0.65)
		Fx.particle(
			x, y,
			math.cos(angle) * speed,
			math.sin(angle) * speed,
			color,
			0.16 + math.random() * 0.18,
			life or (0.4 + math.random() * 0.4),
			gravity
		)
	end
end

function Fx.text(x: number, y: number, message: string, color: Color3, size: number?)
	if #texts >= MAX_TEXTS then
		local oldest = table.remove(texts, 1)
		if oldest then releaseText(oldest.label) end
	end
	local label = acquireText()
	label.Text = message
	label.TextColor3 = color
	label.TextSize = size or 18
	label.TextTransparency = 0
	table.insert(texts, {
		label = label, x = x, y = y,
		vy = -2.6, life = 0.95, maxLife = 0.95,
	})
end

function Fx.damage(x: number, y: number, amount: number, crit: boolean, mine: boolean)
	local color = if crit then Color3.fromRGB(255, 210, 90)
		elseif mine then Color3.fromRGB(255, 120, 120)
		else Color3.fromRGB(255, 245, 230)
	Fx.text(x + (math.random() - 0.5) * 0.6, y, tostring(amount), color, if crit then 24 else 18)
end

function Fx.pickup(x: number, y: number, itemId: string, count: number)
	local item = Items.get(itemId)
	local name = if item then item.name else itemId
	local color = if item then item.color else Color3.fromRGB(240, 240, 240)
	Fx.text(x, y - 1, string.format("%s ×%d", name, count), color, 15)
end

-- ===== التحديث =====

function Fx.update(dt: number)
	local tile = Renderer.tileSize()

	for i = #particles, 1, -1 do
		local particle = particles[i]
		particle.life -= dt
		if particle.life <= 0 then
			releaseParticle(particle.frame)
			table.remove(particles, i)
		else
			particle.vy += particle.gravity * dt
			particle.x += particle.vx * dt
			particle.y += particle.vy * dt
			local pxSize = particle.size * tile
			particle.frame.Size = UDim2.fromOffset(pxSize, pxSize)
			particle.frame.Position = UDim2.fromOffset(particle.x * tile, particle.y * tile)
			particle.frame.BackgroundTransparency = 1 - (particle.life / particle.maxLife)
		end
	end

	for i = #texts, 1, -1 do
		local entry = texts[i]
		entry.life -= dt
		if entry.life <= 0 then
			releaseText(entry.label)
			table.remove(texts, i)
		else
			entry.y += entry.vy * dt
			entry.vy += 3.2 * dt
			local alpha = 1 - (entry.life / entry.maxLife)
			entry.label.Position = UDim2.fromOffset(entry.x * tile, entry.y * tile)
			entry.label.TextTransparency = math.max(0, alpha * alpha)
			entry.label.TextStrokeTransparency = 0.25 + alpha * 0.75
		end
	end
end

-- ===== معالجة رسائل المؤثرات من الخادم =====

function Fx.handle(payload: any)
	if type(payload) ~= "table" then return end
	local kind = payload.kind

	if kind == "break" then
		Fx.blockBurst(payload.x, payload.y, payload.block, 9)
	elseif kind == "place" then
		Fx.blockBurst(payload.x, payload.y, payload.block, 4)
	elseif kind == "mob_death" then
		Fx.burst(payload.x, payload.y, Color3.fromRGB(200, 60, 60), 16, 9)
	elseif kind == "burn_away" then
		Fx.burst(payload.x, payload.y, Color3.fromRGB(250, 170, 70), 14, 7)
	elseif kind == "death" then
		Fx.burst(payload.x, payload.y, Color3.fromRGB(220, 50, 50), 26, 12)
		Renderer.shake(20, 0.5)
	elseif kind == "proj_hit" then
		Fx.burst(payload.x, payload.y, Color3.fromRGB(240, 200, 140), 8, 6, 0.3)
	elseif kind == "teleport" then
		Fx.burst(payload.x, payload.y, Color3.fromRGB(160, 200, 250), 24, 10, 0.6, 0)
	elseif kind == "consume" then
		local item = Items.get(payload.item)
		Fx.burst(payload.x, payload.y, if item then item.color else Color3.fromRGB(240, 240, 240), 10, 5, 0.5, -6)
	elseif kind == "craft" then
		Fx.pickup(payload.x, payload.y - 1.5, payload.item, payload.count)
	elseif kind == "pickup" then
		Fx.pickup(payload.x, payload.y, payload.item, payload.count)
	elseif kind == "swing" then
		if payload.player ~= State.userId then return end
	elseif kind == "chest_open" then
		Fx.burst(payload.x, payload.y, Color3.fromRGB(200, 160, 90), 6, 4, 0.35)
	elseif kind == "upgrade" then
		Fx.burst(payload.x, payload.y - 1, Color3.fromRGB(250, 205, 110), 22, 8, 0.7, -4)
		Fx.text(payload.x, payload.y - 2, "تمّ التطوير!", Color3.fromRGB(250, 210, 110), 20)
	elseif kind == "enchant" then
		Fx.burst(payload.x, payload.y - 1, Color3.fromRGB(180, 150, 250), 26, 9, 0.8, -5)
		Fx.text(payload.x, payload.y - 2, "سِحر!", Color3.fromRGB(190, 150, 250), 20)
	elseif kind == "boss_charge" then
		Renderer.shake(12, 0.3)
		Fx.burst(payload.x, payload.y, Color3.fromRGB(220, 60, 70), 20, 12, 0.5, 0)
	elseif kind == "boss_phase" then
		Renderer.shake(26, 0.7)
		Fx.burst(payload.x, payload.y, Color3.fromRGB(255, 90, 90), 40, 16, 0.9, 0)
	end
end

function Fx.handleHit(payload: any)
	if type(payload) ~= "table" then return end
	if payload.kind == "mob" then
		Fx.damage(payload.x, payload.y, payload.amount, payload.crit == true, false)
		Fx.burst(payload.x, payload.y, Color3.fromRGB(220, 80, 80), 5, 5, 0.3)
	elseif payload.kind == "player" then
		local mine = payload.player == State.userId
		Fx.damage(payload.x, payload.y - 1.4, payload.amount, false, mine)
		if mine then
			Renderer.shake(9, 0.22)
		end
	elseif payload.kind == "heal" then
		Fx.text(payload.x, payload.y - 1.4, "+" .. tostring(payload.amount), Color3.fromRGB(120, 240, 140), 18)
	end
end

return Fx
