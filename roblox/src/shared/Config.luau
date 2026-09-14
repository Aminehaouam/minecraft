--!strict
--[[
	Config — كل الأرقام القابلة للضبط في اللعبة.
	غيّر من هنا فقط؛ لا تنثر الأرقام السحرية في بقية الملفات.
]]

local Config = {}

-- ===== العالم =====
Config.WORLD_NAME = "TerraCraft"
Config.WORLD_W = 2048 -- عرض العالم بالبلاطات
Config.WORLD_H = 512 -- عمق العالم بالبلاطات
Config.CHUNK = 32 -- حجم القطعة (chunk) بالبلاطات
Config.CHUNKS_X = Config.WORLD_W // Config.CHUNK
Config.CHUNKS_Y = Config.WORLD_H // Config.CHUNK
Config.REGION = 8 -- عدد القطع في كل منطقة حفظ (8x8)

-- طبقات العالم (إحداثي Y يزداد للأسفل)
Config.SKY_TOP = 8 -- أعلى حد للبناء
Config.SURFACE = 150 -- متوسط ارتفاع السطح
Config.SURFACE_AMP = 26 -- تضاريس السطح
Config.DIRT_DEPTH = 70 -- سماكة التراب تحت السطح
Config.CAVERN_Y = 300 -- بداية طبقة الكهوف العميقة
Config.HELL_Y = 460 -- بداية طبقة الجحيم
Config.BEDROCK_Y = Config.WORLD_H - 3

-- ===== العرض =====
Config.TILES_ON_SCREEN_Y = 24 -- ثابت الزوم: كم بلاطة تظهر رأسياً
Config.RENDER_PAD = 2 -- بلاطات إضافية خارج الشاشة
Config.LIGHT_PAD = 8 -- هامش حساب الإضاءة (يمنع ظهور حافة مضيئة عند طرف الشاشة)
Config.MAX_LIGHT = 15
Config.LIGHT_HZ = 15 -- أقصى معدل لإعادة حساب الإضاءة
Config.CAMERA_SMOOTH = 12 -- نعومة تتبع الكاميرا

-- ===== الفيزياء (بالبلاطة/الثانية) =====
Config.GRAVITY = 62
Config.MAX_FALL = 46
Config.WALK_SPEED = 9.2
Config.WALK_ACCEL = 62
Config.AIR_ACCEL = 28
Config.GROUND_FRICTION = 58
Config.AIR_FRICTION = 6
Config.JUMP_VELOCITY = 21.5
Config.JUMP_HOLD_TIME = 0.16 -- قفزة متغيرة الارتفاع
Config.COYOTE_TIME = 0.10
Config.JUMP_BUFFER = 0.12
Config.STEP_UP = 1 -- صعود تلقائي لبلاطة واحدة
Config.SWIM_SPEED = 5.5
Config.WATER_DRAG = 0.72
Config.FALL_SAFE = 12 -- بلاطات سقوط بلا ضرر
Config.FALL_DMG_PER_TILE = 6

-- ===== اللاعب =====
Config.PLAYER_W = 1.6
Config.PLAYER_H = 2.8
Config.REACH = 6.5 -- مدى التعدين/البناء بالبلاطات
Config.BASE_HP = 100
Config.BASE_MANA = 40
Config.MANA_REGEN = 3.5
Config.HP_REGEN = 1.1 -- نقطة/ثانية عند الشبع
Config.HP_REGEN_DELAY = 5 -- ثوانٍ بعد آخر ضرر
Config.FOOD_MAX = 100
Config.FOOD_DRAIN = 0.16 -- نقطة/ثانية (شريط ممتلئ ≈ 10 دقائق)
Config.STARVE_DPS = 1.5
Config.RESPAWN_TIME = 5
Config.IFRAMES = 0.55
Config.DROWN_TIME = 12
Config.DROWN_DPS = 8

-- ===== المخزون =====
Config.HOTBAR = 10
Config.INV_ROWS = 4 -- صفوف إضافية تحت الشريط
Config.INV_SLOTS = Config.HOTBAR * (1 + Config.INV_ROWS)
Config.ARMOR_SLOTS = 3 -- خوذة/درع/حذاء
Config.MAX_STACK = 999
Config.PICKUP_RANGE = 2.6
Config.PICKUP_DELAY = 0.55
Config.ITEM_DESPAWN = 300

-- ===== الوقت =====
Config.DAY_LENGTH = 900 -- ثانية لليوم الكامل (15 دقيقة)
Config.DAY_START = 0.25 -- 0 = منتصف الليل، 0.5 = الظهر
Config.NIGHT_FROM = 0.76
Config.NIGHT_TO = 0.22

-- ===== الكائنات =====
Config.MOB_CAP_PER_PLAYER = 9
Config.MOB_SPAWN_MIN = 14 -- أقل مسافة للظهور
Config.MOB_SPAWN_MAX = 34 -- أقصى مسافة
Config.MOB_DESPAWN = 60
Config.MOB_TICK = 1 / 20 -- معدل محاكاة الخادم
Config.SPAWN_INTERVAL = 1.35

-- ===== الشبكة =====
Config.STATE_HZ = 18 -- إرسال حالة اللاعب
Config.ENTITY_HZ = 14 -- إرسال حالة الكائنات
-- نصف قطر القطع المحمّلة حول اللاعب. القيم أكبر من اللازم تعني توليداً أكثر
-- بلا فائدة مرئية: النافذة المرئية ~50×24 بلاطة، وهذه التغطية 160×96.
Config.CHUNK_RADIUS_X = 2
Config.CHUNK_RADIUS_Y = 1
Config.MAX_EDITS_PER_SEC = 14 -- مضاد للغش

-- ===== الحفظ =====
Config.AUTOSAVE = 120
Config.DATASTORE_PLAYER = "TC_Player_v1"
Config.DATASTORE_WORLD = "TC_World_v1"

return Config
