--!strict
--[[
	SaveService — غلاف DataStore مع إعادة محاولة، وذاكرة احتياطية عند غياب الوصول
	(مثلاً في Studio بلا API access) حتى لا تنهار اللعبة أثناء التطوير.
]]

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local SaveService = {}

local playerStore: DataStore? = nil
local worldStore: DataStore? = nil
local available = true
local memory: { [string]: any } = {} -- احتياطي في الذاكرة

do
	local ok, err = pcall(function()
		playerStore = DataStoreService:GetDataStore(Config.DATASTORE_PLAYER)
		worldStore = DataStoreService:GetDataStore(Config.DATASTORE_WORLD)
	end)
	if not ok then
		available = false
		warn("[SaveService] DataStore غير متاح، سيتم الحفظ في الذاكرة فقط: " .. tostring(err))
	end
end

local function retry<T>(label: string, fn: () -> T): (boolean, T?)
	local delayTime = 0.5
	for attempt = 1, 4 do
		local ok, result = pcall(fn)
		if ok then return true, result end
		if attempt == 4 then
			warn(string.format("[SaveService] فشل %s بعد %d محاولات: %s", label, attempt, tostring(result)))
			return false, nil
		end
		task.wait(delayTime)
		delayTime *= 2
	end
	return false, nil
end

function SaveService.isAvailable(): boolean
	return available
end

-- ===== بيانات اللاعب =====
function SaveService.loadPlayer(userId: number): any?
	local key = "p_" .. userId
	if not available or not playerStore then return memory[key] end
	local ok, data = retry("تحميل بيانات اللاعب", function()
		return (playerStore :: DataStore):GetAsync(key)
	end)
	if ok then return data end
	return memory[key]
end

function SaveService.savePlayer(userId: number, data: any): boolean
	local key = "p_" .. userId
	memory[key] = data
	if not available or not playerStore then return false end
	local ok = retry("حفظ بيانات اللاعب", function()
		(playerStore :: DataStore):SetAsync(key, data)
		return true
	end)
	return ok
end

-- ===== بيانات العالم =====
function SaveService.loadMeta(): any?
	local key = "meta_" .. Config.WORLD_NAME
	if not available or not worldStore then return memory[key] end
	local ok, data = retry("تحميل بيانات العالم", function()
		return (worldStore :: DataStore):GetAsync(key)
	end)
	if ok then return data end
	return memory[key]
end

function SaveService.saveMeta(data: any): boolean
	local key = "meta_" .. Config.WORLD_NAME
	memory[key] = data
	if not available or not worldStore then return false end
	return (retry("حفظ بيانات العالم", function()
		(worldStore :: DataStore):SetAsync(key, data)
		return true
	end))
end

-- ===== مناطق التعديلات =====
-- المنطقة = REGION×REGION قطعة، تُخزَّن في مفتاح واحد لتقليل عدد طلبات DataStore.
function SaveService.regionKey(rx: number, ry: number): string
	return string.format("w_%s_%d_%d", Config.WORLD_NAME, rx, ry)
end

function SaveService.loadRegion(rx: number, ry: number): { [string]: { number } }?
	local key = SaveService.regionKey(rx, ry)
	if not available or not worldStore then return memory[key] end
	local ok, data = retry("تحميل منطقة", function()
		return (worldStore :: DataStore):GetAsync(key)
	end)
	if ok and type(data) == "table" then return data end
	return memory[key]
end

function SaveService.saveRegion(rx: number, ry: number, payload: { [string]: { number } }): boolean
	local key = SaveService.regionKey(rx, ry)
	memory[key] = payload
	if not available or not worldStore then return false end
	return (retry("حفظ منطقة", function()
		(worldStore :: DataStore):SetAsync(key, payload)
		return true
	end))
end

-- في Studio نعطّل الكتابة الفعلية إن أراد المطوّر ذلك
function SaveService.setEnabled(enabled: boolean)
	available = enabled and not RunService:IsStudio() or enabled
end

return SaveService
