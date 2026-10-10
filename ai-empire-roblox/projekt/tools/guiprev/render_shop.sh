#!/usr/bin/env bash
# Renders every Robux-shop preview into out/guiprev/ (approximate previews from the real UI tree, ~3 s each).
# usage: tools/guiprev/render_shop.sh
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
G="python3 tools/guiprev/guiprev.py --scene tools/guiprev/scenes/client.luau"
O=out/guiprev; mkdir -p "$O"
$G --state soon    --viewport desktop --out $O/shop_a_soon_1280x720.png
$G --state catalog --viewport desktop --out $O/shop_b_catalog_1280x720.png --strip ShopScroll
$G --state wired   --viewport desktop --out $O/shop_b2_wired_1280x720.png --strip ShopScroll
$G --state owned   --viewport desktop --out $O/shop_c_owned_1280x720.png --strip ShopScroll
$G --state catalog --viewport phone --dpr 2 --out $O/shop_d_catalog_phone_844x390.png --strip ShopScroll
$G --state owned   --viewport phone --dpr 2 --out $O/shop_d2_owned_phone_844x390.png
$G --state toast   --viewport desktop --out $O/shop_e_grant_toast_1280x720.png
$G --state decor   --ppstud 60 --out $O/shop_f_world_guis.png
