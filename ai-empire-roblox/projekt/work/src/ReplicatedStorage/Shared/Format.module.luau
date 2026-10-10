--!strict
-- Anzeigeformate. Rein, ohne Roblox-APIs.

local Format = {}

local SUFFIXES: { { value: number, suffix: string } } = {
	{ value = 1e12, suffix = "T" },
	{ value = 1e9, suffix = "B" },
	{ value = 1e6, suffix = "M" },
	{ value = 1e3, suffix = "K" },
}

function Format.compact(n: number, decimals: number?): string
	if n ~= n then
		return "0"
	end
	local sign = if n < 0 then "-" else ""
	local a = math.abs(n)
	for _, entry in SUFFIXES do
		if a >= entry.value then
			local text = string.format("%." .. tostring(decimals or 1) .. "f", a / entry.value)
			if string.find(text, ".", 1, true) then
				-- "25.0" -> "25", "1.20" -> "1.2"
				text = string.gsub(string.gsub(text, "0+$", ""), "%.$", "")
			end
			return sign .. text .. entry.suffix
		end
	end
	return sign .. tostring(math.floor(a + 0.5))
end

function Format.money(n: number): string
	if math.abs(n) < 1000 then
		return (if n < 0 then "-$" else "$") .. tostring(math.floor(math.abs(n) + 0.5))
	end
	local text = Format.compact(math.abs(n), if math.abs(n) >= 1e6 then 2 else 1)
	return (if n < 0 then "-$" else "$") .. text
end

-- Volle Zahl mit Tausenderpunkten: 1234567 -> "1,234,567"
function Format.int(n: number): string
	local text = tostring(math.floor(math.abs(n) + 0.5))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	if string.sub(formatted, 1, 1) == "," then
		formatted = string.sub(formatted, 2)
	end
	return (if n < 0 then "-" else "") .. formatted
end

function Format.perMinute(perSecond: number): string
	local perMin = perSecond * 60
	return (if perMin >= 0 then "+" else "") .. Format.money(perMin) .. "/min"
end

-- Money per game day (CORE_SPEC 6: 1 game day = 1200 s; the UI shows running money per day)
Format.DAY_SECONDS = 1200
function Format.perDay(perSecond: number): string
	local perDay = perSecond * Format.DAY_SECONDS
	return (if perDay >= 0 then "+" else "") .. Format.money(perDay) .. "/day"
end

-- Company date and visible hour: "Day 8 · 11:54" (hour from CompanyOps.hour)
function Format.dayClock(day: number, hour: number): string
	local h = hour % 24
	return string.format("Day %d · %02d:%02d", math.max(1, math.floor(day)), math.floor(h), math.floor((h % 1) * 60))
end

function Format.tokens(n: number): string
	return Format.compact(n, if n >= 1e9 then 1 else 0)
end

function Format.duration(seconds: number): string
	local s = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", s // 60, s % 60)
end

function Format.price(n: number): string
	return "$" .. string.format("%.2f", n)
end

function Format.percent(fraction: number, decimals: number?): string
	return string.format("%." .. tostring(decimals or 0) .. "f%%", fraction * 100)
end

-- Vorzeichen immer anzeigen: +3.2 / -1.0
function Format.signed(n: number, decimals: number?): string
	return (if n >= 0 then "+" else "-") .. string.format("%." .. tostring(decimals or 1) .. "f", math.abs(n))
end

return Format
