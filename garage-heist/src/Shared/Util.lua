--[[
	Util
	Kleinkram, den Server und Client beide brauchen. Nichts davon trifft
	Entscheidungen ueber Geld.
]]

local HttpService = game:GetService("HttpService")

local Util = {}

local SUFFIXES = { "", "K", "M", "B", "T" }

-- 1234 -> "1,2K"
function Util.FormatCash(amount: number): string
	amount = math.floor(tonumber(amount) or 0)
	local negative = amount < 0
	amount = math.abs(amount)
	local index = 1
	local value = amount
	while value >= 1000 and index < #SUFFIXES do
		value /= 1000
		index += 1
	end
	local text
	if index == 1 then
		text = string.format("%d", value)
	elseif value < 100 then
		text = string.format("%.1f", value):gsub("%.", ",")
	else
		text = string.format("%d", value)
	end
	return (negative and "-$" or "$") .. text .. SUFFIXES[index]
end

-- 0.75 -> "0,8/s"
function Util.FormatRate(rate: number): string
	rate = tonumber(rate) or 0
	if rate >= 100 then
		return Util.FormatCash(rate) .. "/s"
	end
	return "$" .. (string.format("%.1f", rate):gsub("%.", ",")) .. "/s"
end

-- 95 -> "1:35", 7500 -> "2h 05m"
function Util.FormatTime(seconds: number): string
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	if seconds >= 3600 then
		return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
	end
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

function Util.DeepCopy(source)
	if type(source) ~= "table" then
		return source
	end
	local copy = {}
	for key, value in pairs(source) do
		copy[key] = Util.DeepCopy(value)
	end
	return copy
end

-- Fuellt fehlende Felder aus einer Vorlage nach, ohne vorhandene zu ueberschreiben.
-- Damit ueberleben alte Profile ein Schema-Update.
function Util.Reconcile(data, template)
	if type(data) ~= "table" then
		return Util.DeepCopy(template)
	end
	for key, value in pairs(template) do
		if data[key] == nil then
			data[key] = Util.DeepCopy(value)
		elseif type(value) == "table" and type(data[key]) == "table" then
			Util.Reconcile(data[key], value)
		end
	end
	return data
end

function Util.NewUid(): string
	return HttpService:GenerateGUID(false)
end

-- Tag seit Epoch in UTC. Basis fuer die Daily-Kette.
function Util.UtcDay(timestamp: number?): number
	return math.floor((timestamp or os.time()) / 86400)
end

-- Markerposition des Reparatur-Minispiels als Dreieckswelle: 0 -> 1 -> 0.
-- Steht in Shared, weil Client und Server exakt dieselbe Zahl brauchen. `now`
-- kommt von Workspace:GetServerTimeNow() - der einzigen Uhr, die auf beiden
-- Seiten denselben Wert hat. Kein Startzeitpunkt noetig: die Welle laeuft frei
-- durch, alle Reparaturen teilen sich dieselbe Phase.
function Util.RepairMarker(now: number, sweep: number): number
	local phase = (now % sweep) / sweep
	return if phase < 0.5 then phase * 2 else (1 - phase) * 2
end

function Util.SafeNumber(value, fallback: number): number
	local number = tonumber(value)
	if not number or number ~= number or number == math.huge or number == -math.huge then
		return fallback
	end
	return number
end

return Util
