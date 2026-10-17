#!/usr/bin/env bash
# guests_jet: world dump for the jet clearance sweep and the terminal passenger paths (tests/guests_jet/clearance.py,
# tests/guests_jet/paths.py). Builds the real world through the harness mock (CampusService district + CityBuilder:
# Business City, City Airport, Port Meridian), the company jet hull (AircraftModel "bizjet", JetPlan scale, full
# LOD, airstair stowed / deployed) at the origin (model "JetShowcase"), and prints into the log:
#   POSE <flight> <tau> <phase> x y z r00..r22   every low pose (< 150 studs above the ground, 0.25 s) of the jet
#                                               flights out / back / ferry to both Port Meridian slots
#   WALK <name> <radius> <trimStart> <trimEnd> n x1 y1 z1 ... xn yn zn  pilots' / companions' walks (JetPlan) and
#                                               every terminal passenger path (GuestPlan, City Airport + Port Meridian),
#                                               rig-foot height; trims = studs into / out of a seat not checked
#   PARK <name> x y z r00..r22                  the parked jet frames (hangar, stand, PM slots)
# Usage: tests/guests_jet/world_dump.sh [--src DIR] [--out DIR]   (default work/src, out/guests_jet/world)
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
SRC=work/src; OUT=out/guests_jet/world
while [ $# -gt 0 ]; do case "$1" in --src) SRC="$2"; shift;; --out) OUT="$2"; shift;; esac; shift; done
mkdir -p "$OUT"
TMP="$OUT/src_tmp"; GEN=harness/.gen_gj_world_$$
rm -rf "$TMP" && cp -r "$SRC" "$TMP"
cat > "$TMP/ServerScriptService/Server/Services/GuestsJetWorldHarness.module.luau" <<'LUA'
--!nocheck
local RS = game:GetService("ReplicatedStorage")
local Aircraft = require(RS.Shared.AircraftModel)
local JP = require(RS.Shared.JetPlan)
local CityPlan = require(RS.Shared.Config.CityPlan)
local gpm = RS.Shared:FindFirstChild("GuestPlan")
local okGP, GP = false, nil
if gpm then okGP, GP = pcall(require, gpm) end
local function cfLine(tag, a, b, cf)
	local parts = { tag, a }
	if b then table.insert(parts, b) end
	for _, v in { cf:GetComponents() } do table.insert(parts, string.format("%.4f", v)) end
	print(table.concat(parts, " "))
end
local function walk(name, radius, pts, t0, t1)
	local parts = { "WALK", name, string.format("%.2f", radius), string.format("%.2f", t0 or 0), string.format("%.2f", t1 or 0), tostring(#pts) }
	for _, p in pts do table.insert(parts, string.format("%.3f %.3f %.3f", p.X, p.Y, p.Z)) end
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
		local show = Instance.new("Model"); show.Name = "JetShowcase"; show.Parent = world
		Aircraft.build(show, CFrame.new(), { kind = JP.KIND, scale = JP.SCALE, lod = "full", name = "JetHull", airline = "Nimbus Labs", airstair = false })
		Aircraft.build(show, CFrame.new(0, 0, 400), { kind = JP.KIND, scale = JP.SCALE, lod = "full", name = "JetHullStair", airline = "Nimbus Labs", airstair = true })
		local G = CityPlan.GROUND
		local LOW = 150
		for _, kind in { "out", "back", "ferry" } do
			for slot = 1, 2 do
				local tl = JP.timeline(kind, slot, 0)
				local tau = 0
				local name = "jet_" .. kind .. slot
				while tau <= tl.duration do
					local p = JP.pose(tl, tau)
					if p.cf.Position.Y < G + LOW then cfLine("POSE", name, string.format("%.2f %s", tau, p.phase), p.cf) end
					tau += 0.25
				end
				local p = JP.pose(tl, tl.duration + 1)
				cfLine("POSE", name, string.format("%.2f %s", tl.duration + 1, "parked"), p.cf)
			end
		end
		cfLine("PARK", "home", nil, JP.HOME_PARK); cfLine("PARK", "stand", nil, JP.HOME_STAND)
		for _, s in JP.PM_SLOTS do cfLine("PARK", "pm" .. s.id, nil, s.cf) end
		-- walks (JetPlan points are rig-root height = feet + 3)
		local function feet(path) local out = {}; for _, p in path do table.insert(out, p - Vector3.new(0, 3, 0)) end; return out end
		-- the captain gets up from the sofa (the first 3.2 studs leave the seat), the first officer stands
		for i = 1, 2 do walk("pilot" .. i, 0.9, feet(JP.crewPath(JP.HOME_PARK, i)), if JP.CREW.sit[i] then 3.2 else 0, 0) end
		for k = 1, 3 do
			walk("companion_home" .. k, 0.9, feet(JP.companionPath(JP.HOME_PARK, k, true)))
			for slot = 1, 2 do walk("companion_pm" .. slot .. "_" .. k, 0.9, feet(JP.companionPath(JP.slot(slot).cf, k, false, slot))) end
			local seat = JP.POINTS.cabinSeats[JP.COMPANION_SEATS[k]]
			walk("companion_stand" .. k, 0.9, feet(JP.boardPath(JP.HOME_STAND, seat, JP.COMPANION_FROM, nil)))
		end
		if okGP and GP.walksForTests then
			for _, w in GP.walksForTests() do walk(w.name, w.radius, w.path, w.trimStart, w.trimEnd) end
		else
			print("NOGUESTPLAN " .. tostring(GP))
		end
		return world
	end,
}
LUA
python3 harness/make_manifest.py --src "$TMP" --gen "$GEN" >/dev/null || exit 1
tools/luau harness/build_dump.luau -a --tier 1 --gen "$(basename $GEN)" --module ServerScriptService.Server.Services.GuestsJetWorldHarness --no-parent \
  | python3 harness/split_dump.py "$OUT/dump.json" "$OUT/log.txt" || { tail -20 "$OUT/log.txt"; rm -rf "$TMP" "$GEN"; exit 1; }
rm -rf "$TMP" "$GEN"
grep -q "^\[print\] POSE" "$OUT/log.txt" || { echo "world_dump: no poses in the log"; exit 1; }
