# FIX-10 — Messstrecke: plant JARVIS eigentlich gut?

> Auftrag von Noah, 27.08.2026. **Nur Schritt A.** Der Auftrag sagt am Ende:
> *„Halt nach A an. […] Vielleicht ist der Planer besser als gedacht — dann
> ist B überflüssig, und du hast eine Stunde gespart statt eine Verbesserung
> erfunden."*
>
> Diese Datei hält fest, was ich **nachgeprüft und gemessen** habe.

## Blocker

**Die drei Zahlen kann ich nicht liefern.** Die Messstrecke ruft echte
Modelle; hier gibt es keinen Key, und `CLAUDE.md` verbietet mir ausdrücklich,
JARVIS' Modell-Backend zu sein. Gebaut und bewiesen ist die Mechanik gegen den
`FakeLLMProvider`. Die echten Zahlen erzeugt Noah mit einem Befehl, sobald
sein Groq-Key läuft.

## Die Inventur des Auftrags — nachgemessen, und sie stimmt nicht mehr

| Behauptung | Gemessen |
|---|---|
| „`STATUS.md` weist 367 grüne Tests aus" | **1070** — der Auftrag ist auf dem Stand von vor FIX-05 bis FIX-07 |
| „Deine 14 Werkzeugbeschreibungen" | **18** — FIX-07 hat `datei_suchen`, `datei_lesen` und `kalender` gebracht, und `ask_agent` fehlte in der Liste schon vorher |
| „3.808 Zeichen · rund 950 Token" | **4.601 Zeichen · rund 1.150 Token** |
| „kürzeste 120 · längste 596 · Faktor 5" | stimmt weiterhin: `send_email` 120, `satellite_search` 596 |
| `Step`, `Plan`, `StepStatus` in `core/contracts.py:65-90` | `StepStatus` ab Zeile 65, `Step` ab **75** — `Plan` steht **nicht** dort, sondern in `core/planner.py:75` |

Die Zahl, die der Auftrag als Kernbefund nennt — **Faktor 5 zwischen der
kürzesten und der längsten Beschreibung** — hält also. Der Kontextpreis ist
sogar höher als angenommen: 1.150 statt 950 Token bei jedem Aufruf, der
Werkzeuge anbietet.

## Der Fund, der die Messung umbaut

Der Auftrag sagt: *„Auftrag durch den Planungspfad schicken, den erzeugten
Plan einsammeln, die geplanten Werkzeuge und ihre Reihenfolge mit der
Erwartung vergleichen."* Und er warnt im selben Absatz: *„Finde zuerst heraus,
wo die Planung im Code tatsächlich passiert. […] Rate es nicht."*

Nachgesehen. **Der Planer wählt keine Werkzeuge.**

`core/planner.erstelle_plan` liefert `Step`s mit `description` und einem
optionalen `agent`. Der Systemprompt (`core/planner.py:45`) redet über
Schritte und Agenten — Werkzeuge kommen darin nicht vor. Welche Werkzeuge
laufen, entscheidet erst das Modell in `core/tools/loop.run_tool_loop`, Zug
für Zug, mit den Ergebnissen der vorigen Werkzeuge in der Hand
(`reply.tool_uses` → `run_tool`).

Der Plan enthält also gar nichts, was sich mit `werkzeuge` und `kanten`
vergleichen ließe.

### Zwei Wege, beide mit Haken

**(a) Den echten Schleifenpfad fahren** und mitschreiben, was angefordert
wird. Misst das Richtige — führt aber Werkzeuge aus. Das kostet Geld, geht
ins Netz und trifft `send_email`. Schiebt man stattdessen erfundene
Zwischenergebnisse unter, misst man die Erfindung mit.

**(b) Das Modell nach seinem Werkzeugplan fragen**, ohne etwas auszuführen.
Genau das macht TaskBench: es bewertet den **vorhergesagten** Aufrufgraphen,
nicht den Lauf. Ein Aufruf je Fall, keine Nebenwirkungen.

**Gewählt ist (b)** — es ist die Methode, die der Auftrag als Vorbild nennt,
und die einzige, die ohne Erfindung auskommt.

**Was die Zahlen damit nicht sagen:** sie messen den *ausgesprochenen Plan*,
nicht das Laufzeitverhalten. Ein Modell kann gut planen und im Lauf trotzdem
danebengreifen. Das steht auch im Modulkopf von `scripts/plantest.py`, nicht
nur hier.

**Damit die Messung dem echten System entspricht,** kommen die Werkzeugtexte
aus `registry.all_tools()` — nicht aus einer Kopie. Wer in Schritt B eine
Beschreibung umschreibt, misst danach genau diese Änderung.

## Temperatur 0 geht nicht

Der Auftrag verlangt sie für die Reproduzierbarkeit. `LLMProvider.complete`
hat **keinen** Temperaturparameter, und `core/llm.py` sagt im Modulkopf, dass
`temperature`, `top_p` und `top_k` bewusst nicht gesendet werden — auf den
aktuellen Opus-Modellen ist jedes davon ein 400.

Sie nachzurüsten hieße, den Anbietervertrag zu ändern, den `runner`,
`agents` und `loop` alle benutzen — eine Änderung an Produktionscode für eine
Messung.

**Stattdessen wird die Reproduzierbarkeit gemessen statt erzwungen.**
`--laeufe 3` fährt den Satz dreimal und meldet die Spanne je Zahl. Genau das
verlangt Kriterium 4 ohnehin. Bleibt sie unter 0,05, ist die Messstrecke
brauchbar; bleibt sie es nicht, ist **das** der Befund — und dann ist zuerst
die Messung zu reparieren, nicht der Planer.

## Der Deckel läuft auf Token, nicht auf Euro

`Settings.cost_eur` gibt `0.0` zurück, solange keine Preise in der `.env`
stehen (`core/config.py:165`) — und bei einem kostenlosen Anbieter stehen dort
keine. Ein Eurodeckel wäre damit eine Attrappe, die nie greift.

Der harte Deckel läuft deshalb auf **Token**. Der Eurodeckel bleibt zusätzlich
und greift, sobald Preise eingetragen sind.

## Der Prüfsatz

30 Fälle in `tests/plandaten/faelle.json`, Mischung genau wie in A1 verlangt:

| Anzahl | Kategorie |
|---|---|
| 8 | ein Werkzeug |
| 10 | Kette mit echter Datenabhängigkeit |
| 6 | mehrere unabhängig |
| 4 | kein Werkzeug nötig |
| 2 | unmöglich |

**6 Fälle erwarten `[]`** — die vier ohne Bedarf plus die zwei unmöglichen.

Entstanden sind sie in einem Durchlauf mit vier Entwerfern (einer je
Kategorie) und drei Gegenlesern mit **verschiedenen** Blickwinkeln: „ein
Werkzeug zu viel", „ein Werkzeug zu wenig", „stimmen die Kanten". Sieben
Korrekturen wurden übernommen.

### Die beiden schärfsten Fälle

`unmoeglich-01` — *„Trag mir Freitag um 15 Uhr Zahnarzt in den Kalender
ein."* Das Werkzeug `kalender` **existiert**, kann aber nur lesen;
`termin_anlegen` wurde in FIX-07 §6 bewusst nicht gebaut. Ein Planer, der
`kalender` greift, fällt genau hier auf.

`unmoeglich-02` — *„Mach mir die Heizung auf 22 Grad."* JARVIS steuert keine
Geräte; „Computer Agent" steht in `CLAUDE.md` unter *dauerhaft gestrichen*.

### Eine Ermessensfrage, die ich offenlege

`einzel-02` (*„23 Prozent von 6340"*) und `kette-06` (*„wie viele Tage bis
Heiligabend"*) annotieren beide `calculator`. Begründung: die
Werkzeugbeschreibung sagt wörtlich *„Benutze das für JEDE Rechnung — auch für
einfache."* Rechnet das Modell im Kopf statt zu greifen, zählt das hier als
Fehler.

Man kann anderer Meinung sein. **Der Fall wird trotzdem nicht angepasst,
wenn die Zahl schlecht ausfällt** — der Auftrag verbietet das ausdrücklich,
und zu Recht: wer die Prüfung an die Antwort anpasst, misst nichts mehr.
Steht hier, damit man es beim Lesen der Zahl weiß.

## Warum ein Test in `pytest` dazugekommen ist

Kriterium 7 verlangt „`pytest` unberührt — Anzahl grüner Tests unverändert".
Das Skript selbst ruft echte Modelle und liegt deshalb unter `scripts/`. Die
**Metrik** ruft gar nichts: `f1()` ist eine reine Funktion über zwei Mengen,
und sie entscheidet über jede Zahl, die diese Messstrecke je ausgibt.

Fiele der Sonderfall „beide leer = 1.0" falsch aus, wären **6 der 30 Fälle**
systematisch falsch bewertet — und niemand sähe es, weil die Zahl ja eine Zahl
ist. `tests/test_plantest_metrik.py` prüft ihn, dazu Symmetrie, Wertebereich,
Kantenrichtung und das Herauslösen von JSON aus einer Modellantwort. Dazu ein
Test, der den Prüfsatz strukturell abklopft: 30 Fälle, 6 leere, jeder
Werkzeugname existiert wirklich, jede Kante zeigt auf ein deklariertes
Werkzeug.

Die Abweichung ist bewusst: die Testanzahl steigt um genau diese Datei und um
nichts sonst.

## Wie Noah die Zahlen erzeugt

```
python -m scripts.plantest --laeufe 3
```

Das kostet 90 Modellaufrufe. Bei Groqs Gratis-Stufe (1.000 Anfragen am Tag,
200.000 Token) passt das; die Trockenläufe hier lagen bei rund 26.500 Token
für 30 Fälle, also grob 80.000 für drei Läufe.

Drei Zahlen kommen heraus, dazu die Spanne über die drei Läufe. Ist eine
Spanne über 0,05, ist die Messung selbst kaputt und muss zuerst repariert
werden — nicht der Planer.
