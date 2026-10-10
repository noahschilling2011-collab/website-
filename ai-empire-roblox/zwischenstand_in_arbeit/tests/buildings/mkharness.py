#!/usr/bin/env python3
"""Private harness trees for the "buildings" package tests (writes ONLY into tests/buildings/).
gen/       : work/src + people_harness/stubs (Door/Lift/Plot/Session/Remote doubles) - runtime test
gen_build/ : work/src unchanged (real DoorService/LiftService) - build/contract test
gen_neg/   : like gen/ but the package files replaced by the ORIGINAL versions in tests/buildings/orig
gen_negb/  : like gen_build/ with the original package files (negative checks: the tests must FAIL there)
gen_req/   : like gen/ with the changes requested from other packages applied (REQUESTS below)
Each tree gets manifest.luau + sources.luau in the format of harness/make_manifest.py."""
import os, shutil, json
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(ROOT, "work", "src")
STUBS = os.path.join(ROOT, "people_harness", "stubs")
ORIG = os.path.join(HERE, "orig")
SUFFIX = {".module.luau": "ModuleScript", ".server.luau": "Script", ".client.luau": "LocalScript"}


def lstr(s):
    lvl = 0
    while ("]" + "=" * lvl + "]") in s or s.endswith("]" + "=" * lvl):
        lvl += 1
    eq = "=" * lvl
    return "[" + eq + "[\n" + s + "]" + eq + "]"


# The changes this package requests in files it does not own (design/requests/buildings.md), applied to
# a private copy only (gen_req/) so the tests can prove the request is correct and sufficient. A request the
# lead has already applied (old text gone, new text present) is left alone.
REQUESTS = [
    ("ServerScriptService/Server/Services/StaffService.module.luau",
     " local base=if e.garage then Plan.GARAGE_ARRIVAL else Plan.ARRIVAL\n",
     " local base=Plan.staffArrival(e.tier,e.garage)\n"),
    ("ServerScriptService/Server/Services/StaffService.module.luau",
     "tier=s.data.empire.office,",
     "tier=(function(): number local t=office:GetAttribute(\"OfficeTier\");return if typeof(t)==\"number\" then t else Plan.tierForOffice(s.data.empire.office) end)(),"),
]


def apply_requests(tree):
    for rel, old, new in REQUESTS:
        path = os.path.join(tree, rel)
        text = open(path, encoding="utf-8").read()
        if old in text:
            text = text.replace(old, new, 1)
        elif new not in text:
            raise SystemExit(f"request patch no longer applies: {rel}: {old.strip()[:60]}")
        open(path, "w", encoding="utf-8").write(text)


def build(name, negative=False, stubs=True, requests=False):
    out = os.path.join(HERE, name)
    tree = os.path.join(out, "tree")
    if os.path.exists(out):
        shutil.rmtree(out)
    shutil.copytree(SRC, tree)
    if stubs:
        for sub in ("Services", "Lib"):
            dst = os.path.join(tree, "ServerScriptService", "Server", sub)
            src = os.path.join(STUBS, sub)
            for fn in os.listdir(src):
                shutil.copy(os.path.join(src, fn), os.path.join(dst, fn))
    if requests:
        apply_requests(tree)
    if negative:
        for dirpath, _, filenames in os.walk(ORIG):
            for fn in filenames:
                rel = os.path.relpath(os.path.join(dirpath, fn), ORIG)
                if stubs and rel.endswith("Services" + os.sep + "LiftService.module.luau"):
                    continue  # keep the lift double in the runtime tree
                shutil.copy(os.path.join(dirpath, fn), os.path.join(tree, rel))
    entries, scripts, dirs = [], set(), set()
    for dirpath, dirnames, filenames in os.walk(tree):
        dirnames.sort()
        rel = os.path.relpath(dirpath, tree)
        segs = [] if rel == "." else rel.split(os.sep)
        if segs:
            dirs.add(tuple(segs))
        for fn in sorted(filenames):
            for suf, cls in SUFFIX.items():
                if fn.endswith(suf):
                    path = tuple(segs + [fn[:-len(suf)]])
                    entries.append((path, cls, os.path.relpath(os.path.join(dirpath, fn), tree).replace(os.sep, "/")))
                    scripts.add(path)
                    break
    for d in sorted(dirs):
        if d not in scripts and len(d) > 1:
            entries.append((d, "Folder", None))
    entries.sort(key=lambda e: (len(e[0]), e[0]))
    man = ["return {"]
    for path, cls, relfile in entries:
        f = (",file=" + json.dumps(relfile)) if relfile else ""
        man.append("{path={" + ",".join(json.dumps(s) for s in path) + "},class=" + json.dumps(cls) + f + "},")
    man.append("}")
    open(os.path.join(out, "manifest.luau"), "w").write("\n".join(man) + "\n")
    src = ["local S={}"]
    for path, cls, relfile in entries:
        if relfile:
            src.append("S[" + json.dumps(relfile) + "]=" + lstr(open(os.path.join(tree, relfile), encoding="utf-8").read()))
    src.append("return S")
    open(os.path.join(out, "sources.luau"), "w").write("\n".join(src) + "\n")
    shutil.rmtree(tree)
    print(f"buildings harness {name}: {len(entries)} entries")


build("gen")
build("gen_req", requests=True)
build("gen_build", stubs=False)
build("gen_neg", negative=True)
build("gen_negb", negative=True, stubs=False)
