--!nocheck
-- guiprev scene of the drivers package: the ride HUD and the destination sheet on the REAL server + client state
-- (client_setup.luau).
--   python3 tools/guiprev/guiprev.py --scene tests/drivers/scene_drive.luau --gen harness/.gen_drivers --no-manifest \
--       --state riding --viewport phone --dpr 2 --out out/drivers/phone_hud_riding.png
-- states: hud_coming | hud_waiting | hud_board | hud_queued | riding | sheet_free | sheet_busy | sheet_riding | sheet_abroad |
--         hud_toast (a notice toast showing above the HUD) | sheet_far (no pick-up point near: no ETAs)
local M = require("../../harness/mock")
local GuiDump = require("../../tools/guiprev/guidump")
local setup = require("./client_setup")
local args = { ... }
local GEN = args[1] or "../../harness/.gen_drivers"
local STATE = args[2] or "riding"
local VW, VH = tonumber(args[3]) or 1280, tonumber(args[4]) or 720
local insetList = string.split(args[5] or "58,0,0,0", ",")
local INSETS = { top = tonumber(insetList[1]) or 0, right = tonumber(insetList[2]) or 0, bottom = tonumber(insetList[3]) or 0, left = tonumber(insetList[4]) or 0 }
local FEEDBACK = if args[6] and args[6] ~= "-" then require(args[6]) else nil

M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
GuiDump.init(M)

local function body()
	local G = M.G
	local Vector3, CFrame = G.Vector3, G.CFrame
	local ctx = setup(M, { stage = 4, vw = VW, vh = VH, insets = INSETS })
	local Drive, Driver = ctx.Drive, ctx.Driver
	ctx.tick(1.1)
	local plot = ctx.plot
	local entrance = ctx.hq(Vector3.new(0, 3, -60))
	ctx.stand(entrance)
	ctx.camera(entrance + Vector3.new(0, 12, -30), entrance)
	local e = ctx.session.data.empire
	-- a realistic company: two clients signed, one pinned
	e.deals.accounts = { helpdesk = { expires = e.seconds + 4000, since = 0 }, code = { expires = e.seconds + 3000, since = 0 } }
	e.deals.pinned = "pixel"
	local legA = Drive.leg("hq_garage", "hq_entrance", plot.index)
	local function book(to)
		ctx.T.now += 5
		return ctx.call({ action = "ride", op = "request", to = to })
	end
	if STATE == "hud_toast" then
		book("airport_departures")
		ctx.tick(Drive.walkAt(ctx.T.now) + legA.dur + 1) -- "Finn is waiting for you at the HQ entrance." arrives as a toast
		local last = nil
		for _, f in ctx.fired do if f.kind == "CAMPUS_NOTICE" then last = f.payload.text end end
		ctx.Toast.show("info", last or "Your driver is waiting for you.", 6)
	elseif STATE == "sheet_far" then
		ctx.stand(Vector3.new(600, 30, 1250))
		Driver.phoneHook(ctx.session, {})
	elseif STATE == "hud_coming" then
		book("airport_departures")
		ctx.tick(Drive.walkAt(ctx.T.now) + 9)
	elseif STATE == "hud_waiting" or STATE == "hud_board" then
		book("airport_departures")
		ctx.tick(Drive.walkAt(ctx.T.now) + legA.dur + 12)
		if STATE == "hud_board" then ctx.stand((Drive.endCF(legA) * CFrame.new(6, 3, 2)).Position) end
	elseif STATE == "riding" or STATE == "sheet_riding" then
		book("airport_departures")
		ctx.tick(Drive.walkAt(ctx.T.now) + legA.dur + 2)
		ctx.stand((Drive.endCF(legA) * CFrame.new(6, 3, 2)).Position)
		ctx.call({ action = "ride", op = "board" })
		ctx.tick(Drive.BOARD_DELAY + 22)
		if STATE == "sheet_riding" then Driver.phoneHook(ctx.session, {}) end
	elseif STATE == "sheet_free" then
		Driver.phoneHook(ctx.session, {})
	elseif STATE == "sheet_busy" or STATE == "hud_queued" then
		-- both drivers are out: one with the founder's guests, one taking a field rep to the airport
		e.employees.marketer = 3
		e.staffProfiles = e.staffProfiles or {}
		e.staffProfiles.marketer = { { n = "Mia Chen", s = 11 }, { n = "Leo Park", s = 12 }, { n = "Ida Moss", s = 13 } }
		table.insert(e.deals.tripList, { client = "helix", kind = "sign", back = e.seconds + 2400, founder = false, hosted = false, crew = 1, left = e.seconds })
		table.insert(e.deals.tripList, { client = "ledger", kind = "sign", back = e.seconds + 1200, founder = false, hosted = true, crew = 0, left = e.seconds + 1 })
		ctx.tick(1.2)
		ctx.tick(20)
		if STATE == "hud_queued" then
			local r = book("clouddesk")
			assert(r.ok and r.queued, "expected a queued booking: " .. tostring(r.err))
			ctx.tick(3)
		else
			Driver.phoneHook(ctx.session, {})
		end
	elseif STATE == "sheet_abroad" then
		ctx.City.trips[ctx.player.UserId] = { player = ctx.player, state = "abroad", to = "abroad", releaseAt = math.huge }
		local stand = Drive.place("pm_limo")
		ctx.stand(stand.door.Position)
		Driver.phoneHook(ctx.session, {})
	end
	ctx.frame()
	M.settle(0.3)
	GuiDump.setViewport(ctx.playerGui, VW, VH, INSETS)
	local n = GuiDump.applyFeedback({ ctx.playerGui }, FEEDBACK)
	M.settle(0.3)
	ctx.frame()
	M.settle(0.2)
	GuiDump.dump({ ctx.playerGui }, { scene = "drive", state = STATE, viewport = { VW, VH }, insets = INSETS, feedbackChanged = n })
end

local ok, res, status = M.runMain(body, { timeout = 600, maxSteps = 8000000 })
if not ok then print("@@ERROR body crashed (" .. tostring(status) .. "): " .. tostring(res)) end
if M.stats.errors > 0 then print("@@ERROR background thread errors: " .. M.stats.errors) end
