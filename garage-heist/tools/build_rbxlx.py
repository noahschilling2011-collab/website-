#!/usr/bin/env python3
"""
Baut aus src/ eine einzelne Roblox-Place-Datei (GarageHeist.rbxlx).

Damit brauchst du kein Rojo: Datei doppelklicken bzw. in Studio ueber
File > Open from File oeffnen - alles liegt sofort an der richtigen Stelle.

Die Ablage folgt exakt default.project.json:
    src/Shared/*.lua          -> ReplicatedStorage/Shared/<Name>   (ModuleScript)
    src/Server/**             -> ServerScriptService/Server        (Script)
    src/Client/**             -> StarterPlayerScripts/Client       (LocalScript)

Regeln wie bei Rojo:
    init.server.lua  -> der Ordner wird zum Script
    init.client.lua  -> der Ordner wird zum LocalScript
    sonstige .lua    -> ModuleScript
    Unterordner      -> Folder

Aufruf:  python3 tools/build_rbxlx.py
"""

from __future__ import annotations

import pathlib
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
OUT = ROOT / "GarageHeist.rbxlx"

_referent = 0


def next_referent() -> str:
    global _referent
    _referent += 1
    return f"RBX{_referent}"


def open_item(cls: str) -> str:
    return f'<Item class="{cls}" referent="{next_referent()}">'


def properties(name: str, source: str | None = None) -> str:
    out = ["<Properties>", f"<string name=\"Name\">{name}</string>"]
    if source is not None:
        if "]]>" in source:
            # Wuerde die CDATA-Sektion vorzeitig beenden. Kommt im Projekt
            # nicht vor, aber lieber laut abbrechen als eine kaputte Datei.
            raise SystemExit(f"']]>' in {name} - CDATA waere kaputt")
        out.append(f"<ProtectedString name=\"Source\"><![CDATA[{source}]]></ProtectedString>")
    out.append("</Properties>")
    return "".join(out)


def script_class(path: pathlib.Path) -> str | None:
    """Rojo-Namensregeln fuer eine einzelne Datei."""
    if path.name == "init.server.lua":
        return "Script"
    if path.name == "init.client.lua":
        return "LocalScript"
    if path.suffix == ".lua":
        return "ModuleScript"
    return None


def build_directory(directory: pathlib.Path, name: str, lines: list[str]) -> None:
    """Verwandelt einen Ordner in ein Item (Folder oder Script mit Kindern)."""
    init_server = directory / "init.server.lua"
    init_client = directory / "init.client.lua"

    if init_server.exists():
        lines.append(open_item("Script"))
        lines.append(properties(name, init_server.read_text(encoding="utf-8")))
    elif init_client.exists():
        lines.append(open_item("LocalScript"))
        lines.append(properties(name, init_client.read_text(encoding="utf-8")))
    else:
        lines.append(open_item("Folder"))
        lines.append(properties(name))

    for child in sorted(directory.iterdir(), key=lambda p: (p.is_file(), p.name)):
        if child.is_dir():
            build_directory(child, child.name, lines)
        elif child.name in ("init.server.lua", "init.client.lua"):
            continue
        elif child.suffix == ".lua":
            lines.append(open_item(script_class(child) or "ModuleScript"))
            lines.append(properties(child.stem, child.read_text(encoding="utf-8")))
            lines.append("</Item>")

    lines.append("</Item>")


def color3(name: str, r: int, g: int, b: int) -> str:
    return (f'<Color3 name="{name}"><R>{r / 255:.6f}</R>'
            f'<G>{g / 255:.6f}</G><B>{b / 255:.6f}</B></Color3>')


def lighting_item() -> str:
    """Lighting als Place-Eigenschaft.

    Lighting.Technology ist NICHT skriptbar - sie muss in der Place-Datei
    stehen. Enum.Technology.Future hat den Wert 4. Die uebrigen Werte setzt
    zusaetzlich der Bootstrap zur Laufzeit; hier stehen sie, damit die Place
    schon im Bearbeitungsmodus richtig aussieht.
    """
    return (
        open_item("Lighting")
        + "<Properties>"
        + '<string name="Name">Lighting</string>'
        + '<token name="Technology">4</token>'
        + '<float name="ClockTime">18.5</float>'
        + '<float name="Brightness">2</float>'
        + '<float name="ExposureCompensation">0.15</float>'
        + '<bool name="GlobalShadows">true</bool>'
        + '<float name="FogEnd">900</float>'
        + color3("Ambient", 45, 45, 60)
        + color3("OutdoorAmbient", 70, 70, 90)
        + "</Properties>"
        + "</Item>"
    )


def workspace_item() -> str:
    """Workspace mit Terrain und einer Grundplatte.

    Die eigentliche Welt (Boden, 12 Garagen, Spawn) baut der Server zur
    Laufzeit - im Bearbeitungsmodus ist hier deshalb absichtlich fast nichts.
    Die Grundplatte hat zwei Aufgaben: Studio zeigt beim Oeffnen etwas statt
    einer schwarzen Leere, und wenn der Server-Bootstrap doch einmal scheitert,
    faellt niemand ins Nichts. Sie liegt bei y = -8 und damit unter dem
    Laufzeit-Boden bei y = 0.
    """
    return (
        open_item("Workspace")
        + "<Properties>"
        + '<string name="Name">Workspace</string>'
        + "</Properties>"
        + open_item("Terrain")
        + "<Properties>"
        + '<string name="Name">Terrain</string>'
        + "</Properties>"
        + "</Item>"
        + open_item("Part")
        + "<Properties>"
        + '<string name="Name">Baseplate</string>'
        + '<bool name="Anchored">true</bool>'
        + '<bool name="Locked">true</bool>'
        + '<Vector3 name="size"><X>1024</X><Y>16</Y><Z>1024</Z></Vector3>'
        + '<CoordinateFrame name="CFrame">'
        + "<X>0</X><Y>-8</Y><Z>0</Z>"
        + "<R00>1</R00><R01>0</R01><R02>0</R02>"
        + "<R10>0</R10><R11>1</R11><R12>0</R12>"
        + "<R20>0</R20><R21>0</R21><R22>1</R22>"
        + "</CoordinateFrame>"
        + "</Properties>"
        + "</Item>"
        + "</Item>"
    )


def build() -> str:
    lines = [
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">',
        "<External>null</External>",
        "<External>nil</External>",
        lighting_item(),
        workspace_item(),
    ]

    lines.append(open_item("ReplicatedStorage"))
    lines.append(properties("ReplicatedStorage"))
    build_directory(SRC / "Shared", "Shared", lines)
    lines.append("</Item>")

    lines.append(open_item("ServerScriptService"))
    lines.append(properties("ServerScriptService"))
    build_directory(SRC / "Server", "Server", lines)
    lines.append("</Item>")

    lines.append(open_item("StarterPlayer"))
    lines.append(properties("StarterPlayer"))
    lines.append(open_item("StarterPlayerScripts"))
    lines.append(properties("StarterPlayerScripts"))
    build_directory(SRC / "Client", "Client", lines)
    lines.append("</Item>")
    lines.append("</Item>")

    lines.append("</roblox>")
    return "\n".join(lines) + "\n"


def verify(xml_text: str) -> None:
    """Wohlgeformt? Und steckt jede Quelldatei unveraendert drin?"""
    tree = ET.fromstring(xml_text)

    sources: dict[str, str] = {}
    for item in tree.iter("Item"):
        props = item.find("Properties")
        if props is None:
            continue
        name_node = props.find("string[@name='Name']")
        source_node = props.find("ProtectedString[@name='Source']")
        if name_node is not None and source_node is not None:
            sources[name_node.text or ""] = source_node.text or ""

    expected = 0
    for path in sorted(SRC.rglob("*.lua")):
        expected += 1
        if path.name == "init.server.lua":
            key = "Server"
        elif path.name == "init.client.lua":
            key = "Client"
        else:
            key = path.stem
        original = path.read_text(encoding="utf-8")
        if key not in sources:
            raise SystemExit(f"FEHLT in der Place-Datei: {path}")
        if sources[key] != original:
            raise SystemExit(f"Quelltext weicht ab: {path}")

    if len(sources) != expected:
        raise SystemExit(f"Anzahl passt nicht: {len(sources)} in der Datei, {expected} auf der Platte")
    print(f"geprueft: {expected} Skripte, Quelltext identisch")


def main() -> int:
    if not SRC.is_dir():
        raise SystemExit(f"src/ nicht gefunden unter {SRC}")
    xml_text = build()
    verify(xml_text)
    OUT.write_text(xml_text, encoding="utf-8")
    print(f"geschrieben: {OUT.relative_to(ROOT)} ({OUT.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
