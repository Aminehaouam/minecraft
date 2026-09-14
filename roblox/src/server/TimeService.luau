--!strict
--[[ TimeService — دورة الليل والنهار ومزامنتها مع العملاء. ]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local TimeService = {}

local timeOfDay = Config.DAY_START -- 0..1
local dayCount = 1
local accumulator = 0
local bloodMoon = false

function TimeService.get(): number
	return timeOfDay
end

function TimeService.day(): number
	return dayCount
end

function TimeService.isNight(): boolean
	return timeOfDay >= Config.NIGHT_FROM or timeOfDay < Config.NIGHT_TO
end

function TimeService.isBloodMoon(): boolean
	return bloodMoon
end

-- شدة ضوء الشمس 0..1 مع فجر وغسق متدرجين
function TimeService.sunlight(): number
	local t = timeOfDay
	if t >= 0.27 and t <= 0.73 then return 1 end
	if t > 0.73 and t < Config.NIGHT_FROM then
		return 1 - (t - 0.73) / (Config.NIGHT_FROM - 0.73)
	end
	if t > Config.NIGHT_TO and t < 0.27 then
		return (t - Config.NIGHT_TO) / (0.27 - Config.NIGHT_TO)
	end
	return 0
end

function TimeService.set(t: number)
	timeOfDay = t % 1
	TimeService.broadcast()
end

function TimeService.broadcast(player: Player?)
	local payload = { t = timeOfDay, day = dayCount, blood = bloodMoon }
	local remote = Net.get("TimeSync")
	if player then
		remote:FireClient(player, payload)
	else
		remote:FireAllClients(payload)
	end
end

function TimeService.start()
	local wasNight = TimeService.isNight()

	RunService.Heartbeat:Connect(function(dt)
		timeOfDay += dt / Config.DAY_LENGTH
		if timeOfDay >= 1 then
			timeOfDay -= 1
			dayCount += 1
		end

		local night = TimeService.isNight()
		if night ~= wasNight then
			wasNight = night
			if night then
				-- قمر الدم: ليلة عنيفة باحتمال 10% بعد اليوم الثالث
				bloodMoon = dayCount >= 3 and math.random() < 0.10
				if bloodMoon then
					Net.get("Notify"):FireAllClients({
						text = "قمر الدم يرتفع… الوحوش أقوى الليلة!",
						color = { 220, 60, 60 },
						big = true,
					})
				end
			else
				bloodMoon = false
			end
			TimeService.broadcast()
		end

		accumulator += dt
		if accumulator >= 5 then
			accumulator = 0
			TimeService.broadcast()
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		task.wait(1)
		TimeService.broadcast(player)
	end)
end

function TimeService.serialize(): { t: number, day: number }
	return { t = timeOfDay, day = dayCount }
end

function TimeService.load(data: any)
	if type(data) == "table" then
		if type(data.t) == "number" then timeOfDay = data.t % 1 end
		if type(data.day) == "number" then dayCount = math.max(1, math.floor(data.day)) end
	end
end

return TimeService
