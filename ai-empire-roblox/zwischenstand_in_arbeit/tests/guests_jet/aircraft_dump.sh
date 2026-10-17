#!/usr/bin/env bash
# guests_jet: dump AircraftModel builds (320 / 380 at every LOD, bizjet at every LOD) through the harness mock.
# Usage: tests/guests_jet/aircraft_dump.sh SRC OUTJSON
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
SRC="$1"; OUT="$2"
mkdir -p "$ROOT/out/guests_jet"; TMP="$(mktemp -d "$ROOT/out/guests_jet/tmp_ad_XXXX")"; GEN=harness/.gen_gj_ad_$$
cp -r "$SRC" "$TMP/src"
cat > "$TMP/src/ServerScriptService/Server/Services/AircraftShow.module.luau" <<'LUA'
--!nocheck
local RS = game:GetService("ReplicatedStorage")
local Aircraft = require(RS.Shared.AircraftModel)
return { build = function()
	local w = Instance.new("Model"); w.Name = "World"
	local x = 0
	for _, kind in { "320", "380", "bizjet" } do
		for _, lod in { "full", "medium", "low" } do
			if kind ~= "bizjet" or RS.Shared.AircraftModel then
				local ok, m = pcall(function() return Aircraft.build(w, CFrame.new(x, 0, 0), { kind = kind, lod = lod, scale = if kind == "bizjet" then nil else 1.8, airline = "Nimbus Labs", livery = Color3.fromRGB(0, 170, 200), mesh = false, airstair = true, name = kind .. "_" .. lod }) end)
				if not ok then print("BUILDFAIL " .. kind .. " " .. lod .. " " .. tostring(m)) end
			end
			x += 400
		end
	end
	return w
end }
LUA
python3 harness/make_manifest.py --src "$TMP/src" --gen "$GEN" >/dev/null || exit 1
tools/luau harness/build_dump.luau -a --tier 1 --gen "$(basename $GEN)" --module ServerScriptService.Server.Services.AircraftShow --no-parent --quiet \
  | python3 harness/split_dump.py "$OUT" "$OUT.log" || { tail -20 "$OUT.log"; rm -rf "$TMP" "$GEN"; exit 1; }
rm -rf "$TMP" "$GEN"
