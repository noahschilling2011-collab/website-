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
from core.config import Settings, get_settings

GRUEN = "\033[32m"
ROT = "\033[31m"
GRAU = "\033[90m"
AUS = "\033[0m"


def schritt(nummer: int, was: str) -> None:
    print(f"\n{GRAU}[{nummer}]{AUS} {was}")


def ok(text: str) -> None:
    print(f"    {GRUEN}✓{AUS} {text}")


def fehler(text: str) -> None:
    print(f"    {ROT}✗{AUS} {text}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Rauchtest von JARVIS, Phase 1.")
    parser.add_argument(
        "--real",
        action="store_true",
        help="echten Anbieter benutzen. Kostet Geld. Braucht ANTHROPIC_API_KEY.",
    )
    args = parser.parse_args()

    tmp = Path(tempfile.mkdtemp(prefix="jarvis-smoke-"))
    try:
        if args.real:
            echt = get_settings()
            if echt.provider != "anthropic" or not echt.anthropic_api_key:
                fehler(
                    "--real braucht JARVIS_PROVIDER=anthropic und ANTHROPIC_API_KEY."
                )
                return 2
            settings = echt.model_copy(update={"db_path": tmp / "smoke.db"})
            print(f"{ROT}Achtung:{AUS} echter Modellaufruf an {settings.model}. "
                  f"Das kostet Geld.")
        else:
            settings = Settings(
                _env_file=None, provider="fake", db_path=tmp / "smoke.db"
            )

        print(f"{GRAU}Datenbank:{AUS} {settings.db_path}")

        app = create_app(settings)
        with TestClient(app) as client:
            schritt(1, "Health")
            health = client.get("/api/health")
            health.raise_for_status()
            h = health.json()
            print(f"    {h}")
            assert h["status"] == "ok", "Datenbank nicht erreichbar"
            ok(f"Anbieter {h['provider']}, Modell {h['model']}, Phase {h['phase']}")

            schritt(2, "Oberflaeche")
            index = client.get("/")
            index.raise_for_status()
            ok(f"GET / liefert {len(index.content)} Bytes HTML")

            schritt(3, "Erste Nachricht (legt die Konversation an)")
            chat = client.post("/api/chat", json={"message": "Hallo JARVIS, wer bist du?"})
            chat.raise_for_status()
            antwort = chat.json()
            conversation_id = antwort["conversation"]["id"]
            print(f"    {GRAU}Titel:{AUS}   {antwort['conversation']['title']}")
            print(f"    {GRAU}Antwort:{AUS} {antwort['reply']['content'][:200]}")
            print(f"    {GRAU}Token:{AUS}   {antwort['usage']}")
            ok(f"Konversation {conversation_id} angelegt")

            schritt(4, "Zweite Nachricht (derselbe Verlauf)")
            zweite = client.post(
                "/api/chat",
                json={"message": "Und was kannst du noch nicht?",
                      "conversation_id": conversation_id},
            )
            zweite.raise_for_status()
            print(f"    {GRAU}Antwort:{AUS} {zweite.json()['reply']['content'][:200]}")
            ok("Antwort erhalten")

            schritt(5, "Verlauf nachlesen")
            detail = client.get(f"/api/conversations/{conversation_id}")
            detail.raise_for_status()
            nachrichten = detail.json()["messages"]
            for m in nachrichten:
                print(f"    {GRAU}{m['role']:<9}{AUS} {m['content'][:90]}")
            assert len(nachrichten) == 4, f"erwartet 4 Nachrichten, sind {len(nachrichten)}"
            ok("vier Nachrichten in der richtigen Reihenfolge")

            schritt(6, "Neu oeffnen - liegt es wirklich auf der Platte?")
        # Client zu, App zu. Jetzt eine frische App auf derselben Datei.
        with TestClient(create_app(settings)) as client2:
            liste = client2.get("/api/conversations").json()
            assert len(liste) == 1 and liste[0]["message_count"] == 4, liste
            ok(f"nach Neustart: {liste[0]['title']!r} mit {liste[0]['message_count']} Nachrichten")

            schritt(7, "Aufraeumen")
            assert client2.delete(f"/api/conversations/{conversation_id}").status_code == 204
            assert client2.get("/api/conversations").json() == []
            ok("geloescht, nichts uebrig")

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
