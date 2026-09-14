--!strict
--[[
	Services — سجل مركزي لكسر الاعتماد الدائري بين خدمات الخادم.
	يملؤه init.server.luau عند الإقلاع، وتقرأ منه بقية الوحدات.
]]

local Services = {}

Services.Save = nil :: any
Services.Time = nil :: any
Services.World = nil :: any
Services.Player = nil :: any
Services.Entity = nil :: any
Services.Combat = nil :: any
Services.Craft = nil :: any
Services.Station = nil :: any

return Services
