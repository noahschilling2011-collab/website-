#!/usr/bin/env python3
"""T18 geometric checks of the shop package on the guiprev dumps written by tests/shop2/render.sh (--save-dump).

Every dump is laid out again with guiprev's engine. For the shop package's own UI (Shop pages Page_shop_*, the UseSheet
AIEmpire_ShopSheet, the Lab -> Research cards, the Lab level card buttons, the Model Studio lock strip, the Last Epoch
button, Settings "Change colour & logo"):
  * text >= 12 pt and touch targets >= 44 pt on the phone (844x390: 1 px = 1 pt), >= 12 px / 44 px at 1280x720;
  * nothing (text or button) of the whole screen above the 58 pt Roblox top-bar inset;
  * UseSheet rows never truncate or overflow their effect text;
  * with the Studio step-2 lock strip shown, the locked 7B tile's last line ("research") ends >= 4 px above the tile
    border;
  * the Robux context button's text fits inside the button (FINISH NOW · EUREKA | price), and every other shop
    TextButton's label fits inside its button.
Usage: python3 tests/shop2/sizes.py out/shop/*.dump   (prints "shop2_sizes: N passed, M failed", exit 1 on failures)
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools", "guiprev"))
import guiprev  # noqa: E402

PHONE = ((844, 390), (58, 47, 21, 47))
DESK = ((1280, 720), (58, 0, 0, 0))
TEXT_MIN, TAP_MIN, TOL = 12.0, 44.0, 0.06
SHOP_MARKS = ("/Page_shop_", "AIEmpire_ShopSheet", "/Part_research/", "/LabButtons", "/LabEurekaNote", "/LockStrip",
              "/LastEpoch", "/Rebrand")

passed = failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        if os.environ.get("VERBOSE"):
            print(f"pass  {name}")
    else:
        failed += 1
        print(f"FAIL  {name}" + (f"  -- {detail}" if detail else ""))


def chain_visible(n):
    while n is not None:
        if not n.visible:
            return False
        if n.cls == "ScreenGui" and n.p.get("Enabled") is False:
            return False
        n = n.parent
    return True


def inside_clip(n):
    if n.clip is None:
        return True
    x, y, w, h = n.abs
    cx, cy, cw, ch = n.clip
    return x + w > cx + 0.5 and y + h > cy + 0.5 and x < cx + cw - 0.5 and y < cy + ch - 0.5


def fully_inside_clip(n):
    if n.clip is None:
        return True
    x, y, w, h = n.abs
    cx, cy, cw, ch = n.clip
    return x >= cx - 0.5 and y >= cy - 0.5 and x + w <= cx + cw + 0.5 and y + h <= cy + ch + 0.5


def is_shop(n):
    return any(m in n.path for m in SHOP_MARKS)


def text_rect(n):
    blk = n.text_block
    if not blk:
        return None
    x, y, w, h = n.abs
    k = n.k
    pt_, pr, pb, pl = n.padding(*n.size_u)
    tw, th = blk.width * k, blk.height * k
    bx, by, bw, bh = x + pl * k, y + pt_ * k, (n.size_u[0] - pl - pr) * k, (n.size_u[1] - pt_ - pb) * k
    xa, ya = n.p.get("TextXAlignment", "Center"), n.p.get("TextYAlignment", "Center")
    tx = {"Left": bx, "Center": bx + (bw - tw) / 2, "Right": bx + bw - tw}.get(xa, bx)
    ty = {"Top": by, "Center": by + (bh - th) / 2, "Bottom": by + bh - th}.get(ya, by)
    return (tx, ty, tw, th)


def run(path):
    name = os.path.basename(path).replace(".dump", "")
    phone = name.startswith("phone")
    (vw, vh), insets = PHONE if phone else DESK
    with open(path) as f:
        lines = f.read().splitlines()
    roots, nodes, meta, errors, logs = guiprev.load_nodes(lines)
    engine = guiprev.Engine((vw, vh), insets)
    for r in roots:
        if r.cls == "ScreenGui":
            engine.run_root(r)
    vis = [n for n in nodes if not n.is_root and n.abs[2] > 0 and n.abs[3] > 0 and chain_visible(n) and inside_clip(n)]
    unit = "pt" if phone else "px"
    min_text, worst_text, min_tap, worst_tap, above = 99.0, "", 99.0, "", []
    shop_nodes = 0
    for n in vis:
        has_text = n.is_text and str(n.p.get("Text", "")).strip() and float(n.p.get("TextTransparency", 0) or 0) < 0.95
        button = n.cls in ("TextButton", "ImageButton") and n.p.get("Active", True) is not False
        if (has_text or button) and n.abs[1] < insets[0] - 0.5 and "AIEmpire_Dim" not in n.path:
            above.append(f"{n.path} y={n.abs[1]:.1f}")
        if not is_shop(n):
            continue
        shop_nodes += 1
        if has_text:
            size = (n.text_size or float(n.p.get("TextSize", 14) or 14)) * n.k
            if size < min_text:
                min_text, worst_text = size, f"{n.path} {str(n.p.get('Text'))[:30]!r} {size:.2f}"
        if button and fully_inside_clip(n):
            w, h = n.abs[2], n.abs[3]
            if w >= vw - 1 and h >= vh - 1:
                continue  # full-screen blocker
            s = min(w, h)
            if s < min_tap:
                min_tap, worst_tap = s, f"{n.path} {w:.1f}x{h:.1f}"
    if shop_nodes:
        check(f"{name}: shop UI text >= {TEXT_MIN:.0f} {unit} (smallest {min_text:.2f})", min_text >= TEXT_MIN - TOL, worst_text)
        if min_tap < 99:
            check(f"{name}: shop UI targets >= {TAP_MIN:.0f} {unit} (smallest {min_tap:.1f})", min_tap >= TAP_MIN - TOL, worst_tap)
    check(f"{name}: nothing above the {insets[0]} {unit} top inset", not above, "; ".join(above[:3]))
    # UseSheet rows: the effect text never truncates or overflows its label
    for n in vis:
        if "AIEmpire_ShopSheet" in n.path and n.name == "Value" and n.text_block:
            r = text_rect(n)
            x, y, w, h = n.abs
            ok = n.p.get("TextTruncate", "None") == "None" and r[3] <= h + 1 and r[2] <= w + 1
            check(f"{name}: sheet row {n.parent.name} text fits ({r[2]:.0f}x{r[3]:.0f} in {w:.0f}x{h:.0f})", ok, str(n.p.get("Text"))[:60])
    # the Robux context buttons: label + divider + price inside the button
    for n in vis:
        if n.name in ("OfferRight",) and n.text_block and str(n.p.get("Text", "")).strip():
            btn = n.parent.parent
            r = text_rect(n)
            lab = next((c for c in vis if c.parent is n.parent and c.name == "OfferLabel"), None)
            lr = text_rect(lab) if lab is not None else None
            bx, by, bw, bh = btn.abs
            left = lr[0] if lr else r[0]
            ok = left >= bx + 2 and r[0] + r[2] <= bx + bw - 2
            check(f"{name}: {btn.name} text inside the button (margins {left - bx:.1f} / {bx + bw - r[0] - r[2]:.1f})", ok, btn.path)
    # every shop button's own label stays inside the button (CHANGE LOOK › once spilled out of a 170 px primary)
    for n in vis:
        if is_shop(n) and n.cls == "TextButton" and n.text_block and str(n.p.get("Text", "")).strip() and fully_inside_clip(n):
            r = text_rect(n)
            x, y, w, h = n.abs
            if r[0] < x - 1 or r[0] + r[2] > x + w + 1:
                check(f"{name}: button {n.path.split('/')[-2]}/{n.name} label {str(n.p.get('Text'))!r} fits ({r[2]:.0f} in {w:.0f})", False, n.path)
            else:
                check(f"{name}: button label fits", True)
    # Studio step 2: the locked 7B tile's last line >= 4 px above its border while the lock strip shows
    strip = next((n for n in vis if n.name == "LockStrip"), None)
    tile = next((n for n in vis if n.name == "Size_s7b"), None)
    if strip is not None and tile is not None:
        texts = [c for c in vis if c.is_text and str(c.p.get("Text", "")).strip() and tile.path + "/" in c.path + "/" and c is not tile]
        bottoms = [(text_rect(c)[1] + text_rect(c)[3], c) for c in texts if c.text_block]
        if bottoms:
            b, last = max(bottoms, key=lambda t: t[0])
            gap = tile.abs[1] + tile.abs[3] - b
            check(f"{name}: 7B tile last line {str(last.p.get('Text'))!r} ends {gap:.1f} {unit} above the border (>= 4)", gap >= 4 - TOL)
    print(f"ok    {name}: shop text {min_text:.2f} {unit}, tap {min_tap:.1f} {unit}")


def main():
    files = sys.argv[1:]
    if not files:
        print("usage: sizes.py DUMP...")
        sys.exit(2)
    for f in files:
        run(f)
    print(f"shop2_sizes: {passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
