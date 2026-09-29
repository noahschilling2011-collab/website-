#!/usr/bin/env python3
"""Führt einen Befehl aus und schreibt Wandzeit und größten Speicher (max RSS der Kindprozesse) nach stderr.
    python3 tools/messe.py <befehl …>"""
import resource, subprocess, sys, time
t = time.time()
rc = subprocess.run(sys.argv[1:]).returncode
r = resource.getrusage(resource.RUSAGE_CHILDREN)
mib = r.ru_maxrss / (1024 * 1024 if sys.platform == "darwin" else 1024)   # ru_maxrss: Linux KiB, macOS Byte
print(f"[messe] exit {rc}, Wandzeit {time.time() - t:.1f} s, CPU {r.ru_utime + r.ru_stime:.1f} s, max RSS {mib:.0f} MiB", file=sys.stderr)
sys.exit(rc)
