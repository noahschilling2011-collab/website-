#!/usr/bin/env python3
"""Private harness trees for the "life" package tests (writes ONLY into tests/life/).
gen/      : work/src + staff_harness/stubs (DoorService/LiftService/PlotService/SessionService/Remote doubles)
gen_neg/  : the same, but FacilityService/StaffService/WorkstationService/StaffJobs replaced by the ORIGINAL
            versions from agents/life/orig (negative checks: the tests must FAIL on the old code)
Each tree gets manifest.luau + sources.luau in the format of harness/make_manifest.py."""
import os, shutil, json, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(ROOT, "work", "src")
STUBS = os.path.join(ROOT, "staff_harness", "stubs")
ORIG = os.path.join(ROOT, "agents", "life", "orig")
SUFFIX = {".module.luau": "ModuleScript", ".server.luau": "Script", ".client.luau": "LocalScript"}

def lstr(s):
    lvl = 0
    while ("]" + "=" * lvl + "]") in s or s.endswith("]" + "=" * lvl): lvl += 1
    eq = "=" * lvl
    return "[" + eq + "[\n" + s + "]" + eq + "]"

def build(name, negative=False, stubs=True):
    out = os.path.join(HERE, name)
    tree = os.path.join(out, "tree")
    if os.path.exists(out): shutil.rmtree(out)
    shutil.copytree(SRC, tree)
    if stubs:
        for sub in ("Services", "Lib"):
            dst = os.path.join(tree, "ServerScriptService", "Server", sub)
            src = os.path.join(STUBS, sub)
            for fn in os.listdir(src):
                shutil.copy(os.path.join(src, fn), os.path.join(dst, fn))
    if negative:
        for rel in ("ServerScriptService/Server/Services/FacilityService.module.luau",):
            shutil.copy(os.path.join(ORIG, rel), os.path.join(tree, rel))
    entries, scripts, dirs = [], set(), set()
    for dirpath, dirnames, filenames in os.walk(tree):
        dirnames.sort()
        rel = os.path.relpath(dirpath, tree); segs = [] if rel == "." else rel.split(os.sep)
        if segs: dirs.add(tuple(segs))
        for fn in sorted(filenames):
            for suf, cls in SUFFIX.items():
                if fn.endswith(suf):
                    path = tuple(segs + [fn[:-len(suf)]])
                    entries.append((path, cls, os.path.relpath(os.path.join(dirpath, fn), tree).replace(os.sep, "/")))
                    scripts.add(path); break
    for d in sorted(dirs):
        if d not in scripts and len(d) > 1: entries.append((d, "Folder", None))
    entries.sort(key=lambda e: (len(e[0]), e[0]))
    man = ["return {"]
    for path, cls, relfile in entries:
        f = (",file=" + json.dumps(relfile)) if relfile else ""
        man.append("{path={" + ",".join(json.dumps(s) for s in path) + "},class=" + json.dumps(cls) + f + "},")
    man.append("}")
    open(os.path.join(out, "manifest.luau"), "w").write("\n".join(man) + "\n")
    src = ["local S={}"]
    for path, cls, relfile in entries:
        if relfile: src.append("S[" + json.dumps(relfile) + "]=" + lstr(open(os.path.join(tree, relfile), encoding="utf-8").read()))
    src.append("return S")
    open(os.path.join(out, "sources.luau"), "w").write("\n".join(src) + "\n")
    shutil.rmtree(tree)
    print(f"life harness {name}: {len(entries)} entries")

build("gen")
build("gen_neg", negative=True)
build("gen_build", stubs=False)
