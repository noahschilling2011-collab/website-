--!strict
-- Debug-Befehle zum Testen. Nur in Studio oder für UserIds in GameConfig.DEV_USER_IDS.
-- Befehle: money (+$100K), data (+10B Tokens je Typ, Qualität 80 %), finish (Training sofort fertig),
-- rep (+25 Reputation), reset (Spielstand auf Start zurücksetzen; Robux-Käufe data.shop bleiben).
-- Nur in Studio (nie live, auch nicht für DEV_USER_IDS): pass {key} setzt ein Game-Pass-Flag für diese
-- Sitzung (nicht gespeichert), voucher {key} schreibt einen Gutschein gut (ShopConfig-Schlüssel).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local DataConfig = require(ReplicatedStorage.Shared.Config.DataConfig)
local ModelMath = require(ReplicatedStorage.Shared.ModelMath)
local ServerTypes = require(script.Parent.Parent.Lib.ServerTypes)
local Guard = require(script.Parent.Parent.Lib.Guard)
local Remote = require(script.Parent.Parent.Lib.Remote)
local Template = require(script.Parent.Parent.Lib.Template)
local SessionService = require(script.Parent.SessionService)
local EconomyService = require(script.Parent.EconomyService)
local PlotService = require(script.Parent.PlotService)
local AIModelService = require(script.Parent.AIModelService)
local ShopService = require(script.Parent.ShopService)

type Session = ServerTypes.Session

local DebugService = {}

function DebugService.allowed(userId: number): boolean
	return RunService:IsStudio() or table.find(GameConfig.DEV_USER_IDS, userId) ~= nil
end

local function run(session: Session, payload: ServerTypes.Payload): ServerTypes.Result
	if not DebugService.allowed(session.userId) then
		return { ok = false, err = "NOT_ALLOWED" }
	end
	local cmd = Guard.id(payload.cmd)
	if cmd == "money" then
		EconomyService.grant(session, 100_000, "debug")
	elseif cmd == "data" then
		for _, dataType in DataConfig.TYPES do
			ModelMath.addTokens(session.data.data, dataType.id, 1e10, 0.8)
		end
	elseif cmd == "finish" then
		if not AIModelService.finishNow(session) then
			return { ok = false, err = "NO_TRAINING" }
		end
	elseif cmd == "rep" then
		local company = session.data.company
		if company then
			company.reputation = math.min(100, company.reputation + 25)
		end
	elseif cmd == "reset" then
		-- Robux purchases (receipts, vouchers, pass cache) are real money: never reset them
		local shop = (session.data :: any).shop
		session.data = Template.new()
		if shop ~= nil then
			(session.data :: any).shop = shop
		end
		-- reset the market numbers in place: live also carries fields other services own and set
		-- only on change (admin, shop, workforce ...); replacing the table would drop them
		local live = session.live
		live.users = 0
		live.revenue = 0
		live.cost = 0
		live.perModel = {}
		live.npcUsers = {}
		-- company summaries of CompanyOps / EmpireService: rewritten on the next company tick
		local extra = live :: any
		extra.ops = nil
		extra.compute = nil
		extra.waitlist = 0
		extra.load = 0
		extra.demand = 0
		PlotService.refresh(session)
	elseif cmd == "pass" or cmd == "voucher" then
		if not RunService:IsStudio() then
			return { ok = false, err = "NOT_ALLOWED" }
		end
		local key = Guard.id(payload.key)
		local granted = if key == nil then false
			elseif cmd == "pass" then ShopService.debugGrantPass(session, key)
			else ShopService.debugGrantVoucher(session, key)
		if not granted then
			return { ok = false, err = "BAD_INPUT" }
		end
	else
		return { ok = false, err = "BAD_INPUT" }
	end
	SessionService.markDirty(session)
	print(`[Debug] {session.player.Name}: {cmd}`)
	return { ok = true }
end

function DebugService.init()
	Remote.bind("Debug", { burst = 8, perSecond = 4 }, run)
end

return DebugService
