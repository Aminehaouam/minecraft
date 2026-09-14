--!strict
--[[
	Sfx — أصوات اللعبة.
	نستعمل أصوات العميل المدمجة (rbxasset) فلا تحتاج رفع أي أصول.
	إن أردت أصواتاً أفضل: ضع معرّفات rbxassetid في الجدول أدناه.
]]

local SoundService = game:GetService("SoundService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Blocks = require(Shared.Blocks)

local Sfx = {}

local LIBRARY: { [string]: { id: string, volume: number, pitch: number } } = {
	jump = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.35, pitch = 1.1 },
	land = { id = "rbxasset://sounds/action_footsteps_plastic.mp3", volume = 0.4, pitch = 0.8 },
	step = { id = "rbxasset://sounds/action_footsteps_plastic.mp3", volume = 0.18, pitch = 1.05 },
	swing = { id = "rbxasset://sounds/snap.mp3", volume = 0.28, pitch = 1.35 },
	mine_soft = { id = "rbxasset://sounds/action_footsteps_plastic.mp3", volume = 0.22, pitch = 0.7 },
	mine_hard = { id = "rbxasset://sounds/clickfast.wav", volume = 0.3, pitch = 0.65 },
	mine_wood = { id = "rbxasset://sounds/snap.mp3", volume = 0.25, pitch = 0.75 },
	break_block = { id = "rbxasset://sounds/bass.wav", volume = 0.3, pitch = 1.6 },
	place = { id = "rbxasset://sounds/switch3.wav", volume = 0.3, pitch = 1.2 },
	hurt = { id = "rbxasset://sounds/uuhhh.mp3", volume = 0.45, pitch = 1 },
	pickup = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.28, pitch = 1.5 },
	craft = { id = "rbxasset://sounds/switch3.wav", volume = 0.4, pitch = 0.9 },
	splash = { id = "rbxasset://sounds/impact_water.mp3", volume = 0.4, pitch = 1 },
	ui = { id = "rbxasset://sounds/clickfast.wav", volume = 0.25, pitch = 1.3 },
}

local pool: { Sound } = {}
local muted = false

local function acquire(): Sound
	local sound = table.remove(pool)
	if sound then return sound end
	sound = Instance.new("Sound")
	sound.Parent = SoundService
	return sound
end

function Sfx.setMuted(value: boolean)
	muted = value
end

function Sfx.play(name: string, pitchJitter: number?)
	if muted then return end
	local entry = LIBRARY[name]
	if not entry then return end

	local ok = pcall(function()
		local sound = acquire()
		sound.SoundId = entry.id
		sound.Volume = entry.volume
		sound.PlaybackSpeed = entry.pitch + (math.random() - 0.5) * (pitchJitter or 0.12)
		sound.TimePosition = 0
		sound:Play()
		task.delay(3, function()
			sound:Stop()
			if #pool < 24 then
				table.insert(pool, sound)
			else
				sound:Destroy()
			end
		end)
	end)
	if not ok then
		-- صوت غير متاح: تجاهل بصمت بدل إيقاف اللعبة
	end
end

-- صوت مناسب لنوع البلاطة
function Sfx.block(action: string, blockId: number)
	local block = Blocks.get(blockId)
	local material = block.sound or "hard"
	if action == "break" then
		Sfx.play("break_block")
	else
		if material == "wood" then
			Sfx.play("mine_wood")
		elseif material == "soft" then
			Sfx.play("mine_soft")
		else
			Sfx.play("mine_hard")
		end
	end
end

return Sfx
