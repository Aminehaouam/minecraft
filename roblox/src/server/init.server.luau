--!strict
--[[
	نقطة إقلاع الخادم.
	الترتيب مهم: الشبكة -> الحفظ -> الوقت -> العالم -> اللاعبون -> الكيانات -> التصنيع.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

-- أنشئ قنوات الشبكة قبل أي شيء آخر
Net.init()

local Services = require(script.Services)

Services.Save = require(script.SaveService)
Services.Time = require(script.TimeService)
Services.World = require(script.WorldService)
Services.Player = require(script.PlayerService)
Services.Entity = require(script.EntityService)
Services.Craft = require(script.CraftService)

-- لا شخصيات Roblox: اللعبة ثنائية الأبعاد بالكامل عبر الواجهة.
-- نضبطها هنا لا في ملف Rojo لأنها خاصية على خدمة Players وليست StarterPlayer.
Players.CharacterAutoLoads = false
for _, player in Players:GetPlayers() do
	if player.Character then
		player.Character:Destroy()
	end
end

Services.Time.start()
Services.World.start()
Services.Player.start()
Services.Entity.start()
Services.Craft.start()

print(string.format(
	"[TerraCraft] الخادم جاهز | البذرة: %d | نقطة الظهور: %d, %d",
	Services.World.getSeed(),
	math.floor((select(1, Services.World.getSpawn()))),
	math.floor((select(2, Services.World.getSpawn())))
))
