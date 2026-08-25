# PHASE 11 — WELTLAGE (Globus, sprachgesteuert)

> **Voraussetzungen, hart:** Phase 2 (Tools), Phase 4 (Research Agent + `fetch_url`),
> Phase 9 (Voice) müssen in `STATUS.md` auf FERTIG stehen. Solange FIX-01 offen ist,
> läuft in JARVIS kein einziger Auftrag durch — diese Phase kann dann nicht getestet werden.

---

## 1. Die Bildregel — der Kern dieser Phase

**Das Bild kommt aus der Quelle, oder es gibt kein Bild.**

Konkret: der `fetch_url`-Tool holt serverseitig die Artikelseite und liest das
`og:image`-Meta-Tag. Das ist genau das Bild, das der Verlag selbst für Vorschauen
bereitstellt — dasselbe, was WhatsApp, Slack und Signal beim Linkteilen zeigen.

```python
async def hole_quellbild(url: str) -> str | None:
    """Serverseitig, weil der Browser an CORS scheitert.
    Gibt die og:image-URL zurueck oder None. Niemals einen Ersatz."""
    # robots.txt respektieren, 5 s Timeout, ehrlicher User-Agent
    # og:image -> twitter:image -> None. Kein Fallback auf Stockfotos.
```

**Verboten, ohne Ausnahme:**

- Stockfotos, die zum Thema passen. Ein Bild vom Kreml neben einer Moskau-Meldung,
  das nicht zu dieser Meldung gehört, ist eine Attrappe — auch wenn es echt aussieht.
- KI-generierte Bilder zu Nachrichtenlagen. Schlimmer als Stock.
- Bilder aus einer Bildersuche, die nur thematisch passen.
- Ein Platzhalterbild, das wie ein Foto aussieht.

**Wenn kein `og:image` da ist:** Karte des Ereignisorts als Kachel, mit sichtbarem
Label „keine Quellgrafik". Sieht bewusst anders aus als ein Foto. Der Nutzer muss auf
einen Blick sehen, ob er ein Foto oder einen Ersatz vor sich hat.

**Bilder werden nicht neu gehostet.** Direkt einbinden, Herkunft im Bild-Overlay,
`referrerpolicy` nicht abschalten. Wenn ein Verlag das Einbetten unterbindet: kein Bild.

### 1b. Was JARVIS über das Bild sagen darf

Die Bildbeschreibung kommt **aus der Quelle**: `og:image:alt`, das `alt`-Attribut oder
die `<figcaption>` des Artikels. Geschrieben von jemandem, der wusste, was auf dem Foto
ist. Kostet nichts extra, ist präzise, und JARVIS kann sie vorlesen.

**Kein Vision-Modell auf fremde Nachrichtenfotos.** Zwei Gründe, beide hart:

1. Es benennt Personen falsch. Bei echten Menschen in Nachrichtenlagen ist das kein
   Schönheitsfehler, sondern eine Falschbehauptung über eine reale Person.
2. Es beschreibt Dinge, die nicht im Bild sind, und klingt dabei sicher — dieselbe
   Mechanik wie eine erfundene Flugzeugzahl, nur in Bildform.

**Erlaubt** ist das Vision-Modell ausschließlich auf Bildern, die JARVIS selbst erzeugt
hat: eigene Karten, eigene Diagramme, Satellitenkacheln aus Phase 8. Dort weiß er, was
er gezeichnet hat.

**Keine Caption vorhanden → JARVIS sagt zum Bild nichts.** Kein „auf dem Bild ist
vermutlich", kein „zu sehen ist offenbar". Das Bild steht dann einfach mit seinem
Herkunftslabel da.

---

## 2. Kein Link — aber Herkunft bleibt sichtbar

- Jede Karte trägt fest eingeblendet: **Medium · Datum · Uhrzeit**. Nicht klickbar, aber da.
- Über dem Bild liegt ein Verlauf mit demselben Label, damit das Bild nie ohne
  Zuordnung im Raum steht — auch nicht auf einem Screenshot.
- Die vollständige URL wird in `task_log` gespeichert und ist **in JARVIS** unter
  „Details" einsehbar. Nichts geht verloren, es verlässt nur nicht die App.
- **Ohne Medium und Datum wird die Meldung verworfen.** Das ist die Ersatzregel für
  den weggefallenen Link und sie ist nicht verhandelbar.

---

## 3. Alle Länder — aber nicht auf einmal

195 Länder × eine Recherche = 195 Aufträge pro Aktualisierung.

```
Kosten pro Weltdurchlauf = 195 × (Kosten eines Research-Tasks mit Websuche)
```

Trag den echten Preis deines Anbieters ein. Bei jedem realistischen Wert liegt ein
kompletter Durchlauf weit über `BUDGET_MAX_COST_EUR=0.50` — und zwar pro Aktualisierung.

**Deshalb:**

- Der Globus zeigt **alle** Länder als anwählbare Flächen. Das ist billig, das sind Geodaten.
- Geladen wird **nur das angewählte Land**, ein Auftrag.
- Cache pro Land, TTL 60 Minuten. Zweiter Klick innerhalb der Stunde kostet nichts.
- Beim Start werden **6 Ereignisse weltweit** geladen, nicht 195. Das ist die Übersicht.
- Ein sichtbarer Zähler zeigt Cache-Treffer vs. echte Abfragen und die Tageskosten.

Wer 195 Länder gleichzeitig live hält, hat kein Dashboard gebaut, sondern ein Abo.

---

## 4. „Richtig krasse Antworten" — messbar definiert

**Krass heißt hier: Dichte an belegten Einzelheiten. Nicht Tonfall.**

| Nicht krass, nur laut | Krass, weil belegt |
|---|---|
| „ESKALATION IM PAZIFIK" | „Reuters, 14:20 MEZ — dritter Vorfall in 9 Tagen" |
| „Massive Bauarbeiten" | „20 Std./Tag, 7 Tage, Bauherr nennt 65 % Fertigstellung" |
| „Die Lage spitzt sich zu" | (streichen — keine Aussage) |

Regeln für den Systemprompt des Agents:

1. Jede Zahl braucht ihre Quelle in derselben Meldung. Zahl ohne Quelle → Meldung raus.
2. Keine Superlative, die nicht in der Quelle stehen.
3. Keine Vergleiche zum Mittelwert („mehr als sonst"), außer die Quelle nennt den Mittelwert.
4. Keine Prognose. Was passiert ist, nicht was passieren wird.
5. Zwei Sätze pro Meldung. Kürze zwingt zu Substanz.
6. Bei dünner Quellenlage: **weniger Meldungen**, nicht ausgeschmückte.

---

## 4b. Lehrermodus — zwei getrennte Blöcke pro Meldung

```
┌─ MELDUNG ────────────────────────────────┐
│  Aus der Quelle. Zwei Sätze.             │
│  REUTERS · 25.08.2026 · 14:20            │
├─ EINORDNUNG ─────────────────────────────┤   <- andere Fläche, andere Kante
│  JARVIS erklärt. Max. drei Sätze.        │
│  Kein Link, kein Beleg — und das steht   │
│  auch dran.                              │
└──────────────────────────────────────────┘
```

Regeln für die Einordnung:

- Beantwortet genau eine von drei Fragen: *Warum ist das wichtig? Was war vorher?
  Was müsste man wissen, um das einzuordnen?*
- Maximal drei Sätze.
- **Keine Prognose.**
- Unsicherheit wird ausgesprochen, nicht weggelassen: „Das ist Hintergrundwissen von
  mir, nicht aus der Quelle — Stand kann veraltet sein."
- **Hat JARVIS keinen Kontext, sagt er das in einem Satz** und die Einordnung bleibt leer.

Die Trennung ist nicht Kosmetik. Sie ist das eigentliche Lehrmittel: du siehst bei jeder
einzelnen Meldung, wo die Belege aufhören und die Erklärung anfängt.

---

## 4c. „Er muss immer was sagen" — der Konflikt

**Das beißt sich direkt mit „nichts erfinden".** Wenn Dauerreden Pflicht ist, redet
JARVIS auch dann, wenn es nichts zu sagen gibt — und dann erfindet er.

Auflösung: JARVIS redet oft, aber kurz, und **Schweigen ist ein gültiger Zustand.**

Erlaubte Äußerungen, wenn nichts Großes passiert ist:

- „Drei belegte Meldungen aus Moskau. Jüngste um 14:20."
- „Zwei Meldungen verworfen, keine Quelle."
- „Zu Namibia finde ich heute nichts."
- „Aus dem Cache, 40 Minuten alt."

Verboten als Füllmaterial:

- Sätze ohne Informationsgehalt: „Die Lage bleibt angespannt", „es entwickelt sich weiter".
- Die Schlagzeile in anderen Worten wiederholen.
- Ein zweiter Modellaufruf, nur um etwas zum Sagen zu haben.

**Beim Flug** sagt JARVIS **einen** Satz beim Start („Ich schaue nach Moskau") und dann
nichts mehr, bis die Karten da sind.

---

## 5. Sprachsteuerung, kein Scrollen

- Vollbild. **Kein Scrollbalken, nirgends.** Maximal 5 Karten gleichzeitig.
- Push-to-Talk (Leertaste halten) und ein Mikrofonknopf.
- Erkannte Absichten: `<Land>` · „weltweit" · „mehr dazu" · „zurück" · „lauter/leiser".
- Der Globus dreht zur Position, während gesucht wird. Die Drehung **ist** die Ladeanzeige.
- JARVIS liest maximal die Schlagzeilen vor, nicht die Zusammenfassungen.
- Alles ist ohne Stimme mit Maus/Tastatur bedienbar. Sprache ist eine Abkürzung, keine Pflicht.

---

## 6. Design

- Three.js-Globus, Import-Map mit fester Version, Ländergrenzen aus einem TopoJSON.
- Dunkel: Hintergrund nahezu schwarz, Landflächen dunkelgrau, angewähltes Land in der
  Akzentfarbe. Eine Akzentfarbe, sonst Graustufen.
- Glas: dunkle Basis mit ~80 % Deckkraft plus `backdrop-filter`. **Nicht** nur weißer
  Schleier — über einer hellen Fläche ist der Text sonst unlesbar.
- Bewegung 200–400 ms, `cubic-bezier(.4,0,.2,1)`. Globusdrehung max. 1,8 s.
- `prefers-reduced-motion` schaltet die Drehung ab und springt direkt.
- Performancebudget: 60 fps auf einem Mittelklasse-Laptop, Globus pausiert außerhalb
  des Viewports.

---

## 7. Datenvertrag

```python
@dataclass
class Meldung:
    schlagzeile: str
    kurz: str                 # max 2 Saetze
    medium: str               # Pflicht
    veroeffentlicht: datetime # Pflicht
    quell_url: str            # gespeichert, nicht angezeigt
    bild_url: str | None      # NUR og:image der Quelle
    bild_herkunft: str | None # Pflicht, sobald bild_url gesetzt ist
    lat: float | None
    lon: float | None
    land_iso: str
```

Verwerfen, wenn: `medium` leer · `veroeffentlicht` fehlt · `quell_url` ungültig ·
`bild_url` gesetzt aber `bild_herkunft` leer. Die Anzahl der verworfenen Meldungen
steht sichtbar in der Statusleiste.

---

## 8. Definition of Done

1. Globus zeigt alle Länder, jedes anwählbar. Ein Klick auf Deutschland lädt genau
   **einen** Auftrag — im Log nachgewiesen.
2. Zweiter Klick innerhalb von 60 Minuten kostet **null** neue Aufträge (Cache-Treffer im Log).
3. Jede angezeigte Karte trägt Medium und Datum. Eine Testmeldung ohne Medium wird
   nachweislich verworfen und im Zähler hochgezählt.
4. **Bildtest:** Ein Artikel mit `og:image` zeigt genau dieses Bild. Ein Artikel ohne
   `og:image` zeigt die Kartenkachel mit „keine Quellgrafik" — **kein** Ersatzfoto.
   Beide Fälle als automatisierter Test mit einer lokalen Fixture-Seite.
5. **Negativtest, automatisiert:** Bei einer Anfrage ohne belegbare Treffer zeigt die
   Oberfläche „0 belegte Meldungen" und **keine** Karte. Kein erfundener Inhalt.
6. Kein Scrollbalken bei 1280×720 und bei 1920×1080. Headless nachgewiesen.
7. Push-to-Talk: gesprochen „Moskau" → Globus dreht → Meldungen erscheinen. Ohne Stimme
   ist derselbe Weg per Tastatur begehbar.
8. Tageskosten und Cache-Quote sind in der Oberfläche sichtbar und stimmen mit
   `llm_calls` überein — nachgerechnet.
9. `prefers-reduced-motion`: keine Drehung, kein Übergang.
10. **Trennungstest:** Meldung und Einordnung sind zwei getrennte Flächen. Die
    Einordnung trägt sichtbar den Hinweis, dass sie nicht aus der Quelle stammt.
    Screenshot-geprüft.
11. **Captiontest:** Fixture-Seite **mit** `og:image:alt` → JARVIS liest die Caption vor.
    Fixture-Seite **ohne** → JARVIS sagt zum Bild kein Wort. Beides automatisiert.
12. **Kein Vision-Aufruf auf Fremdbildern:** Nach einem vollen Durchlauf steht im
    `llm_calls`-Log **null** Vision-Aufruf mit einer externen Bild-URL.
13. **Schweigetest:** Eine Anfrage ohne Treffer erzeugt „Dazu finde ich heute nichts",
    keine Karte, keinen Füllsatz. Automatisiert.
14. **Kontextlücke:** Eine Meldung zu einem Thema, zu dem das Modell nichts weiß, zeigt
    eine leere Einordnung mit Hinweis — keine ausgedachte Hintergrunderklärung.

---

## 9. Was du dabei nicht bauen sollst

- Kein Vorabladen aller Länder „für später".
- Keine Live-Aktualisierung im Hintergrund. Aktualisiert wird auf Anforderung.
- Keine Kennzahl im HUD, die nicht aus echten Daten kommt. Kein „Threat Level",
  kein „Uplink", keine Zähler, die nur hübsch aussehen.
- Kein zweiter Modellaufruf, um eine Meldung „spannender zu formulieren".
