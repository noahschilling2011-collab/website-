"""Prüfung vom 29.09.2026: Manifest eines Laufs gegen seine Checkpoints (Schritte aus der Datei, sha256).
    python berichte/pruefung_2026-09-29/pruef_manifest.py training/laeufe/<lauf>"""
import hashlib
import json
import sys
import zipfile

d = sys.argv[1]
m = json.load(open(d + '/manifest.json'))
print('status', m['status'], '| schritte', m.get('schritte'), '| fortsetzungen',
      [(f.get('ab_schritt'), f.get('bis_schritt'), bool(f.get('ende'))) for f in m['fortsetzungen']])
for c in ['letzter', 'bester']:
    e = m['checkpoints'][c]
    p = d + '/' + c + '.zip'
    n = json.loads(zipfile.ZipFile(p).read('data'))['num_timesteps']
    sha = hashlib.sha256(open(p, 'rb').read()).hexdigest()[:16]
    print(f"{c}: manifest {e['schritte']} {e['sha256']} | datei {n} {sha} | {'PASST' if (e['schritte'] == n and e['sha256'] == sha) else 'ABWEICHUNG'}"
          + (f" | val {e['validierung']['defizitMittel']['mittel']:.2f}" if e.get('validierung') else ''))
print('_zustand bester', (m['_zustand'].get('bester') or {}).get('schritte'), 'abbruch', m['_zustand'].get('abbruch'))
