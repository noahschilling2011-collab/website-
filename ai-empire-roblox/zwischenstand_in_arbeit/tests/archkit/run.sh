#!/usr/bin/env bash
# Rebuild the ArchKit showcase through the harness mock and dump it to tests/archkit/dump.json.
set -e
cd "$(dirname "$0")/../.."
rm -rf tests/archkit/src && cp -r work/src tests/archkit/src
cp tests/archkit/ArchKitShowcase.module.luau tests/archkit/ArchKitPlanTest.module.luau tests/archkit/src/ServerScriptService/Server/Services/
python3 harness/make_manifest.py --src tests/archkit/src --gen harness/.gen_archkit > /dev/null
(cd harness && ../tools/luau build_dump.luau -a --tier 1 --gen .gen_archkit --module ServerScriptService.Server.Services.ArchKitShowcase) > tests/archkit/raw.txt 2>&1 || { tail -30 tests/archkit/raw.txt; exit 1; }
python3 harness/split_dump.py tests/archkit/dump.json tests/archkit/log.txt < tests/archkit/raw.txt
grep -v "^@@" tests/archkit/raw.txt | grep -v "^\[print\] \[count\]" | tail -5
