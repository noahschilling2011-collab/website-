#!/usr/bin/env python3
"""T7 / T8 geometric checks of the menu package on the guiprev dumps written by tests/menu/render.sh (--save-dump).

For every dump (one per screen state and viewport) the real UI tree is laid out again with guiprev's engine and:
  T7  text >= 12 pt and touch targets >= 44 pt on the phone (844x390: 1 px = 1 pt), >= 12 px / 44 px at 1280x720,
      for the menu package's own UI (HUD, guide layer, Menu shell, Home, Intro, toasts); the Model Studio (lab package,
      measured 11.96 pt by tests/lab) and the legacy pages (UIRoot x 0.80 until P3, ONBOARDING_SPEC B3) are reported
      separately, not failed;
  T7  nothing (text or button) above the 58 pt Roblox top-bar inset;
  T7  the HUD column ends <= 271 pt on the phone (8 pt above the jump button, A2.1);
  T8  the gold ring encloses its target with its 6 px padding (never covers the target's inside);
  T8  the chip never overlaps a button and sits left of the HUD column;
  T9  Home cards: the line under the title ends above the card's button; the guide card's Skip sits on its caption.
Usage: python3 tests/menu/sizes.py out/menu/*.dump   (prints "menu_sizes: N passed, M failed", exit 1 on failures)
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools", "guiprev"))
import guiprev  # noqa: E402

PHONE = ((844, 390), (58, 47, 21, 47))
DESK = ((1280, 720), (58, 0, 0, 0))
TEXT_MIN, TAP_MIN, COLUMN_MAX, TOL = 12.0, 44.0, 271.0, 0.06
LEGACY_PAGES = {"Page_home_money", "Page_home_goals", "data", "compute", "Page_lab_research", "arena", "market",
                "Page_market_lines", "studio", "Page_market_leaderboard", "Page_clients_clients", "Page_clients_receipts",
                "Page_team_staff", "Page_team_office", "Page_team_fleet", "campus", "Page_team_settings", "shop"}
BLOCKERS = {"LockedShade"}  # full-screen tap catchers (no target size)

passed = failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
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


def bucket(n):
    path = n.path
    if "/ModelStudio/" in path or path.endswith("/ModelStudio"):
        return "studio"
    parts = path.split("/")
    if "Content" in parts:
        i = parts.index("Content")
        if i + 1 < len(parts) and parts[i + 1] in LEGACY_PAGES:
            return "legacy"
        if i + 1 < len(parts) and parts[i + 1] == "lab":
            return "labhome"
    return "core"


def is_button(n):
    return n.cls in ("TextButton", "ImageButton")


def rect(n):
    return n.abs


def overlap(a, b):
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    w = min(ax + aw, bx + bw) - max(ax, bx)
    h = min(ay + ah, by + bh) - max(ay, by)
    return max(0.0, w) * max(0.0, h)


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
    mins = {}
    taps = {}
    worst_text = {}
    worst_tap = {}
    above = []
    for n in vis:
        b = bucket(n)
        if n.is_text and str(n.p.get("Text", "")).strip() and float(n.p.get("TextTransparency", 0) or 0) < 0.95:
            size = (n.text_size or float(n.p.get("TextSize", 14) or 14)) * n.k
            if size < mins.get(b, 1e9):
                mins[b], worst_text[b] = size, f"{n.path} {str(n.p.get('Text'))[:30]!r} {size:.2f}"
            if n.abs[1] < insets[0] - 0.5 and "AIEmpire_Dim" not in n.path:
                above.append(f"{n.path} y={n.abs[1]:.1f}")
        if is_button(n) and n.name not in BLOCKERS and n.p.get("Active", True) is not False:
            w, h = n.abs[2], n.abs[3]
            if w >= vw - 1 and h >= vh - 1:
                continue  # a full-screen blocker
            s = min(w, h)
            if s < taps.get(b, 1e9):
                taps[b], worst_tap[b] = s, f"{n.path} {w:.1f}x{h:.1f}"
            if n.abs[1] < insets[0] - 0.5 and "AIEmpire_Dim" not in n.path:
                above.append(f"{n.path} y={n.abs[1]:.1f}")
    unit = "pt" if phone else "px"
    core_text = mins.get("core", 99)
    core_tap = taps.get("core", 99)
    check(f"{name}: menu UI text >= {TEXT_MIN:.0f} {unit} (smallest {core_text:.2f})", core_text >= TEXT_MIN - TOL, worst_text.get("core"))
    check(f"{name}: menu UI targets >= {TAP_MIN:.0f} {unit} (smallest {core_tap:.1f})", core_tap >= TAP_MIN - TOL, worst_tap.get("core"))
    if "labhome" in mins:
        check(f"{name}: Lab home text >= {TEXT_MIN:.0f} {unit} (compact tokens, smallest {mins['labhome']:.2f})", mins["labhome"] >= TEXT_MIN - TOL, worst_text.get("labhome"))
    check(f"{name}: nothing above the {insets[0]} {unit} top inset", not above, "; ".join(above[:4]))
    notes = []
    for b in ("studio", "legacy"):
        if b in mins:
            notes.append(f"{b} text {mins[b]:.2f}")
        if b in taps:
            notes.append(f"{b} tap {taps[b]:.1f}")
    col = next((n for n in vis if n.path.endswith("AIEmpire_HUD/Root/HUD/Column")), None)
    if phone and col is not None:
        bottom = col.abs[1] + col.abs[3]
        check(f"{name}: HUD column bottom {bottom:.1f} <= {COLUMN_MAX:.0f} pt (jump button at 279)", bottom <= COLUMN_MAX + TOL)
        notes.append(f"column bottom {bottom:.1f}")
    # T8: ring around its target, chip never over a button
    ring = next((n for n in vis if n.name == "GuideRing"), None)
    buttons = [n for n in vis if is_button(n) and "AIEmpire_Guide" not in n.path and n.name not in BLOCKERS]
    if ring is not None:
        rx, ry, rw, rh = ring.abs
        target = None
        for btn in buttons:
            bx, by, bw, bh = btn.abs
            if abs(bx - rx - 6) < 1.6 and abs(by - ry - 6) < 1.6 and abs(bw + 12 - rw) < 1.6 and abs(bh + 12 - rh) < 1.6:
                target = btn
        check(f"{name}: T8 the ring encloses a button with its 6 px padding (target inside never covered)", target is not None, f"ring {tuple(round(v) for v in ring.abs)}")
        if target is not None:
            notes.append(f"ring on {target.name}")
    chip = next((n for n in vis if n.name == "GuideChip"), None)
    if chip is not None:
        hits = [b.path for b in buttons if overlap(chip.abs, b.abs) > 1.0]
        check(f"{name}: T8 the chip overlaps no button", not hits, "; ".join(hits[:3]))
        if col is not None:
            check(f"{name}: T8 the chip sits left of the HUD column", chip.abs[0] + chip.abs[2] <= col.abs[0] + 0.5)
    # Home cards: the line under the title ends above the card's button (never under it or under the guide ring)
    for line in (n for n in vis if n.name == "Line" and "/Cards/Card" in n.path and str(n.p.get("Text", "")).strip()):
        card = line.parent
        btn = next((c for c in vis if c.parent is card and c.name == "Action"), None)
        if btn is not None:
            gap = btn.abs[1] - (line.abs[1] + line.abs[3])
            check(f"{name}: {card.name} line ends {gap:.1f} {unit} above its button (>= 2)", gap >= 2 - TOL)
    # the guide card's Skip text sits on the caption line, never on the step bar
    skip = next((n for n in vis if n.name == "GuideSkip"), None)
    cap = next((n for n in vis if n.name == "GuideCaption"), None)
    if skip is not None and cap is not None:
        dy = (skip.abs[1] + skip.abs[3] / 2) - (cap.abs[1] + cap.abs[3] / 2)
        check(f"{name}: Skip centred on the FIRST STEPS caption (dy {dy:.1f})", abs(dy) <= 2)
    print(f"ok    {name}: text {core_text:.2f} {unit}, tap {core_tap:.1f} {unit}" + (" | " + ", ".join(notes) if notes else ""))


def main():
    files = sys.argv[1:]
    if not files:
        print("usage: sizes.py DUMP...")
        sys.exit(2)
    for f in files:
        run(f)
    print(f"menu_sizes: {passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
