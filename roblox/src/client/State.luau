--!strict
--[[ State — الحالة المشتركة بين وحدات العميل (مصدر واحد للحقيقة محلياً). ]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Physics = require(Shared.Physics)

local State = {}

State.ready = false
State.seed = 0
State.userId = 0

-- اللاعب المحلي
State.body = Physics.newBody(0, 0, Config.PLAYER_W, Config.PLAYER_H)
State.facing = 1
State.anim = "idle"
State.animTime = 0
State.lastSwing = 0
State.spawnX = 0
State.spawnY = 0

-- الكاميرا (بالبلاطات)
State.camX = 0
State.camY = 0
State.tilePx = 40

-- الإحصاءات
State.hp = 100
State.maxHp = 100
State.mana = 40
State.maxMana = 40
State.food = 100
State.defense = 0
State.dead = false
State.respawnIn = 0
State.buffs = {} :: { { id: string, t: number } }
State.kills = 0
State.deaths = 0
State.mined = 0

-- المخزون
State.slots = {} :: { [number]: { id: string, n: number }? }
State.armor = {} :: { [string]: { id: string, n: number }? }
State.hotbar = 1

-- العالم
State.pending = 0 -- قطع بانتظار التوليد المحلي
State.time = 0.25
State.day = 1
State.bloodMoon = false

-- الكيانات القادمة من الخادم
State.entities = {} :: { [number]: any }
State.peers = {} :: { [number]: any }

-- الزعيم
State.boss = nil :: any

-- التعدين الجاري
State.mining = nil :: { x: number, y: number, layer: string, progress: number, required: number }?

-- واجهات مفتوحة
State.uiOpen = false
State.shopOpen = false

function State.heldItem(): { id: string, n: number }?
	return State.slots[State.hotbar]
end

return State
