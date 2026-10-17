#!/usr/bin/env bash
# guests_jet: dumps for the Blender renders (tools/blenderprev) - the real game code in the harness mock, the
# client controllers run headless and their figures are cloned into the dump:
#   out/guests_jet/render/guesthouse.json  HQ tier 4 (building-local) + GuestController's hotel guests at two moments
#                                          of the same day: the lobby (most guests in the lobby, someone at the desk)
#                                          and the breakfast room (08:40-09:30)
#   out/guests_jet/render/world.json       district + city + GuestController's passengers (City Airport gate A1 during
#                                          boarding, Port Meridian hall) + JetController: the local company's jet in
#                                          Hangar 1 with the pilots in the crew corner, another company's jet parked on
#                                          the Port Meridian VIP apron (pilots in the cockpit, airstair down)
# Seated rigs get their legs bent here (the mock does not apply Motor6D transforms). Usage: tests/guests_jet/render_dumps.sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
OUT=out/guests_jet/render; mkdir -p "$OUT"
TMP="$OUT/src_tmp"; GEN=harness/.gen_gj_render_$$
rm -rf "$TMP" && cp -r work/src "$TMP"
cat > "$TMP/ServerScriptService/Server/Services/GJRenderHotel.module.luau" <<'LUA'
--!nocheck
local RS = game:GetService("ReplicatedStorage")
local Design = require(script.Parent.HeadquartersDesign)
return {
	build = function(cf, session, accent)
		local office = Design.build(cf, session, accent)
		office:SetAttribute("HotelGuests", 9) -- CompanyOps: 7 + one hosted client team (2)
		local plots = Instance.new("Folder"); plots.Name = "Plots"; plots.Parent = workspace
		local plot = Instance.new("Model"); plot.Name = "Plot_01"; plot.Parent = plots
		office.Parent = plot
		local GP = require(RS.Shared.GuestPlan)
		local Ops = require(RS.Shared.CompanyOps)
		local GC = require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.GuestController)
		local seed = session.userId
		local function inRect(p, x1, x2, z1, z2) return p.X > x1 and p.X < x2 and p.Z > z1 and p.Z < z2 and p.Y < 8 end
		-- the best moment of the day (in 2 s steps over 6 days) for each room
		local best = { lobby = { score = -1 }, breakfast = { score = -1 }, evening = { score = -1 } }
		for d = 900, 905 do
			for s = 0, Ops.DAY - 1, 2 do
				local lobby, desk, sitL, bf, sitB = 0, 0, 0, 0, 0
				for g = 1, 9 do
					for _, a in GP.slotDay(seed, g, d, 9) do
						local mode, f, hint = GP.sample(a, s)
						if f then
							local p = f.Position
							if inRect(p, -116, -98, 76, 104) then lobby += 1; if hint == "checkin" or hint == "checkout" then desk += 1 end; if mode == "sit" then sitL += 1 end end
							if inRect(p, -116, -98, 104, 140) then bf += 1; if mode == "sit" then sitB += 1 end end
						end
					end
				end
				local sl = lobby + sitL + (if desk > 0 then 3 else 0)
				if sl > best.lobby.score and Ops.hour(s) >= 10 and Ops.hour(s) < 17.5 then best.lobby = { score = sl, d = d, s = s } end
				local sb = bf + sitB
				if sb > best.breakfast.score then best.breakfast = { score = sb, d = d, s = s } end
				local se = sitL * 2 + lobby
				if s > 900 and se > best.evening.score then best.evening = { score = se, d = d, s = s } end
			end
		end
		local world = Instance.new("Model"); world.Name = "GuestHouseRender"
		for _, room in { "lobby", "breakfast", "evening" } do
			local b = best[room]
			print("MOMENT", room, b.d, b.s, string.format("%.2f", Ops.hour(b.s)), b.score)
			local T = b.d * Ops.DAY + b.s
			local cam = cf * Vector3.new(-104, 6, 95)
			GC.scan(cam, T)
			local parts, frames = GC.step(1, T, cam)
			for k, p in parts do p.CFrame = frames[k] end
			local snap = Instance.new("Model"); snap.Name = "Guests_" .. room; snap.Parent = world
			for _, fig in GC.pool() do
				if fig.actor then
					local p = fig.pos
					local keep = if room == "breakfast" then inRect(p, -126, -96, 104, 142) else inRect(p, -126, -96, 74, 106)
					if keep then fig.model:Clone().Parent = snap end
				end
			end
			print("FIGURES", room, #snap:GetChildren())
		end
		office.Parent = world
		return world
	end,
}
LUA
cat > "$TMP/ServerScriptService/Server/Services/GJRenderWorld.module.luau" <<'LUA'
--!nocheck
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
return {
	build = function(_cf, _session, _accent)
		local Campus = require(script.Parent.CampusService)
		local Builder = require(script.Parent.CityBuilder)
		Campus.init()
		local district = workspace:FindFirstChild("TechDistrict")
		local city = Builder.build("Port Meridian")
		local world = Instance.new("Model"); world.Name = "World"
		district.Parent = world; city.Parent = world
		local FP = require(RS.Shared.FlightPlan)
		local JP = require(RS.Shared.JetPlan)
		local GP = require(RS.Shared.GuestPlan)
		local Rig = require(script.Parent.EmployeeRigDesign)
		local Client = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers
		-- passengers: City Airport during boarding, Port Meridian before its boarding
		local GC = require(Client.GuestController)
		local I = FP.interval()
		local k = 40
		local function snapshot(name, T, cam)
			GC.scan(cam, T)
			local parts, frames = GC.step(1, T, cam)
			for i, p in parts do p.CFrame = frames[i] end
			local m = Instance.new("Model"); m.Name = name; m.Parent = world
			for _, fig in GC.pool() do if fig.actor then fig.model:Clone().Parent = m end end
			print("FIGURES", name, #m:GetChildren())
		end
		local B0 = FP.legStart("out", k) + FP.leg("out").phases.boarding.t0
		snapshot("Passengers_home", B0 + 6, Vector3.new(-190, 32, 2505))
		local PB0 = FP.legStart("back", k) + FP.leg("back").phases.boarding.t0
		snapshot("Passengers_pm", PB0 - 40, Vector3.new(60, 32, 7655))
		-- jets: a local player, the own company's jet parked in Hangar 1, another company's on the PM VIP apron
		local me = { UserId = 1001, Name = "Tester" }
		local function crew(folder, owner)
			local c = Instance.new("Folder"); c.Name = "Crew"; c.Parent = folder
			for i, key in { "Captain", "FirstOfficer" } do
				local m = Rig.build(c, owner, 9200 + i * 41, "pilot", CFrame.new(), { n = key })
				m.Name = key
				for _, d in m:GetDescendants() do if d:IsA("ProximityPrompt") then d:Destroy() end end
			end
		end
		local root = Instance.new("Folder"); root.Name = "CompanyJets"; root.Parent = RS
		local mine = Instance.new("Folder"); mine.Name = "Jet_1001"
		mine:SetAttribute("Owner", 1001); mine:SetAttribute("Company", "Nimbus Labs"); mine:SetAttribute("Livery", Color3.fromRGB(0, 170, 200))
		mine:SetAttribute("At", "home"); mine:SetAttribute("Slot", 1); crew(mine, 1001); mine.Parent = root
		local other = Instance.new("Folder"); other.Name = "Jet_2002"
		other:SetAttribute("Owner", 2002); other:SetAttribute("Company", "Helix Partners"); other:SetAttribute("Livery", Color3.fromRGB(150, 40, 52))
		other:SetAttribute("At", "abroad"); other:SetAttribute("Slot", 1); crew(other, 2002); other.Parent = root
		local JC = require(Client.JetController)
		JC.localUserId = 1001
		JC.attach(root)
		local cam = workspace.CurrentCamera
		local T = 1.7e9
		local jets = Instance.new("Model"); jets.Name = "Jets"; jets.Parent = world
		for _, at in { JP.HOME_PARK.Position, JP.slot(1).cf.Position } do
			cam.CFrame = CFrame.new(at + Vector3.new(30, 20, 60), at)
			JC.step(0.2)
			for f, v in JC.views() do
				local near = (v.state.pose.cf.Position - at).Magnitude < 5
				if near and v.model then
					v.model:Clone().Parent = jets
					-- the pilots where JetController poses them (the mock has no Motor6D assembly: the rigs are
					-- rebuilt at the posed root frames instead of cloning the client's rigs)
					local state = JC.crewState(v.state)
					for i, r in v.crew do
						local rootCf = r.root.CFrame
						local m = Rig.build(jets, v.userId, 9200 + i * 41, "pilot", rootCf, { n = "Pilot" .. i })
						m.Name = (if v.own then "Own" else "Other") .. "Pilot" .. i
						-- static render copies: no Humanoid (blenderprev's world scene drops Humanoid rigs as NPCs)
						for _, d in m:GetDescendants() do if d:IsA("ProximityPrompt") or d:IsA("Humanoid") then d:Destroy() end end
						-- the window-side arm JetController hides in the cockpit (LocalTransparencyModifier is not dumped)
						if r.outerHidden and r.outer[1] then
							local arm = m:FindFirstChild(r.outer[1].Name)
							for _, d in m:GetDescendants() do
								local w = if d:IsA("BasePart") then d:FindFirstChildOfClass("WeldConstraint") else nil
								if w and w.Part0 == arm then d:Destroy() end
							end
							if arm then arm:Destroy() end
						end
						local sitting = state == "cockpit" or (state == "corner" and JP.CREW.sit[i])
						if sitting then
							local hrp = m:FindFirstChild("HumanoidRootPart")
							for _, side in { -1, 1 } do
								local hip = hrp.CFrame * CFrame.new(side * 0.5, -1, 0)
								for _, d in m:GetDescendants() do
									if d:IsA("BasePart") and d ~= hrp then
										local lp = hrp.CFrame:PointToObjectSpace(d.Position)
										if lp.Y < -0.9 and lp.X * side > 0 then d.CFrame = hip * CFrame.Angles(math.pi / 2, 0, 0) * hip:Inverse() * d.CFrame end
									end
								end
							end
						end
					end
				end
			end
		end
		-- what JetController does locally: the decorative PrivateJet is hidden (LocalTransparencyModifier is not in the
		-- dump, so it is removed here) and the warm hangar light hangs over the own jet
		local pj = city:FindFirstChild("PrivateJet", true)
		if pj then pj:Destroy() end
		cam.CFrame = CFrame.new(JP.HOME_PARK.Position + Vector3.new(30, 20, 60), JP.HOME_PARK.Position)
		JC.step(0.2)
		local cl = workspace:FindFirstChild("CompanyJetClient")
		local lamp = cl and cl:FindFirstChild("JetHangarLight")
		if lamp then lamp:Clone().Parent = jets end
		print("JETS", #jets:GetChildren(), "privateJetRemoved", pj ~= nil, "light", lamp ~= nil)
		return world
	end,
}
LUA
python3 harness/make_manifest.py --src "$TMP" --gen "$GEN" >/dev/null || exit 1
tools/luau harness/build_dump.luau -a --tier 4 --gen "$(basename $GEN)" --module ServerScriptService.Server.Services.GJRenderHotel --no-parent \
  | python3 harness/split_dump.py "$OUT/guesthouse.json" "$OUT/guesthouse_log.txt" || { tail -20 "$OUT/guesthouse_log.txt"; rm -rf "$TMP" "$GEN"; exit 1; }
tools/luau harness/build_dump.luau -a --tier 1 --gen "$(basename $GEN)" --module ServerScriptService.Server.Services.GJRenderWorld --no-parent --allow-thread-errors \
  | python3 harness/split_dump.py "$OUT/world.json" "$OUT/world_log.txt" || { tail -20 "$OUT/world_log.txt"; rm -rf "$TMP" "$GEN"; exit 1; }
rm -rf "$TMP" "$GEN"
grep -h "MOMENT\|FIGURES\|JETS" "$OUT/guesthouse_log.txt" "$OUT/world_log.txt"
