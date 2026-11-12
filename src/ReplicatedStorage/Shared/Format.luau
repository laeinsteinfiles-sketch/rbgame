--!strict
-- Explorer: ReplicatedStorage/Shared/Format (ModuleScript)

local Format = {}

--- 1234 -> "1,234"; 1234567 -> "1.23M" (keeps HUD numbers short on phones).
function Format.cash(n: number): string
	n = math.floor(n + 0.5)
	if n >= 1_000_000 then
		return string.format("%.2fM", n / 1_000_000)
	elseif n >= 100_000 then
		return string.format("%.0fk", n / 1000)
	elseif n >= 10_000 then
		return string.format("%.1fk", n / 1000)
	end
	local s = tostring(n)
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

function Format.depth(metres: number): string
	return string.format("%d m", math.floor(metres))
end

function Format.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function Format.percent(fraction: number): string
	return string.format("%d%%", math.floor(fraction * 100 + 0.5))
end

return Format
