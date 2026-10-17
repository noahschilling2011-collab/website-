#!/usr/bin/env python3
"""guiprev: approximate headless preview of Roblox GUIs built by real game code inside harness/mock.luau.

Pipeline: (1) a scene script (tools/guiprev/scenes/*.luau) builds the real UI in the mock and prints the GUI tree
with guidump.luau; (2) this script lays the tree out for a viewport (UDim2, AnchorPoint, UIPadding, UIListLayout,
UIGridLayout, AutomaticSize from text metrics, UIScale, UISize/AspectRatio constraints, ScrollingFrame canvas +
clipping, ZIndex) and (3) draws it with PIL. Computed AbsoluteSize/AbsolutePosition are fed back into the mock and
the scene is re-run (--passes), so code that reacts to AbsoluteSize (UIRoot scale, sidebar fit, badge placement)
runs like in the engine.

  python3 tools/guiprev/guiprev.py --scene tools/guiprev/scenes/shop.luau --state catalog \
      --viewport 1280x720 --out out/guiprev/shop_catalog.png [--strip ShopScroll] [--debug]

Not a Studio screenshot: fonts are Liberation Sans (Builder Sans is not available), images are placeholder boxes,
rotation/flex/tween states/3D world are not rendered. See README.md.
"""
import argparse
import json
import math
import os
import re
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))  # scratchpad
LUAU = os.path.join(ROOT, "tools", "luau")
MAKE_MANIFEST = os.path.join(ROOT, "harness", "make_manifest.py")
CACHE = os.path.join(HERE, ".cache")

LABEL = "approximate preview rendered from the real UI tree \u2014 not a Studio screenshot"
PRESETS = {
    "desktop": ((1280, 720), (58, 0, 0, 0)),
    "phone": ((844, 390), (58, 47, 21, 47)),  # iPhone 12-14 landscape: notch 47 left/right, home bar 21
}

# ------------------------------------------------------------------------------------------------ fonts
FONT_DIRS = ["/usr/share/fonts/truetype/liberation", "/usr/share/fonts/truetype/dejavu"]
FONT_FILES = {
    ("sans", False, False): "LiberationSans-Regular.ttf",
    ("sans", True, False): "LiberationSans-Bold.ttf",
    ("sans", False, True): "LiberationSans-Italic.ttf",
    ("sans", True, True): "LiberationSans-BoldItalic.ttf",
    ("mono", False, False): "LiberationMono-Regular.ttf",
    ("mono", True, False): "LiberationMono-Bold.ttf",
    ("mono", False, True): "LiberationMono-Italic.ttf",
    ("mono", True, True): "LiberationMono-BoldItalic.ttf",
}
FALLBACK = {False: "DejaVuSans.ttf", True: "DejaVuSans-Bold.ttf"}


def font_path(name):
    for d in FONT_DIRS:
        p = os.path.join(d, name)
        if os.path.exists(p):
            return p
    raise FileNotFoundError(name)


_cmaps = {}


def covers(path, ch):
    cm = _cmaps.get(path)
    if cm is None:
        try:
            from fontTools.ttLib import TTFont
            cm = set(TTFont(path, lazy=True).getBestCmap().keys())
        except Exception:
            cm = None
        _cmaps[path] = cm if cm is not None else False
        cm = _cmaps[path]
    if cm is False:
        return True
    return ord(ch) in cm


_fonts = {}


def get_font(path, size):
    size = max(1.0, round(size * 4) / 4)
    key = (path, size)
    f = _fonts.get(key)
    if f is None:
        f = ImageFont.truetype(path, size)
        _fonts[key] = f
    return f


class Style:
    __slots__ = ("bold", "italic", "mono", "heavy", "color", "size", "underline", "strike")

    def __init__(self, bold=False, italic=False, mono=False, heavy=False, color=None, size=None):
        self.bold, self.italic, self.mono, self.heavy = bold, italic, mono, heavy
        self.color, self.size = color, size
        self.underline = self.strike = False

    def copy(self):
        s = Style(self.bold, self.italic, self.mono, self.heavy, self.color, self.size)
        s.underline, s.strike = self.underline, self.strike
        return s

    def files(self):
        main = font_path(FONT_FILES[("mono" if self.mono else "sans", self.bold, self.italic)])
        return main, font_path(FALLBACK[self.bold])


WEIGHTS = {"Thin": 100, "ExtraLight": 200, "Light": 300, "Regular": 400, "Medium": 500, "SemiBold": 600,
           "Bold": 700, "ExtraBold": 800, "Heavy": 900}


def base_style(props):
    name = str(props.get("Font") or "SourceSans")
    ff = props.get("FontFace")
    n = name.lower()
    weight = 400
    if any(w in n for w in ("extrabold", "black", "heavy")):
        weight = 800
    elif "semibold" in n:
        weight = 600
    elif "bold" in n:
        weight = 700
    elif "medium" in n:
        weight = 500
    elif "light" in n:
        weight = 300
    family = n
    italic = "italic" in n
    if isinstance(ff, dict):  # an explicitly assigned FontFace wins
        weight = WEIGHTS.get(ff.get("weight"), weight)
        family = str(ff.get("family", "")).lower()
        italic = ff.get("style") == "Italic"
    mono = any(m in family for m in ("mono", "code", "inconsolata", "ubuntu mono"))
    return Style(bold=weight >= 600, italic=italic, mono=mono, heavy=weight >= 800)


# ------------------------------------------------------------------------------------------- rich text
ENTITIES = {"&lt;": "<", "&gt;": ">", "&quot;": '"', "&apos;": "'", "&amp;": "&"}


def unescape(s):
    for k, v in ENTITIES.items():
        s = s.replace(k, v)
    return s


def parse_color(v):
    v = v.strip()
    m = re.match(r"#?([0-9a-fA-F]{6})$", v)
    if m:
        h = m.group(1)
        return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))
    m = re.match(r"rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)", v)
    if m:
        return tuple(int(x) for x in m.groups())
    return None


def rich_runs(text, style, rich):
    """-> list of (text, Style); '\n' inside text marks hard breaks."""
    if not rich:
        return [(text, style)]
    runs, stack, cur = [], [style], style
    pos = 0
    for m in re.finditer(r"<(/?)([a-zA-Z]+)([^>]*)>", text):
        if m.start() > pos:
            runs.append((unescape(text[pos:m.start()]), cur))
        pos = m.end()
        closing, tag, attrs = m.group(1) == "/", m.group(2).lower(), m.group(3)
        if tag == "br":
            runs.append(("\n", cur))
            continue
        if closing:
            if len(stack) > 1:
                stack.pop()
            cur = stack[-1]
            continue
        s = cur.copy()
        if tag == "b":
            s.bold = True
        elif tag == "i":
            s.italic = True
        elif tag == "u":
            s.underline = True
        elif tag == "s":
            s.strike = True
        elif tag == "font":
            for k, v in re.findall(r'(\w+)\s*=\s*["\']([^"\']*)["\']', attrs):
                k = k.lower()
                if k == "color":
                    s.color = parse_color(v) or s.color
                elif k == "size":
                    try:
                        s.size = float(v)
                    except ValueError:
                        pass
                elif k == "weight":
                    s.bold = v.lower() in ("bold", "semibold", "extrabold", "heavy") or (v.isdigit() and int(v) >= 600)
        stack.append(s)
        cur = s
    if pos < len(text):
        runs.append((unescape(text[pos:]), cur))
    return runs


def segments(text, style, size):
    """split by glyph coverage -> [(substring, font)]"""
    main, fb = style.files()
    out = []
    for ch in text:
        path = main if covers(main, ch) else fb
        if out and out[-1][1] == path:
            out[-1][0].append(ch)
        else:
            out.append([[ch], path])
    return [("".join(chs), get_font(p, size)) for chs, p in out]


def text_width(text, style, size):
    return sum(f.getlength(s) for s, f in segments(text, style, size))


# --------------------------------------------------------------------------------------- text layout
class TextBlock:
    def __init__(self, lines, line_h, size, broke_word=False):
        self.lines = lines  # list of (list of (text, style, size), width)
        self.line_h = line_h
        self.size = size
        self.broke_word = broke_word  # a word wider than the line had to be split by characters

    @property
    def width(self):
        return max((w for _, w in self.lines), default=0.0)

    @property
    def height(self):
        return len(self.lines) * self.line_h


def layout_text(runs, size, max_w, wrap, line_height=1.0):
    """word wrap of styled runs. max_w None = no wrap."""
    # tokens: (text, style, size, is_space, is_break)
    tokens = []
    for text, st in runs:
        sz = st.size or size
        for part in re.split(r"(\n| +)", text):
            if part == "":
                continue
            if part == "\n":
                tokens.append(("", st, sz, False, True))
            elif part.strip(" ") == "":
                tokens.append((part, st, sz, True, False))
            else:
                tokens.append((part, st, sz, False, False))
    max_size = max([size] + [t[2] for t in tokens])
    line_h = max_size * line_height
    lines, cur, cur_w = [], [], 0.0
    broke = False

    def flush():
        nonlocal cur, cur_w
        while cur and cur[-1][3]:  # trailing spaces do not count
            cur_w -= text_width(cur[-1][0], cur[-1][1], cur[-1][2])
            cur.pop()
        lines.append(([(t, s, z) for t, s, z, _, _ in cur], cur_w))
        cur, cur_w = [], 0.0

    for tok in tokens:
        text, st, sz, is_space, is_break = tok
        if is_break:
            flush()
            continue
        w = text_width(text, st, sz)
        if wrap and max_w is not None and cur and not is_space and cur_w + w > max_w + 0.01:
            flush()
        if is_space and not cur and wrap and lines:
            continue  # leading space of a wrapped line
        if wrap and max_w is not None and not is_space and w > max_w + 0.01 and not cur:
            # a single word longer than the line: break by characters
            broke = True
            piece = ""
            for ch in text:
                if piece and text_width(piece + ch, st, sz) > max_w:
                    cur.append((piece, st, sz, False, False))
                    cur_w = text_width(piece, st, sz)
                    flush()
                    piece = ""
                piece += ch
            if piece:
                cur.append((piece, st, sz, False, False))
                cur_w += text_width(piece, st, sz)
            continue
        cur.append(tok)
        cur_w += w
    flush()
    return TextBlock(lines, line_h, max_size, broke)


def ellipsize(line, max_w):
    """force an ellipsis at the end of a line (it is followed by hidden lines)"""
    parts, w = line
    if not parts:
        return line
    t, s, z = parts[-1]
    parts = parts[:-1] + [(t + "\u2026", s, z)]
    w = w + text_width("\u2026", s, z)
    return truncate_line((parts, w), max_w) if w > max_w else (parts, w)


def truncate_line(line, max_w):
    parts, w = line
    if w <= max_w + 0.5:
        return line
    out, acc = [], 0.0
    for t, s, z in parts:
        tw = text_width(t, s, z)
        ell = text_width("\u2026", s, z)
        if acc + tw + ell <= max_w:
            out.append((t, s, z))
            acc += tw
            continue
        keep = t
        while keep and acc + text_width(keep, s, z) + ell > max_w:
            keep = keep[:-1]
        keep = keep.rstrip()
        out.append((keep + "\u2026", s, z))
        acc += text_width(keep + "\u2026", s, z)
        break
    return (out, acc)


# ------------------------------------------------------------------------------------------- the tree
class Node:
    def __init__(self, d):
        self.d = d
        self.id = d["id"]
        self.parent_id = d.get("parent")
        self.cls = d["class"]
        self.name = d["name"]
        self.path = d["path"]
        self.p = d.get("props", {})
        self.is_root = bool(d.get("root"))
        self.is_text = bool(d.get("text"))
        self.is_image = bool(d.get("image"))
        self.attrs = d.get("attrs") or {}
        self.mods = {}
        for m in d.get("mods", []):
            self.mods.setdefault(m["class"], []).append(m)
        self.children = []
        self.parent = None
        self.index = d.get("index", 0)
        # layout results
        self.size_u = (0.0, 0.0)
        self.local = (0.0, 0.0)
        self.content_origin = (0.0, 0.0)
        self.content_size = (0.0, 0.0)
        self.canvas_size = None
        self.text_block = None
        self.text_size = None
        self.abs = (0.0, 0.0, 0.0, 0.0)
        self.k = 1.0
        self.clip = None
        self.scrollbar = None

    def mod(self, cls):
        lst = self.mods.get(cls)
        return lst[0] if lst else None

    @property
    def visible(self):
        return self.p.get("Visible", True) is not False

    @property
    def scale(self):
        m = self.mod("UIScale")
        return float(m.get("Scale", 1)) if m else 1.0

    def padding(self, w, h):
        m = self.mod("UIPadding")
        if not m:
            return 0.0, 0.0, 0.0, 0.0
        def u(k, ref):
            v = m.get(k, [0, 0])
            return v[0] * ref + v[1]
        return u("PaddingTop", h), u("PaddingRight", w), u("PaddingBottom", h), u("PaddingLeft", w)


def load_nodes(lines):
    nodes, meta, errors, logs = [], {}, [], []
    for line in lines:
        if line.startswith("@@GUI "):
            nodes.append(Node(json.loads(line[6:])))
        elif line.startswith("@@META "):
            meta = json.loads(line[7:])
        elif line.startswith("@@ERROR"):
            errors.append(line)
        elif line.strip() and not line.startswith("@@END"):
            logs.append(line)
    by_id = {n.id: n for n in nodes}
    roots = []
    for n in nodes:
        if n.parent_id is not None and n.parent_id in by_id:
            n.parent = by_id[n.parent_id]
            n.parent.children.append(n)
        else:
            roots.append(n)
    return roots, nodes, meta, errors, logs


# ----------------------------------------------------------------------------------------------- layout
def udim2(v, pw, ph, constraint="RelativeXY"):
    if not v:
        return 0.0, 0.0
    if constraint == "RelativeXX":
        return v[0] * pw + v[1], v[2] * pw + v[3]
    if constraint == "RelativeYY":
        return v[0] * ph + v[1], v[2] * ph + v[3]
    return v[0] * pw + v[1], v[2] * ph + v[3]


def constrain(n, w, h):
    sc = n.mod("UISizeConstraint")
    if sc:
        mn, mx = sc.get("MinSize", [0, 0]), sc.get("MaxSize", [1e30, 1e30])
        w = min(max(w, mn[0]), max(mx[0], mn[0]))
        h = min(max(h, mn[1]), max(mx[1], mn[1]))
    ar = n.mod("UIAspectRatioConstraint")
    if ar:
        r = float(ar.get("AspectRatio", 1)) or 1.0
        if ar.get("AspectType", "FitWithinMaxSize") == "FitWithinMaxSize":
            if w / max(h, 1e-6) > r:
                w = h * r
            else:
                h = w / r
        else:  # ScaleWithParentSize: dominant axis decides
            if ar.get("DominantAxis", "Width") == "Width":
                h = w / r
            else:
                w = h * r
    return w, h


class Engine:
    def __init__(self, viewport, insets, device=(0, 0, 0, 0), ppstud=40, warnings=None):
        self.vw, self.vh = viewport
        self.insets = insets  # top, right, bottom, left
        self.device = device
        self.ppstud = ppstud
        self.warn = warnings if warnings is not None else []

    # --- text
    def measure_text(self, n, avail_w, avail_h, fit=False):
        p = n.p
        text = str(p.get("Text", ""))
        placeholder = False
        if n.cls == "TextBox" and text == "" and p.get("PlaceholderText"):
            text, placeholder = str(p["PlaceholderText"]), True
        mvg = p.get("MaxVisibleGraphemes", -1)
        if isinstance(mvg, (int, float)) and mvg >= 0:
            text = text[: int(mvg)]
        style = base_style(p)
        rich = bool(p.get("RichText"))
        runs = rich_runs(text, style, rich)
        lh = float(p.get("LineHeight", 1) or 1)
        wrap = bool(p.get("TextWrapped")) or bool(p.get("TextScaled"))
        if p.get("TextScaled"):
            tsc = n.mod("UITextSizeConstraint")
            hi = float(tsc.get("MaxTextSize", 100)) if tsc else 100.0
            lo = float(tsc.get("MinTextSize", 1)) if tsc else 1.0
            best = lo
            if avail_w is not None and avail_h is not None and avail_w > 0 and avail_h > 0:
                a, b = lo, hi
                for _ in range(14):
                    mid = (a + b) / 2
                    blk = layout_text(runs, mid, avail_w, True, lh)
                    # Roblox shrinks scaled text until every word fits on a line (never splits a word)
                    if blk.height <= avail_h + 0.5 and not blk.broke_word:
                        best, a = mid, mid
                    else:
                        b = mid
                size = math.floor(best)
                size = max(lo, size)
            else:
                size = hi
            blk = layout_text(runs, size, avail_w, True, lh)
        else:
            size = float(p.get("TextSize", 14) or 14)
            blk = layout_text(runs, size, avail_w if wrap else None, wrap, lh)
        n.text_block, n.text_size, n.text_placeholder = blk, size, placeholder
        return blk

    # --- generic node layout; pw/ph = parent content size (parent local units)
    def layout(self, n, pw, ph):
        p = n.p
        w, h = udim2(p.get("Size"), pw, ph, p.get("SizeConstraint", "RelativeXY"))
        w, h = constrain(n, w, h)
        auto = p.get("AutomaticSize", "None")
        ax, ay = auto in ("X", "XY"), auto in ("Y", "XY")
        if n.is_text:
            pt, pr, pb, pl = n.padding(w, h)
            avail_w = None if ax else max(0.0, w - pl - pr)
            blk = self.measure_text(n, avail_w, max(0.0, h - pt - pb))
            if ax:
                w = max(w, blk.width + pl + pr)
            if ay:
                h = max(h, blk.height + pt + pb)
            if ax and (p.get("TextWrapped")):
                # wrapped + automatic X: re-wrap at the grown width (no-op unless constrained)
                pass
        self.layout_children(n, w, h)
        if (ax or ay) and n.children:
            ew, eh = self.children_extent(n)
            pt, pr, pb, pl = n.padding(w, h)
            nw = max(w, ew + pl + pr) if ax else w
            nh = max(h, eh + pt + pb) if ay else h
            if (nw, nh) != (w, h):
                w, h = nw, nh
                self.layout_children(n, w, h)
        w2, h2 = constrain(n, w, h)
        if (w2, h2) != (w, h):
            w, h = w2, h2
            self.layout_children(n, w, h)
        if n.is_text and n.text_block is not None and not (ax and not p.get("TextWrapped")):
            # final wrap width = final content width (TextScaled also refits)
            pt, pr, pb, pl = n.padding(w, h)
            self.measure_text(n, max(0.0, w - pl - pr), max(0.0, h - pt - pb))
        n.size_u = (w, h)

    def visible_children(self, n):
        return [c for c in n.children if c.visible]

    def layout_children(self, n, w, h):
        pt, pr, pb, pl = n.padding(w, h)
        cw, ch = max(0.0, w - pl - pr), max(0.0, h - pt - pb)
        n.content_origin = (pl, pt)
        if n.cls == "ScrollingFrame":
            self.layout_scrolling(n, w, h, pt, pr, pb, pl)
            return
        n.content_size = (cw, ch)
        for c in self.visible_children(n):
            self.layout(c, cw, ch)
        self.position_children(n, cw, ch)

    def layout_scrolling(self, n, w, h, pt, pr, pb, pl):
        """canvas = max(CanvasSize, window) (+ AutomaticCanvasSize); VerticalScrollBarInset ScrollBar/Always
        narrows the window by ScrollBarThickness while the vertical bar is shown"""
        p = n.p
        cvw, cvh = udim2(p.get("CanvasSize", [0, 0, 2, 0]), w, h)
        auto = p.get("AutomaticCanvasSize", "None")
        thick = float(p.get("ScrollBarThickness", 12))
        vinset = p.get("VerticalScrollBarInset", "None")
        direction = p.get("ScrollingDirection", "XY")
        bar_w = 0.0
        for _ in range(3):
            win_w = w - bar_w
            canvas_w = max(cvw, win_w)
            canvas_h0 = max(cvh, h)
            cw, ch = max(0.0, canvas_w - pl - pr), max(0.0, canvas_h0 - pt - pb)
            for c in self.visible_children(n):
                self.layout(c, cw, ch)
            self.position_children(n, cw, ch)
            ew, eh = self.children_extent(n)
            canvas_h = max(cvh, eh + pt + pb) if auto in ("Y", "XY") else cvh
            if auto in ("X", "XY"):
                canvas_w = max(canvas_w, ew + pl + pr)
            scroll_y = canvas_h > h + 0.5 and direction in ("Y", "XY")
            want_bar = thick if (vinset == "Always" or (vinset == "ScrollBar" and scroll_y)) else 0.0
            if want_bar == bar_w:
                break
            bar_w = want_bar
        canvas_h = max(canvas_h, h)
        n.canvas_size = (canvas_w, canvas_h)
        n.content_size = (cw, canvas_h - pt - pb)
        cp = p.get("CanvasPosition", [0, 0])
        n.canvas_pos = (min(max(cp[0], 0), max(0.0, canvas_w - w)), min(max(cp[1], 0), max(0.0, canvas_h - h)))
        n.content_origin = (pl - n.canvas_pos[0], pt - n.canvas_pos[1])
        n.scrollbar = None
        if canvas_h > h + 0.5 and thick > 0 and direction in ("Y", "XY"):
            n.scrollbar = (w - thick, (n.canvas_pos[1] / canvas_h) * h, thick, max(thick, h * h / canvas_h))

    def vis_size(self, c):
        s = c.scale
        return c.size_u[0] * s, c.size_u[1] * s

    def position_children(self, n, cw, ch):
        lay = n.mod("UIListLayout")
        grid = n.mod("UIGridLayout")
        kids = self.visible_children(n)
        n.layout_extent = None
        if grid:
            self.position_grid(n, grid, kids, cw, ch)
            return
        if lay:
            self.position_list(n, lay, kids, cw, ch)
            return
        if n.mod("UIPageLayout") or n.mod("UITableLayout"):
            self.warn.append(f"{n.path}: UIPageLayout/UITableLayout not supported (children placed by Position)")
        for c in kids:
            ax, ay = udim2(c.p.get("Position"), cw, ch)
            ap = c.p.get("AnchorPoint", [0, 0])
            vw, vh = self.vis_size(c)
            c.local = (ax - ap[0] * vw, ay - ap[1] * vh)

    @staticmethod
    def sort_kids(kids, order):
        if order == "Name":
            return sorted(kids, key=lambda c: (c.name, c.index))
        if order == "Custom":
            return list(kids)
        return sorted(kids, key=lambda c: (c.p.get("LayoutOrder", 0), c.index))

    def position_list(self, n, lay, kids, cw, ch):
        kids = self.sort_kids(kids, lay.get("SortOrder", "LayoutOrder"))
        vertical = lay.get("FillDirection", "Vertical") == "Vertical"
        pad = lay.get("Padding", [0, 0])
        gap = pad[0] * (ch if vertical else cw) + pad[1]
        ha = lay.get("HorizontalAlignment", "Left")
        va = lay.get("VerticalAlignment", "Top")
        wraps = bool(lay.get("Wraps"))
        if lay.get("HorizontalFlex", "None") != "None" or lay.get("VerticalFlex", "None") != "None" or any(c.mod("UIFlexItem") for c in kids):
            self.warn.append(f"{n.path}: UIListLayout flex not supported (items keep their size)")
        sizes = [self.vis_size(c) for c in kids]
        main_len = cw if not vertical else ch
        # split into lines (only when Wraps)
        lines, cur, acc = [], [], 0.0
        for c, s in zip(kids, sizes):
            m = s[1] if vertical else s[0]
            if wraps and cur and acc + gap + m > main_len + 0.01:
                lines.append(cur)
                cur, acc = [], 0.0
            acc = (acc + gap + m) if cur else m
            cur.append((c, s))
        if cur:
            lines.append(cur)
        cross = 0.0
        total_main = 0.0
        placements = []
        for line in lines:
            mains = [(s[1] if vertical else s[0]) for _, s in line]
            crosses = [(s[0] if vertical else s[1]) for _, s in line]
            line_main = sum(mains) + gap * max(0, len(line) - 1)
            line_cross = max(crosses) if crosses else 0.0
            placements.append((line, line_main, line_cross, cross))
            total_main = max(total_main, line_main)
            cross += line_cross + (gap if wraps else 0)
        total_cross = cross - (gap if wraps and lines else 0)
        for line, line_main, line_cross, cross0 in placements:
            if vertical:
                start = {"Top": 0.0, "Center": (ch - line_main) / 2, "Bottom": ch - line_main}.get(va, 0.0)
            else:
                start = {"Left": 0.0, "Center": (cw - line_main) / 2, "Right": cw - line_main}.get(ha, 0.0)
            pos = start
            for c, s in line:
                if vertical:
                    if wraps:
                        x = cross0
                    else:
                        x = {"Left": 0.0, "Center": (cw - s[0]) / 2, "Right": cw - s[0]}.get(ha, 0.0)
                    c.local = (x, pos)
                    pos += s[1] + gap
                else:
                    if wraps:
                        y = cross0
                    else:
                        y = {"Top": 0.0, "Center": (ch - s[1]) / 2, "Bottom": ch - s[1]}.get(va, 0.0)
                    c.local = (pos, y)
                    pos += s[0] + gap
        if vertical:
            n.layout_extent = (total_cross if wraps else max([s[0] for s in sizes] or [0]), total_main)
        else:
            n.layout_extent = (total_main, total_cross if wraps else max([s[1] for s in sizes] or [0]))

    def position_grid(self, n, grid, kids, cw, ch):
        kids = self.sort_kids(kids, grid.get("SortOrder", "LayoutOrder"))
        cell = grid.get("CellSize", [0, 100, 0, 100])
        cpad = grid.get("CellPadding", [0, 5, 0, 5])
        cwid, chei = cell[0] * cw + cell[1], cell[2] * ch + cell[3]
        px, py = cpad[0] * cw + cpad[1], cpad[2] * ch + cpad[3]
        horizontal = grid.get("FillDirection", "Horizontal") == "Horizontal"
        maxc = int(grid.get("FillDirectionMaxCells", 0) or 0)
        if horizontal:
            per = max(1, int((cw + px + 0.01) // (cwid + px))) if cwid + px > 0 else 1
        else:
            per = max(1, int((ch + py + 0.01) // (chei + py))) if chei + py > 0 else 1
        if maxc > 0:
            per = min(per, maxc)
        count = len(kids)
        lines = max(1, math.ceil(count / per)) if count else 0
        cols = min(per, count) if horizontal else lines
        rows = lines if horizontal else min(per, count)
        tw = cols * cwid + max(0, cols - 1) * px
        th = rows * chei + max(0, rows - 1) * py
        ha, va = grid.get("HorizontalAlignment", "Left"), grid.get("VerticalAlignment", "Top")
        ox = {"Left": 0.0, "Center": (cw - tw) / 2, "Right": cw - tw}.get(ha, 0.0)
        oy = {"Top": 0.0, "Center": (ch - th) / 2, "Bottom": ch - th}.get(va, 0.0)
        corner = grid.get("StartCorner", "TopLeft")
        for i, c in enumerate(kids):
            a, b = (i % per, i // per) if horizontal else (i // per, i % per)
            if "Right" in corner:
                a = cols - 1 - a
            if "Bottom" in corner:
                b = rows - 1 - b
            s = c.scale
            c.size_u = (cwid / s if s else cwid, chei / s if s else chei)
            # re-layout the cell's own children at the cell size
            self.layout_children(c, *c.size_u)
            c.local = (ox + a * (cwid + px), oy + b * (chei + py))
        n.layout_extent = (tw, th)

    def children_extent(self, n):
        if n.layout_extent is not None and (n.mod("UIListLayout") or n.mod("UIGridLayout")):
            return n.layout_extent
        ew = eh = 0.0
        for c in self.visible_children(n):
            vw, vh = self.vis_size(c)
            ew = max(ew, c.local[0] + vw)
            eh = max(eh, c.local[1] + vh)
        return ew, eh

    # --- absolute placement
    def place(self, n, ox, oy, k, clip):
        vw, vh = self.vis_size(n)
        x, y = ox + k * n.local[0], oy + k * n.local[1]
        n.abs = (x, y, k * vw, k * vh)
        n.k = k * n.scale
        n.clip = clip
        child_clip = clip
        if n.p.get("ClipsDescendants") or n.cls == "ScrollingFrame":
            child_clip = intersect(clip, n.abs)
        cx, cy = x + n.k * n.content_origin[0], y + n.k * n.content_origin[1]
        for c in self.visible_children(n):
            self.place(c, cx, cy, n.k, child_clip)

    # --- roots
    def screen_rect(self, r):
        mode = r.p.get("ScreenInsets", "CoreUISafeInsets")
        t, rr, b, l = (0, 0, 0, 0)
        if mode in ("CoreUISafeInsets", "TopbarSafeInsets"):
            t, rr, b, l = self.insets
        elif mode == "DeviceSafeInsets":
            t, rr, b, l = self.device
        return (l, t, self.vw - l - rr, self.vh - t - b)

    def root_size(self, r):
        if r.cls == "ScreenGui":
            x, y, w, h = self.screen_rect(r)
            return (x, y), (w, h)
        if r.cls == "BillboardGui":
            s = r.p.get("Size", [0, 0, 0, 0])
            return (0, 0), (max(1.0, s[0] * self.ppstud + s[1]), max(1.0, s[2] * self.ppstud + s[3]))
        if r.cls == "SurfaceGui":
            part = r.d.get("part") or {}
            size = part.get("Size") or [4, 2, 1]
            face = r.p.get("Face", "Front")
            fw, fh = {"Front": (size[0], size[1]), "Back": (size[0], size[1]), "Left": (size[2], size[1]),
                      "Right": (size[2], size[1]), "Top": (size[0], size[2]), "Bottom": (size[0], size[2])}.get(face, (size[0], size[1]))
            if r.p.get("SizingMode") == "PixelsPerStud":
                pps = float(r.p.get("PixelsPerStud", 50))
                return (0, 0), (fw * pps, fh * pps)
            cs = r.p.get("CanvasSize", [800, 600])
            return (0, 0), (cs[0], cs[1])
        return (0, 0), (self.vw, self.vh)

    def run_root(self, r, origin=None, size=None):
        (x, y), (w, h) = self.root_size(r)
        if origin is not None:
            x, y = origin
        if size is not None:
            w, h = size
        r.abs = (x, y, w, h)
        r.size_u = (w, h)
        r.k = 1.0
        r.content_origin = (0.0, 0.0)
        r.content_size = (w, h)
        r.clip = (x, y, w, h) if r.cls != "ScreenGui" or True else None
        for c in self.visible_children(r):
            self.layout(c, w, h)
        self.position_children(r, w, h)
        clip = (x, y, w, h) if (r.cls != "BillboardGui" or r.p.get("ClipsDescendants")) else None
        if r.cls == "ScreenGui":
            clip = (0, 0, self.vw, self.vh)
        for c in self.visible_children(r):
            self.place(c, x, y, 1.0, clip)


def intersect(a, b):
    if a is None:
        return b
    if b is None:
        return a
    x1, y1 = max(a[0], b[0]), max(a[1], b[1])
    x2, y2 = min(a[0] + a[2], b[0] + b[2]), min(a[1] + a[3], b[1] + b[3])
    return (x1, y1, max(0.0, x2 - x1), max(0.0, y2 - y1))


# ---------------------------------------------------------------------------------------------- drawing
def seq_sample(seq, t, channels):
    if not seq:
        return None
    ts = np.array([k[0] for k in seq], dtype=np.float32)
    out = []
    for ci in range(channels):
        vs = np.array([k[1 + ci] for k in seq], dtype=np.float32)
        out.append(np.interp(t, ts, vs))
    return out


class Painter:
    def __init__(self, w, h, ss=2):
        self.ss = ss
        self.W, self.H = int(round(w * ss)), int(round(h * ss))
        self.img = Image.new("RGBA", (self.W, self.H), (0, 0, 0, 0))

    def S(self, v):
        return v * self.ss

    def composite(self, mask, box, rgb, alpha, clip, grad=None, elem=None):
        """mask: L image covering box (x0,y0 in ss px); rgb/alpha constants; grad = UIGradient mod on elem"""
        if alpha <= 0.001 or mask is None:
            return
        x0, y0 = box
        mw, mh = mask.size
        # clip in ss px
        cx0, cy0, cx1, cy1 = 0, 0, self.W, self.H
        if clip is not None:
            cx0, cy0 = max(cx0, int(math.floor(self.S(clip[0])))), max(cy0, int(math.floor(self.S(clip[1]))))
            cx1, cy1 = min(cx1, int(math.ceil(self.S(clip[0] + clip[2])))), min(cy1, int(math.ceil(self.S(clip[1] + clip[3]))))
        ix0, iy0 = max(x0, cx0), max(y0, cy0)
        ix1, iy1 = min(x0 + mw, cx1), min(y0 + mh, cy1)
        if ix1 <= ix0 or iy1 <= iy0:
            return
        m = np.asarray(mask.crop((ix0 - x0, iy0 - y0, ix1 - x0, iy1 - y0)), dtype=np.float32) / 255.0
        hgt, wid = m.shape
        a = m * alpha
        col = np.empty((hgt, wid, 3), dtype=np.float32)
        col[:] = np.array(rgb, dtype=np.float32)
        if grad is not None and grad.get("Enabled", True) is not False and elem is not None:
            ex, ey, ew, eh = [self.S(v) for v in elem]
            ys, xs = np.mgrid[iy0:iy1, ix0:ix1].astype(np.float32)
            u = (xs + 0.5 - ex) / max(ew, 1e-6)
            v = (ys + 0.5 - ey) / max(eh, 1e-6)
            off = grad.get("Offset", [0, 0])
            u, v = u - off[0], v - off[1]
            th = math.radians(float(grad.get("Rotation", 0)))
            t = (u - 0.5) * math.cos(th) + (v - 0.5) * math.sin(th)
            span = abs(math.cos(th)) * 0.5 + abs(math.sin(th)) * 0.5
            t = np.clip(t / (2 * span) + 0.5 if span > 0 else t + 0.5, 0, 1)
            cs = seq_sample(grad.get("Color"), t, 3)
            if cs:
                for ci in range(3):
                    col[:, :, ci] *= cs[ci] / 255.0
            ts = seq_sample(grad.get("Transparency"), t, 1)
            if ts:
                a = a * (1.0 - np.clip(ts[0], 0, 1))
        rgba = np.dstack([col, a * 255.0]).clip(0, 255).astype(np.uint8)
        self.img.alpha_composite(Image.fromarray(rgba, "RGBA"), dest=(ix0, iy0))

    def shape_mask(self, rect, radius, outline=None):
        """rounded-rect mask in ss px; outline=(width) -> ring outside rect"""
        x, y, w, h = [self.S(v) for v in rect]
        r = self.S(radius)
        if outline:
            t = self.S(outline)
            x, y, w, h = x - t, y - t, w + 2 * t, h + 2 * t
            r = r + t if radius > 0 else 0
        x0, y0 = int(math.floor(x)), int(math.floor(y))
        x1, y1 = int(math.ceil(x + w)), int(math.ceil(y + h))
        if x1 - x0 <= 0 or y1 - y0 <= 0:
            return None, (0, 0)
        mask = Image.new("L", (x1 - x0, y1 - y0), 0)
        d = ImageDraw.Draw(mask)
        box = [x - x0, y - y0, max(x - x0, x - x0 + w - 1), max(y - y0, y - y0 + h - 1)]
        rr = max(0, min(r, w / 2, h / 2))
        if outline:
            d.rounded_rectangle(box, radius=rr, fill=255)
            inner = [box[0] + t, box[1] + t, box[2] - t, box[3] - t]
            if inner[2] > inner[0] and inner[3] > inner[1]:
                d.rounded_rectangle(inner, radius=max(0, rr - t), fill=0)
        else:
            if rr > 0:
                d.rounded_rectangle(box, radius=rr, fill=255)
            else:
                d.rectangle(box, fill=255)
        return mask, (x0, y0)


def c3(v, default=(255, 255, 255)):
    if not v:
        return default
    return tuple(v[:3])


def corner_radius(n, w, h):
    m = n.mod("UICorner")
    if not m:
        return 0.0
    cr = m.get("CornerRadius", [0, 8])
    return cr[0] * min(w, h) + cr[1] * n.k


class Renderer:
    def __init__(self, engine, painter, debug=False):
        self.e, self.pt, self.debug = engine, painter, debug

    def draw_tree(self, root):
        mode = root.p.get("ZIndexBehavior", "Sibling")
        if mode == "Global":
            order = []

            def collect(n):
                for c in sorted(self.e.visible_children(n), key=lambda c: c.index):
                    order.append(c)
                    collect(c)
            collect(root)
            order.sort(key=lambda c: c.p.get("ZIndex", 1))  # stable: tree order within a ZIndex
            for n in order:
                self.draw_node(n)
                if n.scrollbar:
                    self.draw_scrollbar(n)
        else:
            self.draw_children(root)

    def draw_children(self, n):
        for c in sorted(self.e.visible_children(n), key=lambda c: (c.p.get("ZIndex", 1), c.index)):
            self.draw_node(c)
            self.draw_children(c)
            if c.scrollbar:
                self.draw_scrollbar(c)

    def draw_node(self, n):
        x, y, w, h = n.abs
        clip = n.clip
        if clip is not None and (clip[2] <= 0 or clip[3] <= 0):
            return
        if w <= 0.01 or h <= 0.01:
            if n.is_text and (w > 0.01 or h > 0.01 or n.text_block):
                self.draw_text(n, clip, None)  # text overflows a zero-size box like in Roblox
            return
        p = n.p
        grad = n.mod("UIGradient")
        radius = corner_radius(n, w, h)
        bt = float(p.get("BackgroundTransparency", 0))
        if n.cls == "CanvasGroup":
            bt = 1 - (1 - bt) * (1 - float(p.get("GroupTransparency", 0)))
        if bt < 0.999:
            mask, off = self.pt.shape_mask(n.abs, radius)
            self.pt.composite(mask, off, c3(p.get("BackgroundColor3")), 1 - bt, clip, grad, n.abs)
            bs = float(p.get("BorderSizePixel", 0))
            if bs > 0 and not n.mod("UICorner"):
                if p.get("BorderMode", "Outline") == "Outline":
                    mask, off = self.pt.shape_mask(n.abs, 0, outline=bs * n.k)
                else:
                    ins = bs * n.k
                    mask, off = self.pt.shape_mask((x + ins, y + ins, w - 2 * ins, h - 2 * ins), 0, outline=ins)
                self.pt.composite(mask, off, c3(p.get("BorderColor3"), (27, 42, 53)), 1 - bt, clip)
        if n.is_image and p.get("Image"):
            self.draw_image_placeholder(n, radius, clip)
        if n.is_text:
            self.draw_text(n, clip, grad if bt >= 0.999 else None)
        for st in n.mods.get("UIStroke", []):
            if st.get("Enabled", True) is False:
                continue
            th = float(st.get("Thickness", 1)) * n.k
            tr = float(st.get("Transparency", 0))
            if th <= 0 or tr >= 0.999:
                continue
            if st.get("ApplyStrokeMode", "Contextual") == "Contextual" and n.is_text:
                self.draw_text(n, clip, None, stroke=(c3(st.get("Color"), (0, 0, 0)), th, 1 - tr))
                continue
            mask, off = self.pt.shape_mask(n.abs, radius, outline=th)
            self.pt.composite(mask, off, c3(st.get("Color"), (0, 0, 0)), 1 - tr, clip, st.get("gradient"),
                              (x - th, y - th, w + 2 * th, h + 2 * th))
        if self.debug:
            mask, off = self.pt.shape_mask(n.abs, 0, outline=0.5)
            self.pt.composite(mask, off, (255, 0, 255), 0.6, None)

    def draw_scrollbar(self, n):
        sb = n.scrollbar
        x, y, w, h = n.abs
        k = n.k
        rect = (x + sb[0] * k, y + sb[1] * k, sb[2] * k, sb[3] * k)
        tr = float(n.p.get("ScrollBarImageTransparency", 0))
        mask, off = self.pt.shape_mask(rect, min(rect[2], rect[3]) / 2)
        self.pt.composite(mask, off, c3(n.p.get("ScrollBarImageColor3"), (0, 0, 0)), 1 - tr, n.clip)

    def draw_image_placeholder(self, n, radius, clip):
        x, y, w, h = n.abs
        it = float(n.p.get("ImageTransparency", 0))
        if it >= 0.999:
            return
        tint = c3(n.p.get("ImageColor3"))
        col = tuple(int(0.5 * 140 + 0.5 * t * 140 / 255) for t in tint)
        mask, off = self.pt.shape_mask(n.abs, radius)
        self.pt.composite(mask, off, col, 0.55 * (1 - it), clip)
        mask, off = self.pt.shape_mask((x + 1, y + 1, max(0, w - 2), max(0, h - 2)), radius, outline=1)
        self.pt.composite(mask, off, (220, 220, 220), 0.8 * (1 - it), clip)
        label = "image: " + str(n.p.get("Image")).replace("rbxassetid://", "#")
        size = max(8, min(12, h * 0.25))
        st = Style()
        if text_width(label, st, size) > w - 4:
            label = n.name
        self.blit_text_line([(label, st, size)], x + 3, y + h / 2, (235, 235, 235), 0.9, clip, 1.0, anchor_mid=True)

    def blit_text_line(self, parts, x, y_mid, rgb, alpha, clip, k, anchor_mid=True, stroke=None, grad=None, elem=None):
        """parts: [(text, Style, size_local)]; x,y in screen px; k = local->screen scale"""
        pt = self.pt
        ss = pt.ss
        cx = x
        for text, st, sz in parts:
            if not text:
                continue
            size_px = sz * k * ss
            col = st.color or rgb
            for sub, font in segments(text, st, size_px):
                wpx = font.getlength(sub)
                pad = int(size_px) + 8
                sw = 0
                if stroke is not None:
                    sw = max(1, int(round(stroke[1] * ss)))
                elif st.heavy:
                    sw = max(0, int(round(size_px * 0.018)))
                mw, mh = int(wpx) + 2 * pad, int(size_px * 2) + 2 * pad
                mask = Image.new("L", (mw, mh), 0)
                d = ImageDraw.Draw(mask)
                if stroke is not None:
                    d.text((pad, mh / 2), sub, font=font, fill=255, anchor="lm", stroke_width=sw, stroke_fill=255)
                else:
                    d.text((pad, mh / 2), sub, font=font, fill=255, anchor="lm", stroke_width=sw, stroke_fill=255)
                ox = int(round(cx * ss)) - pad
                oy = int(round(y_mid * ss - mh / 2))
                if stroke is not None:
                    pt.composite(mask, (ox, oy), stroke[0], stroke[2] * alpha, clip)
                else:
                    pt.composite(mask, (ox, oy), col, alpha, clip, grad, elem)
                    if st.underline or st.strike:
                        yy = (y_mid * ss + size_px * 0.42) if st.underline else y_mid * ss
                        lm = Image.new("L", (max(1, int(wpx)), max(1, int(size_px * 0.07))), 255)
                        pt.composite(lm, (int(round(cx * ss)), int(yy)), col, alpha, clip)
                cx += wpx / ss

    def draw_text(self, n, clip, grad, stroke=None):
        blk = n.text_block
        if blk is None or not blk.lines:
            return
        p = n.p
        x, y, w, h = n.abs
        k = n.k
        lw, lh_ = n.size_u
        pt_, pr, pb, pl = n.padding(*n.size_u)
        tx, ty = x + pl * k, y + pt_ * k
        tw, th = (lw - pl - pr) * k, (lh_ - pt_ - pb) * k
        ttr = float(p.get("TextTransparency", 0))
        if ttr >= 0.999:
            return
        alpha = 1 - ttr
        rgb = c3(p.get("TextColor3"), (27, 42, 53))
        if getattr(n, "text_placeholder", False):
            rgb = c3(p.get("PlaceholderColor3"), (178, 178, 178))
        lines = list(blk.lines)
        trunc = p.get("TextTruncate", "None")
        if trunc != "None":
            maxw = (lw - pl - pr)
            if (p.get("TextWrapped") or p.get("TextScaled")) and blk.line_h > 0:
                maxl = max(1, int((lh_ - pt_ - pb + 0.5) // blk.line_h))
                if len(lines) > maxl:
                    lines = lines[:maxl]
                    lines[-1] = ellipsize(lines[-1], maxw)
            lines = [truncate_line(l, maxw) for l in lines]
        total_h = len(lines) * blk.line_h * k
        ya = p.get("TextYAlignment", "Center")
        y0 = {"Top": ty, "Center": ty + (th - total_h) / 2, "Bottom": ty + th - total_h}.get(ya, ty)
        xa = p.get("TextXAlignment", "Center")
        tstroke = float(p.get("TextStrokeTransparency", 1))
        for i, (parts, lwid) in enumerate(lines):
            lwpx = lwid * k
            lx = {"Left": tx, "Center": tx + (tw - lwpx) / 2, "Right": tx + tw - lwpx}.get(xa, tx)
            ymid = y0 + (i + 0.5) * blk.line_h * k
            if stroke is None and tstroke < 0.999:
                self.blit_text_line(parts, lx, ymid, rgb, alpha, clip, k,
                                    stroke=(c3(p.get("TextStrokeColor3"), (0, 0, 0)), 1.0 * k, (1 - tstroke)))
            self.blit_text_line(parts, lx, ymid, rgb, alpha, clip, k, stroke=stroke, grad=grad, elem=n.abs)


# ------------------------------------------------------------------------------------------- scene runs
def run_scene(scene, gen, state, viewport, insets, feedback_path, extra):
    scene_dir = os.path.dirname(os.path.abspath(scene))
    gen_rel = os.path.relpath(os.path.abspath(gen), scene_dir)
    if not gen_rel.startswith("."):
        gen_rel = "./" + gen_rel
    fb = "-"
    if feedback_path:
        fb = os.path.relpath(os.path.splitext(os.path.abspath(feedback_path))[0], scene_dir)
        if not fb.startswith("."):
            fb = "./" + fb
    cmd = [LUAU, os.path.abspath(scene), "-a", gen_rel, state, str(viewport[0]), str(viewport[1]),
           ",".join(str(v) for v in insets), fb] + list(extra)
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    out = res.stdout.splitlines() + [l for l in res.stderr.splitlines()]
    if res.returncode != 0 and not any(l.startswith("@@GUI") for l in out):
        sys.stderr.write("\n".join(out[-40:]) + "\n")
        raise SystemExit(f"scene failed (exit {res.returncode})")
    return out


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def write_feedback(path, nodes):
    lines = ["return {"]
    fb = {}
    for n in nodes:
        if n.is_root:
            continue
        root = n
        while root.parent is not None:
            root = root.parent
        rx, ry = root.abs[0], root.abs[1]
        x, y, w, h = n.abs
        v = (round(x - rx, 2), round(y - ry, 2), round(w, 2), round(h, 2))
        fb[n.path] = v
        lines.append(f"\t[{lua_str(n.path)}] = {{ {v[0]}, {v[1]}, {v[2]}, {v[3]} }},")
    lines.append("}")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    return fb


# ---------------------------------------------------------------------------------------------- output
def draw_backdrop(img_painter, vw, vh):
    """stand-in for the 3D world behind the UI"""
    ss = img_painter.ss
    W, H = img_painter.W, img_painter.H
    yy = np.linspace(0, 1, H, dtype=np.float32)[:, None]
    sky_top, sky_bot = np.array([126, 164, 204]), np.array([196, 214, 226])
    ground = np.array([112, 128, 112])
    horizon = 0.62
    col = np.where(yy < horizon, sky_top + (sky_bot - sky_top) * (yy / horizon), ground - 30 * (yy - horizon))
    arr = np.repeat(col[:, None, :], W, axis=1).reshape(H, W, 3)
    base = Image.fromarray(np.dstack([arr, np.full((H, W), 255)]).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(base)
    f = get_font(font_path(FONT_FILES[("sans", False, False)]), 13 * ss)
    d.text((W / 2, H * horizon - 20 * ss), "3D world (not rendered)", font=f, fill=(90, 100, 110, 255), anchor="mm")
    img_painter.img = Image.alpha_composite(base, img_painter.img)


def stamp(img, text_lines, ss=1):
    """adds a footer band with the label in its right corner (the UI itself stays uncovered)"""
    f = get_font(font_path(FONT_FILES[("sans", False, False)]), 11 * ss)
    fb = get_font(font_path(FONT_FILES[("sans", True, False)]), 11 * ss)
    W, H = img.size
    band = (len(text_lines) * 14 + 8) * ss
    probe = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    need = max(probe.textlength(t, font=fb if i == 0 else f) for i, t in enumerate(text_lines)) + 16 * ss
    W = max(W, int(math.ceil(need)))  # a narrow image gets a wider footer instead of a cut label
    out = Image.new("RGBA", (W, H + band), (18, 18, 20, 255))
    out.alpha_composite(img.convert("RGBA"), (0, 0))
    d = ImageDraw.Draw(out)
    d.line([0, H, W, H], fill=(255, 210, 90, 255), width=max(1, ss))
    for i, t in enumerate(text_lines):
        font = fb if i == 0 else f
        tw = d.textlength(t, font=font)
        d.text((W - tw - 8 * ss, H + (4 + i * 14) * ss), t, font=font,
               fill=(255, 225, 140, 255) if i == 0 else (225, 225, 225, 255))
    return out


def draw_insets(painter, vw, vh, insets):
    t, r, b, l = insets
    ss = painter.ss
    d = ImageDraw.Draw(painter.img)
    col = (255, 255, 255, 110)
    for x0, y0, x1, y1 in ((0, t, vw, t), (l, 0, l, vh), (vw - r, 0, vw - r, vh), (0, vh - b, vw, vh - b)):
        if (x0 == x1 and (x0 <= 0 or x0 >= vw)) or (y0 == y1 and (y0 <= 0 or y0 >= vh)):
            continue
        n = int(max(abs(x1 - x0), abs(y1 - y0)) // 6)
        for i in range(n):
            if i % 2:
                continue
            fx = x0 + (x1 - x0) * i / max(n, 1)
            fy = y0 + (y1 - y0) * i / max(n, 1)
            gx = x0 + (x1 - x0) * (i + 1) / max(n, 1)
            gy = y0 + (y1 - y0) * (i + 1) / max(n, 1)
            d.line([fx * ss, fy * ss, gx * ss, gy * ss], fill=col, width=max(1, ss // 2))
    if t > 0:
        f = get_font(font_path(FONT_FILES[("sans", False, False)]), 10 * ss)
        label = f"Roblox top bar / safe-area inset ({t}px, CoreUISafeInsets) - not drawn"
        tw = d.textlength(label, font=f)
        x0, y0 = (l + 6) * ss, (t - 16) * ss
        d.rounded_rectangle([x0, y0, x0 + tw + 8 * ss, y0 + 13 * ss], radius=3 * ss, fill=(0, 0, 0, 120))
        d.text((x0 + 4 * ss, y0 + 1 * ss), label, font=f, fill=(255, 255, 255, 190))


def render_screen(roots, engine, args, meta_lines, out):
    painter = Painter(engine.vw, engine.vh, args.ss * args.dpr)
    screens = sorted([r for r in roots if r.cls == "ScreenGui" and r.p.get("Enabled", True)],
                     key=lambda r: (r.p.get("DisplayOrder", 0), r.id))
    rend = Renderer(engine, painter, args.debug)
    for r in screens:
        rend.draw_tree(r)
    if not args.no_backdrop:
        draw_backdrop(painter, engine.vw, engine.vh)
    draw_insets(painter, engine.vw, engine.vh, engine.insets)
    img = painter.img.resize((engine.vw * args.dpr, engine.vh * args.dpr), Image.LANCZOS) if args.ss != 1 else painter.img
    img = stamp(img, [LABEL] + meta_lines, args.dpr)
    img.convert("RGB").save(out)
    return img


def render_strip(nodes, engine, args, name, out, meta_lines):
    target = next((n for n in nodes if n.cls == "ScrollingFrame" and n.name == name and n.abs[2] > 0), None)
    if target is None:
        print(f"strip: no visible ScrollingFrame named {name!r}", file=sys.stderr)
        return None
    k = target.k
    cw, chh = target.canvas_size
    W, H = int(math.ceil(target.abs[2])), int(math.ceil(chh * k))
    painter = Painter(W, H, args.ss * args.dpr)
    # background: nearest ancestor with an opaque-ish background
    bg = (20, 24, 28)
    a = target.parent
    while a is not None:
        if float(a.p.get("BackgroundTransparency", 1)) < 0.5:
            bg = c3(a.p.get("BackgroundColor3"))
            break
        a = a.parent
    painter.img = Image.new("RGBA", (painter.W, painter.H), bg + (255,))
    pt_, pr, pb, pl = target.padding(*target.size_u)
    clip = (0, 0, W, H)
    for c in engine.visible_children(target):
        engine.place(c, pl * k, pt_ * k, k, clip)
    rend = Renderer(engine, painter, args.debug)
    rend.draw_children(target)
    img = painter.img.resize((W * args.dpr, H * args.dpr), Image.LANCZOS) if args.ss != 1 else painter.img
    img = stamp(img, [LABEL, f"full scroll canvas of '{name}' ({int(cw * k)}x{H}px at UI scale {k:.3f})"] + meta_lines, args.dpr)
    img.convert("RGB").save(out)
    return img


def render_world_sheet(roots, engine, args, out, meta_lines):
    """Billboard/SurfaceGuis drawn standalone, side by side, each on its part colour / a neutral backdrop"""
    world = [r for r in roots if r.cls in ("BillboardGui", "SurfaceGui")]
    if not world:
        return None
    tiles = []
    for r in world:
        engine.run_root(r)
        w, h = r.abs[2], r.abs[3]
        margin = 24
        painter = Painter(max(w + 2 * margin, 460), h + 2 * margin + 18, args.ss)
        part = r.d.get("part") or {}
        if r.cls == "SurfaceGui":
            bgc = c3(part.get("Color"), (160, 160, 160))
            back = (70, 78, 86)
        else:
            bgc = None
            back = (120, 150, 180)
        painter.img = Image.new("RGBA", (painter.W, painter.H), back + (255,))
        if bgc:
            d = ImageDraw.Draw(painter.img)
            d.rectangle([margin * args.ss, margin * args.ss, (margin + w) * args.ss - 1, (margin + h) * args.ss - 1], fill=bgc + (255,))
        engine.run_root(r, origin=(margin, margin))
        Renderer(engine, painter, args.debug).draw_tree(r)
        d = ImageDraw.Draw(painter.img)
        f = get_font(font_path(FONT_FILES[("sans", False, False)]), 11 * args.ss)
        if r.cls == "BillboardGui":
            s = r.p.get("Size", [0, 0, 0, 0])
            cap = f"{r.cls} '{r.name}' on {part.get('name', '?')}: {s[0]:g}x{s[2]:g} studs at {engine.ppstud} px/stud"
        else:
            cap = f"{r.cls} '{r.name}' on {part.get('name', '?')} ({r.p.get('Face')}), {int(w)}x{int(h)} px ({r.p.get('SizingMode')} {r.p.get('PixelsPerStud', '')})"
        d.text((margin * args.ss, (margin + h + 4) * args.ss), cap, font=f, fill=(240, 240, 240, 255))
        img = painter.img.resize((painter.W // args.ss, painter.H // args.ss), Image.LANCZOS)
        tiles.append(img)
    W = max(t.size[0] for t in tiles) + 20
    H = sum(t.size[1] for t in tiles) + 10 * (len(tiles) + 1) + 40
    sheet = Image.new("RGBA", (max(W, 560), H), (40, 44, 50, 255))
    y = 10
    for t in tiles:
        sheet.alpha_composite(t, (10, y))
        y += t.size[1] + 10
    sheet = stamp(sheet, [LABEL] + meta_lines)
    sheet.convert("RGB").save(out)
    return sheet


def parse_viewport(s):
    if s in PRESETS:
        return PRESETS[s]
    m = re.match(r"(\d+)x(\d+)$", s)
    if not m:
        raise SystemExit("--viewport WxH or desktop/phone")
    return (int(m.group(1)), int(m.group(2))), None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--scene", help="Luau scene script that builds the UI in the mock and calls GuiDump.dump")
    ap.add_argument("--state", default="default", help="scene state argument")
    ap.add_argument("--from-json", help="render a saved dump (stdout of a scene) instead of running a scene")
    ap.add_argument("--viewport", default="desktop", help="WxH or preset: desktop (1280x720), phone (844x390)")
    ap.add_argument("--insets", help="top,right,bottom,left px for CoreUISafeInsets ScreenGuis (default per preset: 58,0,0,0)")
    ap.add_argument("--out", required=True, help="output PNG")
    ap.add_argument("--strip", action="append", default=[], help="also render the full canvas of this ScrollingFrame (name) -> <out>_strip_<name>.png")
    ap.add_argument("--passes", type=int, default=3, help="AbsoluteSize feedback passes (re-run scene with computed sizes)")
    ap.add_argument("--ss", type=int, default=2, help="supersampling factor")
    ap.add_argument("--dpr", type=int, default=1, help="device pixel ratio of the output (2 = phone retina-like, same layout)")
    ap.add_argument("--ppstud", type=float, default=40, help="pixels per stud for BillboardGuis")
    ap.add_argument("--src", default=os.path.join(ROOT, "work", "src"))
    ap.add_argument("--gen", default=os.path.join(ROOT, "harness", ".gen_guiprev"))
    ap.add_argument("--no-manifest", action="store_true", help="skip make_manifest.py")
    ap.add_argument("--save-dump", help="write the final scene output (dump lines) here")
    ap.add_argument("--no-backdrop", action="store_true")
    ap.add_argument("--debug", action="store_true", help="outline every GuiObject")
    ap.add_argument("--report", action="store_true", help="print a layout report (overflow / clipped / overlapping text)")
    ap.add_argument("extra", nargs="*", help="extra scene args")
    args = ap.parse_args()

    (vw, vh), preset_insets = parse_viewport(args.viewport)
    insets = tuple(int(v) for v in args.insets.split(",")) if args.insets else (preset_insets or (58, 0, 0, 0))
    out = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    warnings = []

    if args.from_json:
        with open(args.from_json) as f:
            lines = f.read().splitlines()
        passes = 1
    else:
        if not args.scene:
            raise SystemExit("--scene or --from-json required")
        if not args.no_manifest:
            subprocess.run([sys.executable, MAKE_MANIFEST, "--src", args.src, "--gen", args.gen], check=True,
                           capture_output=True)
        passes = max(1, args.passes)
    fb_path = None
    prev_fb = None
    for i in range(passes):
        if not args.from_json:
            lines = run_scene(args.scene, args.gen, args.state, (vw, vh), insets, fb_path, args.extra)
        roots, nodes, meta, errors, logs = load_nodes(lines)
        for e in errors:
            print(e, file=sys.stderr)
        engine = Engine((vw, vh), insets, ppstud=args.ppstud, warnings=warnings)
        for r in roots:
            if r.cls == "ScreenGui":
                engine.run_root(r)
        if args.from_json:
            break
        tag = re.sub(r"[^A-Za-z0-9_]+", "_", os.path.basename(out))
        fb_path = os.path.join(CACHE, f"fb_{tag}.luau")
        fb = write_feedback(fb_path, [n for n in nodes if n.abs[2] or n.abs[3]])
        if fb == prev_fb:
            break
        prev_fb = fb
    if args.save_dump:
        with open(args.save_dump, "w") as f:
            f.write("\n".join(lines) + "\n")
    scene_name = os.path.splitext(os.path.basename(args.scene or args.from_json))[0]
    extra = (" / " + " ".join(args.extra)) if args.extra else ""
    meta_lines = [f"scene {scene_name} / state {args.state}{extra} / viewport {vw}x{vh} / insets t{insets[0]} r{insets[1]} b{insets[2]} l{insets[3]} / passes {i + 1}"]
    screens = [r for r in roots if r.cls == "ScreenGui"]
    written = []
    if args.report:
        report(nodes, engine)
    if screens:
        render_screen(roots, engine, args, meta_lines, out)
        written.append(out)
        for name in args.strip:
            so = os.path.splitext(out)[0] + f"_strip_{name}.png"
            if render_strip(nodes, engine, args, name, so, meta_lines):
                written.append(so)
    if any(r.cls in ("BillboardGui", "SurfaceGui") for r in roots):
        wo = out if not screens else os.path.splitext(out)[0] + "_world.png"
        render_world_sheet(roots, engine, args, wo, [f"scene {scene_name} / state {args.state}{extra} / world GUIs drawn standalone (BillboardGui at {args.ppstud:g} px/stud, SurfaceGui at its own canvas size)"])
        written.append(wo)
    for w in sorted(set(warnings)):
        print("warn:", w, file=sys.stderr)
    for w in written:
        print(w)


# ------------------------------------------------------------------------------------------------ report
def report(nodes, engine):
    """heuristic checks: text wider than its box, things outside the viewport, overlapping sibling text"""
    for n in nodes:
        if n.is_root or n.abs[2] <= 0:
            continue
        chain_visible = True
        a = n
        while a is not None:
            if not a.visible:
                chain_visible = False
            a = a.parent
        if not chain_visible:
            continue
        x, y, w, h = n.abs
        if n.is_text and n.text_block and n.p.get("Text"):
            pt_, pr, pb, pl = n.padding(*n.size_u)
            inner_w = (n.size_u[0] - pl - pr)
            inner_h = (n.size_u[1] - pt_ - pb)
            if n.text_block.width > inner_w + 1 and n.p.get("TextTruncate", "None") == "None":
                print(f"text overflow X  {n.path}: text {n.text_block.width:.0f} > box {inner_w:.0f}  {n.p.get('Text')!r}")
            if n.text_block.height > inner_h + 1:
                print(f"text overflow Y  {n.path}: text {n.text_block.height:.0f} > box {inner_h:.0f}  {n.p.get('Text')!r}")
        if n.clip is not None:
            cx, cy, cw, ch = n.clip
            if (x + w > cx + cw + 1 or y + h > cy + ch + 1 or x < cx - 1 or y < cy - 1) and not _inside_scroll(n):
                print(f"clipped          {n.path}: {tuple(round(v) for v in n.abs)} vs clip {tuple(round(v) for v in n.clip)}")
    # overlapping visible text labels with different parents' siblings
    texts = [n for n in nodes if n.is_text and n.p.get("Text") and n.abs[2] > 0 and _vis(n)]
    for i, a in enumerate(texts):
        ra = _text_rect(a)
        for b in texts[i + 1:]:
            rb = _text_rect(b)
            if ra and rb and _overlap(ra, rb) > 4 and not _is_ancestor(a, b) and not _is_ancestor(b, a):
                print(f"text overlap     {a.path} {a.p.get('Text')!r}  <->  {b.path} {b.p.get('Text')!r}")


def _vis(n):
    while n is not None:
        if not n.visible:
            return False
        n = n.parent
    return True


def _inside_scroll(n):
    a = n.parent
    while a is not None:
        if a.cls == "ScrollingFrame":
            return True
        a = a.parent
    return False


def _is_ancestor(a, b):
    p = b.parent
    while p is not None:
        if p is a:
            return True
        p = p.parent
    return False


def _text_rect(n):
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
    if n.clip is not None:
        r = intersect(n.clip, (tx, ty, tw, th))
        return r if r[2] > 0 and r[3] > 0 else None
    return (tx, ty, tw, th)


def _overlap(a, b):
    r = intersect(a, b)
    return r[2] * r[3] if r[2] > 0 and r[3] > 0 else 0


if __name__ == "__main__":
    main()
