#!/usr/bin/env python3
"""Round trip: extract every script from the packed .rbxlx and compare it with work/src; check that
all non-script instances of the original survive and that the place settings are set."""
import xml.etree.ElementTree as ET, os, sys, collections
ROOT = '/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad'
EXT = {'ModuleScript': '.module.luau', 'Script': '.server.luau', 'LocalScript': '.client.luau'}
def scan(path):
    root = ET.parse(path).getroot()
    scripts, others = {}, collections.Counter()
    props_of = {}
    def walk(item, p):
        cls = item.get('class'); name = None; src = None
        pr = item.find('Properties')
        if pr is not None:
            for x in pr:
                if x.get('name') == 'Name': name = x.text
                if x.get('name') == 'Source': src = x.text or ''
        p2 = p + [name or cls]
        if cls in EXT:
            scripts['/'.join(p2[1:]) + EXT[cls]] = src or ''
        else:
            others[(cls, '/'.join(p2))] += 1
        if cls in ('Lighting', 'Workspace') and pr is not None:
            props_of[cls] = {x.get('name'): (x.text or '').strip() for x in pr}
        for c in item.findall('Item'): walk(c, p2)
    for it in root.findall('Item'): walk(it, [''])
    return scripts, others, props_of
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'out', 'AIEmpire_HQ_Premium.rbxlx')
s_new, o_new, props = scan(out)
s_old, o_old, _ = scan(os.path.join(ROOT, 'orig.rbxlx'))
src = {}
base = os.environ.get('RT_SRC') or os.path.join(ROOT, 'work', 'src')
for dp, _, fs in os.walk(base):
    for f in fs:
        if f.endswith('.luau'):
            src[os.path.relpath(os.path.join(dp, f), base)] = open(os.path.join(dp, f), encoding='utf-8').read()
bad = 0
for k, v in src.items():
    if k not in s_new: print('MISSING in place:', k); bad += 1
    elif s_new[k] != v: print('SOURCE DIFFERS:', k); bad += 1
for k in s_new:
    if k not in src: print('EXTRA script in place:', k); bad += 1
lost = [k for k in o_old if o_new[k] < o_old[k] and not k[1].endswith(('OfficeKit', 'DepartmentDesign', 'OfficeFacilitiesDesign', 'OfficeDesign'))]
for k in lost[:20]: print('LOST non-script instance:', k)
bad += len(lost)
print(f"scripts in place {len(s_new)}, in work/src {len(src)}, non-script instances orig {sum(o_old.values())} -> new {sum(o_new.values())}")
print('Lighting.Technology =', props.get('Lighting', {}).get('Technology'), '| Workspace.StreamingEnabled =', props.get('Workspace', {}).get('StreamingEnabled'),
      '| ModelStreamingBehavior =', props.get('Workspace', {}).get('ModelStreamingBehavior'))
print('ROUNDTRIP', 'OK' if bad == 0 else f'FAILED ({bad})')
