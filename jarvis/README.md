# JARVIS

Persönliches AI-Operating-System. Läuft lokal, spricht Deutsch, gehört dir.
Wird in zehn Phasen gebaut — der Stand steht in [STATUS.md](STATUS.md).

## Installation

```bash
pip install -r requirements.txt
```

## Start

```bash
python -m uvicorn main:app --reload
```

Dann <http://127.0.0.1:8000> öffnen.

---

## Vor dem ersten echten Modellaufruf

`cp .env.example .env`, dann eintragen:

| Variable | Woher |
|---|---|
| `JARVIS_TOKEN` | selbst würfeln, z. B. `python -c "import secrets;print(secrets.token_urlsafe(32))"` |
| `LLM_PROVIDER` | `anthropic` — der einzige, der in Phase 1 gebaut ist |
| `LLM_API_KEY` | Konto beim Anbieter, Key aus der Console |
| `LLM_MODEL` | Modell-ID **aus der Doku des Anbieters**, nicht raten |
| `LLM_PRICE_IN_PER_MTOK`, `LLM_PRICE_OUT_PER_MTOK` | Preisseite des Anbieters, in EUR je 1 Mio. Token |

**Ab dann kostet jeder Aufruf Geld.** Solange `LLM_PROVIDER` leer ist, läuft der
`FakeLLMProvider`: deterministische Antworten, kein Netz, keine Kosten. Die
Oberfläche kann man damit vollständig ausprobieren.

Bleiben die Preisfelder leer, steht in `llm_calls.cost_eur` eine `0.0` — keine
geschätzte Zahl. Eine erfundene Kostenrechnung wäre schlimmer als gar keine.

## Prüfen

```bash
pytest -q                       # ohne Netz, ohne Kosten
python -m scripts.smoke         # End-zu-End gegen den Fake-Anbieter
python -m scripts.smoke --real  # dasselbe mit echtem Modell — kostet Geld
```

`pytest` kann keinen echten Modellaufruf machen: `tests/conftest.py` sperrt die
httpx-Transportschicht für die ganze Testsitzung, `tests/test_no_network.py`
prüft nach, dass die Sperre hält.

## Zugangsschutz

Jeder `/api/`-Request braucht den Header `X-Jarvis-Token` (§0.4). Die
Oberfläche bekommt den Token beim Ausliefern von `/` eingesetzt — der
**LLM**-Key verlässt das Backend dabei nie.

Steht in der `.env` kein `JARVIS_TOKEN`, würfelt JARVIS beim Start einen und
schreibt ihn ins Log. Der Schutz ist damit nie aus, aber der Token ändert sich
bei jedem Neustart.

## Aufbau

```
main.py              Einstiegspunkt
core/config.py       .env, Preise, Budgets
core/db.py           SQLite: messages, llm_calls
core/llm.py          LLMProvider (abstrakt) · FakeLLMProvider · AnthropicProvider
api/                 Endpunkte, Zugangsschutz, Fehlerübersetzung
index.html           die gesamte Oberfläche, ohne Build-Step
docs/                Verträge, Phasenaufträge, Entscheidungen
```
