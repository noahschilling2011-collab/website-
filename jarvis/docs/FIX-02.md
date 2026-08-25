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
| 0 | ✓ ausgeführt — Befund widerlegt |
| 1 | **entfällt** — es gibt nichts zu löschen |
| 2 | **blockiert** — dieselbe Sperre wie FIX-01: ohne `LLM_API_KEY` liefert der Fake kein Plan-JSON, und ohne `SEARCH_API_KEY` findet der Research Agent nichts. Die Weltlage geht heute **nicht** über `/api/tasks`, sondern ruft den Provider direkt — das ist der berechtigte Kern der Kritik und gehört repariert, aber erst nach FIX-01 Schritt 1 |
| 3 | **gültig und offen** — Duplikat-, Länder- und Inhaltsprüfung fehlen wirklich |
| 4 | **hängt an FIX-01 Schritt 8** — ohne `ClaudeCodeProvider` gibt es keine CLI-Aufrufe zu zählen. Der Wechsel von `€` auf Aufrufe ist trotzdem richtig, sobald der Provider steht |
