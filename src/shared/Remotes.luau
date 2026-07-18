--!strict
-- Remotes.luau
-- Einziger Ort, der die Remotes erstellt (Server) bzw. holt (Client).
-- Contract (exakt diese, keine weiteren):
--   PlaceItem(itemId, cellX, cellZ, rot) -> (ok: boolean, errMsg: string?)   [RemoteFunction]
--   DemolishItem(buildingGuid) -> (ok: boolean, errMsg: string?)            [RemoteFunction]
--   StateSync {cash, population, incomePerTick, unlockedItems}              [RemoteEvent, Server->Client]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "MiniCityRemotes"
local isServer = RunService:IsServer()

local Remotes = {}

local function getFolder(): Folder
	if isServer then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		return folder :: Folder
	else
		return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	end
end

local function ensure(name: string, className: string): Instance
	local folder = getFolder()
	if isServer then
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
		return remote
	else
		return folder:WaitForChild(name)
	end
end

function Remotes.PlaceItem(): RemoteFunction
	return ensure("PlaceItem", "RemoteFunction") :: RemoteFunction
end

function Remotes.DemolishItem(): RemoteFunction
	return ensure("DemolishItem", "RemoteFunction") :: RemoteFunction
end

function Remotes.StateSync(): RemoteEvent
	return ensure("StateSync", "RemoteEvent") :: RemoteEvent
end

return Remotes
