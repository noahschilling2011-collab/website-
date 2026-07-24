--[[
	Remotes
	Erzeugt die RemoteEvents/-Functions auf dem Server und wartet auf dem Client
	darauf. Ein einziger Ort, an dem der Name eines Remotes steht.

	Wichtig: Der Client ruft hier nur ab. Jede Anfrage wird im jeweiligen Service
	auf dem Server validiert (Besitz, Cash, Fenster offen, Entfernung).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "GarageHeistRemotes"

-- Server -> Client
local TO_CLIENT = {
	"ProfileSync", -- kompletter Zustand der eigenen Garage
	"CashUpdate", -- {cash, pile, rate}
	"HeistState", -- {open, endsAt, nextAt, lockedUntil}
	"Notify", -- {text, kind}
	"CarryState", -- {part = {...} | nil}
	"DismountProgress", -- {state = "start"|"cancel"|"done", duration, label}
	"RadarPing", -- Liste der wertvollsten Teile im Server
	"DailyState", -- {streak, canClaim, nextInSeconds}
	"LeaderboardUpdate", -- {richest = {...}, thieves = {...}}
	"ShopState", -- {vip, autoCollect, garageLock}
	"Effect", -- {kind = "sound"|"shake", ...} - reine Praesentation
}

-- Client -> Server (alles wird serverseitig geprueft)
local TO_SERVER = {
	"RequestBuyPart", -- (carIndex, slotId)
	"RequestInstantRepair", -- (carIndex, slotId)  -> loest den Robux-Kauf aus
	"RequestBuyCar", -- (carId)
	"RequestUpgradeGarage", -- ()
	"RequestRebirth", -- ()
	"RequestSellLoosePart", -- (uid)
	"RequestInstallLoosePart", -- (uid, carIndex)
	"RequestCollect", -- ()
	"RequestClaimDaily", -- ()
	"RequestTackle", -- ()
	"RequestDropPart", -- ()
	"RequestPromptPurchase", -- (kind, key) -> Server kennt die IDs, nicht der Client
}

local FUNCTIONS = {
	"GetSnapshot", -- Erstzustand beim Beitreten
}

local Remotes = {}

local function getFolder()
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		for _, name in TO_CLIENT do
			if not folder:FindFirstChild(name) then
				local ev = Instance.new("RemoteEvent")
				ev.Name = name
				ev.Parent = folder
			end
		end
		for _, name in TO_SERVER do
			if not folder:FindFirstChild(name) then
				local ev = Instance.new("RemoteEvent")
				ev.Name = name
				ev.Parent = folder
			end
		end
		for _, name in FUNCTIONS do
			if not folder:FindFirstChild(name) then
				local fn = Instance.new("RemoteFunction")
				fn.Name = name
				fn.Parent = folder
			end
		end
		return folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME, 30)
end

local cachedFolder = nil

function Remotes.Get(name)
	if not cachedFolder then
		cachedFolder = getFolder()
	end
	assert(cachedFolder, "Remotes-Ordner nicht gefunden")
	local remote = cachedFolder:FindFirstChild(name)
	if not remote and RunService:IsClient() then
		remote = cachedFolder:WaitForChild(name, 20)
	end
	assert(remote, ("Remote '%s' existiert nicht"):format(name))
	return remote
end

-- Nur auf dem Server aufrufen: legt alle Remotes an.
function Remotes.Init()
	assert(RunService:IsServer(), "Remotes.Init nur auf dem Server")
	cachedFolder = getFolder()
	return cachedFolder
end

return Remotes
