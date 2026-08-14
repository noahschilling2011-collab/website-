"""
Insta-Story Renderer v2 — alle Zahlen an einem Ort.

Koordinaten-Konventionen:
  * Tiefe p:      0.0 = am weitesten weg (Himmel), 1.0 = am nächsten (Balkon/Dach)
  * cx / cy:      Fensterversatz als Anteil des verfügbaren Spielraums, -1..+1.
                  cy negativ = Ausschnitt wird nach OBEN gezogen (weg vom toten
                  schwarzen Balkon/Parkplatz im unteren Drittel).
  * par_x/par_y:  Parallax-Amplitude über den ganzen Shot, als Anteil der
                  Bildbreite. Wirkt proportional zu p (nahe Schichten schneller).
"""

# ----------------------------------------------------------------- Ausgabe ---
OUT_W, OUT_H = 1080, 1920
FPS = 60

SHOT_DURATION = 5.6      # s pro Shot
CROSSFADE = 0.9          # s Überblendung zwischen den Shots
FADE_IN = 0.7            # s Aufblende aus Schwarz
FADE_OUT = 0.8           # s Abblende nach Schwarz
# 3 * 5.6 - 2 * 0.9 = 15.0 s exakt -> 900 Frames bei 60 fps

CRF = 17
X264_PRESET = "slow"

# --------------------------------------------------------------- Phase 1 -----
# Real-ESRGAN ist in diesem Environment NICHT installierbar (basicsr bricht bei
# der Metadaten-Generierung an einem CUDA-Versionskonflikt ab, siehe README).
# Fallback ist Lanczos + dezentes Unsharp. Das ist KEIN Ersatz: es erfindet
# keine Details, es hält die vorhandenen nur sauber.
UPSCALE = 2
UNSHARP_AMOUNT = 0.45
UNSHARP_RADIUS = 1.6

# --------------------------------------------------------------- Phase 2 -----
DEPTH_MODEL = "depth-anything/Depth-Anything-V2-Small-hf"
DEPTH_MAX_SIDE = 1036            # Vielfaches von 14 (DPT-Patchgröße)

# Kantenerhaltendes Glätten der Tiefenkarte
BILATERAL_D = 9
BILATERAL_SIGMA_COLOR = 40.0
BILATERAL_SIGMA_SPACE = 40.0

# Dunkler Vordergrund: das Depth-Modell hat dort keine Bildinformation und rät.
# Alles unter dieser Luminanz wird pauschal auf "nah" geklemmt, damit sich der
# schwarze Balkon als EINE Ebene bewegt statt in sich zu wabern.
DARK_LUMA_THRESHOLD = 0.085      # 0..1
DARK_CLAMP_DEPTH = 0.94          # auf diesen p-Wert klemmen
DARK_MIN_REGION = 4000           # kleinere dunkle Flecken ignorieren (px @ Arbeitsres.)
DARK_CLOSE_KERNEL = 21           # Löcher in der Dunkelmaske schließen

# Der Nachthimmel ist genauso dunkel wie der Balkon. Geklemmt wird deshalb nur,
# was am unteren Bildrand hängt und nicht schon in der oberen Bildhälfte anfängt.
DARK_BOTTOM_TOL = 12             # px Toleranz zum unteren Rand
DARK_MIN_TOP_FRAC = 0.45         # Region darf frühestens hier oben beginnen

# --------------------------------------------------------------- Phase 3 -----
N_LAYERS = 7                     # Tiefenschichten (Brief: 6-8)
LAYER_FEATHER = 13               # Gauss-Kernel für weiche Schichtkanten (px @ 2x)
LAYER_INPAINT_RING = 26          # Breite des Rings, der pro Schicht gefüllt wird
INPAINT_RADIUS = 5               # cv2.inpaint Telea

# Harte Obergrenze für den Versatz zwischen nächster und fernster Schicht.
# Mehr sieht sofort nach billigem 3D-Foto aus. Wird nach dem Bau der Kamera
# nachgemessen (qc_parallax) und laut gemeldet, wenn überschritten.
MAX_PARALLAX_FRAC = 0.04

# Ease-in-out, aber mit linearem Sockel: reines Cosine-Easing steht am Anfang
# und Ende praktisch still, und der Clip soll nie stillstehen.
EASE_LINEAR_MIX = 0.28

MOTION_BLUR_SUBFRAMES = 3        # 0/1 = aus. 3 = deutlich cineastischer.
SUBFRAME_SPREAD = 0.75           # Anteil des Frame-Intervalls, über den gemittelt wird

# --------------------------------------------------------------- Phase 4 -----
LIGHT_LUMA_THRESHOLD = 0.62      # Luminanz, ab der ein Pixel als Lichtquelle gilt
LIGHT_MIN_AREA = 6               # px @ Arbeitsauflösung
LIGHT_MAX_AREA = 1400            # größer = Hauswand/Dachfläche, ignorieren
LIGHT_MAX_EXTENT = 90            # Bounding-Box-Kantenlänge max (px)
LIGHT_MIN_FILL = 0.34            # Fläche / Bounding-Box: aussortiert lange Streifen
LIGHT_MAX_COUNT = 260            # Sicherheitsnetz

GLOW_RADIUS_SCALE = 3.4          # Glow-Radius = sqrt(area) * scale
GLOW_RADIUS_MIN = 10
GLOW_RADIUS_MAX = 64
GLOW_STRENGTH = 0.17             # additive Spitzenhelligkeit
GLOW_FALLOFF = 3.2               # Exponent des radialen Abfalls (höher = weicher Rand)

FLICKER_AMP = 0.04               # max 4 % Helligkeit — soll man kaum bewusst sehen
FLICKER_FREQ = (0.11, 0.33)      # Hz, pro Lampe zufällig aus diesem Bereich

# --------------------------------------------------------------- Phase 5 -----
HAZE_ENABLED = True
HAZE_OPACITY = 0.075             # <= 0.08
HAZE_BAND_CENTER = 0.50          # relative Höhe im Ausgabeframe
HAZE_BAND_WIDTH = 0.20           # Sigma des vertikalen Gauss-Bandes
HAZE_DEPTH_MAX = 0.42            # nur ferne Bereiche (p <= dieser Wert) bekommen Haze
HAZE_DRIFT = (7.0, -1.6)         # px/s Drift des Rauschens
HAZE_SCALE = 190                 # Basis-Wellenlänge des Rauschens in px
HAZE_OCTAVES = 4

# --------------------------------------------------------- Schattensockel ---
# Ein Nachtfoto vom Balkon liegt roh zu >50 % unter der Schwarzgrenze (Himmel
# UND Balkon). Statt global aufzuhellen wird nur der Fuß der Kurve angehoben.
#
# WICHTIG — Reihenfolge: der Sockel läuft NACH dem Grading. Ein Lift vor eq +
# vignette wird von genau diesen beiden wieder zugedrückt (gemessen: 0 % vor
# dem Grading, 48 % danach). Deshalb sitzt er als letzte Kurve in der
# ffmpeg-Kette, und die Blenden kommen erst danach — sonst startet das Video
# nicht mehr in echtem Schwarz.
SHADOW_LIFT = 0.105              # Anhebung bei Schwarz, nach dem Grading
SHADOW_KNEE = 0.38               # ab hier ist die Kurve wieder identisch
SHADOW_TINT = (1.00, 0.90, 0.76)  # BGR — leicht blau: Nachtluft statt Grauschleier

ADD_STARS = False                # Sterne waren NICHT im Bild — bewusst erfunden.
STAR_COUNT = 130
STAR_REGION = 0.42               # nur oberste 42 % des Frames
STAR_MAX_BRIGHT = 0.30
STAR_TWINKLE = 0.35

# --------------------------------------------------------------- Grading -----
# Aus v1 übernommen. Achtung: KEIN flächiger Bloom über den ganzen Frame —
# das hat in v1 den blauen Nachthimmel lila gefärbt. Licht bleibt lokal (Phase 4).
GRADE_ENABLED = True
GRADE_CONTRAST = 1.12
GRADE_SATURATION = 1.14
GRADE_CURVES_B = "0/0.02 0.5/0.5 1/1"
GRADE_VIGNETTE = "PI/5"
GRADE_NOISE = "alls=4:allf=t+u"

# Die Quellframes stammen aus dem bereits gegradeten v1-Render. Ein zweiter
# voller Grading-Durchlauf würde die Schatten zudrücken (Kriterium 5) und die
# Sättigung überziehen. Mit echten RAW/JPEG-Originalen auf 1.0 stellen.
GRADE_STRENGTH = 0.45

# --------------------------------------------------------------- Shots -------
# zoom: (start, ende) — >1 nötig, damit für den Hochzieh-Crop überhaupt
#       Spielraum existiert. Bei zoom=1 füllt das Fenster exakt das Bild.
SHOTS = [
    dict(
        name="01_street",
        src="01_street.png",
        # Langsamer Dolly nach vorne, minimal nach unten.
        zoom=(1.22, 1.40),
        cx=(0.00, 0.02),
        cy=(-0.70, -0.58),      # Ausschnitt hoch gezogen, driftet minimal runter
        par_x=0.000,
        par_y=0.011,
        dolly_gain=0.020,
    ),
    dict(
        name="02_roofs_wide",
        src="02_roofs_wide.png",
        # Langsamer Pull-back, seitlicher Drift nach rechts.
        zoom=(1.40, 1.23),
        cx=(-0.06, 0.14),
        cy=(-0.66, -0.62),
        par_x=0.016,
        par_y=0.000,
        dolly_gain=-0.018,      # negativ = Rückwärtsfahrt
    ),
    dict(
        name="03_roofs_close",
        src="03_roofs_close.png",
        # Dolly nach vorne + leichter Seitendrift links.
        zoom=(1.22, 1.39),
        cx=(0.05, -0.11),
        cy=(-0.68, -0.60),
        par_x=-0.014,
        par_y=0.007,
        dolly_gain=0.019,
    ),
]

# --------------------------------------------------------------- QC ----------
BLACK_LUMA = 16 / 255.0          # ab hier gilt ein Pixel als "reines Schwarz"
BLACK_MAX_FRAC = 0.35            # Akzeptanzkriterium 5
QC_JPEG_QUALITY = 92
