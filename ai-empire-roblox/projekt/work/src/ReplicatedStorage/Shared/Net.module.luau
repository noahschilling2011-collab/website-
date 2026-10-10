--!strict
-- Alle Remotes an einer Stelle. Der Server legt sie beim Start in ReplicatedStorage.Remotes an,
-- der Client wartet darauf. Neue Aktion = Namen hier eintragen + Handler im Server binden.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

Net.FOLDER = "Remotes"

-- Client -> Server (Antwort immer { ok = boolean, err = string?, ... })
Net.FUNCTIONS = {
	"RequestState",
	"CreateCompany",
	"Scrape",
	"BuyData",
	"BuyGPU",
	"SellGPU",
	"StartTraining",
	"ResolveEvent",
	"ReleaseModel",
 "EvaluateModel",
	"UpdatePricing",
	"RetireModel",
	"Debug",
	"AdminAction",
	"OpenSecurity",
	"HireEmployee",
	"BuySnack",
	"ReplaceCard",
	"UseCampusLift",
	"GrantGuestCard",
	"RevokeGuestCard",
	"UpgradeRetail",
	"BuyCar",
	"SpawnCar",
	"FireEmployee",
	"StartResearch",
	"UpgradeOffice",
	"ClaimQuest",
	"DeliverContract",
	"ClaimDaily",
	"ImproveModel",
	"BuildProject",
	"CancelProject",
	"ArchiveProject",
	"PublishProject",
	"DeliverProject",
	"RunArena",
	"SetComputeShare",
	"UpgradeCooling",
	"BuyModelAccess",
	"CancelModelAccess",
	"RecruitAction", -- applications & interviews {action=invite|open|question|reply|hire|reject|close, id, ...}
	"AssistantAction", -- the founder's assistant {action=coffee|brief}
	"TalkAction", -- talk to anyone {action=open|say|close, ...} (TalkService)
	"ShopAction", -- Robux shop helpers {action=status|redeem, ...} (ShopService); purchases go through MarketplaceService
	"TravelAction", -- world travel {action=flight|route|...} (CityService)
	"DealAction", -- B2B clients {action=pin|skip|joinMeeting, clientId} (EmpireService, CompanyOps)
	"EmpireAction", -- company settings {action=labLevel|buyJet|hrBudget|hrAuto|nightShift|saveMode|autoPrice, ...}
	"PhoneAction", -- company phone {action=inbox|read|calendar|chat|call, ...} (PhoneService)
} :: { string }

-- Server -> Client
Net.EVENTS = {
	"VehicleInput", -- validated driver input (client -> server)
	"State", -- kompletter Snapshot der eigenen Spielerdaten
	"Notify", -- (kind: string, payload: table) für Momente wie TRAINING_COMPLETE
} :: { string }

local function folder(): Instance
	return ReplicatedStorage:WaitForChild(Net.FOLDER)
end

function Net.getFunction(name: string): RemoteFunction
	return folder():WaitForChild(name) :: RemoteFunction
end

function Net.getEvent(name: string): RemoteEvent
	return folder():WaitForChild(name) :: RemoteEvent
end

return Net
