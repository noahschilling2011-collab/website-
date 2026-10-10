#!/usr/bin/env python3
"""Rebuild a .rbxlx from the original place file and the edited sources in work/src.

- Existing scripts keep their referent; Source is replaced from work/src.
- Scripts whose file was deleted from work/src are removed from the place.
- New *.module.luau / *.server.luau / *.client.luau files are inserted (folders created as needed).
- Place-level settings that scripts cannot change (Lighting.Technology, Workspace streaming
  behaviour) are written as real properties.
"""
import os
import sys
import xml.etree.ElementTree as ET

ROOT = "/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad"
SRC = os.environ.get("PACK_SRC") or os.path.join(ROOT, "work", "src")
ORIG = os.path.join(ROOT, "orig.rbxlx")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "out", "AIEmpire_HQ_Premium.rbxlx")
EXT = {".module.luau": "ModuleScript", ".server.luau": "Script", ".client.luau": "LocalScript"}
CLASS_EXT = {v: k for k, v in EXT.items()}

tree = ET.parse(ORIG)
root = tree.getroot()
serial = [0]


def new_ref():
    serial[0] += 1
    return "RBXHQP%08d" % serial[0]


def prop(item, name):
    props = item.find("Properties")
    for p in props:
        if p.get("name") == name:
            return p
    return None


def name_of(item):
    p = prop(item, "Name")
    return p.text if p is not None else item.get("class")


def make_item(cls, name, source=None):
    item = ET.Element("Item", {"class": cls, "referent": new_ref()})
    props = ET.SubElement(item, "Properties")
    n = ET.SubElement(props, "string", {"name": "Name"})
    n.text = name
    a = ET.SubElement(props, "bool", {"name": "Archivable"})
    a.text = "true"
    if source is not None:
        s = ET.SubElement(props, "ProtectedString", {"name": "Source"})
        s.text = source
    return item


# Index files on disk: relpath (without suffix) -> (class, abs file)
disk = {}
for dirpath, _, files in os.walk(SRC):
    for f in files:
        for ext, cls in EXT.items():
            if f.endswith(ext):
                rel = os.path.relpath(os.path.join(dirpath, f[: -len(ext)]), SRC)
                disk[tuple(rel.split(os.sep))] = (cls, os.path.join(dirpath, f))

seen = set()
removed = []
updated = 0


def walk(parent_elem, item, path):
    global updated
    cls = item.get("class")
    p = path + (name_of(item),)
    if cls in CLASS_EXT:
        entry = disk.get(p)
        if entry is None:
            parent_elem.remove(item)
            removed.append("/".join(p))
            return
        seen.add(p)
        src = open(entry[1], encoding="utf-8").read()
        sp = prop(item, "Source")
        if sp.text != src:
            sp.text = src
            updated += 1
    for ch in list(item.findall("Item")):
        walk(item, ch, p)


for it in list(root.findall("Item")):
    walk(root, it, ())


def find_child(elem, name):
    for ch in elem.findall("Item"):
        if name_of(ch) == name:
            return ch
    return None


added = []
for p, (cls, f) in sorted(disk.items()):
    if p in seen:
        continue
    parent = root
    for seg in p[:-1]:
        nxt = find_child(parent, seg)
        if nxt is None:
            nxt = make_item("Folder", seg)
            # keep the new folder before scripts for readability
            parent.append(nxt)
        parent = nxt
    parent.append(make_item(cls, p[-1], open(f, encoding="utf-8").read()))
    added.append("/".join(p))


def set_prop(item, tag, name, value):
    props = item.find("Properties")
    p = prop(item, name)
    if p is None:
        p = ET.SubElement(props, tag, {"name": name})
    p.text = str(value)


# Workspace: streaming stays on; Improved model streaming lets Atomic room groups work as designed.
ws = next(i for i in root.findall("Item") if i.get("class") == "Workspace")
set_prop(ws, "bool", "StreamingEnabled", "true")
set_prop(ws, "int", "StreamingMinRadius", 128)
set_prop(ws, "int", "StreamingTargetRadius", 512)
set_prop(ws, "token", "ModelStreamingBehavior", 2)  # Improved
set_prop(ws, "token", "StreamOutBehavior", 2)  # Opportunistic
set_prop(ws, "token", "StreamingIntegrityMode", 2)  # MinimumRadiusPause

# Lighting.Technology is RobloxScriptSecurity -> must live in the place file.
light = next((i for i in root.findall("Item") if i.get("class") == "Lighting"), None)
if light is None:
    light = make_item("Lighting", "Lighting")
    root.append(light)
set_prop(light, "token", "Technology", 4)  # Future
set_prop(light, "bool", "GlobalShadows", "true")
set_prop(light, "float", "EnvironmentDiffuseScale", 0.6)
set_prop(light, "float", "EnvironmentSpecularScale", 0.45)
set_prop(light, "float", "ShadowSoftness", 0.25)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
tree.write(OUT, encoding="utf-8", xml_declaration=True)
print(f"wrote {OUT}")
print(f"updated {updated} scripts, added {len(added)}, removed {len(removed)}")
for a in added:
    print("  + " + a)
for r in removed:
    print("  - " + r)
