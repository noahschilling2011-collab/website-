# Insta-Story Renderer v2 — 2.5D-Parallax

Ersetzt den flachen Ken-Burns-Zoom aus v1 durch eine echte Tiefenzerlegung:
Foto → Tiefenkarte → 7 Schichten → Schichten mit unterschiedlicher
Geschwindigkeit bewegt. Ausgabe 1080×1920, 60 fps, exakt 15.0 s, H.264,
yuv420p, ohne Audio, `+faststart`.

```bash
pip install numpy pillow opencv-python-headless scipy transformers imageio-ffmpeg
pip install --index-url https://download.pytorch.org/whl/cpu torch

python3 render.py              # kompletter Durchlauf (~10 min, siehe Renderzeit)
python3 render.py --qc-only    # nur Tiefenkarten + QC-Frames, kein Video (~30 s)
python3 render.py --preview    # 30 fps, kein Motion Blur (~2.5 min)
```

Alle Zahlen stehen in `config.py`. `render.py` enthält keine Magic Numbers.

---

## Zwei Dinge vorweg, die du wissen musst

### 1. Die drei Originalfotos waren nicht dabei

Hochgeladen wurde `story_sunset.mp4` — das **fertige v1-Rendering**
(15.00 s, 1080×1920, 30 fps), nicht die drei Quellfotos.

Damit es überhaupt ein prüfbares Ergebnis gibt, habe ich pro Shot einen Frame
aus dem v1-Video gezogen (`src/01_street.png`, `src/02_roofs_wide.png`,
`src/03_roofs_close.png`, bei t = 1.2 s / 6.3 s / 11.3 s, jeweils außerhalb der
Überblendungen). Diese Standins sind den Originalen in vier Punkten unterlegen:

| | Standin aus v1 | Originalfoto |
|---|---|---|
| Auflösung | 1080×1920, bereits auf v1-Ausschnitt beschnitten | volle Kameraauflösung |
| Grading | v1-Grading schon eingebrannt | neutral |
| Ken-Burns | schon leicht hineingezoomt | keiner |
| Kompression | H.264-Artefakte in den dunklen Flächen | verlustfrei/JPEG |

Praktische Folgen: der Ausschnitt kann nicht weiter nach oben gezogen werden als
v1 es schon getan hat, das Grading läuft mit `GRADE_STRENGTH = 0.45` statt 1.0
(sonst doppelt gegradet), und die H.264-Artefakte in den Schattenflächen sind
genau dort, wo das Tiefenmodell ohnehin am wenigsten Information hat.

**Mit den echten Fotos:** die drei Dateien nach `src/` legen, in `config.py` die
`src`-Felder anpassen und `GRADE_STRENGTH = 1.0` setzen. Sonst ändert sich nichts.

### 2. Real-ESRGAN ist hier nicht installierbar

Geprüft, nicht vermutet:

```
$ pip install --dry-run realesrgan
  pkg_resources.ContextualVersionConflict:
    (nvidia-cublas 13.6.1.10, Requirement.parse('nvidia-cublas==13.1.1.3.*'), {'cuda-toolkit'})
  error: metadata-generation-failed
```

`realesrgan` zieht `basicsr`, dessen `setup.py` beim Erzeugen der Metadaten an
einem CUDA-Versionskonflikt abbricht. Kein Wheel, kein Workaround ohne Fork.

Phase 1 macht deshalb **Lanczos ×2 + dezentes Unsharp**. Das ist ausdrücklich
**kein gleichwertiger Ersatz**: Lanczos erfindet keine Details, es hält die
vorhandenen nur sauber und vermeidet Matsch bei Kamerafahrten bis Faktor 1.4.
Real-ESRGAN würde Kanten und Dachziegel rekonstruieren, die hier schlicht
fehlen. Wenn dir das wichtig ist, muss das auf einer Maschine mit
funktionierendem `basicsr` laufen — der Rest der Pipeline bleibt gleich.

---

## Was geprüft ist und was nicht

| Schritt | Status |
|---|---|
| Real-ESRGAN-Installierbarkeit | **ausgeführt**, schlägt fehl (Log oben) |
| Depth-Anything-V2-Modellname | **ausgeführt**, HF-API: `depth-anything/Depth-Anything-V2-Small-hf` → 200 |
| `pipeline("depth-estimation")`-Signatur | **ausgeführt** gegen transformers 5.15.0, nicht aus dem Gedächtnis geschrieben |
| Tiefenkarten aller drei Shots | **ausgeführt**, als PNG geprüft (`out/qc/depth_*.png`) |
| Parallax-Amplitude | **gemessen** pro Shot, siehe `out/stats.json` |
| Occlusion-Löcher | **ausgeführt**, Kante bei maximalem Versatz kontrolliert |
| Renderzeit | **gemessen**, nicht geschätzt |
| Vollständiger 15-s-Render | **ausgeführt**, Ergebnis unter `out/story_v2.mp4` |

Die verifizierte API-Signatur (transformers 5.15.0, torch 2.13.0+cpu):

```python
out = pipeline("depth-estimation", model=..., device="cpu")(pil_image)
# -> dict mit 'predicted_depth' (torch.Tensor, HxW, bereits Eingabegröße)
#           'depth'            (PIL.Image)
```

---

## Pipeline

**Phase 1 — Upscale.** Lanczos ×2 + Unsharp (siehe oben).

**Phase 2 — Tiefenkarte.** Depth Anything V2 Small auf CPU, ~2 s pro Bild.
Danach bilateral gefiltert (kantenerhaltend). Debug-PNG pro Shot nach
`out/qc/depth_*.png`, grüne Kontur = geklemmter Vordergrund.

Der schwarze Vordergrund wird pauschal auf `p = 0.94` geklemmt, damit sich
Balkongeländer und Dach als **eine** Ebene bewegen statt in sich zu wabern.

> **Fallstrick, der beim ersten Durchlauf zugeschlagen hat:** der Nachthimmel ist
> genauso dunkel wie der Balkon. Eine reine Luminanzschwelle klemmt ihn mit —
> der Himmel wurde als „nah" eingestuft und wanderte beim Parallax über die
> Hügelkante, mit sichtbar ausgefranster Horizontlinie. Geklemmt wird deshalb
> nur, was am **unteren Bildrand** hängt und nicht schon in der oberen
> Bildhälfte anfängt (`DARK_BOTTOM_TOL`, `DARK_MIN_TOP_FRAC`).

**Phase 3 — Parallax.** 7 Schichten, ease-in-out mit linearem Sockel
(`EASE_LINEAR_MIX = 0.28`) — reines Cosine-Easing steht am Shot-Anfang und
-Ende praktisch still, und der Clip soll nie stillstehen.

Occlusion: Basis ist das komplette Bild mit der Transformation der **fernsten**
Schicht, darüber die Einzelschichten. Damit kann strukturell kein Loch
entstehen — eine Lücke zeigt immer minimal versetzten Hintergrund. Zusätzlich
wird pro Schicht ein Ring von 26 px mit `cv2.inpaint` (Telea) gefüllt, damit die
weiche Kante keine Farbe der Nachbarschicht mitzieht.

Motion Blur: 3 Subframes pro Ausgabeframe.

**Phase 4 — Licht.** Luminanzschwelle → Connected Components → nur kompakte,
kleine Regionen (Fläche, Bounding-Box-Kantenlänge, Füllgrad). Große helle
Flächen wie Hauswände fallen raus. Pro Lampe ein radialer Glow, Radius nach
Größe der Quelle, plus eine eigene langsame Sinus-Phase mit 4 % Amplitude.

Kein flächiger Bloom über den ganzen Frame — genau der hat in v1 den blauen
Nachthimmel lila gefärbt. Licht bleibt lokal.

**Phase 5 — Atmosphäre.** Fraktales Value-Noise, langsam driftend,
Screen-Blend mit Opacity 0.075, nur im Horizontband und per Tiefe maskiert
(nur ferne Bereiche). Der Screen-Blend läuft gegen ein neutral-kaltes Grau statt
gegen Weiß, damit der Himmel nicht ins Magenta kippt.

Sterne: `ADD_STARS = False`. Sie waren nicht im Bild — das wäre erfunden.
Schalter steht, Entscheidung liegt bei dir.

**Phase 6 — Schnitt.** 3 × 5.6 s, Crossfades 0.9 s (smoothstep), Fade-in 0.7 s,
Fade-out 0.8 s. `3 × 5.6 − 2 × 0.9 = 15.0 s` → 900 Frames bei 60 fps, exakt.

Die Montage läuft in numpy und streamt direkt in ffmpeg. Im Speicher liegt
immer nur der Überblendungs-Tail (54 Frames), nicht der ganze Clip.

---

## Schwarzanteil

Kriterium: kein Frame über ~35 % reines Schwarz. Die Rohbilder liegen bei
**über 50 %** unter der Schwarzgrenze — Himmel *und* Balkon, das ist bei einem
Nachtfoto normal und nicht mit Ausschnitt-Verschieben zu lösen.

Statt global aufzuhellen (macht das Bild milchig) hebt eine Kurve nur den Fuß
an: bei 0 kommt `SHADOW_LIFT = 0.105` dazu, ab `SHADOW_KNEE = 0.38` ist die
Kurve wieder identisch. Midtones und Lichter bleiben unangetastet. Der Sockel
ist leicht blau getönt, damit Schwarz nach Nachtluft aussieht statt nach
Grauschleier.

> **Zweiter Fallstrick, der zugeschlagen hat — Reihenfolge.** Der Sockel saß
> zuerst in numpy, also *vor* dem ffmpeg-Grading. Gemessen an den Pipeline-
> Frames: 0 % Schwarz. Gemessen an der fertigen Datei: **48 %**. `eq=contrast`
> und `vignette` drücken einen vorher gesetzten Sockel exakt wieder unter die
> Grenze — der Lift bei 0.085 landet nach Kontrast 1.054 bei 16.0/255, also
> genau auf der Schwelle, und die Vignette schiebt die Ränder darunter.
>
> Der Sockel läuft jetzt als letzte Kurve *nach* dem Grading, die Blenden
> danach — sonst startet das Video nicht mehr in echtem Schwarz. Und die
> Abnahme misst seitdem die **fertige Datei**, nicht die Pipeline
> (`verify_output()`). Ein QC-Wert aus der falschen Stufe ist schlimmer als
> keiner, weil er wie eine bestandene Prüfung aussieht.

## Renderzeit (gemessen, dieser Container, CPU)

| Subframes | ms/Frame | 60 fps | 30 fps |
|---|---|---|---|
| 1 (aus) | 281 | 4.7 min | 2.4 min |
| **3 (Default)** | **582** | **9.8 min** | 4.9 min |
| 4 | 879 | 14.8 min | 7.4 min |

Tabelle = reine Frame-Zeit aus dem Benchmark. Der vollständige Lauf inklusive
Tiefenkarten, Schichtaufbau und Encode hat **641 s (10.7 min)** gebraucht
(`out/stats.json`, `render_seconds`).

Der Default liegt bei 60 fps knapp über 10 Minuten. Wenn es schneller gehen
soll: `MOTION_BLUR_SUBFRAMES = 1` halbiert die Zeit, kostet aber genau das
Cineastische an der langsamen Bewegung. `--preview` (30 fps, kein Blur) ist für
schnelles Gegensehen da, nicht für die Ausspielung.

## QC-Artefakte

`render.py` schreibt bei jedem Lauf nach `out/qc/`:

- `depth_<shot>.png` — Tiefenkarte, grüne Kontur = geklemmter Vordergrund
- `shot_<shot>.jpg` — Frame aus der Shot-Mitte
- `../stats.json` — Parallax-Amplitude, Schwarzanteil, Himmel-Farbton,
  Schicht- und Lichtzahl pro Shot

Zusätzlich wird pro Shot geloggt, ob die gemessene Parallax-Amplitude das
4-%-Limit hält. Nach dem Encode prüft `verify_output()` die **fertige Datei**:
26 Stichproben über den Clip, Blendenbereiche ausgenommen.

## Abnahme gegen die Kriterien

Gemessen am ausgelieferten `out/story_v2.mp4`:

| # | Kriterium | Ergebnis |
|---|---|---|
| 1 | 15.0 s, 1080×1920, ohne Neukodierung abspielbar | `Duration 00:00:15.00`, 1080×1920, 60 fps, h264 High, yuv420p, kein Audio, `moov` vor `mdat` — **erfüllt** |
| 2 | Himmel blau, nicht lila/magenta | H = 103 (206°) im Mittel über den Clip — **erfüllt** |
| 3 | keine sichtbaren Löcher oder wabernden Kanten | Kante bei maximalem Versatz kontrolliert (`out/qc/edge_zoom.jpg`); strukturell hole-frei durch die Vollbild-Basis — **erfüllt** |
| 4 | Einzelframe ohne Bewegungseindruck, Clip nie stillstehend | 0.37/255 mittlere Differenz zwischen zwei Frames, 13.7/255 über einen ganzen Shot; Ease hat bei t=0 und t=1 die Ableitung `EASE_LINEAR_MIX` > 0 — **erfüllt** |
| 5 | kein Frame über ~35 % reines Schwarz | 0.0 % über alle Stichproben außerhalb der Blenden — **erfüllt** |

Kriterium 3 ist das einzige, das am Ende ein Auge braucht und keine Zahl:
„keine sichtbaren Löcher" ist visuell, und geprüft habe ich Standbilder plus
den kritischen Ausschnitt, nicht jeden der 900 Frames in Bewegung.
