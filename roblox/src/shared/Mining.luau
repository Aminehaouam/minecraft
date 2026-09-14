--!strict
--[[
	Mining — صيغة زمن الكسر.
	مشتركة عمداً: العميل يستعملها لرسم شريط التقدّم، والخادم يستعملها للتحقق،
	فلا يحدث خلاف بين ما يراه اللاعب وما يقبله الخادم.
]]

local Blocks = require(script.Parent.Blocks)
local Items = require(script.Parent.Items)

local Mining = {}

-- يُعيد زمن الكسر بالثواني، أو nil إن كانت البلاطة غير قابلة للكسر بهذه الأداة
function Mining.breakTime(blockId: number, itemId: string?, miningMultiplier: number?): number?
	local block = Blocks.get(blockId)
	if block.hard == math.huge then return nil end
	if blockId == Blocks.ID.AIR then return nil end

	local item = if itemId then Items.get(itemId) else nil
	local power = 0
	local matching = false

	if item then
		if block.tool == "pickaxe" and item.pick then
			power = item.pick
			matching = item.tool == "pickaxe"
		elseif block.tool == "axe" and item.axe then
			power = item.axe
			matching = item.tool == "axe"
		elseif block.tool == nil then
			matching = true
			power = math.max(item.pick or 0, item.axe or 0)
		end
	end

	if block.pick > 0 and power < block.pick then
		return nil -- يحتاج معولاً أقوى
	end

	if block.fragile then
		return 0.05
	end

	local efficiency = 1 + power / 22
	if not matching and block.tool ~= nil then
		efficiency *= 0.35
	end
	return block.hard / efficiency / (miningMultiplier or 1)
end

-- هل يستطيع هذا العنصر كسر هذه البلاطة أصلاً؟
function Mining.canBreak(blockId: number, itemId: string?): boolean
	return Mining.breakTime(blockId, itemId, 1) ~= nil
end

return Mining
