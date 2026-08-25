# REPARATURAUFTRAG 02 — WELTLAGE MIT ECHTEN DATEN

## Befund (wie beauftragt)

Screenshot vom 25.08.2026 zeigt fünf Karten mit identischem Text, durchnummeriert
`(0)` bis `(4)`, alle mit Herkunft `REUTERS · 25.8.2026 · 16:26`, alle mit Länderkürzel
`DEU`, obwohl „Weltweit" aktiv war. Statusleiste: `verworfen 0`, `heute 0,0000 €`.

---

# ERGEBNIS SCHRITT 0 — die Quelle, mit Fundstellen

**Der Befund trifft nicht zu. Es gibt keinen Demo-Pfad im Produktivcode.**
Nach Regel 4 („Wenn ein Schritt etwas Unerwartetes aufdeckt: melden und stoppen")
habe ich vor Schritt 1 angehalten.

## Wo steht der Text?

```
$ grep -rn "Dritter Vorfall\|neun Tagen\|14:20" --include="*.py" --include="*.html" .
./tests/test_weltlage.py:107:        "schlagzeile": "Dritter Vorfall in neun Tagen",
./tests/test_weltlage_ui.py:75:        "schlagzeile": "Dritter Vorfall in neun Tagen",
./core/agents.py:63:    "ESKALATION IM PAZIFIK"   "Reuters, 14:20 MEZ - dritter Vorfall in 9 Tagen"
./core/agents.py:91:Erlaubt:  "Drei belegte Meldungen aus Moskau. Juengste um 14:20."
```

Zwei Testdateien — und `core/agents.py:63`, wo der Satz als **Formbeispiel im Prompt**
steht, also genau dort, wo PHASE-11 §4 ihn haben will („Nicht krass, nur laut" gegen
„Krass, weil belegt"). Er ist Anweisung an das Modell, nicht Inhalt.

## Wie kam er in die Ansicht?

**Über mein eigenes Prüfskript, nicht über die Anwendung.** Der Screenshot heißt
`karten_fuenf_1920.png` und stammt aus `scratchpad/p11/karten.py`, das ich geschrieben
habe, um zu prüfen, ob fünf Karten ohne Scrollbalken passen:

```python
app.state.provider = FakeLLMProvider(replies=[json.dumps(
    {"meldungen":[eintrag(i) for i in range(n)], "gesagt":""})])
```

Die `(0)` bis `(4)` sind meine Schleifenzähler. `DEU` bei aktivem „Weltweit" ebenso:
mein `eintrag()` setzt `land_iso` fest auf `"DEU"`.

## Wurde ein Fehler abgefangen und durch Demo-Daten ersetzt?

**Nein.** Es gibt genau einen Datenweg, `api/weltlage.py:234`:

```python
antwort = await provider.complete([LLMMessage("user", ziel)], system=WELTLAGE_PROMPT)
```

Zwei `except` gibt es, keiner erfindet Inhalt:

- `api/weltlage.py:242` — kaputtes JSON → `{"meldungen": [], "gesagt": "Das Modell hat
  kein verwertbares JSON geliefert."}`. Das ist eine **leere** Antwort mit Begründung,
  genau der Zustand, den Schritt 1 verlangt.
- `api/weltlage.py:115` — ein Bild lässt sich nicht holen → diese eine Karte bleibt ohne
  Bild. Kein Ersatzbild, keine erfundene Meldung.

Im Auslieferungszustand, live geprüft:

```
$ curl -X POST -H "X-Jarvis-Token: …" http://127.0.0.1:8030/api/weltlage/WELT
{"land_iso":"WELT","meldungen":[],"verworfen":0,
 "gesagt":"Das Modell hat kein verwertbares JSON geliefert.","cache":false}
```

**Null Karten.** Kein Platzhalter, kein Demo-Datensatz.

---

## Woran der Screenshot trotzdem richtig erinnert

Zwei Zahlen darin sind echte Defekte, unabhängig von der Demo-Frage — beide in
`docs/BUGS-01.md` reproduziert:

**`heute 0,0000 €`** ist nicht harmlos. `post_weltlage` ruft das Modell direkt auf und
schreibt nie `db.log_llm_call`. Die Kachel bleibt auf null, egal wie viele Länder
angeklickt werden (BUGS-01, Fund 5).

**`verworfen 0` bei fünf gleichen Karten** wäre auch mit echten Daten möglich: `pruefe()`
kennt weder Duplikatprüfung noch Länderprüfung, und leere Schlagzeilen bestehen den
Vertrag (BUGS-01, Fund 12).

---

## Status der übrigen Schritte

| Schritt | Stand |
|---|---|
| 0 | ✓ ausgeführt — Befund widerlegt, kein Demo-Pfad |
| 1 | ✓ **erledigt** — zwei verschluckende `except` sind raus |
| 2 | ✓ **erledigt** — die Weltlage ist jetzt ein Agent, kein eigener Datenweg |
| 3 | ✓ **erledigt** — Inhalts-, Alters-, Duplikat- und Länderprüfung |
| 4 | ✓ **erledigt** — Euro-Kachel raus, `Modellaufrufe heute` rein |

## Definition of Done

| # | Kriterium | Stand | BELEG |
|---|---|---|---|
| 1 | `grep -rn "Dritter Vorfall" .` findet nichts außerhalb `docs/` | ✓ | Die Fixtures heißen jetzt `TESTMELDUNG Alpha`. Ein Testtext, der wie eine echte Meldung aussieht, hat genau diese Verwechslung ausgelöst |
| 2 | „Weltweit" liefert mindestens drei `land_iso`, sonst Ablehnung | ✓ | `test_fix02_dod_2_weltweit_aus_einem_land_wird_abgelehnt` → `verworfen_gruende: {"nur ein Land im Weltweit-Modus": 3}`. Gegenprobe: Prüfung aus → rot |
| 3 | Keine zwei Karten mit identischer Schlagzeile | ✓ | `test_fix02_dod_3_…` speist fünf identische ein → 1 Karte, 4× „doppelte Schlagzeile". Auch gleiche `quell_url` zählt. Gegenprobe → rot |
| 4 | Medium und Datum aus der echten Quelle, drei Stichproben | ✗ | **NICHT AUSGEFÜHRT** — ohne `SEARCH_API_KEY` gibt es keine echten Quellen zu öffnen |
| 5 | Negativtest: `0 belegte Meldungen` plus Fehlermeldung, keine Karte | ✓ | Im Browser: `Karten sichtbar: 0`, `Leer-Kasten: 0 belegte Meldungen.`, Statusleiste mit dem echten Grund |
| 6 | Zählertest: eine Meldung ohne `medium` → `verworfen 1` | ✓ | Im Browser: 2 Karten (`Gilt`, `Gilt auch`), `verworfen 1`, Statusleiste „Verworfen: 1× kein Medium." |
| 7 | Aufrufe in der Statusleiste passen zu `llm_calls` | ✓ | `test_fix02_dod_7_…` rechnet gegen eine unabhängige SQL-Summe. Live über drei Länder: `llm_calls 9`, Seitenzähler `9`, `/api/stats 9` |
| 8 | Kein `except`, der eine Ausnahme in Inhalt verwandelt | ✓ | Die zwei sind raus. Übrig bleiben: Datumsformate durchprobieren, Bildholen (→ kein Bild, wie spezifiziert), Provider-Fehler → 502 |

## Was dabei zusätzlich herauskam

**Der Kern des Befunds ist repariert, nur an anderer Stelle als vermutet.** `heute
0,0000 €` kam nicht von einem Demo-Pfad, sondern davon, dass `post_weltlage` den
Provider direkt rief — vorbei am Runner und damit an `db.log_llm_call`, am Budget und
am Audit. Schritt 2 hat das an der Wurzel behoben: die Weltlage ist jetzt ein Agent
`weltlage` in `core/agents.py` und läuft durch `fuehre_task_aus` wie jeder andere
Auftrag.

**Ein Konflikt musste entschieden werden.** Phase 9 verlangt den Sprachstil in *jedem*
Agentenprompt; beim Weltlage-Agenten würde er das JSON zerstören. Die Ausnahme steht
als benannte Liste `OHNE_SPRACHSTIL` im Test, mit zwei Wächtern gegen stilles Wachsen.

**Kartenzahl:** gekappt wird jetzt *nach* dem Bildholen, nicht davor — sonst rücken
gültige Kandidaten nicht nach, wenn eine der ersten fünf am Bild scheitert
(BUGS-01 Fund 13, miterledigt).

## BLOCKER

- **`SEARCH_API_KEY` fehlt** — gemeldet, nicht ersetzt. Ohne ihn findet der
  Weltlage-Agent nichts Echtes; DoD 4 bleibt unausgeführt.
- **`LLM_API_KEY` fehlt** — mit dem Fake liefert der Weltlage-Agent kein gültiges JSON,
  die Ansicht zeigt dann korrekt `0 belegte Meldungen` plus Fehlermeldung.
- **Schritt 4 auf CLI-Aufrufe** braucht den `ClaudeCodeProvider` aus FIX-01 Schritt 1.
  Bis dahin zählt die Kachel `Modellaufrufe heute` aus `llm_calls` — dieselbe Wirkung:
  0 Aufrufe bei sichtbaren Karten wäre ein sichtbarer Widerspruch.
