# ANHANG B — Was ich gestrichen habe und warum

| Gestrichen | Grund |
|---|---|
| **Computer Agent** (Programme öffnen, UI steuern) | Größte Angriffsfläche des ganzen Systems bei geringstem Nutzen. Ein LLM mit Tastatur- und Mauszugriff auf deinem Rechner ist ein Fehlklick von einem sehr schlechten Tag entfernt. Wenn du es wirklich brauchst: eigenes Projekt, eigene VM, nicht hier. |
| **Postgres + pgvector ab Tag 1** | Zwei zusätzliche Systeme, bevor überhaupt Daten existieren. SQLite mit FTS5 trägt dich problemlos bis in die Tausende Einträge. Migration ist später ein Nachmittag. |
| **Next.js + React + TypeScript ab Tag 1** | Ein Build-System für ein Chatfenster. Kostet dich einen halben Tag npm-Fehlersuche, bevor die erste Nachricht durchgeht. |
| **Docker ab Tag 1** | Docker verpackt fertige Software. Es macht unfertige Software nur langsamer zu debuggen. |
| **Wake Word in v1** | Dauerhorchen, Falschauslösungen, Mikrofonrechte, Energieverbrauch. Push-to-Talk liefert 90 % des Nutzens für 5 % des Aufwands. |
| **10-Schritte-Beispielplan im Planner-Prompt** | Solche Beispiele bringen Modelle dazu, jede Frage in zehn Schritte zu zerlegen. "Wie spät ist es?" wird dann zu einem Rechercheprojekt. Der Planner braucht die gegenteilige Anweisung. |
| **"Model Router" mit Auto-Auswahl** | Erst brauchst du Messwerte, welches Modell für welche Aufgabe besser ist. Bis dahin ist der Router ein `dict` in der Config. Trag echte Modell-IDs ein, rate keine. |

**Was ich hinzugefügt habe, weil es fehlte:** Budget und Kill-Switch (§0.5) · JSON-Robustheit und Retry-Grenzen (§0.6) · API-Token auch lokal (§0.4) · Definition of Done pro Phase · das Verbot, den API-Key ins Frontend zu legen · Bodenauflösung als Pflichtfeld im Satellite Agent · Non-Goals.

---

# ANHANG C — Anti-Patterns, die du dem Modell verbieten musst

Hänge das bei Bedarf an einen Phasen-Block an:

```
VERBOTENE ANTWORTMUSTER:

- "Hier ist die vollständige Implementierung" für Code, den du nicht ausgeführt hast.
- Dateien mit ausschließlich Klassenrümpfen und `pass`.
- Mehr als eine Ebene Ordnerstruktur ohne eine einzige lauffähige Datei darin.
- Endpunkte, Parameter oder Modell-IDs, die du nicht in einer Doku gesehen hast.
- "Du musst nur noch deinen API-Key eintragen" — ohne zu sagen, wo man ihn bekommt
  und was er kostet.
- Eine Zusammenfassung am Ende, die mehr behauptet als der Code kann.
- Fortfahren mit Phase N+1, wenn die Definition of Done von Phase N nicht erfüllt ist.
- Stillschweigendes Erhöhen von Budgets, Timeouts oder Retry-Grenzen, um einen
  Testfall grün zu bekommen.
```

---

# ANHANG D — Ehrliche Einschätzung des Umfangs

Damit du weißt, worauf du dich einlässt:

| Phase | Realistischer Aufwand für dich mit Claude als Coding-Engine |
|---|---|
| 1 Skeleton | 1 Abend |
| 2 Tools | 1–2 Abende |
| 3 Memory | 2 Abende |
| 4 Planner + Agent | 3–4 Abende, hier wird es zum ersten Mal richtig fummelig |
| 5 Permissions | 1 Abend |
| 6 Hermes | 3–5 Abende, viel Prompt-Tuning |
| 7 Dashboard | 2–3 Abende |
| 8 Satellite | 3–5 Abende, davon die Hälfte Doku lesen |
| 9 Voice | 1–2 Abende (Web Speech API) |
| 10 Härten | 2–3 Abende |

Summe: grob 20–30 Abende, verteilt über Monate — bei laufendem Weiterarbeiten, nicht bei Neustart nach drei Wochen Pause.

**Laufende Kosten:** jeder Hermes-Task mit Recherche kostet echtes Geld. Trag die Preise deines Anbieters in `.env` ein und setz `max_cost_eur` bewusst. Ein Bug in einer Retry-Schleife kann über Nacht mehr verbrauchen, als du erwartest — deshalb steht der Kill-Switch in §0.5 und nicht in Phase 10.

**Der ehrlichste Rat in diesem Dokument:** Wenn nach Phase 3 die Luft raus ist, hast du trotzdem etwas Fertiges — einen Chat-Assistenten mit Tools und Gedächtnis, den du täglich benutzen kannst. Das ist mehr wert als ein zu 60 % gebautes Hermes-System. Phase 1–3 sind so geschnitten, dass sie allein einen Sinn ergeben.
