# Sprach-Abnahme — fünf Minuten, vier Schritte

> FIX-05 Schritt C. **Hier wird nichts gebaut, nur abgenommen.**
>
> Der Sprachpfad steht seit Phase 9: `index.html:1680-1814` — `BrowserVoice()`
> mit `SpeechRecognition` (Zuhören) und `speechSynthesis` (Vorlesen),
> Push-to-Talk auf `#btn-mic`, DE/EN-Umschalter auf `#btn-sprache`, das
> `voice`-Flag an `POST /api/tasks` (`index.html:1429`) und `SPRACHSTIL` im
> Systemprompt (`core/agents.py:26`).
>
> **Warum Claude das nicht selbst prüfen kann:** Headless-Chromium hat kein
> Mikrofon und keine Sprachsynthese. Alle vier Kriterien brauchen beides.
> Deshalb steht Phase 9 in `STATUS.md` auf `◐` — nicht weil Code fehlt.

## Vorher: zwei Dinge, ohne die es nicht geht

1. **Chrome oder Edge.** Firefox hat `SpeechRecognition` nicht. Ist er nicht
   da, schaltet JARVIS den Mikrofonknopf grau und schreibt den Grund in den
   Titel (`index.html:1818`) — das ist dann kein Fehler, sondern der Browser.
2. **`http://127.0.0.1:8000`, nicht die LAN-Adresse.** Browser geben das
   Mikrofon nur auf `localhost` oder über HTTPS frei. Über
   `http://192.168.x.x` kommt „Kein Zugriff aufs Mikrofon".

Starten:

```bash
cd jarvis
uvicorn main:app --reload
```

Dann `http://127.0.0.1:8000` öffnen, Token eingeben. Beim ersten Drücken des
Mikrofons fragt Chrome nach Erlaubnis — **erlauben**, sonst schlagen alle vier
Schritte fehl.

---

## Schritt 1 — Halten, sprechen, loslassen

> Prüft DoD 1: *„Taste halten, sprechen, loslassen → Transkript erscheint im
> Chat und der Task startet."*

1. Mikrofonknopf rechts im Eingabefeld **gedrückt halten** (nicht klicken).
2. Der Knopf färbt sich, unten steht „Ich höre… loslassen zum Senden."
3. Sag: **„Was ist die Hauptstadt von Norwegen?"**
4. Loslassen.

**Sichtbares Ergebnis:** Dein Satz steht als deine Nachricht im Verlauf, und
darunter läuft sofort ein Plan-Kasten mit einer Vorgangsnummer.

| geht | Was du siehst |
|------|---------------|
| ja   | Der gesprochene Satz steht da, ein Vorgang läuft an |
| nein | Was steht stattdessen unten in der Statuszeile? Wörtlich aufschreiben |

---

## Schritt 2 — Die Antwort wird vorgelesen und lässt sich abbrechen

> Prüft DoD 2: *„Die Antwort wird vorgelesen und lässt sich abbrechen."*

1. Warte, bis der Vorgang aus Schritt 1 fertig ist.
2. **Die Antwort wird von selbst vorgelesen.** Der Mikrofonknopf leuchtet
   dabei in der Akzentfarbe.
3. Während sie noch spricht: den Mikrofonknopf **kurz antippen**.

**Sichtbares Ergebnis:** Die Stimme bricht mitten im Satz ab, der Knopf hört
auf zu leuchten.

> **Warum tippen und nicht ein eigener Stopp-Knopf:** derselbe Knopf hält an
> und hört zu (`hoerenStarten` ruft zuerst `voice.stopp()`,
> `index.html:1765`). Ein kurzer Tipper stoppt also das Vorlesen und startet
> eine leere Aufnahme, die beim Loslassen mit „Nichts verstanden." endet. Das
> ist erwartet, kein Fehler.

**Gegenprobe, die dazugehört:** tipp dieselbe Frage **mit der Tastatur** ein
und schick sie ab. Sie darf **nicht** vorgelesen werden — nur gesprochene
Fragen werden vorgelesen (`index.html:1486`, geprüft von
`tests/test_voice.py::test_nur_gesprochene_fragen_werden_vorgelesen`).

| geht | Was du siehst |
|------|---------------|
| ja   | Liest vor, Tippen bricht ab, getippte Frage bleibt stumm |
| nein | Welches der drei? |

---

## Schritt 3 — Gesprochen ist kürzer als getippt

> Prüft DoD 3: *„Die Antwort ist im Sprachmodus kürzer als im Textmodus — der
> Systemprompt muss das erzwingen."*

Dieselbe Frage zweimal, einmal gesprochen, einmal getippt. Nimm eine, bei der
die lange Antwort wirklich lang wäre:

> **„Erklär mir, wie ein Satellit ein Bild von der Erde macht."**

1. Erst **sprechen** (halten, fragen, loslassen). Antwort abwarten.
2. Dann **tippen**, wortgleich. Antwort abwarten.

**Sichtbares Ergebnis:** Die gesprochene Antwort ist spürbar kürzer —
höchstens drei Sätze, keine Aufzählung, keine Überschrift, keine URL im Text.
Die getippte darf all das haben.

Das kommt nicht von der Oberfläche, sondern aus `SPRACHSTIL`
(`core/agents.py:26-35`), das `api/tasks.py:263` nur bei `voice=true`
anhängt. Wenn beide Antworten gleich lang sind, ist das Flag nicht
angekommen — dann bitte melden, das wäre ein echter Fehler.

| geht | Sätze gesprochen | Sätze getippt |
|------|------------------|---------------|
|      |                  |               |

---

## Schritt 4 — Deutsch und Englisch

> Prüft DoD 4: *„Deutsch und Englisch funktionieren beide."*

1. Auf den **DE**-Knopf links vom Mikrofon klicken — er wird zu **EN**.
2. Halten und auf Englisch fragen: **„What is the capital of Norway?"**
3. Loslassen.

**Sichtbares Ergebnis:** Das Transkript ist englisch geschrieben (nicht
„Wott is se kepitel"), und die Antwort wird mit **englischer** Stimme
vorgelesen, nicht mit deutscher.

Danach zurück auf **DE** und einen deutschen Satz — beides muss gehen, nicht
nur das zuletzt eingestellte.

| geht | Transkript EN | Stimme EN | zurück auf DE geht |
|------|---------------|-----------|--------------------|
|      |               |           |                    |

---

## Was diese Abnahme ausdrücklich NICHT prüft

- **Wake Word** und **Streaming-STT** sind in `CLAUDE.md` verboten und nicht
  gebaut. `continuous = false` und `interimResults = false` bleiben stehen
  (`index.html:1711-1712`), und
  `tests/test_voice.py::test_die_oberflaeche_hat_push_to_talk_und_keine_dauererkennung`
  hält das fest. Wenn dir „es hört nicht dauerhaft zu" auffällt: das ist
  Absicht.
- **Wie gut** die Erkennung ist. Das ist Chromes Modell, nicht JARVIS.
- Andere Sprachen als DE und EN. `SPRACHEN` kennt genau diese zwei
  (`index.html:1749`).

## So kommt dein Ergebnis in die Akten

Schick die vier Tabellen zurück — auch die Zeilen, wo „nein" steht,
besonders die. Der Eintrag in `STATUS.md` bekommt dann den Vermerk, dass der
Beleg **vom Nutzer** stammt und nicht aus einem ausgeführten Befehl, genau wie
der Groq-Eintrag vom 26.08.2026. Ein „✓" ohne diesen Vermerk wäre in dieser
Datei eine Lüge.
