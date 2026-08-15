--[[
	Remotes.lua

	Legt die RemoteEvents an (Server) bzw. holt sie ab (Client).
	Kein Nebeneffekt beim Require -- die Instanzen entstehen erst beim ersten
	Remotes.Get(). Auf dem Client blockiert Get() per WaitForChild.

	C -> S   ChooseOrder(terminalId: string, offerIndex: number)
	         Der einzige Client-Request mit Nutzdaten. Terminal, Uebergabepunkt
	         und Bank laufen ueber ProximityPrompt.Triggered, das der Server
	         selbst empfaengt -- der Client sendet dabei gar nichts.

	S -> C   OffersReady(terminalId, offers, terminalPosition)
	                                           drei Karten fuer diesen Spieler
	         CloseTerminal()                   Panel schliessen
	         StateChanged(state)               cash / banked / heat
	         ActivityChanged(activity | nil)   laufende Interaktion
	         OrderChanged(order | nil, point)  getragener Auftrag + Zielpart
	         RoundState(state)                 Phase, Ende, Endspurt
	         RoundEnded(result)                Endtafel
	         Notify(kind, text)                Toast im HUD
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "CashoutRemotes"

local Remotes = {}

-- Namen als Konstanten, damit Tippfehler beim Require auffallen und nicht
-- erst zur Laufzeit in einem WaitForChild haengen bleiben.
Remotes.ChooseOrder = "ChooseOrder"
Remotes.OffersReady = "OffersReady"
Remotes.CloseTerminal = "CloseTerminal"
Remotes.StateChanged = "StateChanged"
Remotes.ActivityChanged = "ActivityChanged"
Remotes.OrderChanged = "OrderChanged"
Remotes.RoundState = "RoundState"
Remotes.RoundEnded = "RoundEnded"
Remotes.Notify = "Notify"

local ALL = {
	Remotes.ChooseOrder,
	Remotes.OffersReady,
	Remotes.CloseTerminal,
	Remotes.StateChanged,
	Remotes.ActivityChanged,
	Remotes.OrderChanged,
	Remotes.RoundState,
	Remotes.RoundEnded,
	Remotes.Notify,
}

local cache = {}

local function getFolder(): Instance
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		return folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

function Remotes.Get(name: string): RemoteEvent
	local cached = cache[name]
	if cached then
		return cached
	end

	local folder = getFolder()
	local remote

	if RunService:IsServer() then
		remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	else
		remote = folder:WaitForChild(name)
	end

	cache[name] = remote
	return remote
end

-- Vom Server einmal beim Start aufgerufen, damit alle Remotes existieren,
-- bevor der erste Client sie sucht.
function Remotes.CreateAll()
	assert(RunService:IsServer(), "Remotes.CreateAll nur auf dem Server aufrufen")
	for _, name in ipairs(ALL) do
		Remotes.Get(name)
	end
end

return Remotes
