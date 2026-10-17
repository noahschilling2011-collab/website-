#!/usr/bin/env bash
# Flight package: world dump for the clearance sweep (tests/flight/clearance.py). Builds the real world through
# the harness mock (CampusService district + CityBuilder: Business City, City Airport, Port Meridian), the
# shuttle hull (AircraftModel, FlightPlan.CONFIG kind/scale, full LOD) and the VIP helicopter at the origin
# (model "FlightShowcase"), and prints every low pose of the shuttle legs, the ambient runway traffic and the
# helicopter transfer as "POSE <what> <tau> <phase> x y z r00..r22" lines into the log.
# Usage: tests/flight/clearance_dump.sh [--src DIR] [--out DIR]   (default work/src, out/flight_clearance)
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
SRC=work/src; OUT=out/flight_clearance
while [ $# -gt 0 ]; do case "$1" in --src) SRC="$2"; shift;; --out) OUT="$2"; shift;; esac; shift; done
mkdir -p "$OUT"
TMP="$OUT/src_tmp"; GEN=harness/.gen_flight_clear
rm -rf "$TMP" && cp -r "$SRC" "$TMP"
cat > "$TMP/ServerScriptService/Server/Services/FlightClearanceHarness.module.luau" <<'LUA'
--!nocheck
local RS = game:GetService("ReplicatedStorage")
local Aircraft = require(RS.Shared.AircraftModel)
local FP = require(RS.Shared.FlightPlan)
local CityPlan = require(RS.Shared.Config.CityPlan)
local function line(what, tau, phase, cf)
	local c = { cf:GetComponents() }
	local parts = { "POSE", what, string.format("%.2f", tau), phase }
	for _, v in c do table.insert(parts, string.format("%.4f", v)) end
	print(table.concat(parts, " "))
end
return {
	build = function(_cf, _session, _accent)
		local Campus = require(script.Parent.CampusService)
		local Builder = require(script.Parent.CityBuilder)
		Campus.init()
		local district = workspace:FindFirstChild("TechDistrict")
		local city = Builder.build("Port Meridian")
		local world = Instance.new("Model"); world.Name = "World"
		district.Parent = world; city.Parent = world
		local show = Instance.new("Model"); show.Name = "FlightShowcase"; show.Parent = world
		local C = FP.CONFIG
		Aircraft.build(show, CFrame.new(), { kind = C.kind, scale = C.scale, lod = "full", mesh = false, name = "ShuttleHull", airline = C.airline })
		Aircraft.buildHelicopter(show, CFrame.new(), { name = "HeliHull" })
		local G = CityPlan.GROUND
		local LOW = 150 -- poses below this height above the ground are swept
		for _, dir in { "out", "back" } do
			local leg = FP.leg(dir)
			local tau = 0
			while tau <= leg.duration do
				local p = FP.legPose(leg, tau)
				if p.cf.Position.Y < G + LOW then line("shuttle_" .. dir, tau, p.phase, p.cf) end
				tau += 0.25
			end
		end
		for _, kind in { "arrival", "departure" } do
			-- one ambient event of each kind (all events of a kind fly the same segments)
			for k = 0, 40 do
				local found = false
				for _, e in FP.ambient(k) do
					if e.kind == kind then
						local tau = 0
						while tau <= e.duration do
							local p = FP.ambientPose(e, e.t0 + tau)
							if p and p.cf.Position.Y < G + LOW then line("ambient_" .. kind, tau, p.phase, p.cf) end
							tau += 0.25
						end
						found = true
						break
					end
				end
				if found then break end
			end
		end
		-- the shuttle stand's jet bridge, retracted (ShuttleController moves it locally the same way)
		local bridge = city:FindFirstChild("JetBridge_A" .. CityPlan.AIRPORT.shuttleStand, true)
		local cab = bridge and bridge:FindFirstChild("CabFloor")
		if bridge and cab and typeof(bridge:GetAttribute("TerminalDoor")) == "Vector3" then
			local pivot, axis, away = FP.bridgeAxes(bridge:GetAttribute("TerminalDoor"), cab.CFrame)
			for _, d in bridge:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 0.99 then
					local cf = FP.bridgeFrame(d.CFrame, FP.bridgeInner(d.Name), 1, pivot, axis, away)
					local c = { cf:GetComponents() }
					local parts = { "BRIDGE", string.format("%.3f", d.Position.X), string.format("%.3f", d.Position.Y), string.format("%.3f", d.Position.Z) }
					for _, v in c do table.insert(parts, string.format("%.4f", v)) end
					print(table.concat(parts, " "))
				end
			end
		else
			print("NOBRIDGE")
		end
		-- VIP helicopter: the real pads as built (MetroBuilder), both directions
		local a, b
		for _, d in city:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "Helipad" then
				local top = d.Position + Vector3.new(0, d.Size.Y / 2, 0)
				if d:GetAttribute("Purpose") == "VIPAirport" then a = top elseif d:GetAttribute("Purpose") == "VIP" then b = top end
			end
		end
		if a and b then
			for _, pair in { { "heli_to_hotel", a, b }, { "heli_to_airport", b, a } } do
				local plan = FP.heliPlan(pair[2], pair[3])
				local tau = 0
				while tau <= plan.duration do
					local cf = FP.heliPose(plan, tau)
					line(pair[1], tau, "heli", cf)
					tau += 0.25
				end
			end
		else
			print("NOPADS")
		end
		return world
	end,
}
LUA
python3 harness/make_manifest.py --src "$TMP" --gen "$GEN" >/dev/null || exit 1
tools/luau harness/build_dump.luau -a --tier 1 --gen .gen_flight_clear --module ServerScriptService.Server.Services.FlightClearanceHarness --no-parent \
  | python3 harness/split_dump.py "$OUT/dump.json" "$OUT/log.txt" || { tail -20 "$OUT/log.txt"; rm -rf "$TMP" "$GEN"; exit 1; }
rm -rf "$TMP" "$GEN"
grep -q "^\[print\] POSE" "$OUT/log.txt" || { echo "clearance_dump: no poses in the log"; exit 1; }
