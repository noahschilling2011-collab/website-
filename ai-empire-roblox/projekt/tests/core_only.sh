#!/usr/bin/env bash
# CoreDesign alone: assertions for tiers 1-4 (tests/core_only.luau) + section renders (out/core/*.png),
# then the same build through the official harness (build_dump/check_geometry/render.py) via a
# throw-away wrapper module in an overlay copy of work/src (out/core/src, never packed).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p out/core
python3 harness/make_manifest.py --src work/src --gen harness/.gen_core 2>/dev/null || exit 1
tools/luau tests/core_only.luau -a --dump > out/core/core_only.log 2>&1
status=$?
grep -v "@@P" out/core/core_only.log
python3 tests/core_render.py out/core < out/core/core_only.log | grep -c wrote | sed 's/^/section renders: /'

# official harness on the core alone
rm -rf out/core/src && cp -r work/src out/core/src
cat > out/core/src/ServerScriptService/Server/Services/CoreOnlyHarness.module.luau <<'LUA'
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Plan = require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Core = require(script.Parent.CoreDesign)
return {
	build = function(cf: CFrame, session: any, accent: Color3): Model
		local tier = session.data.empire.office
		local office = Instance.new("Model")
		office.Name = "Office"
		local folders = {}
		for _, n in { "Structure", "Facade", "Site", "Core", "Lift", "Walls", "Doors", "Rooms", "Circulation", "Cameras", "Navigation" } do
			local f = Instance.new("Folder")
			f.Name = n
			f.Parent = office
			folders[n] = f
		end
		Core.build({ office = office, cf = cf, tier = tier, floors = Plan.floors(tier), owner = session.userId, accent = accent, company = "Nimbus Labs", folders = folders })
		-- test-only stand-ins for the exterior generator's slabs: lift lobby + stair front landing
		for level = -1, Plan.roofLevel(tier) do
			local y = Plan.levelY(level)
			for _, r in { { -22, 22, 36, 53.75 }, { -21.5, -7.5, 53.75, 60 } } do
				local p = Instance.new("Part")
				p.Name = "TestSlab"
				p.Anchored = true
				p.Size = Vector3.new(r[2] - r[1], 1, r[4] - r[3])
				p.CFrame = cf * CFrame.new((r[1] + r[2]) / 2, y - 0.5, (r[3] + r[4]) / 2)
				p.Parent = folders.Structure
			end
		end
		return office
	end,
}
LUA
python3 harness/make_manifest.py --src out/core/src --gen harness/.gen_core 2>/dev/null || exit 1
for t in ${TIERS:-4}; do
  tools/luau harness/build_dump.luau -a --tier $t --gen .gen_core --module ServerScriptService.Server.Services.CoreOnlyHarness --quiet \
    | python3 harness/split_dump.py out/core/dump_core_tier$t.json out/core/log_core_tier$t.txt || status=1
  tools/luau harness/build_dump.luau -a --tier $t --gen .gen_core --module ServerScriptService.Server.Services.CoreOnlyHarness --quiet --cf "-37.5,11,90,37" \
    | python3 harness/split_dump.py out/core/dump_core_tier${t}_rot.json out/core/log_core_tier${t}_rot.txt || status=1
  python3 harness/compare_dumps.py out/core/dump_core_tier$t.json out/core/dump_core_tier${t}_rot.json || status=1
  # stairs only (no lift links): every level's lobby nodes must be reachable from the B1 lobby
  python3 harness/check_geometry.py out/core/dump_core_tier$t.json --start=0,-16,45 --lift none --img-prefix out/core/walk_core_t$t > out/core/check_core_tier$t.txt 2>&1
  grep -A12 "^== SUMMARY" out/core/check_core_tier$t.txt
  python3 harness/render.py out/core/dump_core_tier$t.json --prefix out/core/h_tier$t --only elev,iso,section --cut-z 60.8 --cut-z 67.5 >/dev/null 2>&1 || echo "render.py failed"
done
rm -rf out/core/src harness/.gen_core
exit $status
