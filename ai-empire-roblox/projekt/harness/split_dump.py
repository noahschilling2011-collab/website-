#!/usr/bin/env python3
"""Read build_dump.luau stdout from stdin; write {"meta":...,"instances":[...]} JSON and a log file.

usage: luau build_dump.luau -a --tier N | python3 split_dump.py out/dump_tierN.json out/log_tierN.txt
Lines starting with "@@D " are instances, "@@M " is the meta record, everything else is log.
Exit code: 0 if a meta record was received and every instance line parsed, else 1.
"""
import json, sys


def main():
    out_json, out_log = sys.argv[1], sys.argv[2]
    insts, meta, logs, bad = [], None, [], 0
    for raw in sys.stdin.buffer:
        line = raw.decode("utf-8", errors="replace").rstrip("\n")
        if line.startswith("@@D "):
            try:
                insts.append(json.loads(line[4:]))
            except json.JSONDecodeError as e:
                bad += 1
                logs.append(f"[split] bad instance JSON: {e}: {line[:200]}")
        elif line.startswith("@@M "):
            try:
                meta = json.loads(line[4:])
            except json.JSONDecodeError as e:
                bad += 1
                logs.append(f"[split] bad meta JSON: {e}")
        else:
            logs.append(line)
    with open(out_log, "w", encoding="utf-8") as f:
        f.write("\n".join(logs) + ("\n" if logs else ""))
    if meta is None:   # build failed: the log file has the traceback (run.sh prints it)
        return 1
    meta["logLines"] = len(logs)
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump({"meta": meta, "instances": insts}, f, separators=(",", ":"), allow_nan=True)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
