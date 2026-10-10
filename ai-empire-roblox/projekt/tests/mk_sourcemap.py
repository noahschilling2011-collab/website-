#!/usr/bin/env python3
"""Write sourcemap_work.json (Rojo-style) for work/src so luau-lsp resolves requires."""
import os, json
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'work', 'src')
EXT = {'.module.luau': 'ModuleScript', '.server.luau': 'Script', '.client.luau': 'LocalScript'}
def node(path, name):
    full = os.path.join(SRC, *path)
    n = {"name": name, "className": "Folder", "children": []}
    for e in sorted(os.listdir(full)):
        p = os.path.join(full, e)
        if os.path.isdir(p):
            n["children"].append(node(path + [e], e))
        else:
            for ext, cls in EXT.items():
                if e.endswith(ext):
                    n["children"].append({"name": e[:-len(ext)], "className": cls, "filePaths": [p]})
    return n
svc = {"ReplicatedStorage": "ReplicatedStorage", "ServerScriptService": "ServerScriptService", "StarterPlayer": "StarterPlayer"}
dm = {"name": "Game", "className": "DataModel", "children": []}
for s in sorted(os.listdir(SRC)):
    n = node([s], s); n["className"] = svc.get(s, "Folder")
    if s == "StarterPlayer":
        for c in n["children"]:
            if c["name"] == "StarterPlayerScripts": c["className"] = "StarterPlayerScripts"
    dm["children"].append(n)
json.dump(dm, open(os.path.join(ROOT, 'sourcemap_work.json'), 'w'), indent=1)
print("sourcemap_work.json written")
