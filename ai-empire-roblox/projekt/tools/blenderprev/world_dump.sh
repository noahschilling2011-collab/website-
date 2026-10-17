#!/usr/bin/env bash
# Fresh district + shared-world dump for the Blender previews (adapted copy of agents/world/world_dump.sh:
# own output folder and own generated manifest, no checks/maps, never touches the world package's files).
# Usage: tools/blenderprev/world_dump.sh [--src DIR] [--out DIR]   (default out/blenderprev/world)
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
SRC=work/src; OUT=out/blenderprev/world
while [ $# -gt 0 ]; do case "$1" in --src) SRC="$2"; shift;; --out) OUT="$2"; shift;; esac; shift; done
mkdir -p "$OUT"
TMP="$OUT/world_src"; GENNAME=.gen_blenderprev_world; GEN=harness/$GENNAME
rm -rf "$TMP" && cp -r "$SRC" "$TMP"
cat > "$TMP/ServerScriptService/Server/Services/WorldHarness.module.luau" <<'LUA'
--!strict
local Campus = require(script.Parent.CampusService)
local Builder = require(script.Parent.CityBuilder)
return {
	build = function(_cf: CFrame, _session: any, _accent: Color3): Model
		Campus.init()
		local district = workspace:FindFirstChild("TechDistrict") :: Model
		local city = Builder.build("Port Meridian · $1.5k return")
		local world = Instance.new("Model")
		world.Name = "World"
		district.Parent = world
		city.Parent = world
		return world
	end,
}
LUA
python3 harness/make_manifest.py --src "$TMP" --gen "$GEN" >/dev/null || exit 1
tools/luau harness/build_dump.luau -a --tier 1 --gen $GENNAME --module ServerScriptService.Server.Services.WorldHarness --no-parent --quiet \
  | python3 harness/split_dump.py "$OUT/world_dump.json" "$OUT/world_log.txt" || { tail -20 "$OUT/world_log.txt"; rm -rf "$TMP" "$GEN"; exit 1; }
rm -rf "$TMP" "$GEN"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print('world dump:', d['meta']['counts'])" "$OUT/world_dump.json"
