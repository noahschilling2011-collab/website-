#!/usr/bin/env bash
# Builds every tier with the shop decor (team party kit + Founder Suite) in a private tree, dumps it,
# runs the geometry check and renders plan/iso views. Output: out/shop/decor_*.
# usage: tests/shop/decor.sh [tiers...]   (default 1 2 3 4)
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
TREE=agents/shop/decor_src; OUT=out/shop; mkdir -p "$OUT"
rm -rf "$TREE"; cp -r work/src "$TREE"
cp tests/shop/ShopDecorBuild.module.luau "$TREE/ServerScriptService/Server/Services/ShopDecorBuild.module.luau"
python3 harness/make_manifest.py --src "$TREE" --gen harness/.gen_shopdecor >/dev/null 2>&1
TIERS="${*:-1 2 3 4}"
for t in $TIERS; do
  tools/luau harness/build_dump.luau -a --tier "$t" --gen .gen_shopdecor --module ServerScriptService.Server.Services.ShopDecorBuild --quiet 2>&1 \
    | python3 harness/split_dump.py "$OUT/decor_dump_tier$t.json" "$OUT/decor_log_tier$t.txt" || { echo "tier $t build FAILED"; tail -n 20 "$OUT/decor_log_tier$t.txt"; exit 1; }
  echo "tier $t dumped"
done
rm -rf "$TREE"
