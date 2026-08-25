"""End-zu-End-Rauchtest der aktuellen Phase.

    python -m scripts.smoke              # Fake-Anbieter, kostet nichts
    python -m scripts.smoke --real       # echter Modellaufruf, kostet Geld

Ohne `--real` wird kein einziges Byte ins Netz geschickt, egal was in der
`.env` steht. Ein Rauchtest, der ungefragt Geld ausgibt, ist ein schlechter
Rauchtest.
"""

from __future__ import annotations

import argparse
import shutil
import sys
import tempfile
from pathlib import Path

from fastapi.testclient import TestClient

from api.app import create_app
from core import db
from core.config import Settings, get_settings

GRUEN, ROT, GRAU, AUS = "\033[32m", "\033[31m", "\033[90m", "\033[0m"


def await_sync(coro):
    """Eine Coroutine im Rauchtest ausfuehren - der laeuft synchron."""
    import asyncio

    return asyncio.run(coro)


def schritt(nummer: int, was: str) -> None:
    print(f"\n{GRAU}[{nummer}]{AUS} {was}")


def ok(text: str) -> None:
    print(f"    {GRUEN}✓{AUS} {text}")


def fehler(text: str) -> None:
    print(f"    {ROT}✗{AUS} {text}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Rauchtest von JARVIS.")
    parser.add_argument(
        "--real", action="store_true",
        help="echten Anbieter benutzen. Kostet Geld. Braucht LLM_API_KEY.",
    )
    args = parser.parse_args()

    tmp = Path(tempfile.mkdtemp(prefix="jarvis-smoke-"))
    try:
        if args.real:
            echt = get_settings()
            if not echt.llm_provider or not echt.llm_api_key or not echt.llm_model:
                fehler("--real braucht LLM_PROVIDER, LLM_API_KEY und LLM_MODEL in .env.")
                return 2
            settings = echt.model_copy(
                update={"db_path": tmp / "smoke.db", "jarvis_token": "smoke-token"}
            )
            print(f"{ROT}Achtung:{AUS} echter Modellaufruf an {settings.llm_model}. "
                  f"Das kostet Geld.")
        else:
            settings = Settings(
                _env_file=None, db_path=tmp / "smoke.db", jarvis_token="smoke-token"
            )

        kopf = {"X-Jarvis-Token": settings.jarvis_token}
        print(f"{GRAU}Datenbank:{AUS} {settings.db_path}")

        with TestClient(create_app(settings)) as client:
            schritt(1, "Zugangsschutz")
            assert client.get("/api/health").status_code == 401, "ohne Token muss 401 kommen"
            ok("ohne X-Jarvis-Token: 401")

            schritt(2, "Health")
            health = client.get("/api/health", headers=kopf)
            health.raise_for_status()
            h = health.json()
            print(f"    {h}")
            assert h["status"] == "ok", "Datenbank oder Anbieter nicht bereit"
            ok(f"Anbieter {h['provider']}, Modell {h['model']}, Phase {h['phase']}")

            schritt(3, "Oberflaeche")
            index = client.get("/")
            index.raise_for_status()
            assert "__JARVIS_TOKEN__" not in index.text, "Token wurde nicht eingesetzt"
            ok(f"GET / liefert {len(index.content)} Bytes HTML mit gesetztem Token")

            schritt(4, "Erste Nachricht")
            chat = client.post(
                "/api/chat", json={"message": "Hallo JARVIS, wer bist du?"}, headers=kopf
            )
            chat.raise_for_status()
            antwort = chat.json()
            assert {"reply", "task_id"} <= set(antwort), antwort
            print(f"    {GRAU}reply:{AUS}   {antwort['reply'][:200]}")
            print(f"    {GRAU}task_id:{AUS} {antwort['task_id']}")
            ok("Antwort im Format {reply, task_id, tool_calls}")

            schritt(5, "Zweite Nachricht (derselbe Verlauf)")
            zweite = client.post(
                "/api/chat", json={"message": "Und was kannst du noch nicht?"},
                headers=kopf,
            )
            zweite.raise_for_status()
            print(f"    {GRAU}reply:{AUS}   {zweite.json()['reply'][:200]}")
            ok("Antwort erhalten")

            schritt(6, "Werkzeuge (Phase 2)")
            from core.contracts import Permission
            from core.tools import registry
            from core.tools.dispatch import run_tool

            print(f"    {GRAU}registriert:{AUS} {', '.join(registry.names())}")
            rechnung = await_sync(run_tool("calculator", {"expression": "4380 * 0.17"}))
            print(f"    {GRAU}calculator:{AUS}  {rechnung.display}")
            assert rechnung.ok and rechnung.data["result"] == 744.6, rechnung

            uhr = await_sync(run_tool("clock"))
            print(f"    {GRAU}clock:{AUS}       {uhr.display}")
            assert uhr.ok, uhr

            verweigert = await_sync(
                run_tool("web_search", {"query": "x"}, max_permission=Permission.INFO)
            )
            print(f"    {GRAU}verweigert:{AUS}  {verweigert.error}")
            assert verweigert.ok is False, "web_search haette abgelehnt werden muessen"
            ok("Rechner, Uhr und Permission-Sperre arbeiten")

            schritt(7, "llm_calls")
            calls = db.list_llm_calls(settings.db_path)
            for c in reversed(calls):
                print(f"    {GRAU}{c.created_at}{AUS} {c.model} "
                      f"{c.in_tokens}/{c.out_tokens} Token, {c.duration_ms} ms, "
                      f"{c.cost_eur:.6f} EUR, ok={c.ok}")
            assert len(calls) == 2, f"erwartet 2 Aufrufe, sind {len(calls)}"
            ok("jeder Modellaufruf ist protokolliert")

            schritt(8, "Verlauf")
            messages = client.get("/api/messages", headers=kopf).json()
            for m in messages:
                print(f"    {GRAU}{m['role']:<9}{AUS} {m['content'][:80]}")
            assert len(messages) == 4, f"erwartet 4 Nachrichten, sind {len(messages)}"
            ok("vier Nachrichten in der richtigen Reihenfolge")

            schritt(9, "Neustart - liegt es wirklich auf der Platte?")

        with TestClient(create_app(settings)) as zweiter_start:
            messages = zweiter_start.get("/api/messages", headers=kopf).json()
            assert len(messages) == 4, messages
            spend = zweiter_start.get("/api/health", headers=kopf).json()["spend"]
            ok(f"nach Neustart: {len(messages)} Nachrichten, {spend['calls']} Aufrufe, "
               f"{spend['cost_eur']:.6f} EUR")
            if not spend["prices_configured"]:
                print(f"    {GRAU}Hinweis: LLM_PRICE_*_PER_MTOK sind leer - "
                      f"deshalb 0 EUR statt einer geschaetzten Zahl.{AUS}")

        print(f"\n{GRUEN}Rauchtest bestanden.{AUS}")
        return 0

    except AssertionError as exc:
        fehler(f"Erwartung verletzt: {exc}")
        return 1
    except Exception as exc:  # noqa: BLE001 - der Rauchtest soll alles melden
        fehler(f"{type(exc).__name__}: {exc}")
        return 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
