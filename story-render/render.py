#!/usr/bin/env python3
"""
Insta-Story Renderer v2 — 2.5D-Parallax statt flachem Ken-Burns.

Ablauf:
    Phase 1  Upscale            (Lanczos + Unsharp; siehe README zu Real-ESRGAN)
    Phase 2  Tiefenkarte        (Depth Anything V2, bilateral geglättet,
                                 dunkler Vordergrund auf "nah" geklemmt)
    Phase 3  Parallax-Fahrt     (N Tiefenschichten, ease-in-out, Motion Blur)
    Phase 4  Licht              (lokale Glows auf erkannten Lampen, dezentes Flackern)
    Phase 5  Atmosphäre         (Haze-Band, optional Sterne)
    Phase 6  Schnitt            (3 Shots, Crossfades, Fades, exakt 15.0 s)

Aufruf:
    python3 render.py                 # kompletter Durchlauf
    python3 render.py --preview       # 30 fps, kein Motion Blur (schneller QC)
    python3 render.py --qc-only       # nur Debug-PNGs + QC-Frames, kein Video
"""
from __future__ import annotations

import argparse
import json
import math
import zlib
import os
import subprocess
import sys
import time
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

import config as C

ROOT = Path(__file__).resolve().parent
SRC_DIR = ROOT / "src"
OUT_DIR = ROOT / "out"
WORK_DIR = OUT_DIR / "work"
QC_DIR = OUT_DIR / "qc"


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def ffmpeg_bin() -> str:
    for cand in ("ffmpeg", "/usr/bin/ffmpeg"):
        if subprocess.run(["which", cand], capture_output=True).returncode == 0:
            return cand
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


# =============================================================== Phase 1 =====
def upscale(path: Path) -> np.ndarray:
    """Lanczos-Upscale + dezentes Unsharp. Gibt BGR uint8 zurück."""
    img = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if img is None:
        raise FileNotFoundError(path)
    h, w = img.shape[:2]
    big = cv2.resize(img, (w * C.UPSCALE, h * C.UPSCALE), interpolation=cv2.INTER_LANCZOS4)

    blur = cv2.GaussianBlur(big, (0, 0), C.UNSHARP_RADIUS)
    sharp = cv2.addWeighted(big, 1.0 + C.UNSHARP_AMOUNT, blur, -C.UNSHARP_AMOUNT, 0)
    return np.clip(sharp, 0, 255).astype(np.uint8)


# =============================================================== Phase 2 =====
_DEPTH_PIPE = None


def depth_pipeline():
    global _DEPTH_PIPE
    if _DEPTH_PIPE is None:
        from transformers import pipeline
        log(f"Lade Depth-Modell {C.DEPTH_MODEL} ...")
        _DEPTH_PIPE = pipeline("depth-estimation", model=C.DEPTH_MODEL, device="cpu")
    return _DEPTH_PIPE


def estimate_depth(img_bgr: np.ndarray) -> np.ndarray:
    """
    Tiefenkarte als float32 in [0,1], 1.0 = nah.

    Depth Anything liefert inverse Tiefe (großer Wert = nah). Die Polarität wird
    unten gegen die Bildgeometrie gegengeprüft und notfalls gedreht.
    """
    h, w = img_bgr.shape[:2]
    scale = C.DEPTH_MAX_SIDE / max(h, w)
    dh, dw = int(round(h * scale / 14)) * 14, int(round(w * scale / 14)) * 14
    small = cv2.resize(img_bgr, (dw, dh), interpolation=cv2.INTER_AREA)
    pil = Image.fromarray(cv2.cvtColor(small, cv2.COLOR_BGR2RGB))

    out = depth_pipeline()(pil)
    raw = out["predicted_depth"].detach().cpu().numpy().astype(np.float32)
    if raw.ndim == 3:
        raw = raw[0]

    lo, hi = np.percentile(raw, 1.0), np.percentile(raw, 99.0)
    d = np.clip((raw - lo) / max(hi - lo, 1e-6), 0.0, 1.0)

    # Sanity-Check der Polarität: die obere Bildhälfte ist bei diesen Motiven
    # Himmel (fern), die untere Balkon/Dach (nah).
    if d[: dh // 3].mean() > d[-dh // 3:].mean():
        log("  Polarität gedreht (oben war 'näher' als unten)")
        d = 1.0 - d

    return cv2.resize(d, (w, h), interpolation=cv2.INTER_LINEAR)


def refine_depth(depth: np.ndarray, img_bgr: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Bilateral glätten + schwarzen Vordergrund als eine Ebene klemmen."""
    d = cv2.bilateralFilter(
        depth, C.BILATERAL_D, C.BILATERAL_SIGMA_COLOR / 255.0, C.BILATERAL_SIGMA_SPACE
    )

    luma = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY).astype(np.float32) / 255.0
    luma = cv2.GaussianBlur(luma, (0, 0), 3.0)
    dark = (luma < C.DARK_LUMA_THRESHOLD).astype(np.uint8)

    k = np.ones((C.DARK_CLOSE_KERNEL, C.DARK_CLOSE_KERNEL), np.uint8)
    dark = cv2.morphologyEx(dark, cv2.MORPH_CLOSE, k)
    dark = cv2.morphologyEx(dark, cv2.MORPH_OPEN, np.ones((7, 7), np.uint8))

    # Nur große zusammenhängende Dunkelflächen klemmen, die am UNTEREN Bildrand
    # hängen. Der Nachthimmel ist genauso dunkel wie der Balkon — ohne diese
    # Bedingung würde er als "nah" geklemmt und beim Parallax über die Hügel-
    # kante wandern. Der blinde Vordergrund ist der, der unten rausläuft.
    h_img = dark.shape[0]
    n, labels, stats, _ = cv2.connectedComponentsWithStats(dark, 8)
    keep = np.zeros_like(dark)
    for i in range(1, n):
        if stats[i, cv2.CC_STAT_AREA] < C.DARK_MIN_REGION:
            continue
        y0 = stats[i, cv2.CC_STAT_TOP]
        y1 = y0 + stats[i, cv2.CC_STAT_HEIGHT]
        touches_bottom = y1 >= h_img - C.DARK_BOTTOM_TOL
        starts_low = y0 >= h_img * C.DARK_MIN_TOP_FRAC
        if touches_bottom and starts_low:
            keep[labels == i] = 1

    soft = cv2.GaussianBlur(keep.astype(np.float32), (0, 0), 9.0)
    d = d * (1.0 - soft) + C.DARK_CLAMP_DEPTH * soft
    return np.clip(d, 0.0, 1.0), keep


def write_depth_debug(depth: np.ndarray, dark: np.ndarray, name: str) -> None:
    vis = (np.clip(depth, 0, 1) * 255).astype(np.uint8)
    vis = cv2.applyColorMap(vis, cv2.COLORMAP_MAGMA)
    edge = cv2.dilate(dark, np.ones((3, 3), np.uint8)) - dark
    vis[edge > 0] = (80, 255, 80)          # grüne Kontur = geklemmter Vordergrund
    small = cv2.resize(vis, (vis.shape[1] // 2, vis.shape[0] // 2), interpolation=cv2.INTER_AREA)
    cv2.imwrite(str(QC_DIR / f"depth_{name}.png"), small)


# =============================================================== Phase 3 =====
def build_layers(img_bgr: np.ndarray, depth: np.ndarray) -> list[dict]:
    """
    Zerlegt das Bild in N Tiefenschichten.

    Pro Schicht:
      rgba  — Farbe + weiche Alphamaske. Der Ring um die Maske wird mit
              cv2.inpaint (Telea) gefüllt, damit die weiche Kante beim
              Verschieben keine Farbe der Nachbarschicht mitschleift.
      p     — Parallaxfaktor (0 = fern, 1 = nah)
      bbox  — Quell-Bounding-Box, begrenzt die Warp-Kosten
    """
    h, w = depth.shape
    edges = np.linspace(0.0, 1.0, C.N_LAYERS + 1)
    layers = []

    for i in range(C.N_LAYERS):
        lo, hi = edges[i], edges[i + 1]
        band = ((depth >= lo) & (depth < hi if i < C.N_LAYERS - 1 else depth <= hi))
        band_u8 = band.astype(np.uint8)
        if band_u8.sum() < 500:
            continue

        ring = cv2.dilate(band_u8, np.ones((C.LAYER_INPAINT_RING, C.LAYER_INPAINT_RING), np.uint8))
        ring_only = (ring - band_u8).astype(np.uint8)

        color = cv2.inpaint(img_bgr, ring_only, C.INPAINT_RADIUS, cv2.INPAINT_TELEA)

        alpha = cv2.GaussianBlur(band_u8.astype(np.float32) * 255.0, (0, 0), C.LAYER_FEATHER / 3.0)
        alpha = np.clip(alpha, 0, 255).astype(np.uint8)

        rgba = np.dstack([color, alpha])

        ys, xs = np.nonzero(ring)
        pad = C.LAYER_FEATHER * 2
        bbox = (
            max(int(xs.min()) - pad, 0), max(int(ys.min()) - pad, 0),
            min(int(xs.max()) + pad, w - 1), min(int(ys.max()) + pad, h - 1),
        )
        layers.append(dict(p=float((lo + hi) / 2.0), rgba=rgba, bbox=bbox))

    layers.sort(key=lambda L: L["p"])          # fern -> nah
    return layers


def ease(t: float) -> float:
    """Ease-in-out mit linearem Sockel, damit die Fahrt nie ganz stillsteht."""
    s = 0.5 - 0.5 * math.cos(math.pi * t)
    return (1.0 - C.EASE_LINEAR_MIX) * s + C.EASE_LINEAR_MIX * t


def camera_matrix(shot: dict, u: float, p: float, src_shape: tuple[int, int]) -> np.ndarray:
    """
    Affine Quelle -> Ausgabe für eine Schicht mit Parallaxfaktor p.

    Nahe Schichten bekommen mehr Zoom (Dolly) und mehr Versatz (Parallaxe).
    """
    sh, sw = src_shape
    e = ease(u)

    z = shot["zoom"][0] + (shot["zoom"][1] - shot["zoom"][0]) * e
    z_layer = z * (1.0 + shot["dolly_gain"] * (p - 0.5))

    k = C.OUT_W * z_layer / sw                 # Quellpixel -> Ausgabepixel

    # Verfügbarer Spielraum in Ausgabepixeln, bevor der Rand ins Bild läuft
    mx = max((sw * k - C.OUT_W) * 0.5, 0.0)
    my = max((sh * k - C.OUT_H) * 0.5, 0.0)

    cx = shot["cx"][0] + (shot["cx"][1] - shot["cx"][0]) * e
    cy = shot["cy"][0] + (shot["cy"][1] - shot["cy"][0]) * e

    # Parallaxe: proportional zu p, über den Shot ein-/ausgeblendet
    par_x = shot["par_x"] * C.OUT_W * (e - 0.5) * p
    par_y = shot["par_y"] * C.OUT_W * (e - 0.5) * p

    tx = C.OUT_W * 0.5 - (sw * 0.5) * k - cx * mx + par_x
    ty = C.OUT_H * 0.5 - (sh * 0.5) * k - cy * my + par_y

    return np.array([[k, 0.0, tx], [0.0, k, ty]], dtype=np.float32)


def warp_into(dst: np.ndarray, layer: dict, M: np.ndarray) -> None:
    """Warpt eine Schicht und alphablendet sie in dst (float32, 0..1)."""
    x0, y0, x1, y1 = layer["bbox"]
    corners = np.array([[x0, y0], [x1, y0], [x0, y1], [x1, y1]], dtype=np.float32)
    pts = corners @ M[:, :2].T + M[:, 2]

    ox0 = max(int(np.floor(pts[:, 0].min())) - 2, 0)
    oy0 = max(int(np.floor(pts[:, 1].min())) - 2, 0)
    ox1 = min(int(np.ceil(pts[:, 0].max())) + 2, C.OUT_W)
    oy1 = min(int(np.ceil(pts[:, 1].max())) + 2, C.OUT_H)
    if ox1 <= ox0 or oy1 <= oy0:
        return

    M2 = M.copy()
    M2[0, 2] -= ox0
    M2[1, 2] -= oy0

    patch = cv2.warpAffine(
        layer["rgba"], M2, (ox1 - ox0, oy1 - oy0),
        flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE,
    )

    a = patch[:, :, 3].astype(np.float32) * (1.0 / 255.0)
    a = a[:, :, None]
    roi = dst[oy0:oy1, ox0:ox1]
    np.multiply(roi, 1.0 - a, out=roi)
    roi += patch[:, :, :3].astype(np.float32) * (1.0 / 255.0) * a


# =============================================================== Phase 4 =====
def detect_lights(img_bgr: np.ndarray, depth: np.ndarray) -> list[dict]:
    """
    Isoliert kompakte helle Regionen (Lampen, beleuchtete Fenster).
    Große helle Flächen (Hauswand) fallen über Fläche/Kompaktheit raus.
    """
    luma = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY).astype(np.float32) / 255.0
    mask = (luma > C.LIGHT_LUMA_THRESHOLD).astype(np.uint8)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))

    n, labels, stats, cent = cv2.connectedComponentsWithStats(mask, 8)
    rng = np.random.default_rng(1234)
    lights = []

    for i in range(1, n):
        area = int(stats[i, cv2.CC_STAT_AREA])
        bw, bh = int(stats[i, cv2.CC_STAT_WIDTH]), int(stats[i, cv2.CC_STAT_HEIGHT])
        if not (C.LIGHT_MIN_AREA <= area <= C.LIGHT_MAX_AREA):
            continue
        if max(bw, bh) > C.LIGHT_MAX_EXTENT:
            continue
        if area / float(max(bw * bh, 1)) < C.LIGHT_MIN_FILL:
            continue

        cx, cy = float(cent[i][0]), float(cent[i][1])
        xi, yi = int(round(cx)), int(round(cy))
        col = img_bgr[
            max(yi - 2, 0):yi + 3, max(xi - 2, 0):xi + 3
        ].reshape(-1, 3).mean(axis=0)
        col = col / max(col.max(), 1.0)

        r = float(np.clip(math.sqrt(area) * C.GLOW_RADIUS_SCALE,
                          C.GLOW_RADIUS_MIN, C.GLOW_RADIUS_MAX))
        lights.append(dict(
            x=cx, y=cy, r=r,
            p=float(depth[yi, xi]),
            color=col.astype(np.float32),
            freq=float(rng.uniform(*C.FLICKER_FREQ)),
            phase=float(rng.uniform(0, 2 * math.pi)),
            weight=float(np.clip(area / 120.0, 0.35, 1.0)),
        ))

    lights.sort(key=lambda L: -L["r"])
    return lights[: C.LIGHT_MAX_COUNT]


_SPRITES: dict[int, np.ndarray] = {}


def glow_sprite(radius: int) -> np.ndarray:
    if radius not in _SPRITES:
        n = radius * 2 + 1
        yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
        d = np.sqrt((xx - radius) ** 2 + (yy - radius) ** 2) / radius
        s = np.clip(1.0 - d, 0.0, 1.0) ** C.GLOW_FALLOFF
        _SPRITES[radius] = s.astype(np.float32)
    return _SPRITES[radius]


def draw_glows(frame: np.ndarray, lights: list[dict], shot: dict, u: float,
               t_abs: float, src_shape: tuple[int, int]) -> None:
    """Additiver lokaler Glow — bewusst NICHT flächig über den ganzen Frame."""
    for L in lights:
        M = camera_matrix(shot, u, L["p"], src_shape)
        x = M[0, 0] * L["x"] + M[0, 2]
        y = M[1, 1] * L["y"] + M[1, 2]

        r = int(round(L["r"] * M[0, 0]))
        if r < 3:
            continue
        r = min(r, C.GLOW_RADIUS_MAX)

        xi, yi = int(round(x)), int(round(y))
        if xi < -r or yi < -r or xi > C.OUT_W + r or yi > C.OUT_H + r:
            continue

        flick = 1.0 + C.FLICKER_AMP * math.sin(2 * math.pi * L["freq"] * t_abs + L["phase"])
        amp = C.GLOW_STRENGTH * L["weight"] * flick

        sp = glow_sprite(r)
        x0, y0 = max(xi - r, 0), max(yi - r, 0)
        x1, y1 = min(xi + r + 1, C.OUT_W), min(yi + r + 1, C.OUT_H)
        if x1 <= x0 or y1 <= y0:
            continue
        sx0, sy0 = x0 - (xi - r), y0 - (yi - r)
        patch = sp[sy0:sy0 + (y1 - y0), sx0:sx0 + (x1 - x0)]

        frame[y0:y1, x0:x1] += patch[:, :, None] * (L["color"][None, None, :] * amp)


# =============================================================== Phase 5 =====
def fractal_noise(h: int, w: int, scale: int, octaves: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    acc = np.zeros((h, w), np.float32)
    amp, tot, s = 1.0, 0.0, scale
    for _ in range(octaves):
        gh, gw = max(int(h / s) + 2, 2), max(int(w / s) + 2, 2)
        g = rng.random((gh, gw)).astype(np.float32)
        acc += cv2.resize(g, (w, h), interpolation=cv2.INTER_CUBIC) * amp
        tot += amp
        amp *= 0.5
        s = max(s // 2, 4)
    return acc / tot


def make_haze(seed: int) -> np.ndarray:
    margin = 256
    return fractal_noise(C.OUT_H + margin, C.OUT_W + margin, C.HAZE_SCALE, C.HAZE_OCTAVES, seed)


def apply_haze(frame: np.ndarray, canvas: np.ndarray, depth_out: np.ndarray, t: float) -> None:
    """Feiner driftender Haze, screen-geblendet, nur im Horizontband und nur fern."""
    ox = int(C.HAZE_DRIFT[0] * t) % 200
    oy = int(C.HAZE_DRIFT[1] * t) % 200
    n = canvas[oy:oy + C.OUT_H, ox:ox + C.OUT_W]

    yy = np.linspace(0.0, 1.0, C.OUT_H, dtype=np.float32)[:, None]
    band = np.exp(-((yy - C.HAZE_BAND_CENTER) ** 2) / (2 * C.HAZE_BAND_WIDTH ** 2))

    far = np.clip((C.HAZE_DEPTH_MAX - depth_out) / C.HAZE_DEPTH_MAX, 0.0, 1.0)

    a = (n * band * far * C.HAZE_OPACITY)[:, :, None]
    # Screen-Blend: 1-(1-a)(1-b), hier mit neutral-kaltem Grau statt Weiß,
    # damit der Himmel nicht ins Magenta kippt.
    tint = np.array([0.72, 0.70, 0.66], np.float32)
    np.copyto(frame, 1.0 - (1.0 - frame) * (1.0 - a * tint))


def make_stars(seed: int) -> list[dict]:
    rng = np.random.default_rng(seed)
    return [dict(
        x=float(rng.uniform(0, C.OUT_W)),
        y=float(rng.uniform(0, C.OUT_H * C.STAR_REGION)),
        b=float(rng.uniform(0.25, 1.0)) * C.STAR_MAX_BRIGHT,
        f=float(rng.uniform(0.05, 0.25)),
        ph=float(rng.uniform(0, 2 * math.pi)),
    ) for _ in range(C.STAR_COUNT)]


def draw_stars(frame: np.ndarray, stars: list[dict], t: float) -> None:
    for s in stars:
        tw = 1.0 + C.STAR_TWINKLE * math.sin(2 * math.pi * s["f"] * t + s["ph"])
        xi, yi = int(s["x"]), int(s["y"])
        if 1 <= xi < C.OUT_W - 1 and 1 <= yi < C.OUT_H - 1:
            frame[yi - 1:yi + 2, xi - 1:xi + 2] += s["b"] * tw * 0.25
            frame[yi, xi] += s["b"] * tw


# =============================================================== Rendering ===
class ShotRenderer:
    def __init__(self, shot: dict, subframes: int, fps: int):
        self.shot = shot
        self.subframes = max(subframes, 1)
        self.fps = fps
        name = shot["name"]

        log(f"Shot {name}: Upscale ...")
        self.img = upscale(SRC_DIR / shot["src"])
        self.src_shape = self.img.shape[:2]

        cache = WORK_DIR / f"depth_{name}.npy"
        dark_cache = WORK_DIR / f"dark_{name}.npy"
        if cache.exists() and dark_cache.exists():
            log(f"Shot {name}: Tiefenkarte aus Cache")
            depth, dark = np.load(cache), np.load(dark_cache)
        else:
            log(f"Shot {name}: Tiefenkarte ...")
            depth = estimate_depth(self.img)
            depth, dark = refine_depth(depth, self.img)
            np.save(cache, depth)
            np.save(dark_cache, dark)
        self.depth = depth
        write_depth_debug(depth, dark, name)

        log(f"Shot {name}: Schichten ...")
        self.layers = build_layers(self.img, depth)

        log(f"Shot {name}: Lichter ...")
        self.lights = detect_lights(self.img, depth)
        log(f"  {len(self.layers)} Schichten, {len(self.lights)} Lichtquellen")

        self.haze = make_haze(zlib.crc32(name.encode()) % 9999) if C.HAZE_ENABLED else None
        self.stars = make_stars(zlib.crc32(name.encode()) % 7777) if C.ADD_STARS else None
        self._depth_small = cv2.resize(depth, (C.OUT_W // 4, C.OUT_H // 4),
                                       interpolation=cv2.INTER_AREA)

    def _compose(self, u: float, t_abs: float) -> np.ndarray:
        """Ein (Sub-)Frame: Basis + Schichten + Licht."""
        far_p = self.layers[0]["p"]
        M_base = camera_matrix(self.shot, u, far_p, self.src_shape)
        base = cv2.warpAffine(
            self.img, M_base, (C.OUT_W, C.OUT_H),
            flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE,
        )
        frame = base.astype(np.float32) * (1.0 / 255.0)

        for layer in self.layers:
            warp_into(frame, layer, camera_matrix(self.shot, u, layer["p"], self.src_shape))

        draw_glows(frame, self.lights, self.shot, u, t_abs, self.src_shape)
        return frame

    def frame(self, i: int, n_frames: int, t_shot_start: float) -> np.ndarray:
        """Ausgabeframe inkl. Motion Blur, Haze und Sternen."""
        span = C.SUBFRAME_SPREAD / max(n_frames - 1, 1)
        acc = None
        for s in range(self.subframes):
            off = 0.0 if self.subframes == 1 else (s / (self.subframes - 1) - 0.5) * span
            u = min(max(i / max(n_frames - 1, 1) + off, 0.0), 1.0)
            t_abs = t_shot_start + i / self.fps
            f = self._compose(u, t_abs)
            acc = f if acc is None else acc + f
        frame = acc / self.subframes

        if self.haze is not None:
            u = i / max(n_frames - 1, 1)
            M = camera_matrix(self.shot, u, 0.5, self.src_shape)
            d_out = cv2.warpAffine(self.depth, M, (C.OUT_W, C.OUT_H),
                                   flags=cv2.INTER_NEAREST, borderMode=cv2.BORDER_REPLICATE)
            apply_haze(frame, self.haze, d_out, t_shot_start + i / self.fps)

        if self.stars is not None:
            draw_stars(frame, self.stars, t_shot_start + i / self.fps)

        return np.clip(frame, 0.0, 1.0)


# =============================================================== QC ==========
def qc_parallax(shot: dict, src_shape: tuple[int, int]) -> float:
    """
    Misst den Versatz zwischen nächster und fernster Schicht — und zwar nur an
    Punkten, die tatsächlich im Bild landen. Die Ecken der Quelle liegen bei
    Zoom > 1 außerhalb des Frames und würden den Wert künstlich aufblähen.
    """
    worst = 0.0
    corners = [(0, 0), (C.OUT_W, 0), (0, C.OUT_H), (C.OUT_W, C.OUT_H),
               (C.OUT_W / 2, C.OUT_H / 2)]
    for u in np.linspace(0, 1, 21):
        M0 = camera_matrix(shot, float(u), 0.0, src_shape)
        M1 = camera_matrix(shot, float(u), 1.0, src_shape)
        for ox, oy in corners:
            # Sichtbare Ecke zurück in Quellkoordinaten (über die ferne Schicht)
            sx = (ox - M0[0, 2]) / M0[0, 0]
            sy = (oy - M0[1, 2]) / M0[1, 1]
            a = np.array([ox, oy], np.float32)
            b = np.array([M1[0, 0] * sx + M1[0, 2], M1[1, 1] * sy + M1[1, 2]], np.float32)
            worst = max(worst, float(np.hypot(*(a - b))))
    return worst / C.OUT_W


def black_fraction(frame: np.ndarray) -> float:
    luma = frame @ np.array([0.114, 0.587, 0.299], np.float32)
    return float((luma < C.BLACK_LUMA).mean())


def sky_hue(frame: np.ndarray) -> tuple[float, float]:
    """Mittlerer Farbton der oberen Bildhälfte (OpenCV-H in 0..179) + Sättigung."""
    top = (frame[: C.OUT_H // 3] * 255).astype(np.uint8)
    hsv = cv2.cvtColor(top, cv2.COLOR_BGR2HSV)
    m = hsv[:, :, 2] > 12
    if m.sum() == 0:
        return -1.0, 0.0
    return float(hsv[:, :, 0][m].mean()), float(hsv[:, :, 1][m].mean())


# =============================================================== Encode ======
def grade_filter(total_frames: int, fps: int) -> str:
    """
    Vollständige Ausgabekette.

    Reihenfolge ist hier der entscheidende Punkt:
      1. Grading (aus v1 übernommen)
      2. Schattensockel — MUSS nach dem Grading kommen. eq=contrast und
         vignette drücken einen vorher gesetzten Sockel wieder unter die
         Schwarzgrenze (gemessen: 0 % vorher, 48 % nachher).
      3. Korn
      4. Blenden — ganz zum Schluss, damit Anfang und Ende trotz Sockel
         echtes Schwarz erreichen.
    """
    chain = []
    s = C.GRADE_STRENGTH
    if C.GRADE_ENABLED and s > 0:
        contrast = 1.0 + (C.GRADE_CONTRAST - 1.0) * s
        sat = 1.0 + (C.GRADE_SATURATION - 1.0) * s
        chain.append(f"eq=contrast={contrast:.4f}:saturation={sat:.4f}")
        chain.append(f"curves=b='0/{0.02 * s:.4f} 0.5/0.5 1/1'")
        chain.append(f"vignette={C.GRADE_VIGNETTE}*{s:.3f}")

    if C.SHADOW_LIFT > 0:
        b, g, r = (C.SHADOW_LIFT * t for t in C.SHADOW_TINT)
        knee = C.SHADOW_KNEE
        chain.append(
            f"curves=r='0/{r:.4f} {knee}/{knee} 1/1'"
            f":g='0/{g:.4f} {knee}/{knee} 1/1'"
            f":b='0/{b:.4f} {knee}/{knee} 1/1'"
        )

    if C.GRADE_ENABLED and s > 0:
        chain.append(f"noise=alls={max(int(round(4 * s)), 1)}:allf=t+u")

    out_start = (total_frames / fps) - C.FADE_OUT
    chain.append(f"fade=t=in:st=0:d={C.FADE_IN}")
    chain.append(f"fade=t=out:st={out_start:.4f}:d={C.FADE_OUT}")
    return ",".join(chain) if chain else "null"


def open_encoder(path: Path, fps: int, total_frames: int) -> subprocess.Popen:
    cmd = [
        ffmpeg_bin(), "-y", "-loglevel", "error",
        "-f", "rawvideo", "-pix_fmt", "bgr24",
        "-s", f"{C.OUT_W}x{C.OUT_H}", "-r", str(fps), "-i", "-",
        "-an",
        "-vf", grade_filter(total_frames, fps),
        "-c:v", "libx264", "-preset", C.X264_PRESET, "-crf", str(C.CRF),
        "-pix_fmt", "yuv420p", "-color_range", "tv",
        "-movflags", "+faststart",
        str(path),
    ]
    return subprocess.Popen(cmd, stdin=subprocess.PIPE)


def verify_output(path: Path, fps: int, total: int) -> dict:
    """
    Prüft die FERTIGE Datei, nicht die Pipeline.

    Grading, Sockel und Blenden laufen in ffmpeg — was in der Pipeline gemessen
    wird, ist nicht das, was am Ende in der Story läuft. Genau daran ist der
    erste Durchlauf gescheitert (0 % Schwarz vor dem Grading, 48 % danach).
    Blendenbereiche werden übersprungen, die sind zulässig schwarz.
    """
    ff = ffmpeg_bin()
    skip_head = C.FADE_IN + 0.25
    skip_tail = (total / fps) - C.FADE_OUT - 0.25
    times = [t for t in np.linspace(0.0, total / fps, 26) if skip_head <= t <= skip_tail]

    worst_black, worst_t, hues = 0.0, -1.0, []
    for t in times:
        r = subprocess.run(
            [ff, "-loglevel", "error", "-ss", f"{t:.3f}", "-i", str(path),
             "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "bgr24", "-"],
            capture_output=True,
        )
        if len(r.stdout) < C.OUT_W * C.OUT_H * 3:
            continue
        fr = np.frombuffer(r.stdout[: C.OUT_W * C.OUT_H * 3], np.uint8)
        fr = fr.reshape(C.OUT_H, C.OUT_W, 3)

        luma = fr @ np.array([0.114, 0.587, 0.299], np.float32)
        frac = float((luma < 16).mean())
        if frac > worst_black or worst_t < 0:
            worst_black, worst_t = frac, float(t)

        hsv = cv2.cvtColor(fr[: C.OUT_H // 3], cv2.COLOR_BGR2HSV)
        m = hsv[:, :, 2] > 12
        if m.sum():
            hues.append(float(hsv[:, :, 0][m].mean()))

    hue = float(np.mean(hues)) if hues else -1.0
    ok_black = worst_black <= C.BLACK_MAX_FRAC
    ok_hue = 90 <= hue <= 135                     # OpenCV-H: 180-270° = blau
    log("--- Abnahme auf der fertigen Datei ---")
    log(f"  Schwarzanteil max: {worst_black * 100:.1f} % bei t={worst_t:.2f}s "
        f"(Limit {C.BLACK_MAX_FRAC * 100:.0f} %) [{'OK' if ok_black else 'FAIL'}]")
    log(f"  Himmel-Farbton: H={hue:.0f} ({hue * 2:.0f}°) "
        f"[{'blau, OK' if ok_hue else 'FAIL — Richtung Magenta?'}]")
    return dict(black_frac_worst=worst_black, black_worst_t=worst_t,
                sky_hue=hue, black_ok=ok_black, hue_ok=ok_hue)


# =============================================================== Main ========
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true", help="30 fps, kein Motion Blur")
    ap.add_argument("--qc-only", action="store_true", help="nur Depth-Debug + QC-Frames")
    ap.add_argument("--out", default="story_v2.mp4")
    args = ap.parse_args()

    for d in (OUT_DIR, WORK_DIR, QC_DIR):
        d.mkdir(parents=True, exist_ok=True)

    fps = 30 if args.preview else C.FPS
    subframes = 1 if args.preview else C.MOTION_BLUR_SUBFRAMES

    n_shot = int(round(C.SHOT_DURATION * fps))
    n_cf = int(round(C.CROSSFADE * fps))
    total = len(C.SHOTS) * n_shot - (len(C.SHOTS) - 1) * n_cf
    log(f"Ziel: {total} Frames @ {fps} fps = {total / fps:.3f} s, "
        f"Motion-Blur-Subframes: {subframes}")

    stats = {"shots": [], "fps": fps, "frames": total, "duration": total / fps}

    enc = None if args.qc_only else open_encoder(OUT_DIR / args.out, fps, total)

    black_worst = 0.0
    emitted = 0
    tail: list[np.ndarray] = []
    t0 = time.time()

    def emit(frame: np.ndarray) -> None:
        nonlocal emitted, black_worst
        # Nur informativ: das ist der Wert VOR Grading und Sockel. Verbindlich
        # ist verify_output() auf der fertigen Datei.
        black_worst = max(black_worst, black_fraction(frame))
        if enc is not None:
            enc.stdin.write((frame * 255.0).astype(np.uint8).tobytes())
        emitted += 1

    for k, shot in enumerate(C.SHOTS):
        r = ShotRenderer(shot, subframes, fps)

        par = qc_parallax(shot, r.src_shape)
        flag = "OK" if par <= C.MAX_PARALLAX_FRAC + 1e-6 else "ÜBER LIMIT"
        log(f"  Parallax-Versatz nah<->fern: {par * 100:.2f} % der Breite [{flag}]")

        # QC-Frame aus der Shot-Mitte
        mid = r.frame(n_shot // 2, n_shot, k * (C.SHOT_DURATION - C.CROSSFADE))
        qc_path = QC_DIR / f"shot_{shot['name']}.jpg"
        cv2.imwrite(str(qc_path), (mid * 255).astype(np.uint8),
                    [cv2.IMWRITE_JPEG_QUALITY, C.QC_JPEG_QUALITY])
        hue, sat = sky_hue(mid)
        bf = black_fraction(mid)
        log(f"  QC {qc_path.name}: Schwarz {bf * 100:.1f} %, Himmel H={hue:.0f} S={sat:.0f}")
        stats["shots"].append(dict(name=shot["name"], parallax_frac=par,
                                   black_frac_mid=bf, sky_hue=hue, sky_sat=sat,
                                   layers=len(r.layers), lights=len(r.lights)))

        if args.qc_only:
            del r
            continue

        t_start = k * (C.SHOT_DURATION - C.CROSSFADE)
        new_tail: list[np.ndarray] = []
        for i in range(n_shot):
            f = r.frame(i, n_shot, t_start)
            if k > 0 and i < n_cf:
                w = i / n_cf
                w = w * w * (3 - 2 * w)                     # smoothstep
                emit(tail[i] * (1 - w) + f * w)
            elif i >= n_shot - n_cf and k < len(C.SHOTS) - 1:
                new_tail.append(f)
            else:
                emit(f)

            if i % 40 == 0:
                el = time.time() - t0
                log(f"    {shot['name']} {i}/{n_shot}  (gesamt {emitted}/{total}, {el:.0f}s)")

        tail = new_tail
        del r

    if enc is not None:
        enc.stdin.close()
        enc.wait()
        log(f"Encode fertig: {OUT_DIR / args.out}")
        stats["verify"] = verify_output(OUT_DIR / args.out, fps, total)

    stats["black_frac_pre_grade"] = black_worst
    stats["render_seconds"] = time.time() - t0
    (OUT_DIR / "stats.json").write_text(json.dumps(stats, indent=2))

    log(f"Frames geschrieben: {emitted} (erwartet {total})")
    log(f"Renderzeit: {time.time() - t0:.0f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
