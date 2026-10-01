# STADT – Etappe 2, Schritt 2: Speicherformat 10 und Migration (30.09.2026, 18:43–19:50 UTC)

> **Ablage im Repo (Etappe 2, Schritt 5, 01.10.2026).** Bericht aus dem Arbeitsordner der Sitzung, inhaltlich unverändert (sha256 des
> Originals in `quellen.sha256`). Bereinigt sind nur Pfade: Der absolute Pfad des Arbeitsordners heißt hier `SP`, das Repo `<repo>`.
> `E` = `SP/ml/e2bau` liegt nicht im Repo; `E/stadt` ist der Ordner, der als `stadt/` ins Repo kommt. Was aus `E/mess/…` hier liegt,
> steht unter `mess/…` neben diesem Bericht (Liste in `LIESMICH.md`); Werkzeuge aus `E/werkzeug/…`, die die Doku braucht, liegen in
> `tools/` (ebenfalls dort aufgeführt). Alles andere aus `SP` (Rohdaten, Sicherungen, Prototypen) ist nicht mitgeliefert.

`SP` = Arbeitsordner der Sitzung (nicht im Repo), `E` = `SP/ml/e2bau`. Baukopie `E/stadt`.
Sicherung vor den Änderungen: `E/sicherung_schritt2` (= Schlussstand von SIM_FIX.md, `stadt.html` `6cc9f533…`, Sim-Hash `aa03039229cca193`).
Rohdaten `E/mess/schritt2/`, Werkzeuge `E/werkzeug/s2_*`. **Im Repo ist nichts geändert, nichts angelegt, nichts committet**
(`git status` leer, HEAD `6c1741e`, vorher und nachher).

**Schlussstand:** `stadt/stadt.html` sha256 `6340538f107c8e3e…`, Sim-Hash `1d16a3626d8fb495` (sim-Block Zeilen 922–8908), `VERSION = 10`,
`GED: 1, GED_STAERKE: 1.5, PLAN_RUECKLAGE: 1` (unverändert). `tools/simtest.mjs` sha256 `bdf42513a03fb17f…`.
Alle Zahlen sind gemessen, außer wo „Annahme“ oder „nicht geprüft“ steht.

## 0. Ergebnis

Alle Fertig-Kriterien von VERGLEICH.md Schritt 2 und aus dem Auftrag sind erfüllt. Eine Einschränkung beim Aufholen ist alt und bleibt:
Siehe 5, Fall (c).

| Kriterium | Ergebnis | Rohdaten (`E/mess/schritt2/`) |
|---|---|---|
| `VERSION` 10, `MIGRIERBAR` = 2–9, die alte Kette nur bis Version 8 | ja | `diff_stadt_html.txt` |
| `migriereGed`: Gedächtnis neu verteilt, memName weg, Fakt und Verweis 0, Erfahrung, Plan und letzte Entscheidung neutral | ja; unabhängig nachgeprüft für jede Person in 24 Ständen der Versionen 2–9 (0 falsch) | `simtest_alle/migrationstest.txt` |
| `--migrationstest` (2–9 → 10) | **grün**: 368 ok, 0 FEHL (vorher 6 FEHL) | ebenso |
| Stand der Version 9 ohne Übernahme abgelehnt, mit Übernahme angenommen | ja, in 3 von 3 Ständen aus `6c1741e` (dazu 3 aus `31ce452`) | ebenso |
| Stand der Version 10 von Version 9 abgelehnt (`git show 6c1741e`) | ja, in Node mit und ohne Übernehmen (3 von 3) und im Browser | ebenso, `browser/p10speicher.log` |
| `gedPruefen` erkennt beschädigte Stände (≥ 10), Pflichtfelder ab 10 | **23 Fälle**, alle mit ihrem Grund abgelehnt; der unveränderte Stand wird angenommen | `simtest_alle/speichertest.txt` |
| Speichern und Laden mitten am Tag bitgleich (`--speichertest`) | **grün**; neu ein Stand mit 372 offenen Handlungen, Tag 300, 13 Uhr: 60 Tage später bitgleich, beide lernen 526 Erfahrungen | ebenso |
| Aufholen 1 × 90 = 3 × 30 über Gedächtnis-Ereignisse hinweg (`--aufholtest`) | **grün** für (a) Grenzen um 0 Uhr und (b) rein stündlich ab 13 Uhr; an jeder Grenze 273–330 Handlungen offen | `simtest_alle/aufholtest.txt` |
| Größe Seed 1, Tag 365 / 730 | 934.966 / 1.170.599 Zeichen | `groesse_s1.jsonl` |
| Größe große Stadt (Umland 300.000, Seed 2, Tag 750) ≤ 4,4 MB | **4.190.777 Zeichen** (Node), 4.190.779 im Browser (7.085 Einwohner) | `groesse_gross.jsonl` |
| Browser-Test (Port 9091): große Stadt in `localStorage` schreiben und wieder lesen | **10 von 10 OK** (`tests/p10speicher.cjs`) | `browser/p10speicher.log` |
| Versionsdialog und Meldungen im Modul-Skript | Version 9 → 10, „neuere Version“, Meldung nach der Übernahme | ebenso |
| Policy `policy_v9_lokal_1` sichtbar abgelehnt („neu trainieren“), Regeln entscheiden; die Datei bleibt in `ki/` | ja, im Browser (Übernahme und „Trainierte Policy“ wählen) und in Node (`tools/ki_liste.mjs --nur-pruefen`) | `browser/p10speicher.log`, `ki_liste_nur_pruefen.txt` |
| Alle Schalter aus = `6c1741e` Tag für Tag (Seeds 1–3, 730 Tage, stündlich und in Tagesschritten) | **730 von 730 Tagen** je Seed und Weg, bis auf memName und die Versionsnummer | `aus_gleich_std.txt`, `aus_gleich_tagschritt.txt` |
| Mit `R.GED = 1` rechnet die Stadt wie vor Schritt 2 | Seeds 1–3 × 730 Tage (stündlich und Tagesschritte) und Seeds 4–20 × 365 Tage: jeden Tag gleich, bis auf memName und die Versionsnummer | `ged1_gleich_*.txt` |
| Gate T nicht langsamer | Median 1.507,5 ms (vorher 1.512,5, Basis 4.287,5), neu/vorher 0,997, 6 Runden im Wechsel, Rechner ruhig | `gate_t/auswertung.txt` |
| Harte Grenze, Namenstausch | statisch in Ordnung (29 + 2 Funktionen, neu `migriereGed`, `gedPruefen`), Namenstausch Seeds 1 und 2 × 200 Tage bitgleich | `harte_grenze.txt` |

**`simtest_alle`: 15 von 22 Läufen mit Exit 0** (vorher 14). Neu grün ist `--migrationstest`. Rot sind dieselben 7 Läufe wie vorher, mit
denselben FEHL-Zeilen (Vergleiche mit älteren Fassungen, siehe 9). Neu ist nur, wie `--kipolicy --policy ki/policy_v9_lokal_1.json` rot
wird: Die Policy wird jetzt beim Laden abgelehnt („… Version 10 (neu trainieren)“). Das ist Noahs Entscheidung 5, der Test gehört zu
Schritt 4.

## 1. Was geändert ist

Geändert sind genau diese Dateien (`diff -rq` gegen `sicherung_schritt2`):

- `stadt.html`: +104/−21 Zeilen
- `tools/simtest.mjs`: +275/−9
- `tests/alle.sh` und `tests/LIESMICH.md`: +5/−2
- neu: `tests/p10speicher.cjs`

Die Diffs liegen in `mess/schritt2/diff_*.txt`.

### 1.1 sim-Block

- **`VERSION = 10`.** Der Kommentar nennt jetzt auch Version 9 (fehlte) und Version 10.
- **`memName` ist aus `PF` gestrichen** (Noahs Entscheidung 1). Das spart 32 Byte je Person.
  - `erinnere` schreibt memName nicht mehr, auch nicht mit `R.GED = 0`. Die Zeile rechnete `namePack`, rein und ohne Zufall.
  - `memBehalten` setzt es nicht mehr.
  - `personInfo` nennt Menschen, die nicht mehr in der Stadt leben, immer nach der Beziehung (`bezugWort`), auch mit `R.GED = 0`. Namen
    lebender Personen kommen wie bisher über `nr`.
- **`MIGRIERBAR = [2, …, 9]`.** Die Kette `migriereV2` … `migriereTech9` läuft nur noch für Stände bis Version 8. Danach läuft
  `migriereGed` für jeden übernommenen Stand.
- **`importZustand`:**
  - Pflichtfelder ab Version 10 sind die 10 Felder aus `PF_GED`.
  - `p.memName` eines Stands bis Version 9 wird beim Lesen weggelassen (Typ geprüft). In einem Stand der Version 10 ist es „beschädigt“.
  - `gedPruefen` läuft für jeden Stand.
  - Der Fehler „andere Version“ trägt neu `neuer` (Stand von einer neueren Datei).
- **`migriereGed`** (neu, 2.1) und **`gedPruefen`** (neu, 3).
- Export `_ged: { migriereGed, gedPruefen, planSchrittVon, gedStatLeer }`, nur für `tools/simtest.mjs`.

### 1.2 Modul-Skript

- **Versionsdialog:**
  - Für Version 9 ein eigener Text: „Seit Version 10 lernen die Bewohner aus den Folgen ihrer Entscheidungen …“.
  - Der Hinweis dazu: „Erfahrungen und Pläne beginnen am Übernahmetag. Erinnerungen an Menschen, die nicht mehr in der Stadt leben, nennen
    die Beziehung statt des Namens. Eine trainierte Policy aus Version 9 gilt nicht mehr (neu trainieren); es entscheiden die Regeln.“
  - Für Stände bis Version 8 ein zusätzlicher kurzer Satz zu Version 10.
  - Neu ist der Titel „Spielstand ist von einer neueren Version“ für Stände mit höherer Version. Bis Version 9 hieß der Titel immer „älteren
    Version“.
- **Meldung nach der Übernahme:** `NEU_KURZ` nennt „Bewohner mit Erfahrung und Plänen“. Aus Version 9 fällt der Satz „Mehr im Stadtbuch …“
  weg, denn Etappe 2 schreibt keine Zeile ins Stadtbuch.
- **„Stadt übernehmen“ im Dialog** liest jetzt wie der Datei-Import die Policy-Wahl des Stands (`kiQuellenFuer`, `kiWahlAusUi`).
  - Verlangte ein Stand der Version 9 die Policy aus Etappe 1, entscheiden danach sichtbar die Regeln: Hinweis in der Meldung, Ablehnung mit
    „neu trainieren“ im Fenster „Entscheidungen der Bewohner“.
  - Vorher hätte dieser Weg die Wahl still übergangen.
- Nur für Tests: `__stadt.spielstandText` im Debug-Haken.

### 1.3 Tests (`tools/simtest.mjs`, `tests/`)

- **`--migrationstest`:**
  - Die Vergleiche „läuft danach wie Version 6/7“ laufen mit den Etappe-2-Schaltern aus, wie die übrigen Bausteine dort (Regel:
    Vergleiche mit alten Fassungen über `R.GED = 0`).
  - Neu ist je alter Fassung (2–7) die Übernahme mit Gedächtnis (`gedUebernommen`).
  - Neu ist der Teil „Version 8 und 9 → 10“ mit den Ständen aus `31ce452` und `6c1741e`.
- **`--speichertest`:** neu ein Stand mit Gedächtnis, Erfahrung, offenen Handlungen und Plänen, dazu 23 beschädigte Stände der Version 10.
- **`--aufholtest`:** neu 1 × 90 gegen 3 × 30 mit Speichern und Laden zwischen den Stücken. Vorher endete der Modus immer mit 0; jetzt ist
  er ein echter Test mit Exit-Code.
- **`spurRelativ` und `OHNE_SICH` (gemeinsam für die Vergleiche mit alten Fassungen):**
  - memName und die Felder aus `PF_GED` werden nicht mehr verglichen; die alte Fassung hat keine `PF_GED`-Felder, die neue kein memName.
  - Damit nichts schwächer wird, verändert jedes `PF_GED`-Feld, das nicht 0 ist, die Spur. Mit `R.GED = 1` bleiben solche Vergleiche also
    rot, mit `R.GED = 0` wird geprüft, dass alle Felder 0 sind.
- **`--kipolicy`:** Der Teil „Beobachtung (verändert)“ sichert und verändert memName nur noch, wenn es das Feld gibt. Sonst wäre der Modus
  abgestürzt; seine Prüfungen sind sonst unverändert.
- **`tests/p10speicher.cjs`:** neuer Browser-Test (7). In `tests/alle.sh` (Soll 10) und `tests/LIESMICH.md` eingetragen.

## 2. Übernahme von Version 9 (und älter)

### 2.1 Regel

- **Gedächtnis ohne `R.GED` (nur für Vergleiche):** Der Ring bleibt, wie er ist; memName fällt weg.
- **Gedächtnis mit `R.GED`:**
  - Die alten Einträge (8 Plätze im Ring, ab `memPos` der älteste) laufen in der Reihenfolge des Erlebens noch einmal durch die Kurzzeit.
  - Was dabei herausfällt, behält `memBehalten` wie im Spiel, wenn die Bedeutung mindestens `MEM_SCHWELLE` ist; sonst ist es vergessen.
  - Weil höchstens 5 Einträge älter sind als die 3 jüngsten, passen alle mit genug Bedeutung in die 5 Langzeitplätze.
  - Leere Plätze stehen wie bei einer neuen Person (`memRef = −1`, Tag 0, Generation 0).
- **Fakt und Verweis:** 0, der alte Stand kennt sie nicht.
- **Neutral:** Erfahrung, offene Handlung, letzter Plan und letzte Entscheidung stehen auf 0 (die Felder fehlen im alten Stand).
- **Planschritt:** kommt aus dem Zustand (`planSchrittVon`), wie jede Nacht in `zielPruefen`.
  - Er ist kein Gedächtnis, sondern der erste noch nicht erfüllte Schritt des aktuellen Ziels.
  - Grund (eigene Entscheidung): Mit 0 hätte jemand mit dem Ziel „eigener Laden“ bis zur ersten Nacht als „spart noch“ gegolten und darum
    ungern gekündigt (`PLAN_SPAREN`), auch wenn die Rücklage schon da ist.
- **`S.stat.ged`** beginnt bei 0. Es gibt keine Zeile im Stadtbuch.

### 2.2 Geprüft in `--migrationstest`

Stände aus Git: Version 2–7 aus den bisherigen Commits, Version 8 aus `31ce452`, Version 9 aus `6c1741e`; je Seed 1/2/3 an Tag 150/300/400,
also 24 Stände.

- **Ohne Übernehmen abgelehnt** und als übernehmbar markiert; die Meldung lautet „Spielstand ist von Version 9, diese Datei ist Version 10.“
- **Mit Gedächtnis gegen ohne** (sonst gleiche Schalter):
  - alle Arrays außer Gedächtnis und Planschritt gleich, dazu alle Einzelwerte und alle JSON-Teile außer `stat.ged`;
  - kein memName, Version 10.
- **Das Gedächtnis je Person unabhängig nachgerechnet:** Kurzzeit = die jüngsten 3 im Ring der Reihe nach, Langzeit = genau die älteren mit
  Bedeutung ab der Schwelle.
  - 0 falsch in allen 24 Ständen.
  - Zum Beispiel `6c1741e` Seed 3: 9.042 Erinnerungen, davon 4.040 in der Langzeit und 1.334 unter der Schwelle vergessen.
- **Neue Felder:** alle 0, der Planschritt wie `planSchrittVon` (0 falsch), die Summen leer.
- **Namen:** Keine Erinnerung an jemanden, der nicht mehr in der Stadt lebt, trägt den Namen, weder als Namensmarke noch als Klartext des
  alten memName.
  - `6c1741e`: 23 / 37 / 169 solche Erinnerungen, alle noch im Gedächtnis, Name darin 0.
  - **Gegenprobe** (`werkzeug/s2_namen_gegenprobe.mjs`, `namen_gegenprobe.txt`): Derselbe Stand in der Fassung vor Schritt 2 zeigt 169 von
    169 dieser Erinnerungen mit Namensmarke, nach der Übernahme 0. Die Prüfung erkennt Namen also.
- **10 Tage weiter** mit Gedächtnis, gespeichert und geladen (dabei läuft `gedPruefen`): 5 Tage später bitgleich.
- **Aus Version 9 mit `R.GED = 0`:** Die Stadt läuft 60 Tage lang jeden Tag wie `6c1741e` weiter (alle Arrays außer memName, `PF_GED` 0,
  Einzelwerte außer der Version, JSON-Teile); 3 von 3.
- **Aus Version 8 und 9 mit Gedächtnis:** 60 Tage ohne NaN, es wird gelernt (68 bis 286 Erfahrungen); als Version 10 gespeichert und geladen
  sind die Städte 20 Tage später bitgleich.
- **Stand der Version 10 in `6c1741e`:** mit und ohne Übernehmen abgelehnt, nicht als übernehmbar markiert. Die Meldung lautet „Spielstand
  ist von Version 10, diese Datei ist Version 9.“

## 3. `gedPruefen`: beschädigte Stände

Ab Version 10 prüft `gedPruefen` jeden Stand, auch übernommene. Abgelehnt wird mit „Spielstand beschädigt: …“, nichts wird still
korrigiert:

- **Gedächtnis:** Kurzzeit-Platz außerhalb des Rings (mit `R.GED` höchstens `MEM_KURZ − 1`), unbekannter Code, Fakt oder Verweis an einem
  leeren Platz.
- **Erfahrung:** Wert −32 oder Wert ohne Beobachtung.
- **Offene Handlung:** unbekannte Handlung, Frist außerhalb 1 … `ERF_FRIST` bzw. eine Frist ohne offene Handlung.
- **Plan:** Planschritt jenseits der Schritte des Ziels, letzter Plan mit unbekanntem Ziel oder Grund.
- **Letzte Entscheidung:** unbekannte Aktion oder Quelle, Zeit in der Zukunft, Werte ohne Aktion.
- **`S.stat.ged`:** Mit `R.GED` Pflicht (4 + 4 + 8 ganze Zahlen ≥ 0, „schlecht“ höchstens „gelernt“). Ohne `R.GED` verboten, denn dann ist
  das Gedächtnis anders geordnet.

**Geprüft in `--speichertest`:** 23 Fälle, 0 falsch:

- zwei fehlende Pflichtfelder;
- memName in Version 10;
- falscher Typ;
- je Bedingung mindestens ein Fall;
- 3 Fälle der Summen.

Dazu kommen zwei Kontrollen: Der unveränderte Stand wird angenommen, und ein Stand mit Gedächtnis in einer Fassung mit `R.GED = 0` wird
abgelehnt.

## 4. Speichern und Laden mitten am Tag

`--speichertest` hat neu einen Stand an Tag 300, 13 Uhr (Seed 1): der erste Tag ab 300, an dem eine Gründung und ein Stellenwechsel offen
sind. Er enthält:

- 372 offene Handlungen;
- 3.974 Erinnerungen in der Langzeit, 3.940 mit Fakt, 148 mit Verweis;
- 718 Erfahrungen, 251 Planschritte > 0, 893 letzte Entscheidungen.

**Geprüft:**

- Format: Version 10, alle `PF_GED`-Felder, `stat.ged`, kein memName.
- Direkt nach dem Laden gleich; 60 Tage später bitgleich (Fingerabdruck und sortiert).
- Beide lernen in diesen 60 Tagen gleich viel (526 Erfahrungen).
- Die bisherigen Fälle (Tag 150, Haft, Bund) bleiben grün.

## 5. Aufholen in Stücken

`--aufholtest` bildet `aufholen()` der Oberfläche nach: bis Mitternacht stündlich, ganze Tage im Tagesschritt, dann stündlich bis zur
Zielstunde. Zwischen den Stücken wird gespeichert und geladen. Seed 1, ab Tag 200:

| Fall | 1 × 90 gegen 3 × 30 | über Gedächtnis-Ereignisse hinweg |
|---|---|---|
| (a) Grenzen um 0 Uhr (Tagesschritte wie im Spiel) | **bitgleich** (1.057 Einwohner) | offene Handlungen an den Grenzen 273 / 330; je Stück gelernt 125 / 164 / 209, Pläne beendet 469 / 615 / 810 |
| (b) ab 13 Uhr, rein stündlich | **bitgleich** (986 Einwohner) | offen an den Grenzen 283 / 309; gelernt 123 / 152 / 200 |
| (c) ab 13 Uhr wie `aufholen()` | nicht bitgleich (1.034 / 1.035), nur gemeldet | – |

- **Fall (c) ist die bekannte, ungekennzeichnete Näherung** aus `docs/GRENZEN.md` und `berichte/etappe0/BESTAND.md` Abschnitt 5. Jedes
  Stück rechnet seinen angebrochenen Tag stündlich statt im Tagesschritt.
- **Sie kommt nicht von Etappe 2.** `werkzeug/s2_aufholen.mjs` (`aufholen_basis_neu.txt`), Seeds 1–3:
  - `6c1741e`: (a) und (b) bitgleich, (c) verschieden (803/794, 940/989, 1.040/1.065 Einwohner);
  - Baukopie: ebenso (1.034/1.035, 960/1.003, 1.222/1.141).
- Ob Aufholen exakt (Option A) oder gekennzeichnet (Option B) wird, bleibt Noahs Entscheidung für Etappe 5. Daran habe ich nichts geändert.

## 6. Größe (wie `spielstandText`, `werkzeug/s2_groesse.mjs`)

| Stadt | Baukopie Version 10 (`R.GED = 1`) | Basis `6c1741e` | Fassung vor Schritt 2 (mit memName) |
|---|---|---|---|
| Seed 1, Tag 365 | 934.966 Zeichen (1.288 Einw.) | 841.339 (1.169) | 989.970 (1.288) |
| Seed 1, Tag 730 | 1.170.599 (1.569 Einw., pMax 1.713) | 1.011.778 (1.449) | 1.243.735 (1.569) |
| Große Stadt Tag 750 (Umland 300.000, Seed 2) | **4.190.777** (7.085 Einw.) | 4.174.643 (7.149) | – |
| ebenso, Schalter aus (gleiche Stadt wie die Basis) | 4.270.920 (7.149 Einw., pMax 7.188) | – | – |

- **Je Person:** 381 Byte roh gegen 371 in der Basis, also +10, wie in VERGLEICH.md Abschnitt 3 vorgesehen (+42 neu, −32 memName).
  - Die gleiche Stadt wird dadurch um 96.277 Zeichen größer.
  - Der Vergleich hatte ≈ 4,27 MB gerechnet; gemessen sind es 4.270.920 Zeichen.
- **Mit Gedächtnis** ist die große Stadt kleiner (7.085 statt 7.149 Einwohner) und liegt bei 4.190.777 Zeichen. Das ist unter 4,4 Mio. und
  unter der gemessenen Chromium-Grenze von 5.242.867 Zeichen.
- Die eigene Warnschwelle des Spiels (Meldung ab 4 MB beim Speichern) wird in der großen Stadt überschritten, wie schon in Version 9
  (4.174.643).

## 7. Browser-Test (`tests/p10speicher.cjs`, Port 9091)

**Umgebung:** Seitenserver `python3 -m http.server 9091 --bind 127.0.0.1 --directory E/stadt`, per PID beendet (9091 danach frei).
Chromium von Playwright, SwiftShader, `THREE_DIR=SP/three/package`, `STADT_GIT=<repo>`.

**Aufruf:** `PORT=9091 node tests/p10speicher.cjs` einzeln, nicht über `alle.sh`. Anfragen an `localhost:11434` bricht der Browser ab; der
dort laufende Dienst (PID 388) bleibt unberührt.

**Ergebnis 10 von 10 OK, 95 s** (`browser/p10speicher.log`, Bilder `browser/bilder_p10/`):

1. **Große Stadt** (`?debug&umland=300000&tage=750&seed=2`, im Browser 17 s gerechnet):
   - `spielstandText` hat Version 10 und 4.190.779 Zeichen;
   - in `localStorage` geschrieben und gleich zurückgelesen;
   - Format 10 (kein memName, alle `PF_GED`-Felder, `stat.ged`).
2. **Neu geladen ohne `?umland`:** Die Seite liest den Stand aus `localStorage` (`spielstandLesen`). Tag 750, 7.085 Einwohner, kein Dialog;
   Version, Einzelwerte, JSON-Teile und 172 Arrays sind gleich.
   - Verglichen wird ohne die Reihenfolge der Arrays: Nach dem Laden stehen die Arrays auf oberster Ebene von S in anderer Reihenfolge.
   - Das ist auch in `6c1741e` so (in Node nachgeprüft), und `simtest` sortiert dafür ebenfalls.
3. **Stand der Version 9** (`6c1741e`, Seed 1, Tag 150) mit der Policy aus Etappe 1 als Wahl:
   - Der Dialog nennt 9 → 10 und „neu trainieren“, dazu die Knöpfe Export / Neu / Übernehmen.
   - Nach der Übernahme: Version 10, gespeichert; die Meldung „… Es entscheiden die Regeln (Rückfall) …“ ist eine Warnung.
   - Das Fenster zeigt: „Abgelehnt: ki/policy_v9_lokal_1.json: Policy ungültig: trainiert auf Stadt-Version 9, diese Stadt ist Version 10
     (neu trainieren).“
4. **Neue Stadt, „Trainierte Policy“ gewählt:** abgelehnt mit „neu trainieren“, die Regeln bleiben. Die Meldung lautet „Keine gültige Policy
   in ki/. Umschalten nicht möglich, es entscheiden weiter die Regeln.“
5. **Stand der Version 10 in `6c1741e`** (`stadt.orig.html` per Route):
   - abgelehnt, nur „Export behalten“ und „Neu anfangen“;
   - der Stand bleibt gespeichert;
   - Titel dort „Spielstand ist von einer älteren Version“: irreführend, lässt sich in `6c1741e` aber nicht mehr ändern.
6. **„Version 11“ in Version 10:** Titel „… neueren Version“, nicht übernehmbar.
7. Konsole ohne Fehler; die gewollten Abbrüche an 11434 sind ausgenommen, wie in `browser_ki`.

**Nicht geprüft:** der Versionsdialog in Handybreite. Firefox und Safari (die Grenze von `localStorage` ist dort nicht gemessen).

## 8. KI-Policy aus Etappe 1

- **Die Ablehnung kommt allein aus `VERSION = 10`:** Die Prüfung `simVersion !== VERSION` gab es schon, mit dem Grund „(neu trainieren)“.
  In Node: `node tools/ki_liste.mjs --nur-pruefen` meldet „abgelehnt policy_v9_lokal_1.json: Policy ungültig: trainiert auf Stadt-Version 9,
  diese Stadt ist Version 10 (neu trainieren)“.
- **`ki/policy_v9_lokal_1.json` bleibt als Beleg.** `ki/policies.json` habe ich nicht neu geschrieben: Es nennt die Datei weiter, deshalb
  zeigt das Spiel die Ablehnung mit Grund an.
  - Achtung: `tools/ki_liste.mjs` ohne `--nur-pruefen` würde die Liste jetzt leer schreiben. Das Spiel sagte dann nur noch „nennt keine
    Policy“.
  - Ob die Liste so bleibt, ist für Schritt 4/5 zu klären (Annahme: bis zum neuen Training in Etappe 3 so lassen).

## 9. Nichts anderes geändert: Belege

- **Schalter aus = `6c1741e`** (`werkzeug/s2_gleich.mjs --gegen basis --aus`; `GED`, `OPFER_FREI`, `HAFT_EROEFFNUNG` = 0):
  - Seeds 1–3 × 730 Tage, stündlich und in Tagesschritten: jeden Tag alle Arrays, Einzelwerte, JSON-Teile und Schlüssel von S gleich.
  - Genau zwei begründete Ausnahmen: `p.memName` gibt es nicht mehr (in `6c1741e` an 730 von 730 Tagen ≠ 0, nur Anzeige), und
    `werte.version` ist 9 gegen 10.
  - Die `PF_GED`-Felder bleiben 0.
- **Mit Gedächtnis wie vor Schritt 2** (`--gegen sicherung`, Stärke 1,5, Rücklage 1):
  - Seeds 1–3 × 730 Tage, stündlich und in Tagesschritten, dazu Seeds 4–20 × 365 Tage stündlich: jeden Tag gleich, mit denselben zwei
    Ausnahmen.
  - memName war dort mit `R.GED` ohnehin immer 0.
  - Die Kalibrierung (KALIBRIERUNG.md Teil C, Stärke 1,5) gilt damit unverändert. Gates 1–80 und probe8 habe ich deshalb nicht neu
    gemessen.
- **Gate T** (`werkzeug/s2_gate_t.sh`, 6 Runden, Reihenfolge je Runde verschoben, immer ein Prozess; 1-Minuten-Last vor den Läufen 0,46–1,09,
  fremde Rechenprozesse 0 in 18 von 18):
  - neu 1.486 / 1.629 / 1.400 / 1.529 / 1.620 / 1.456 ms;
  - vorher Median 1.512,5 ms, Basis 4.287,5 ms;
  - neu/vorher 0,997 (gepaart 0,974), neu/Basis 0,352;
  - Gates in 18 von 18 Läufen bestanden.
- **Harte Grenze** (`werkzeug/s2_harte_grenze.mjs`, Kopie der Schritt-1-Prüfung mit `migriereGed` und `gedPruefen`):
  - keine Namen, kein Geschlecht, keine Herkunft, keine Eltern, kein Einzugstag;
  - `memBehalten` und `migriereGed` kopieren `memRef`/`memGen` nur mit;
  - memName steht im sim-Block nur noch in der Zeile, die es beim Laden alter Stände weglässt;
  - Namenstausch Seeds 1 und 2 × 200 Tage: jeden Tag alles gleich.

## 10. `simtest_alle` (15 von 22 mit Exit 0)

Lauf: `STADT_GIT=<repo> JOBS=2 bash tools/simtest_alle.sh`, 19:30–19:36 UTC, Logs in `simtest_alle/`.

- **Grün:** sicherheit, buergermeister, autos, militaer, haushalt, tech, regierung, kita, speichertest, **migrationstest** (neu grün),
  kitest, bau, waren, aufholtest, gate.
- **Rot wie vorher, mit denselben FEHL-Zeilen:** schule (1), rathaus (2), techfrueh (3), erweiterung (7), wachstum (3), kipolicy (3). Alle
  sind Vergleiche mit älteren Fassungen, die mit `R.GED = 1` laufen. Das bleibt für Schritt 4 („über alle drei Schalter aus“).
- **kipolicy_datei:** Die Policy wird jetzt beim Laden abgelehnt (Abbruch mit „… (neu trainieren)“ statt 3 FEHL). Schritt 4 soll hier die
  Ablehnung ausdrücklich prüfen (VERGLEICH.md Schritt 4).
- **Hinweis für Schritt 4:** `OHNE_SICH` und `spurRelativ` sind schon auf Version 10 vorbereitet (1.3). Dort fehlen noch die Schalter
  `GED`, `OPFER_FREI` und `HAFT_EROEFFNUNG` in der Liste `AUS` und die eigenen Spuren in `--rathaus`, `--schule`, `--techfrueh`.

## 11. Offen und Hinweise für die nächsten Schritte

- **Browser-Tests, die Version 9 erwarten** und in Schritt 4 angepasst werden müssen (nicht ausgeführt, aus dem Code gelesen):
  - `p6migration` (`NEU = 9`);
  - `browser_ki` (Version 9 im Spielstand, Test-Policies mit `simVersion` 9);
  - `techfrueh` (`u.v === 9` nach der Übernahme);
  - dazu `basis.cjs` (Kette bis 10) und `umgebung.cjs` (Fassung `6c1741e` fehlt in `FASSUNGEN`).
  - Den ganzen Lauf `tests/alle.sh` habe ich nicht gemacht; er würde auch einen KI-Nachbau auf 11434 starten, wenn dort nichts antwortet.
- **Schritt 3 (Karte):** Der Knopf „Warum?“ und die Liste bauen auf `Sim.warum` und den Beobachter; siehe SIM_FIX.md 5.2.
- **Nach der Übernahme** sind Fakt und Verweis der alten Erinnerungen 0. Die Karte darf dort „weil …“ nicht erwarten.
- **Schritt 5 (Doku):**
  - README: Speicherformat 10, Pflichtfelder, `gedPruefen`, Übernahme aus 9;
  - `docs/GRENZEN.md`: Aufholen (c) gilt weiter, jetzt auf Version 9 und 10 gemessen;
  - die Größe der großen Stadt über der eigenen 4-MB-Warnschwelle.
- **Nicht gemacht:** keine neue Kalibrierung und keine Gates 1–80 (Begründung in 9); keine Doku-Dateien außer `tests/LIESMICH.md`
  geändert.
- **Rechner:** nie mehr als zwei eigene Rechenprozesse. Gate T lief allein (fremde Rechenprozesse 0). Die Server 8000 und 11434 habe ich
  nicht angefasst, kein `pkill`/`killall`.
  - Zwei eigene Warteschleifen (`until … pgrep …`) blieben hängen, weil ihr Muster die eigene Befehlszeile traf. Ich habe sie per PID
    beendet (24475, 24560, 28035); das Messergebnis betraf das nicht.

## 12. Dateien und Befehle

- **Baukopie:** `E/stadt/stadt.html`, `E/stadt/tools/simtest.mjs`, `E/stadt/tests/p10speicher.cjs`, `E/stadt/tests/alle.sh`,
  `E/stadt/tests/LIESMICH.md`.
- **Werkzeuge:**
  - `E/werkzeug/s2_gleich.mjs`: Tag-für-Tag-Vergleich mit den zwei Ausnahmen;
  - `s2_groesse.mjs`;
  - `s2_gate_t.sh` und `s2_gate_t_auswertung.mjs`;
  - `s2_harte_grenze.mjs`;
  - `s2_namen_gegenprobe.mjs`;
  - `s2_aufholen.mjs`.
- **Rohdaten:** `E/mess/schritt2/`:
  - `aus_gleich_*.txt`, `ged1_gleich_*.txt`;
  - `groesse_*.jsonl`;
  - `gate_t/`;
  - `harte_grenze.txt`, `namen_gegenprobe.txt`;
  - `aufholen_basis_neu.txt`;
  - `ki_liste_nur_pruefen.txt`;
  - `simtest_alle/`, `browser/`;
  - `diff_*.txt`.
- **Nachrechnen** (im Ordner `E/stadt`):
  - `node tools/simtest.mjs --migrationstest --git <repo>` (etwa 70 s)
  - `node tools/simtest.mjs --speichertest` (7 s)
  - `node tools/simtest.mjs --aufholtest` (4 s)
  - `node ../werkzeug/s2_gleich.mjs --gegen basis --aus` (730 Tage, etwa 2 min)
  - Browser: `python3 -m http.server 9091 --bind 127.0.0.1 --directory .` starten, dann
    `PORT=9091 THREE_DIR=SP/three/package STADT_GIT=<repo> node tests/p10speicher.cjs`, danach den Server per PID beenden
