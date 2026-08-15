#!/usr/bin/env python3
"""Baut aus src/ eine einzelne Roblox-Place-Datei (.rbxlx).

    python3 tools/build_place.py            -> cashout/CASHOUT.rbxlx
    python3 tools/build_place.py mein.rbxlx -> eigener Pfad

Die Datei ist das XML-Place-Format von Roblox: in Studio über
Datei > Öffnen zu laden, danach reicht Play. Kein Rojo, kein Plugin.

Der Generator liest immer den aktuellen Stand von src/ -- er hält keine Kopie
des Codes. Nach jeder Änderung neu laufen lassen, sonst driftet die Place-Datei
vom Quellcode weg.
"""

import os
import sys
import xml.etree.ElementTree as ElementTree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "src"))
DEFAULT_OUT = os.path.normpath(os.path.join(HERE, "..", "CASHOUT.rbxlx"))

# Dateiendung -> Roblox-Klasse. Entspricht der Rojo-Konvention, damit beide
# Wege dasselbe Ergebnis liefern.
SUFFIXES = [
    (".server.lua", "Script"),
    (".client.lua", "LocalScript"),
    (".lua", "ModuleScript"),
]

# Verzeichnisse, die KEINE gewöhnlichen Folder sind, sondern eigene
# Roblox-Klassen. Ein LocalScript unter einem Folder namens
# "StarterPlayerScripts" würde nie starten -- es muss die echte Klasse sein.
CONTAINER_CLASSES = {
    "StarterPlayerScripts": "StarterPlayerScripts",
    "StarterCharacterScripts": "StarterCharacterScripts",
}

# Dienste, die die Place-Datei mitbringt, und was aus src/ hineingehört.
# None heißt: Dienst anlegen, aber leer lassen.
SERVICES = [
    ("Workspace", None),
    ("Lighting", None),
    ("ReplicatedStorage", "ReplicatedStorage"),
    ("ServerScriptService", "ServerScriptService"),
    ("StarterPlayer", "StarterPlayer"),
]

_next_referent = 0


def referent() -> str:
    global _next_referent
    value = f"RBX{_next_referent}"
    _next_referent += 1
    return value


def classify(filename: str):
    """(Instanzname, Klasse) für eine Datei, oder None wenn keine Lua-Datei."""
    for suffix, class_name in SUFFIXES:
        if filename.endswith(suffix):
            return filename[: -len(suffix)], class_name
    return None


def make_item(parent: ElementTree.Element, class_name: str, name: str) -> ElementTree.Element:
    item = ElementTree.SubElement(parent, "Item", {"class": class_name, "referent": referent()})
    properties = ElementTree.SubElement(item, "Properties")
    label = ElementTree.SubElement(properties, "string", {"name": "Name"})
    label.text = name
    return item


def add_source(item: ElementTree.Element, source: str) -> None:
    properties = item.find("Properties")
    node = ElementTree.SubElement(properties, "ProtectedString", {"name": "Source"})
    # Kein CDATA: ElementTree maskiert &, < und > selbst, und das ist
    # bulletproof gegenüber einem "]]>" irgendwo im Lua-Code.
    node.text = source


def add_directory(parent: ElementTree.Element, path: str) -> int:
    """Hängt den Inhalt eines Verzeichnisses an. Rückgabe: Anzahl Skripte."""
    count = 0
    for entry in sorted(os.listdir(path)):
        full = os.path.join(path, entry)

        if os.path.isdir(full):
            container = make_item(parent, CONTAINER_CLASSES.get(entry, "Folder"), entry)
            count += add_directory(container, full)
            continue

        classified = classify(entry)
        if not classified:
            continue

        name, class_name = classified
        with open(full, encoding="utf-8") as handle:
            source = handle.read()

        item = make_item(parent, class_name, name)
        add_source(item, source)
        count += 1

    return count


def build() -> tuple:
    root = ElementTree.Element(
        "roblox",
        {
            "xmlns:xmime": "http://www.w3.org/2005/05/xmlmime",
            "xmlns:xsi": "http://www.w3.org/2001/XMLSchema-instance",
            "xsi:noNamespaceSchemaLocation": "http://www.roblox.com/roblox.xsd",
            "version": "4",
        },
    )

    total = 0
    for service, folder in SERVICES:
        item = make_item(root, service, service)
        if folder is None:
            continue

        path = os.path.join(ROOT, folder)
        if not os.path.isdir(path):
            raise SystemExit(f"fehlt: {path}")
        total += add_directory(item, path)

    return root, total


def main() -> int:
    out = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUT
    root, total = build()

    tree = ElementTree.ElementTree(root)
    ElementTree.indent(tree, space="\t")
    tree.write(out, encoding="utf-8", xml_declaration=True)

    size = os.path.getsize(out)
    print(f"{out} gebaut: {total} Skripte, {size / 1024:.0f} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
