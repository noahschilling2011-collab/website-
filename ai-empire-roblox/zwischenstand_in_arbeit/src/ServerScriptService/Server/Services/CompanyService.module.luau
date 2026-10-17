--!strict
-- Firmengründung. Name wird geprüft (Guard) und durch den Roblox-Textfilter geschickt,
-- weil andere Spieler ihn auf dem Firmenschild sehen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local CompanyConfig = require(ReplicatedStorage.Shared.Config.CompanyConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local ServerTypes = require(script.Parent.Parent.Lib.ServerTypes)
local Guard = require(script.Parent.Parent.Lib.Guard)
local TextFilter = require(script.Parent.Parent.Lib.TextFilter)
local Remote = require(script.Parent.Parent.Lib.Remote)
local Funnel = require(script.Parent.Parent.Lib.Funnel)
local SessionService = require(script.Parent.SessionService)
local PlotService = require(script.Parent.PlotService)
local ShopService = require(script.Parent.ShopService) -- shop package: Identity Kit colours / logos (SHOP_SPEC 3.5)

type Session = ServerTypes.Session

local CompanyService = {}

CompanyService.REBRAND_COOLDOWN = ShopConfig.REBRAND_COOLDOWN
local lastRebrand: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any -- runtime only, never saved

-- Identity Kit colours and logos need the pass (or the Style Collection bundle); free ones never do. The company's
-- own saved colour / logo never need it (fix round 1, R9): after a refund, or before refreshPasses has answered on
-- join, a player can still change only the logo (or only the colour) and keep the other saved Kit choice.
local function kitAllowed(session: Session, colorId: string, logo: string): boolean
	local company = session.data.company
	local kitColor = CompanyConfig.isKitColor(colorId) and not (company and company.color == colorId)
	local kitLogo = CompanyConfig.isKitLogo(logo) and not (company and company.logo == logo)
	if kitColor or kitLogo then
		return ShopService.owns(session, CompanyConfig.KIT_PASS)
	end
	return true
end

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
	if not kitAllowed(session, colorId, logo) then
		return { ok = false, err = "PASS_NEEDED" }
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
	Funnel.step(session.player, 2) -- onboarding funnel "Company created" (ONBOARDING_SPEC A11)
	return { ok = true }
end

-- Free "Change colour & logo" for everyone (SHOP_SPEC 3.5, owner decision S4): validated like the founding;
-- Kit ids need the Identity Kit pass (PASS_NEEDED); at most one change per REBRAND_COOLDOWN seconds (TOO_FAST,
-- runtime only). GPU racks repaint at once (PlotService.refresh); HQ trim, cars and the jet at their next build.
-- After a refund the saved Kit choice stays (R9) until the player changes it.
function CompanyService.rebrand(session: Session, color: any, logo: any): ServerTypes.Result
	local company = session.data.company
	if not company then
		return { ok = false, err = "NO_COMPANY" }
	end
	if typeof(logo) ~= "string" or not CompanyConfig.isLogo(logo) then
		return { ok = false, err = "BAD_INPUT" }
	end
	local colorId = Guard.id(color)
	if not colorId or not CompanyConfig.getColor(colorId) then
		return { ok = false, err = "BAD_INPUT" }
	end
	if company.color == colorId and company.logo == logo then
		return { ok = true, unchanged = true }
	end
	if not kitAllowed(session, colorId, logo) then
		return { ok = false, err = "PASS_NEEDED" }
	end
	local now = os.clock()
	local last = lastRebrand[session]
	if last and now - last < CompanyService.REBRAND_COOLDOWN then
		return { ok = false, err = "TOO_FAST", wait = math.ceil(CompanyService.REBRAND_COOLDOWN - (now - last)) }
	end
	lastRebrand[session] = now
	company.color = colorId
	company.logo = logo
	SessionService.markDirty(session, true)
	PlotService.refresh(session)
	return { ok = true }
end

function CompanyService.init()
	Remote.bind("CreateCompany", { burst = 3, perSecond = 0.2 }, createCompany)
end

return CompanyService
