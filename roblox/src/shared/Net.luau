--!strict
--[[
	Net — تعريف قنوات الشبكة في مكان واحد.
	الخادم ينشئها، والعميل ينتظرها. الحزم عالية التردد تستعمل UnreliableRemoteEvent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

-- اسم القناة -> هل هي غير موثوقة (للحزم المتكررة التي لا يضرّ ضياعها)
local CHANNELS: { [string]: boolean } = {
	Hello = false, -- بداية الجلسة: البذرة، نقطة الظهور، البيانات المحفوظة
	RequestChunks = false, -- العميل يطلب تعديلات قطع
	ChunkDiff = false, -- الخادم يرسل تعديلات قطعة
	Edit = false, -- طلب تعدين/بناء
	BlockUpdate = false, -- بثّ تغيّر بلاطة
	PlayerState = true, -- موضع اللاعب (عميل -> خادم)
	PeerState = true, -- مواضع بقية اللاعبين (خادم -> عميل)
	Entities = true, -- حالة الوحوش والمقذوفات والأغراض
	Inventory = false, -- مزامنة المخزون
	InvAction = false, -- نقل/رمي/تجهيز
	Craft = false,
	UseItem = false, -- هجوم/استخدام عنصر
	Stats = false, -- حياة/مانا/جوع/تعزيزات
	Hit = false, -- أرقام الضرر والمؤثرات
	TimeSync = false,
	Notify = false,
	Container = false, -- الصناديق
	Shop = false,
	Respawn = false,
	Boss = false,
	Fx = false, -- مؤثرات لمرة واحدة
}

local folder: Folder? = nil

function Net.init(): Folder
	assert(RunService:IsServer(), "Net.init يُستدعى على الخادم فقط")
	local existing = ReplicatedStorage:FindFirstChild("Net")
	if existing then
		folder = existing :: Folder
		return existing :: Folder
	end
	local created = Instance.new("Folder")
	created.Name = "Net"
	for name, unreliable in CHANNELS do
		local remote = if unreliable then Instance.new("UnreliableRemoteEvent") else Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = created
	end
	created.Parent = ReplicatedStorage
	folder = created
	return created
end

local cache: { [string]: any } = {}

function Net.get(name: string): any
	local cached = cache[name]
	if cached then return cached end
	local root = folder
	if not root then
		root = ReplicatedStorage:WaitForChild("Net", 30) :: Folder
		folder = root
	end
	assert(root, "تعذّر العثور على مجلد الشبكة")
	local remote = root:WaitForChild(name, 20)
	assert(remote, "قناة شبكة غير معروفة: " .. name)
	cache[name] = remote
	return remote
end

return Net
