#!/usr/bin/env python3
"""Compare luau-lsp findings of work/src against the original src (line numbers ignored).
Prints findings that are new in work/src, grouped per file. Exit code 0 always."""
import os, re, subprocess, json, collections, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T = os.path.join(ROOT, 'tools')

def sourcemap(src, out):
    EXT = {'.module.luau': 'ModuleScript', '.server.luau': 'Script', '.client.luau': 'LocalScript'}
    def node(path, name):
        full = os.path.join(src, *path)
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
    for s in sorted(os.listdir(src)):
        n = node([s], s); n["className"] = svc.get(s, "Folder")
        if s == "StarterPlayer":
            for c in n["children"]:
                if c["name"] == "StarterPlayerScripts": c["className"] = "StarterPlayerScripts"
        dm["children"].append(n)
    json.dump(dm, open(out, 'w'))

def run(src):
    sm = os.path.join(ROOT, '_sm_%s.json' % os.path.basename(os.path.dirname(src)))
    sourcemap(src, sm)
    r = subprocess.run([os.path.join(T, 'luau-lsp'), 'analyze', '--platform=roblox', '--sourcemap=' + sm,
                        '--definitions=@roblox=' + os.path.join(T, 'globalTypes.d.luau'), '--formatter=plain', src],
                       capture_output=True, text=True)
    found = collections.defaultdict(collections.Counter)
    for line in (r.stdout + r.stderr).splitlines():
        m = re.match(r'(.+?\.luau)(?: \[[^\]]*\])?:(\d+):(\d+)(?:-\d+)?: \((W\d+)\) (.*)', line)
        if not m:
            continue
        rel = os.path.relpath(m.group(1), src)
        msg = re.sub(r'\s+', ' ', m.group(5))[:160]
        found[rel][msg] += 1
    return found

base = run(os.path.join(ROOT, 'src'))
work = run(os.path.join(ROOT, 'work', 'src'))
only = sys.argv[1:]
total = 0
for f in sorted(work):
    if only and not any(o in f for o in only):
        continue
    new = work[f] - base.get(f, collections.Counter())
    if new:
        print('== %s (%d new)' % (f, sum(new.values())))
        for msg, n in new.most_common():
            print('   %3d× %s' % (n, msg))
        total += sum(new.values())
print('TOTAL new findings:', total)
