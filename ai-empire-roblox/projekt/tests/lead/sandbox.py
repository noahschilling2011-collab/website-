#!/usr/bin/env python3
"""Create/refresh a private sandbox copy of the test tooling: sandbox.py ROOT SB [SRC]  (SRC defaults to ROOT/work/src)"""
import os, shutil, sys, glob
root, sb = sys.argv[1], sys.argv[2]
src = sys.argv[3] if len(sys.argv) > 3 else os.path.join(root, "work", "src")
def sync(name, ignore):
    dst = os.path.join(sb, name)
    if os.path.exists(dst): shutil.rmtree(dst)
    shutil.copytree(os.path.join(root, name), dst, ignore=shutil.ignore_patterns(*ignore), symlinks=True)
os.makedirs(sb, exist_ok=True)
sync("harness", [".gen_*", "__pycache__"])
sync("people_harness", ["tree", "manifest.luau", "sources.luau", "__pycache__"])
sync("staff_harness", ["tree", "manifest.luau", "sources.luau", "__pycache__"])
sync("tests", ["__pycache__"])
os.makedirs(os.path.join(sb, "agents", "screens"), exist_ok=True)
for f in glob.glob(os.path.join(root, "agents", "screens", "*.luau")):
    shutil.copy(f, os.path.join(sb, "agents", "screens"))
# work/src is COPIED (Luau's require does not follow symlinked directories); fresh on every run
w = os.path.join(sb, "work")
if os.path.islink(w): os.remove(w)
elif os.path.exists(w): shutil.rmtree(w)
shutil.copytree(src, os.path.join(w, "src"))
# package-specific baselines some test generators read (e.g. tests/life/mkharness.py negative build)
for extra in ("agents/life/orig",):
    srcd = os.path.join(root, extra)
    if os.path.isdir(srcd):
        dst = os.path.join(sb, extra)
        if os.path.exists(dst): shutil.rmtree(dst)
        shutil.copytree(srcd, dst)
# tools: a real directory of symlinks, except tools/guiprev which is COPIED (Luau's require does not follow
# symlinked directories; tests/models/ui_setup.luau and tests/corefix/test_ui.luau require guiprev/guidump)
p = os.path.join(sb, "tools")
if os.path.islink(p): os.remove(p)
elif os.path.exists(p): shutil.rmtree(p)
os.makedirs(p)
for name in os.listdir(os.path.join(root, "tools")):
    srcp = os.path.join(root, "tools", name)
    if name == "guiprev" and os.path.isdir(srcp):
        shutil.copytree(srcp, os.path.join(p, name), ignore=shutil.ignore_patterns("__pycache__", "out*"))
    else:
        os.symlink(srcp, os.path.join(p, name))
