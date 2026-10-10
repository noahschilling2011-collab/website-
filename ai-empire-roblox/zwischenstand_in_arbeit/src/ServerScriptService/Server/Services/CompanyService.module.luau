--!strict
-- Firmengründung. Name wird geprüft (Guard) und durch den Roblox-Textfilter geschickt,
-- weil andere Spieler ihn auf dem Firmenschild sehen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local CompanyConfig = require(ReplicatedStorage.Shared.Config.CompanyConfig)
local ServerTypes = require(script.Parent.Parent.Lib.ServerTypes)
local Guard = require(script.Parent.Parent.Lib.Guard)
local TextFilter = require(script.Parent.Parent.Lib.TextFilter)
local Remote = require(script.Parent.Parent.Lib.Remote)
local SessionService = require(script.Parent.SessionService)
local PlotService = require(script.Parent.PlotService)

type Session = ServerTypes.Session

local CompanyService = {}

local function createCompany(session: Session, payload: ServerTypes.Payload): ServerTypes.Result
	if session.data.company then
		return { ok = false, err = "ALREADY_FOUNDED" }
	end
	local name = Guard.text(payload.name, GameConfig.COMPANY_NAME_MIN, GameConfig.COMPANY_NAME_MAX)
	if not name then
		return { ok = false, err = "BAD_NAME" }
	end
	local logo = payload.logo
	if typeof(logo) ~= "string" or not CompanyConfig.isLogo(logo) then
		return { ok = false, err = "BAD_INPUT" }
	end
	local colorId = Guard.id(payload.color)
	local specId = Guard.id(payload.spec)
	if not colorId or not CompanyConfig.getColor(colorId) or not specId or not CompanyConfig.getSpec(specId) then
		return { ok = false, err = "BAD_INPUT" }
	end

	local filtered = TextFilter.forBroadcast(name, session.userId) -- yieldet
	if filtered == nil then
		return { ok = false, err = "FILTER_DOWN" }
	end
	if filtered ~= name then
		return { ok = false, err = "NAME_FILTERED" }
	end
	-- Während des Yields kann eine zweite Anfrage durchgelaufen oder der Spieler gegangen sein
	if session.closed or session.data.company then
		return { ok = false, err = "ALREADY_FOUNDED" }
	end

	session.data.company = {
		name = name,
		logo = logo,
		color = colorId,
		spec = specId,
		foundedAt = os.time(),
		reputation = 0,
	}
	SessionService.markDirty(session)
	PlotService.refresh(session)
	return { ok = true }
end

function CompanyService.init()
	Remote.bind("CreateCompany", { burst = 3, perSecond = 0.2 }, createCompany)
end

return CompanyService
