#!/usr/bin/env python3
"""
مُجمِّع صغير: يحوّل وحدات ReplicatedStorage.Shared النقية إلى ملف Luau واحد
حتى تُشغَّل الاختبارات بمُفسِّر Luau خارج Roblox.

الوحدات النقية فقط (بلا game:GetService) — هذه هي التي تحمل منطق اللعبة:
التوليد، الفيزياء، المخزون، الوصفات، السجلات.
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHARED = ROOT / "src" / "shared"

MODULES = [
    "Util", "Noise", "Config", "Blocks", "Items", "Recipes",
    "Chunk", "WorldGen", "World", "Physics", "Mining", "Inventory",
    "Buffs", "Mobs", "Smelting", "Upgrades",
]

STUBS = r'''
-- ===== بدائل واجهات Roblox المستعملة في الوحدات النقية =====
local function clamp01(v) return math.max(0, math.min(1, v)) end

local Color3Meta = {}
Color3Meta.__index = Color3Meta
function Color3Meta:Lerp(other, t)
	return setmetatable({
		R = self.R + (other.R - self.R) * t,
		G = self.G + (other.G - self.G) * t,
		B = self.B + (other.B - self.B) * t,
	}, Color3Meta)
end

Color3 = {
	new = function(r, g, b)
		return setmetatable({ R = clamp01(r or 0), G = clamp01(g or 0), B = clamp01(b or 0) }, Color3Meta)
	end,
	fromRGB = function(r, g, b)
		return setmetatable({ R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255 }, Color3Meta)
	end,
}

-- سجل الوحدات
local __modules = {}
local __cache = {}
local function __req(name)
	if __cache[name] ~= nil then return __cache[name] end
	local factory = __modules[name]
	if not factory then error("وحدة غير معروفة: " .. tostring(name)) end
	local value = factory()
	__cache[name] = value
	return value
end
'''

def convert(name: str, source: str) -> str:
    # require(script.Parent.X) -> __req("X")
    source = re.sub(r'require\(script\.Parent\.([A-Za-z_][A-Za-z0-9_]*)\)', r'__req("\1")', source)
    # اقطع تعليق --!strict لأنه يجب أن يكون أول سطر في الملف
    source = re.sub(r'^--!\w+\s*\n', '', source)
    body = "\n".join("\t" + line if line.strip() else line for line in source.split("\n"))
    return f'__modules["{name}"] = function()\n{body}\nend\n'

def build() -> str:
    parts = [STUBS]
    for name in MODULES:
        path = SHARED / f"{name}.luau"
        parts.append(convert(name, path.read_text(encoding="utf-8")))
    parts.append("return __req\n")
    return "\n".join(parts)

if __name__ == "__main__":
    out = ROOT / "tests" / ".bundle.luau"
    out.write_text(build(), encoding="utf-8")
    print(out)
