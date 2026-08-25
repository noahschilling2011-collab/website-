# website-

Dieses Repository ist eine Werkstatt: pro Branch ein Projekt. Auf **diesem**
Branch entsteht JARVIS. Das ältere Blitzerwarner-Projekt liegt unangetastet in
[`blitzerwarner/`](blitzerwarner/README.md) daneben.

---

# JARVIS

Persönliches AI-Operating-System. Läuft lokal, spricht Deutsch, gehört dir.
Wird in zehn Phasen gebaut — **Phase 1 ist fertig**, der genaue Stand steht in
[STATUS.md](STATUS.md).

Kein Account, kein Deployment, keine Nutzerverwaltung. JARVIS läuft auf
`127.0.0.1` und redet mit genau einem Menschen.

## Was Phase 1 kann

Eine Nachricht geht vom Browser ans eigene Backend, von dort an ein Modell und
zurück — und ist nach dem Neuladen noch da. Mehrere Konversationen, Verlauf,
Umbenennen, Löschen. Mehr nicht, und das mit Absicht: Streaming, Werkzeuge,
Aufgaben und Agenten haben ihre eigenen Phasen.

## Loslegen

```bash
pip install -r requirements.txt
uvicorn main:app --reload
```

Dann [http://127.0.0.1:8000](http://127.0.0.1:8000) öffnen. Ohne weitere
Einrichtung läuft der **Fake-Anbieter**: deterministische Antworten, kein Netz,
keine Kosten. Gut genug, um alles außer der Modellqualität zu prüfen.

### Echtes Modell anschließen

```bash
cp .env.example .env
```

In der `.env`:

```
JARVIS_PROVIDER=anthropic
ANTHROPIC_API_KEY=sk-ant-...
```

**Ab hier kostet jeder Aufruf Geld.** Preise je eine Million Token:

| Modell | Eingabe | Ausgabe |
|---|---|---|
| `claude-opus-5` (Voreinstellung) | 5 $ | 25 $ |
| `claude-sonnet-5` | 2 $ | 10 $ |
| `claude-haiku-4-5` | 1 $ | 5 $ |

Der Key liegt ausschließlich im Backend. Der Browser sieht ihn nie und ruft
auch kein Modell direkt auf.

## Prüfen

```bash
pytest -q                       # 72 Tests, kein Netz, kostenlos
python -m scripts.smoke         # End-zu-End gegen den Fake-Anbieter
python -m scripts.smoke --real  # dasselbe mit echtem Modell — kostet Geld
```

`pytest` kann keinen echten Modellaufruf machen: `tests/conftest.py` sperrt die
httpx-Transportschicht für die ganze Testsitzung, und `tests/test_no_network.py`
prüft nach, dass die Sperre hält.

## Aufbau

```
main.py              uvicorn-Einstiegspunkt
core/
  config.py          Konfiguration aus Umgebung und .env
  db.py              SQLite, kein ORM
  schema.sql         conversations, messages
  llm.py             LLMProvider · FakeLLMProvider · AnthropicProvider
api/
  app.py             Anwendungsfabrik, Fehlerübersetzung
  routes.py          Endpunkte
  schemas.py         was über HTTP geht
web/index.html       die gesamte Oberfläche, ohne Build-Step
scripts/smoke.py     Rauchtest der aktuellen Phase
docs/
  contracts.md       Tool · ToolResult · Permission · Task · Step · Agent
  phases/            ein Auftrag je Phase
```

## Entscheidungen, die erklärungsbedürftig sind

**Kein `anthropic`-SDK.** Der Stack in `CLAUDE.md` legt `httpx` fest. Der
Provider spricht deshalb die dokumentierte Messages-API direkt. Das SDK wäre
sonst die naheliegendere Wahl — ein Wechsel ist eine Stack-Änderung und wird
vorher besprochen, nicht nebenbei gemacht.

**SQLite statt Postgres.** Für einen Nutzer reicht es, und es hat keinen
Betriebsaufwand. Ein Wechsel ist Phase 10 — und nur, wenn eine Messung zeigt,
dass es nötig ist.

**Eine `index.html` ohne Build-Step.** Bis Phase 7. Solange die Oberfläche in
eine Datei passt, ist das die Variante mit den wenigsten beweglichen Teilen.

**`temperature` wird nicht gesendet.** Auf den aktuellen Opus-Modellen ist der
Parameter entfernt und ergibt einen 400. Dasselbe gilt für
`thinking.budget_tokens`. Ein Test hält das fest.

## Mitarbeiten

`CLAUDE.md` enthält die Regeln, `STATUS.md` den Stand, `docs/phases/` die
Aufträge. Es wird immer nur die als `AKTUELL` markierte Phase bearbeitet.
