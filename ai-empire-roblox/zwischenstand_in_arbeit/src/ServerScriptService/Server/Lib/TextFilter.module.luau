--!strict
-- Roblox-Pflicht: Text, den andere Spieler sehen (Firmen- und Modellnamen), muss gefiltert werden.

local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")

local TextFilter = {}

-- Gibt den gefilterten Text zurück, oder nil, wenn der Filter nicht erreichbar ist. Yieldet.
function TextFilter.forBroadcast(text: string, fromUserId: number): string?
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, fromUserId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok and typeof(result) == "string" then
		return result
	end
	-- ungeprüft: ob der Filter in einem unveröffentlichten Studio-Ort fehlschlägt. Falls ja, darf Studio
	-- weiterlaufen (niemand sonst sieht den Text). Auf echten Servern wird ohne Filter abgelehnt.
	if RunService:IsStudio() then
		return text
	end
	warn("[TextFilter] Filter nicht erreichbar:", result)
	return nil
end

return TextFilter
