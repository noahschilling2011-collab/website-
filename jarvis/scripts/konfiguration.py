"""Lokale Einrichtung/Diagnose, ohne Netz oder Ausgabe von Secret-Werten.

python -m scripts.konfiguration --init  # neue .env; bestehende nie ersetzen
python -m scripts.konfiguration --json  # gleiche Diagnose wie Health
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import secrets

from pydantic import ValidationError

from core.config import PROJECT_ROOT, Settings
from core.konfig_pruefung import integrationen


def initialisiere(ziel: Path) -> None:
    text = (PROJECT_ROOT / ".env.example").read_text(encoding="utf-8")
    zeilen = text.splitlines()
    token_zeilen = [i for i, z in enumerate(zeilen) if z.startswith("JARVIS_TOKEN=")]
    if len(token_zeilen) != 1:
        raise ValueError("Die Vorlage braucht genau eine JARVIS_TOKEN-Zeile.")
    zeilen[token_zeilen[0]] = "JARVIS_TOKEN=" + secrets.token_urlsafe(32)
    # Exklusives Anlegen verhindert Ueberschreiben auch bei parallelen Starts.
    # 0600 unter POSIX; Windows-Zugriff wird durch die lokalen ACLs bestimmt.
    fd = os.open(ziel, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as datei:
        datei.write("\n".join(zeilen) + "\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="JARVIS lokal konfigurieren; keine externen Aufrufe.")
    parser.add_argument("--env", type=Path, default=Path(".env"), help="Konfigurationsdatei (Vorgabe: .env im Startordner).")
    parser.add_argument("--init", action="store_true", help="Neue .env mit Zufallstoken anlegen; nie ueberschreiben.")
    parser.add_argument("--json", action="store_true", help="Diagnose als JSON, ohne Werte oder Pfade.")
    args = parser.parse_args(argv)
    try:
        if args.init:
            initialisiere(args.env)
        settings = Settings(_env_file=args.env)
        stand = integrationen(settings)
    except FileExistsError:
        print("Konfigurationsdatei existiert bereits und wurde nicht veraendert.")
        return 1
    except ValidationError as exc:
        # Pydantic druckt normalerweise input_value mit: bei Secrets tabu.
        felder = sorted({str(e["loc"][0]) for e in exc.errors(include_input=False)})
        print("Konfiguration ungueltig. Betroffene Felder: " + ", ".join(felder))
        return 1
    except (OSError, UnicodeError, ValueError):
        print("Konfigurationsdatei oder lokale Einstellung nicht lesbar. UTF-8 und Dateirechte pruefen.")
        return 1
    if args.json:
        print(json.dumps(stand, ensure_ascii=False, indent=2))
    else:
        if args.init:
            print("Neue Konfiguration angelegt. Der Zugangstoken wurde direkt in der Datei gespeichert.")
        print("Lokale Diagnose; externe Dienste wurden nicht aufgerufen. Werte bleiben geheim.")
        for name, eintrag in stand.items():
            print(f"{name}: {eintrag['status']} — {eintrag['hinweis']}")
    return 1 if any(e["status"] == "ungueltig" for e in stand.values()) else 0


if __name__ == "__main__":
    raise SystemExit(main())
