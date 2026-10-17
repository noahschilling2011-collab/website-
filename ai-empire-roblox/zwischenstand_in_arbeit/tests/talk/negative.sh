#!/usr/bin/env bash
# Negative checks for the talk package: the same tests against the PRE-CHANGE files (tests/talk/orig: the
# lead's TalkService/TalkController stubs + EmployeeRigDesign without Public prompts) and against five
# deliberate mutations of TalkService must FAIL. Private trees under agents/talk/neg_* (never work/src).
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
SVC=ServerScriptService/Server/Services
mk() { # name; then optional sed expression applied to TalkService
  local name="$1"; local tree="agents/talk/neg_$name"
  rm -rf "$tree"; cp -r work/src "$tree"
  if [ "$name" = "orig" ]; then
    cp tests/talk/orig/TalkService.module.luau "$tree/$SVC/TalkService.module.luau"
    cp tests/talk/orig/EmployeeRigDesign.module.luau "$tree/$SVC/EmployeeRigDesign.module.luau"
    cp tests/talk/orig/TalkController.module.luau "$tree/StarterPlayer/StarterPlayerScripts/Client/Controllers/TalkController.module.luau"
  else
    sed -i "$2" "$tree/$SVC/TalkService.module.luau"
    grep -q "NEGMARK" "$tree/$SVC/TalkService.module.luau" || { echo "mutation $name did not apply"; exit 1; }
  fi
  python3 harness/make_manifest.py --src "$tree" --gen "harness/.gen_talk_neg_$name" >/dev/null
}
run() { tools/luau "tests/talk/$1.luau" -a ".gen_talk_neg_$2" 2>&1 | grep -E "^FAIL|^ERROR|tests:" | head -${3:-6}; }
mk orig
echo "--- original stubs: service test (expect ERROR/FAIL):"; run test_talk orig 3
echo "--- original stubs: client test (expect FAIL):"; run test_client orig 3
mk nodistance 's/^Talk.OPEN_DISTANCE=12/Talk.OPEN_DISTANCE=1e9 -- NEGMARK/'
echo "--- mutation: no distance check (expect '12.5 studs' FAIL):"; run test_talk nodistance
mk nolock 's/if busy and not busy.closed and busy.player~=player then return refuse(player,i,"NPC_BUSY",viaPrompt) end/-- NEGMARK lock removed/'
echo "--- mutation: no one-conversation-per-NPC lock (expect lock FAILs):"; run test_talk nolock
mk norestore 's/if faced and root and root.Parent and root.Anchored and (root.Position-faced.Position).Magnitude<.3 then root.CFrame=faced end/-- NEGMARK no restore/'
echo "--- mutation: NPC not turned back (expect 'facing restored' FAIL):"; run test_talk norestore
mk nosweep 's/then table.insert(ended,conv) end/then end -- NEGMARK sweep disabled/'
echo "--- mutation: no walk-away sweep (expect sweep FAILs):"; run test_talk nosweep
mk nodesk 's/^ sub.desk=deskOf(i,st,tier)/ sub.desk=nil -- NEGMARK no desk/'
echo "--- mutation: no home desk lookup (expect 'team: home desk' FAIL):"; run test_talk nodesk
rm -rf agents/talk/neg_* harness/.gen_talk_neg_*
