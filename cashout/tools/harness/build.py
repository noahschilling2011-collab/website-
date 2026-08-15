#!/usr/bin/env python3
"""Baut aus prelude.lua + einem Treiber eine einzelne ausfuehrbare Luau-Datei.

Die echten Servermodule werden als Quelltext eingebettet und zur Laufzeit per
loadstring geladen -- es gibt also keine Kopie des Spielcodes, der Test laeuft
immer gegen den aktuellen Stand von src/.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", "src"))

FILES = {
    "Shared/Balance": "ReplicatedStorage/Shared/Balance.lua",
    "Shared/DealCatalog": "ReplicatedStorage/Shared/DealCatalog.lua",
    "Shared/Remotes": "ReplicatedStorage/Shared/Remotes.lua",
    "Shared/Assets": "ReplicatedStorage/Shared/Assets.lua",
    "Shared/SoundCatalog": "ReplicatedStorage/Shared/SoundCatalog.lua",
    "Modules/MapBuilder": "ServerScriptService/Modules/MapBuilder.lua",
    "Modules/PlayerState": "ServerScriptService/Modules/PlayerState.lua",
    "Modules/RoundManager": "ServerScriptService/Modules/RoundManager.lua",
    "Modules/OrderService": "ServerScriptService/Modules/OrderService.lua",
    "Modules/HeatService": "ServerScriptService/Modules/HeatService.lua",
    "Modules/BankService": "ServerScriptService/Modules/BankService.lua",
    "Main.server": "ServerScriptService/Main.server.lua",
}


def main() -> int:
    driver = sys.argv[1] if len(sys.argv) > 1 else "round.lua"
    out = sys.argv[2] if len(sys.argv) > 2 else "harness.lua"

    chunks = ["SOURCES = {}"]
    for key, relative in FILES.items():
        path = os.path.join(ROOT, relative)
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        if "]===]" in source:
            raise SystemExit(f"{path}: enthaelt ]===] und laesst sich nicht einbetten")
        chunks.append(f'SOURCES["{key}"] = [===[\n{source}]===]')

    with open(os.path.join(HERE, "prelude.lua"), encoding="utf-8") as handle:
        prelude = handle.read()
    with open(os.path.join(HERE, driver), encoding="utf-8") as handle:
        body = handle.read()

    with open(os.path.join(HERE, out), "w", encoding="utf-8") as handle:
        handle.write("\n\n".join(["\n".join(chunks), prelude, body]))

    print(f"{out} gebaut aus {driver}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
