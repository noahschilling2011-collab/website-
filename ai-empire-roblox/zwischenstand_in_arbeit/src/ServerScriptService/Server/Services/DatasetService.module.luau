--!strict
-- Trainingsdaten: kostenlos scrapen (langsam, schlecht) oder Pakete kaufen.
-- Preise und Mengen kommen nur aus DataConfig – der Client schickt nur Paket-ID und Anzahl.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataConfig = require(ReplicatedStorage.Shared.Config.DataConfig)
local ModelMath = require(ReplicatedStorage.Shared.ModelMath)
local ServerTypes = require(script.Parent.Parent.Lib.ServerTypes)
local Guard = require(script.Parent.Parent.Lib.Guard)
local Remote = require(script.Parent.Parent.Lib.Remote)
local SessionService = require(script.Parent.SessionService)
local EconomyService = require(script.Parent.EconomyService)

type Session = ServerTypes.Session

local DatasetService = {}

local function scrape(session: Session, _payload: ServerTypes.Payload): ServerTypes.Result
	local now = workspace:GetServerTimeNow()
	local remaining = session.data.lastScrapeAt + DataConfig.SCRAPE.cooldown - now
	if remaining > 0 then
		return { ok = false, err = "COOLDOWN", wait = remaining }
	end
	session.data.lastScrapeAt = now
	ModelMath.addTokens(session.data.data, DataConfig.SCRAPE.type, DataConfig.SCRAPE.tokens, DataConfig.SCRAPE.quality)
	SessionService.markDirty(session)
	return { ok = true, tokens = DataConfig.SCRAPE.tokens }
end

local function buyData(session: Session, payload: ServerTypes.Payload): ServerTypes.Result
	local packId = Guard.id(payload.packId)
	local pack = if packId then DataConfig.getPack(packId) else nil
	local count = Guard.integer(payload.count, 1, DataConfig.MAX_BUY)
	if not pack or not count then
		return { ok = false, err = "BAD_INPUT" }
	end
	if not EconomyService.spend(session, pack.price * count, "data") then
		return { ok = false, err = "NO_MONEY" }
	end
	ModelMath.addTokens(session.data.data, pack.type, pack.tokens * count, pack.quality)
	SessionService.markDirty(session)
	return { ok = true, tokens = pack.tokens * count }
end

function DatasetService.init()
	Remote.bind("Scrape", { burst = 3, perSecond = 0.5, company = true }, scrape)
	Remote.bind("BuyData", { burst = 6, perSecond = 3, company = true }, buyData)
end

return DatasetService
