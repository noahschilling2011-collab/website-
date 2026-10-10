--!nocheck
-- Talk package: TalkService in the headless mock with real EmployeeRigDesign rigs, the real
-- StaffService/Dialogue and stubbed Session/Plot/Remote (tests/talk/stubs.luau).
-- Covers: prompt + remote open, owner/public rules (incl. a mutation check that the job rule is what
-- blocks visitors), distance on open and while talking, off-duty/inactive, one conversation per NPC and
-- per player, prompt cooldown + say interval, option validation and full option flow, idle timeout,
-- NPC removed, player leaving / session closing, facing + restore, StaffService hold/release hooks,
-- visitors-today sampler, numbers in answers (room, wage, desks, café seats, guest cards), home desk room
-- (HomeWorkstation → HomeRoom) + desks in use (OccupiedBy), lunch phase via Staff.recordOf (and a failing
-- recordOf), the 1 s walk-away sweep (15 studs kept, 17 studs ended with the farewell) and MAX_SECONDS.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_talk && tools/luau tests/talk/test_talk.luau [-a .gen_dir]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_talk")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
for path, src in require("./stubs") do sources[path] = src end
local fixture = require("./fixture")
M.loadTree(manifest, sources)
M.quiet = true
local G = M.G
local say = print
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; say("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end

local function body()
	local Vector3, CFrame = G.Vector3, G.CFrame
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local Services = Server.Services
	local Remote = M.require(Server.Lib.Remote)
	local Session = M.require(Services.SessionService)
	local Staff = M.require(Services.StaffService)
	local Talk = M.require(Services.TalkService)
	local Dialogue = M.require(RS.Shared.Dialogue)
	local Plan = M.require(RS.Shared.Config.BuildingPlan)
	local EmpireConfig = M.require(RS.Shared.Config.EmpireConfig)
	local Format = M.require(RS.Shared.Format)
	local EmployeeConfig = M.require(RS.Shared.Config.EmployeeConfig)
	local TIER = 2
	local fx = fixture(M, G, TIER)
	local rigs, owner, visitor = fx.rigs, fx.ownerPlayer, fx.visitorPlayer
	local clock = 100
	Talk.clock = function() return clock end
	Talk.init()
	local function tick(dt) clock += dt or 1 end
	local function fired(kind, player)
		local out = {}
		for _, f in Remote.fired do if f.name == "Notify" and f.args[1] == kind and (player == nil or f.player == player) then table.insert(out, f.args[2]) end end
		return out
	end
	local function last(kind, player) local list = fired(kind, player); return list[#list] end
	local function prompt(model) return model.Head.EmployeeTalk end
	local function stand(player, model, offset) fx.moveTo(if player == owner then fx.ownerRoot else fx.visitorRoot, fx.near(model, offset)) end
	local act = Remote.binds.TalkAction

	------------------------------------------------------------------ A. setup + prompt attributes
	check("TalkAction bound with a rate limit", act ~= nil and Remote.limits.TalkAction and Remote.limits.TalkAction.burst > 0 and Remote.limits.TalkAction.perSecond > 0)
	local publicJobs = { Reception = true, Security = true, Barista = true, Chef = true, ["Cafe Host"] = true }
	for i, job in fx.jobs do
		local m = rigs["ops" .. i]
		if m then
			local q = prompt(m)
			check("prompt Public only for front-of-house: " .. job, (q:GetAttribute("Public") == true) == (publicJobs[job] == true))
			if publicJobs[job] then check("public ObjectText names the job: " .. job, q.ObjectText == m:GetAttribute("EmployeeName") .. " · " .. job, q.ObjectText) end
			check("prompt keeps owner + index: " .. job, q:GetAttribute("OwnerUserId") == fx.OWNER and q:GetAttribute("EmployeeTalk") == 300 + i)
		end
	end
	check("researcher prompt owner-only", prompt(rigs.researcher):GetAttribute("Public") == nil and prompt(rigs.researcher).ObjectText == rigs.researcher:GetAttribute("EmployeeName"))

	------------------------------------------------------------------ B. owner opens via prompt; facing
	local r = rigs.researcher
	-- the researcher's home desk C1 and desk C2 belong to the First AI Studio (HomeRoom), C2 is in use
	r:SetAttribute("HomeWorkstation", "C1")
	local desks = {}
	for _, m in fx.office:GetChildren() do if m:GetAttribute("WorkstationType") == "Computer" then desks[m:GetAttribute("WorkstationId")] = m end end
	desks.C1:SetAttribute("HomeRoom", "G_FIRSTAI"); desks.C1:SetAttribute("Department", "design")
	desks.C2:SetAttribute("HomeRoom", "G_FIRSTAI"); desks.C2:SetAttribute("OccupiedBy", 5)
	local before = r.PrimaryPart.CFrame
	stand(owner, r, Vector3.new(4, 0, 3))
	Talk._prompt(prompt(r), owner)
	local open = last("TALK_OPEN", owner)
	check("prompt → TALK_OPEN", open ~= nil and type(open.id) == "string" and open.npc == r)
	check("payload: name/job/initials/greeting/options", open and open.name == r:GetAttribute("EmployeeName") and open.job == "AI Researcher" and open.initials == Dialogue.initials(open.name) and #open.greeting > 10 and #open.options >= 2 and #open.options <= 4 and open.options[#open.options].id == "bye")
	check("payload: room + level where the NPC stands", open and open.room == "First AI Studio" and open.level == "G", open and tostring(open.room) .. " " .. tostring(open.level))
	check("viewer owner", open and open.viewer == "owner")
	check("rig attributes TalkingTo/TalkFace", r:GetAttribute("TalkingTo") == fx.OWNER and typeof(r:GetAttribute("TalkFace")) == "Vector3")
	local look = r.PrimaryPart.CFrame.LookVector
	local toPlayer = (fx.ownerRoot.Position - r.PrimaryPart.Position) * Vector3.new(1, 0, 1)
	check("standing NPC turns to face the player", look:Dot(toPlayer.Unit) > 0.99, look:Dot(toPlayer.Unit))
	check("position unchanged by facing", (r.PrimaryPart.Position - before.Position).Magnitude < 1e-6)
	check("conversation registered", Talk.conversation(r) and Talk.conversation(r).userId == fx.OWNER)

	------------------------------------------------------------------ C. say: validation + flow + numbers
	local res = act(fx.ownerS, { action = "say", id = open.id, option = "not_offered" })
	check("not offered option → BAD_INPUT", res.ok == false and res.err == "BAD_INPUT")
	res = act(fx.ownerS, { action = "say", id = "talk999", option = "work" })
	check("wrong conversation id → NO_TALK", res.ok == false and res.err == "NO_TALK")
	res = act(fx.ownerS, { action = "say", id = open.id, option = { "x" } })
	check("non-string option → BAD_INPUT", res.ok == false and res.err == "BAD_INPUT")
	res = act(fx.ownerS, { action = "say", id = open.id, option = "work" })
	check("say right after open is rate limited", res.ok == false and res.err == "RATE_LIMIT")
	tick(1)
	res = act(fx.ownerS, { action = "say", id = open.id, option = "work" })
	check("work answer", res.ok and has(res.text, "First AI Studio") and #res.options >= 2 and #res.options <= 4, res.text)
	tick(1)
	local notYet = act(fx.ownerS, { action = "say", id = open.id, option = "you" })
	check("an option not yet offered is refused", notYet.ok == false and notYet.err == "BAD_INPUT")
	r.PrimaryPart.CFrame = before -- a job step turns the NPC back to its desk mid-conversation
	tick(1)
	local again = act(fx.ownerS, { action = "say", id = open.id, option = res.options[1].id })
	check("NPC faces the player again on the next answer", again.ok and r.PrimaryPart.CFrame.LookVector:Dot(toPlayer.Unit) > 0.99)
	local asked2 = again.ok and res.options[1].id or nil
	res = act(fx.ownerS, { action = "say", id = open.id, option = "work" })
	check("asked topic is no longer offered (and rate limited)", res.ok == false)
	local offered = {}
	local steps, sawYou, sawCompany = 0, false, false
	local opts = act and nil
	-- ask everything that is offered until only bye is left
	local function ask(option)
		tick(1)
		return act(fx.ownerS, { action = "say", id = open.id, option = option })
	end
	local current = { "research", "company", "day", "you", "team", "room" }
	local teamText, roomText
	if asked2 == "you" then sawYou = true end
	for _, id in current do
		if id == asked2 then continue end
		local a = ask(id)
		steps += 1
		if not a.ok then check("flow answer " .. id, false, a.err); break end
		check("flow options 2..4 + bye last after " .. id, #a.options >= 1 and #a.options <= 4 and a.options[#a.options].id == "bye", #a.options)
		if id == "you" then
			sawYou = has(a.text, "5 out of 5") and has(a.text, string.format("$%.2f", EmpireConfig.ROLES[1].wage * 1.4)) and has(a.text, Format.money(EmpireConfig.ROLES[1].wage * 1.4 * 1200)) -- econ: role wage from EmpireConfig (CORE_SPEC 4)
		elseif id == "company" then
			sawCompany = has(a.text, Format.money(54321))
		elseif id == "team" then
			teamText = a.text
		elseif id == "room" then
			roomText = a.text
		end
	end
	check("you: skill + wage from the persistent profile", sawYou)
	check("company: cash from the owner's session", sawCompany)
	check("team: home desk room (HomeWorkstation → HomeRoom), department of the desk, desks in use", has(teamText, "My desk is in the First AI Studio (G), part of Model Architecture.") and has(teamText, "2 desks in there, 1 in use right now."), teamText)
	check("team: the role's effect from EmpireConfig.ROLES", has(teamText, "Each of us adds " .. string.match(EmpireConfig.ROLES[1].desc, "^(.-) per employee")), teamText)
	check("room: the plan room the NPC stands in + its desks in use", has(roomText, "This is the First AI Studio") and has(roomText, "2 desks in here, 1 in use right now."), roomText)
	local bye = ask("bye")
	check("bye closes", bye.ok and bye.close == true and #bye.options == 0 and has(bye.text, "Noah"), bye.text)
	check("conversation cleared after bye", Talk.conversation(r) == nil and r:GetAttribute("TalkingTo") == nil and r:GetAttribute("TalkFace") == nil)
	check("facing restored exactly after the conversation", (r.PrimaryPart.CFrame.Position - before.Position).Magnitude < 1e-6 and r.PrimaryPart.CFrame.LookVector:Dot(before.LookVector) > 0.9999)
	res = act(fx.ownerS, { action = "say", id = open.id, option = "work" })
	check("say after close → NO_TALK", res.ok == false and res.err == "NO_TALK")

	------------------------------------------------------------------ D. distance
	local e = rigs.engineer
	stand(owner, e, Vector3.new(12.5, 0, 0))
	tick(2)
	Talk._prompt(prompt(e), owner)
	check("12.5 studs → no conversation", Talk.conversation(e) == nil)
	check("too far → toast with the name", has(last("TALK_NOTICE", owner) and last("TALK_NOTICE", owner).text, "closer to " .. string.match(e:GetAttribute("EmployeeName"), "^%S+")))
	stand(owner, e, Vector3.new(11.5, 0, 0))
	tick(2)
	res = act(fx.ownerS, { action = "open", npc = e })
	check("11.5 studs → remote open works", res.ok and res.talk and res.talk.npc == e and Talk.conversation(e) ~= nil)
	local eid = res.talk.id
	stand(owner, e, Vector3.new(15, 0, 0))
	tick(1)
	res = act(fx.ownerS, { action = "say", id = eid, option = "work" })
	check("15 studs while talking still answers (keep distance 16)", res.ok, res.err)
	stand(owner, e, Vector3.new(17, 0, 0))
	tick(1)
	res = act(fx.ownerS, { action = "say", id = eid, option = res.options and res.options[1] and res.options[1].id or "day" })
	check("17 studs → TOO_FAR and the conversation ends", res.ok == false and res.err == "TOO_FAR" and Talk.conversation(e) == nil and e:GetAttribute("TalkingTo") == nil)

	------------------------------------------------------------------ E. owner/public rules
	local reception, kitchen = rigs.ops1, rigs.ops9
	stand(visitor, r, Vector3.new(3, 0, 0)); tick(2)
	local noticesBefore = #fired("TALK_NOTICE", visitor)
	Talk._prompt(prompt(r), visitor)
	check("visitor → researcher refused silently", Talk.conversation(r) == nil and #fired("TALK_NOTICE", visitor) == noticesBefore)
	res = act(fx.visitorS, { action = "open", npc = r })
	check("visitor → researcher via remote → NOT_PUBLIC", res.ok == false and res.err == "NOT_PUBLIC")
	stand(visitor, kitchen, Vector3.new(3, 0, 0)); tick(2)
	res = act(fx.visitorS, { action = "open", npc = kitchen })
	check("visitor → kitchen team → NOT_PUBLIC", res.ok == false and res.err == "NOT_PUBLIC")
	-- a Public attribute alone is not enough: the server checks the job too
	prompt(kitchen):SetAttribute("Public", true)
	res = act(fx.visitorS, { action = "open", npc = kitchen })
	check("forged Public attribute on a back-of-house prompt still refused", res.ok == false and res.err == "NOT_PUBLIC")
	-- mutation check: with the job rule broken the same request gets through (the test above is sensitive)
	local realRule = Dialogue.isPublicKind
	Dialogue.isPublicKind = function() return true end
	tick(2)
	res = act(fx.visitorS, { action = "open", npc = kitchen })
	check("NEGATIVE: without the job rule the visitor would get in", res.ok == true)
	if res.ok then act(fx.visitorS, { action = "close", id = res.talk.id }) end
	Dialogue.isPublicKind = realRule
	prompt(kitchen):SetAttribute("Public", nil)
	stand(visitor, reception, Vector3.new(3, 0, 0)); tick(2)
	Talk._prompt(prompt(reception), visitor)
	local vopen = last("TALK_OPEN", visitor)
	check("visitor → reception opens", vopen ~= nil and vopen.npc == reception and vopen.viewer == "visitor" and Talk.conversation(reception).viewer == "visitor")
	local vids = {}; for _, o in vopen.options do vids[o.id] = true end
	check("visitor topics (about/where/visitors), no company cash topic", vids.about and vids.where and vids.visitors and not vids.company)
	check("visitor greeting introduces the receptionist", has(vopen.greeting, "welcome to Nimbus Labs") and has(vopen.greeting, "I'm " .. string.match(reception:GetAttribute("EmployeeName"), "^%S+")), vopen.greeting)
	------------------------------------------------------------------ F. lock: one conversation per NPC
	stand(owner, reception, Vector3.new(-3, 0, 0)); tick(2)
	Talk._prompt(prompt(reception), owner)
	check("owner blocked while a visitor talks to the receptionist", Talk.conversation(reception).userId == fx.VISITOR and has(last("TALK_NOTICE", owner).text, "talking to someone else"))
	res = act(fx.ownerS, { action = "open", npc = reception })
	check("remote open → NPC_BUSY", res.ok == false and res.err == "NPC_BUSY")
	-- visitor answers: where → café directions, visitors today
	tick(1)
	local w = act(fx.visitorS, { action = "say", id = vopen.id, option = "where" })
	check("visitor where → only public places", w.ok and #w.options >= 2 and w.options[1].id == "where:G_CAFE")
	local onlyPublic = true
	for _, o in w.options do if o.id ~= "bye" and o.id ~= "where:more" then local room = Plan.room(TIER, string.sub(o.id, 7)); if not room or room.access ~= "public" then onlyPublic = false end end end
	check("visitor place chips are public rooms", onlyPublic)
	tick(1)
	local cafe = act(fx.visitorS, { action = "say", id = vopen.id, option = "where:G_CAFE" })
	check("café directions: left, ground floor, same floor", cafe.ok and has(cafe.text, "on the left") and has(cafe.text, "ground floor") and has(cafe.text, "on this floor"), cafe.text)
	act(fx.visitorS, { action = "close", id = vopen.id })
	check("close releases the receptionist", Talk.conversation(reception) == nil and reception:GetAttribute("TalkingTo") == nil)
	tick(2)
	Talk._prompt(prompt(reception), owner)
	local oopen = last("TALK_OPEN", owner)
	check("owner can talk once the visitor left", oopen and oopen.npc == reception and oopen.viewer == "owner")
	------------------------------------------------------------------ G. one conversation per player
	local barista = rigs.ops7
	stand(owner, barista, Vector3.new(3, 0, 0)); tick(2)
	Talk._prompt(prompt(barista), owner)
	check("opening a second conversation ends the first", Talk.conversation(reception) == nil and reception:GetAttribute("TalkingTo") == nil and Talk.conversation(barista) ~= nil)
	local bopen = last("TALK_OPEN", owner)
	tick(1)
	local menu = act(fx.ownerS, { action = "say", id = bopen.id, option = "menu" })
	check("barista menu from CampusConfig.SNACKS", menu.ok and has(menu.text, "House Coffee $25") and has(menu.text, "Campus Lunch $65"), menu.text)
	tick(1)
	local lunch = act(fx.ownerS, { action = "say", id = bopen.id, option = "lunch" })
	check("café seats counted in the office (5)", lunch.ok and has(lunch.text, "5 seats"), lunch.text)
	check("no lunch count claimed without LunchesServed", not has(lunch.text, "served"))
	fx.office:SetAttribute("LunchesServed", 9)
	act(fx.ownerS, { action = "close", id = bopen.id })
	------------------------------------------------------------------ H. prompt cooldown
	local chef = rigs.ops8
	stand(owner, chef, Vector3.new(3, 0, 0)); tick(2)
	local opens = #fired("TALK_OPEN", owner)
	Talk._prompt(prompt(chef), owner)
	Talk._prompt(prompt(chef), owner)
	check("double prompt trigger → one TALK_OPEN", #fired("TALK_OPEN", owner) == opens + 1)
	local copen = last("TALK_OPEN", owner)
	tick(1)
	local cl = act(fx.ownerS, { action = "say", id = copen.id, option = "lunch" })
	check("lunches served when the office reports them", cl.ok and has(cl.text, "9 lunches served today"), cl.text)
	------------------------------------------------------------------ I. idle timeout
	M.settle(Talk.IDLE + 1)
	local closed = last("TALK_CLOSE", owner)
	check("idle conversation ends with TALK_CLOSE + farewell", closed and closed.id == copen.id and type(closed.text) == "string" and #closed.text > 5 and Talk.conversation(chef) == nil and chef:GetAttribute("TalkingTo") == nil)
	------------------------------------------------------------------ J. off duty / inactive
	local it = rigs.ops6
	stand(owner, it, Vector3.new(3, 0, 0)); tick(2)
	it:SetAttribute("OffDuty", true)
	Talk._prompt(prompt(it), owner)
	check("off duty → refused with a toast", Talk.conversation(it) == nil and has(last("TALK_NOTICE", owner).text, "off duty"))
	it:SetAttribute("OffDuty", false); it:SetAttribute("Activity", "INACTIVE"); tick(2)
	res = act(fx.ownerS, { action = "open", npc = it })
	check("inactive → UNAVAILABLE", res.ok == false and res.err == "UNAVAILABLE")
	it:SetAttribute("Activity", "WORKING"); tick(2)
	res = act(fx.ownerS, { action = "open", npc = it })
	check("IT opens", res.ok)
	tick(1)
	local faultJobs = false
	for _, steps in EmployeeConfig.JOBS or {} do for _, st in steps do if st.fault then faultJobs = true end end end
	-- a broken desk screen in the First AI Studio (PropFx contract: tag + FxState)
	local screen = G.Instance.new("Part"); screen.Name = "DisplayContent"; screen.Anchored = true
	screen.CFrame = fx.cf * CFrame.new(-36, 6, 0); screen.Parent = fx.office
	if faultJobs then
		local faults = act(fx.ownerS, { action = "say", id = res.talk.id, option = "faults" })
		check("IT with the fault system and nothing broken → no open faults", faults.ok and has(faults.text, "No open faults"), faults.text)
	else
		local faults = act(fx.ownerS, { action = "say", id = res.talk.id, option = "faults" })
		check("IT without a fault system → generic text, no count", faults.ok and has(faults.text, "No ticket system") and not string.find(faults.text, "%d"), faults.text)
	end
	act(fx.ownerS, { action = "close", id = res.talk.id }); tick(2)
	screen:SetAttribute("Fx", "screen"); screen:SetAttribute("FxState", "broken"); game:GetService("CollectionService"):AddTag(screen, "PropFx")
	res = act(fx.ownerS, { action = "open", npc = it }); tick(1)
	local broken = act(fx.ownerS, { action = "say", id = res.talk.id, option = "faults" })
	check("IT: 1 open fault in the First AI Studio", broken.ok and has(broken.text, "1 open fault") and has(broken.text, "First AI Studio"), broken.text)
	screen:SetAttribute("FxState", "idle")
	tick(1)
	local hw = act(fx.ownerS, { action = "say", id = res.talk.id, option = "hardware" })
	check("IT hardware: 7 desks counted, 1 GPU slot", hw.ok and has(hw.text, "7 computer desks") and has(hw.text, "1 GPU slot"), hw.text)
	------------------------------------------------------------------ K. NPC removed during the conversation
	local itId = res.talk.id
	it.Parent = nil
	check("removed NPC → TALK_CLOSE + released", Talk.conversation(it) == nil and last("TALK_CLOSE", owner).id == itId)
	------------------------------------------------------------------ L. StaffService hold/release hooks
	local holds, releases = {}, {}
	Staff.hold = function(model, at) table.insert(holds, { model = model, at = at }); return true end
	Staff.release = function(model) table.insert(releases, model) end
	local fleet = rigs.ops12
	stand(owner, fleet, Vector3.new(3, 0, 0)); tick(2)
	res = act(fx.ownerS, { action = "open", npc = fleet })
	check("Staff.hold called with the NPC and the player position", res.ok and #holds == 1 and holds[1].model == fleet and (holds[1].at - fx.ownerRoot.Position).Magnitude < 1e-6)
	tick(1)
	local carsA = act(fx.ownerS, { action = "say", id = res.talk.id, option = "cars" })
	check("fleet: the founder's starter car", carsA.ok and has(carsA.text, "1 company car") and has(carsA.text, "Founder's Hatch"), carsA.text)
	act(fx.ownerS, { action = "close", id = res.talk.id })
	check("Staff.release called once on close", #releases == 1 and releases[1] == fleet)
	Staff.hold = function() error("boom") end
	tick(2)
	res = act(fx.ownerS, { action = "open", npc = fleet })
	check("a failing Staff.hold never breaks talking", res.ok)
	act(fx.ownerS, { action = "close", id = res.talk.id })
	check("no release after a failed hold", #releases == 1)
	Staff.hold = nil; Staff.release = nil
	------------------------------------------------------------------ M. walking NPC: not turned
	local host = rigs.ops10
	host.PrimaryPart.Anchored = false; host:SetAttribute("Activity", "WALKING"); host:SetAttribute("Task", "Lunch")
	local hostCF = host.PrimaryPart.CFrame
	stand(owner, host, Vector3.new(0, 0, -4)); tick(2)
	res = act(fx.ownerS, { action = "open", npc = host })
	check("walking NPC talks without being turned", res.ok and host.PrimaryPart.CFrame.LookVector:Dot(hostCF.LookVector) > 0.9999)
	check("walking NPC greeting says where they're going", res.ok and has(res.talk.greeting, "on my way to lunch"), res.ok and res.talk.greeting)
	act(fx.ownerS, { action = "close", id = res.talk.id })
	host.PrimaryPart.Anchored = true; host:SetAttribute("Activity", "WORKING")
	------------------------------------------------------------------ M2. lunch phase from the live staff record
	local realRecord = Staff.recordOf
	local eng = rigs.engineer
	eng:SetAttribute("Activity", "LUNCH"); eng:SetAttribute("Task", "Lunch")
	Staff.recordOf = function(model) return if model == eng then { lunch = { phase = "queue" } } else nil end
	stand(owner, eng, Vector3.new(3, 0, 0)); tick(2)
	res = act(fx.ownerS, { action = "open", npc = eng }); tick(1)
	local q = act(fx.ownerS, { action = "say", id = res.talk.id, option = "work" })
	check("lunch phase from Staff.recordOf (queue)", q.ok and has(q.text, "lunch queue"), q.text)
	act(fx.ownerS, { action = "close", id = res.talk.id })
	Staff.recordOf = function() error("boom") end
	tick(2)
	res = act(fx.ownerS, { action = "open", npc = eng }); tick(1)
	q = act(fx.ownerS, { action = "say", id = res.talk.id, option = "work" })
	check("a failing Staff.recordOf never breaks talking (plain lunch line)", q.ok and has(q.text, "café") and not has(q.text, "queue"), q.text)
	act(fx.ownerS, { action = "close", id = res.talk.id })
	Staff.recordOf = realRecord
	eng:SetAttribute("Activity", "WORKING"); eng:SetAttribute("Task", "WriteCode")
	------------------------------------------------------------------ M3. walking away ends the conversation (server sweep)
	stand(owner, eng, Vector3.new(3, 0, 0)); tick(2)
	res = act(fx.ownerS, { action = "open", npc = eng })
	stand(owner, eng, Vector3.new(15, 0, 0))
	Talk._sweep()
	check("sweep keeps a conversation at 15 studs", Talk.conversation(eng) ~= nil)
	stand(owner, eng, Vector3.new(17, 0, 0))
	M.settle(Talk.SWEEP_EVERY + 0.5)
	local walked = last("TALK_CLOSE", owner)
	check("walking 17 studs away → the 1 s sweep ends it with the farewell", Talk.conversation(eng) == nil and eng:GetAttribute("TalkingTo") == nil and walked and walked.id == res.talk.id and type(walked.text) == "string" and #walked.text > 5, walked and walked.text)
	stand(owner, eng, Vector3.new(3, 0, 0)); tick(2)
	res = act(fx.ownerS, { action = "open", npc = eng })
	clock += Talk.MAX_SECONDS + 1
	Talk._sweep()
	check("sweep ends conversations older than MAX_SECONDS", Talk.conversation(eng) == nil and last("TALK_CLOSE", owner).id == res.talk.id)
	------------------------------------------------------------------ N. visitors today + guest cards
	local sec = rigs.ops3
	fx.moveTo(fx.visitorRoot, fx.cf * Vector3.new(0, 3, -36)) -- reception hall, inside the building
	Talk._sample()
	stand(owner, sec, Vector3.new(3, 0, 0)); tick(2)
	res = act(fx.ownerS, { action = "open", npc = sec })
	tick(1)
	local vis = act(fx.ownerS, { action = "say", id = res.talk.id, option = "visitors" })
	check("security visitors: 1 now, 1 today", vis.ok and has(vis.text, "1 visitor in the building") and has(vis.text, "1 visitor so far today"), vis.text)
	tick(1)
	local acc = act(fx.ownerS, { action = "say", id = res.talk.id, option = "access" })
	check("security access: 1 guest card from live.campus.passes", acc.ok and has(acc.text, "1 guest card"), acc.text)
	fx.moveTo(fx.visitorRoot, fx.cf * Vector3.new(0, 3, -150)) -- out on the street again
	Talk._sample()
	tick(1)
	local cams = act(fx.ownerS, { action = "say", id = res.talk.id, option = "cameras" })
	check("cameras: Campus Security on level 1 of the pavilion", cams.ok and has(cams.text, "Campus Security") and has(cams.text, "pavilion"), cams.text)
	act(fx.ownerS, { action = "close", id = res.talk.id })
	------------------------------------------------------------------ O. player leaving + session closing
	stand(visitor, reception, Vector3.new(3, 0, 0)); tick(2)
	res = act(fx.visitorS, { action = "open", npc = reception })
	check("visitor talks again", res.ok)
	for _, fn in Session.closing do fn(fx.ownerS) end
	check("owner session closing ends conversations with the owner's staff (visitor notified)", Talk.conversation(reception) == nil and last("TALK_CLOSE", visitor) and last("TALK_CLOSE", visitor).id == res.talk.id)
	tick(2)
	res = act(fx.visitorS, { action = "open", npc = reception })
	check("visitor can talk to the receptionist again", res.ok)
	M.fire(game:GetService("Players").PlayerRemoving, visitor)
	check("player leaving ends the conversation", Talk.conversation(reception) == nil and reception:GetAttribute("TalkingTo") == nil)
	------------------------------------------------------------------ P. bad remote input
	check("open without npc → BAD_INPUT", act(fx.ownerS, { action = "open" }).err == "BAD_INPUT")
	check("open with a non-staff instance → NPC_GONE", act(fx.ownerS, { action = "open", npc = fx.office }).err == "NPC_GONE")
	check("unknown action → BAD_INPUT", act(fx.ownerS, { action = "dance" }).err == "BAD_INPUT")
	check("close without a conversation is harmless", act(fx.ownerS, { action = "close", id = "nope" }).ok == true)
	-- visitor/assistant rigs (prompt renamed to PeopleTalk) are not handled here
	local fake = rigs.ops5
	prompt(fake).Name = "PeopleTalk"
	stand(owner, fake, Vector3.new(3, 0, 0)); tick(2)
	local before2 = #fired("TALK_OPEN", owner)
	Talk._prompt(fake.Head.PeopleTalk, owner)
	check("PeopleTalk prompts (applicants/assistant) are ignored", #fired("TALK_OPEN", owner) == before2)
	say(string.format("talk: %d notifications fired", #Remote.fired))
end
setfenv(body, M.envFor(nil))
local ok, err = M.runMain(body, { timeout = 600 })
if not ok then say("ERROR: " .. tostring(err)); failc += 1 end
say(string.format("talk service tests: %d passed, %d failed", pass, failc))
if failc > 0 then error("talk service tests failed", 0) end
