--!strict
-- Explorer: ReplicatedStorage/Shared/Format (ModuleScript)

local Format = {}

local SUFFIXES = { "K", "M", "B", "T" }

local function withCommas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

--- 1234 -> "1,234"; 12345 -> "12.3K"; 1234567 -> "1.23M" (short on phones).
function Format.cash(n: number): string
	n = math.floor(n + 0.5)
	if math.abs(n) < 10_000 then
		return withCommas(n)
	end
	local value = n
	local index = 0
	while math.abs(value) >= 1000 and index < #SUFFIXES do
		value /= 1000
		index += 1
	end
	local digits = if math.abs(value) >= 100 then 0 elseif math.abs(value) >= 10 then 1 else 2
	local text = string.format(`%.{digits}f`, value)
	-- "12.0K" reads worse than "12K"
	text = text:gsub("%.0+$", "")
	return text .. SUFFIXES[index]
end

function Format.money(n: number): string
	return "$" .. Format.cash(n)
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

function Format.ordinal(n: number): string
	local suffix = "th"
	local lastTwo = n % 100
	if lastTwo < 11 or lastTwo > 13 then
		local last = n % 10
		suffix = if last == 1 then "st" elseif last == 2 then "nd" elseif last == 3 then "rd" else "th"
	end
	return `{n}{suffix}`
end

return Format
