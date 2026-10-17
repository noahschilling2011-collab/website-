#!/usr/bin/env python3
"""Negative checks of the apps suites: every mutation below breaks one promised behaviour in a private copy of
work/src; the named suite must then report failures (or crash). Prints "apps_negative: N passed, M failed" where
passed = mutation detected. Usage: python3 tests/apps/negative.py [filter]"""
import os, shutil, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "work", "src")
WORK = os.path.join(ROOT, "agents", "apps", "neg_src")
GEN = ".gen_apps_neg"
UI = "StarterPlayer/StarterPlayerScripts/Client/UI/"
HUD = UI + "Screens/HUD.module.luau"
EMP = UI + "Apps/EmpireApp.module.luau"
CMP = UI + "Apps/ComputeApp.module.luau"
ACT = "StarterPlayer/StarterPlayerScripts/Client/Controllers/ActionController.module.luau"
SEC = "StarterPlayer/StarterPlayerScripts/Client/Controllers/SecurityController.module.luau"
AST = "ServerScriptService/Server/Services/AssistantService.module.luau"
BSS = "ServerScriptService/Server/Services/BuildingStateService.module.luau"

# (name, file, old, new, test, state)
MUTATIONS = [
    ("HUD drops 'Client ✓'", HUD, 'if id == "office2" then "Client ✓ · " else ""', '""', "test_ui", "save"),
    ("HUD ETA rounds down", HUD, 'return "~" .. tostring(math.ceil(minutes)) .. " min"', 'return "~" .. tostring(math.floor(minutes)) .. " min"', "test_ui", "save"),
    ("HUD ignores nextGoal (old quest text)", HUD, "view.title = goal.text", 'view.title = "Next step"', "test_ui", "garage"),
    ("HUD Save-mode tag never shown", HUD, "saveTag.Visible = view.saving", "saveTag.Visible = false", "test_ui", "mid"),
    ("HUD never compact on phones", HUD, "compact = scale ~= nil and scale.Scale < COMPACT_SCALE", "compact = false", "test_ui", "phone"),
    ("HUD money per minute instead of per day", HUD, "moneySub.Text = Format.perDay(net)", "moneySub.Text = Format.perMinute(net)", "test_ui", "mid"),
    ("Pin sends skip", EMP, 'Kit.onClick(pin, function() toggle("pin") end)', 'Kit.onClick(pin, function() toggle("skip") end)', "test_ui", "mid"),
    ("Join sends the wrong client", EMP, '{ action = "joinMeeting", clientId = c.id }', '{ action = "joinMeeting", clientId = "helpdesk" }', "test_ui", "mid"),
    ("account end day off by one", EMP, "return Ops.day(e) + math.floor(into + math.max(0, secondsLeft) / Ops.DAY)",
     "return Ops.day(e) + 1 + math.floor(into + math.max(0, secondsLeft) / Ops.DAY)", "test_ui", "mid"),
    ("ledger totals skip a category", EMP, 'table.insert(out, { cat = cat, value = n }); total += n', 'table.insert(out, { cat = cat, value = n }); total += if cat == "wages" then 0 else n', "test_ui", "mid"),
    ("day picker ignores the picked day", EMP, "local shownDay = if picked and ledger[tostring(picked)] ~= nil and picked ~= dayNow then picked :: number else dayNow",
     "local shownDay = dayNow", "test_ui", "mid"),
    ("ledger keeps zero lines", EMP, "if n > 0 and typeof(cat) == \"string\" then", "if n >= 0 and typeof(cat) == \"string\" then", "test_ui", "rich"),
    ("wage budget payload fixed at 40 %", EMP, 'queued("EmpireAction", { action = "hrBudget", budget = tonumber(id) }', 'queued("EmpireAction", { action = "hrBudget", budget = 0.4 }', "test_ui", "mid"),
    ("apprentice flag missing", EMP, '{ roleId = roleDef.id, apprentice = true }', '{ roleId = roleDef.id }', "test_ui", "mid"),
    ("night shift only one department", EMP, "for _, dept in Ops.ROLE_DEPTS[roleDef.id] or {} do\n\t\t\t\t\tlocal ok, res = paced(",
     "for _, dept in { (Ops.ROLE_DEPTS[roleDef.id] or {})[1] } do\n\t\t\t\t\tlocal ok, res = paced(", "test_ui", "mid"),
    ("jet button enabled before the stage", EMP, "Kit.setDisabled(jetButton, stage < J.stage or s.data.money < J.price)", "Kit.setDisabled(jetButton, s.data.money < J.price)", "test_ui", "mid"),
    ("old Contracts tab back", EMP, '{"clients","Clients"}', '{"clients","Contracts"}', "test_ui", "mid"),
    ("split ignores the client reservation", CMP, "local clients = math.min(reserved, online)", "local clients = math.min(reserved, online) * 0.5", "test_ui", "mid"),
    ("split ignores cooling for faults", CMP, "offline = lost * thermal,", "offline = lost,", "test_ui", "rich"),
    ("fault countdown ignores IT", CMP, "math.max(0, (if it then F_.it else F_.alone) - elapsed)", "math.max(0, F_.alone - elapsed)", "test_ui", "mid"),
    ("rack shows every slot", CMP, "slots[i].frame.Visible = i <= slotCount", "slots[i].frame.Visible = true", "test_ui", "mid"),
    ("old studio split text (corefix #10)", CMP, "leaves less capacity for studio projects.", "leaves less capacity for projects and business customers.", "test_ui", "mid"),
    ("OFFICE error text missing", ACT, '\tOFFICE = "This needs a bigger office stage. Move up in Company → Office.",\n', "", "test_ui", "garage"),
    ("security titles by office index (corefix #7)", SEC, "return Plan.tierForOffice(if snapshot then snapshot.data.empire.office else 1)",
     "return if snapshot then snapshot.data.empire.office or 1 else 1", "test_server", "garage"),
    ("briefing without the Customers section", AST, 'table.insert(sections,{title="Customers",rows=custRows})', "", "test_server", "mid"),
    ("briefing P&L sums only income", AST, 'local costText,costs=topLines(entry and entry.o,3)', 'local costText,costs=topLines(entry and entry.o,3);costs=0', "test_server", "mid"),
    ("briefing counts vacation as present", AST, 'if state=="present" then present+=1 elseif state=="vacation" then vacation+=1',
     'if state=="present" or state=="vacation" then present+=1 elseif false then vacation+=1', "test_server", "rich"),
    ("Next goal not the first recommendation", AST, "  local text,app,section=goalRecommendation(s,goal,stock,journey,unreleased)\n  recommend(text,app,section)",
     "  local text,app,section=goalRecommendation(s,goal,stock,journey,unreleased)\n  recommend(\"Keep going.\",app,section)", "test_server", "mid"),
    ("data hall without reserved compute", BSS, 'table.insert(lines,string.format("Reserved for clients %.1f units · %d account%s"', 'local _unused=(string.format("Reserved for clients %.1f units · %d account%s"', "test_server", "mid"),
    ("clients screen shows old lease text", BSS, 'table.insert(lines,string.format("Accounts %d / %d · %s/day",#accounts,limit,money(retainer)))',
     'table.insert(lines,string.format("API customers %d · %s from leases",#accounts,money(retainer)))', "test_server", "mid"),
    # fix round (REVIEW_last.json): one mutation per review issue, caught by test_adv / test_ui
    ("advice ignores a full rack (buy GPUs)", CMP, "if fleet.slotsUsed < slots then", "if true then", "test_adv", "rackfull"),
    ("advice: upgrade cooling at 8/8", CMP, 'a.kind = if cooling < ComputeApp.COOLING_MAX then "cooling" else "maxed"', 'a.kind = "cooling"', "test_adv", "rackfull"),
    ("briefing advice ignores a full rack", AST, "if fleet.slotsUsed<slots then", "if true then", "test_adv", "rackfull"),
    ("briefing: upgrade cooling at 8/8", AST, 'a.kind=if cooling<COOLING_MAX then "cooling" else "maxed"', 'a.kind="cooling"', "test_adv", "stage5"),
    ("'a AI Accelerator' article", CMP, 'return (if vowel then "an " else "a ") .. label', 'return "a " .. label', "test_adv", "rackfull"),
    ("HUD 'best live model: 0'", HUD, "local function needsText(c: any, best: number): string\n\tif best <= 0 then", "local function needsText(c: any, best: number): string\n\tif best < 0 then", "test_adv", "garage_edge"),
    ("briefing 'best live model: 0'", AST, 'if best<=0 then return string.format("%s: %s needs %s %d. No model is live', 'if best<0 then return string.format("%s: %s needs %s %d. No model is live', "test_adv", "garage_edge"),
    ("night shift lane without the bucket mirror", EMP, "\t\tif l.tokens < 1 then", "\t\tif false then", "test_adv", "spam"),
    ("night shift: plain calls (no bucket mirror, no retry)", EMP, "\t\tif l.tokens < 1 then\n\t\t\ttask.wait((1 - l.tokens) / RATE)\n\t\t\tl.tokens = 1\n\t\t\tl.last = os.clock()\n\t\tend\n\t\tl.tokens -= 1\n\t\tlocal ok, res = Action.call(name, payload, true)\n\t\tlast = res\n\t\tif ok then return true, res end\n\t\tif res.err ~= \"RATE_LIMIT\" and res.err ~= \"BUSY\" then return false, res end",
     "\t\tlocal ok, res = Action.call(name, payload, true)\n\t\tlast = res\n\t\tif ok then return true, res end\n\t\tdo return false, res end", "test_adv", "spam"),
    ("Pin lock released at once (double tap undoes)", EMP, "if (seen == lock.want and age >= MIN_LOCK) or age > LOCK_SECONDS then", "if true then", "test_adv", "spam"),
    ("Money day table rebuilt every snapshot", EMP, "if dk ~= daysKey then", "if true then", "test_adv", "many"),
    ("Kit.segmented keeps its accent listener", "StarterPlayer/StarterPlayerScripts/Client/UI/Kit.module.luau", "\tframe.Destroying:Once(disconnect)\n", "", "test_adv", "many"),
    ("HUD says 'release models' while losing money", HUD, "if have < need and goal.etaMinutes == nil and earning and cost > revenue then", "if false then", "test_adv", "broke"),
    ("safety lines hidden", EMP, '\t\tt.Visible = text ~= ""', "\t\tt.Visible = false", "test_adv", "broke"),
    ("HUD safety badge missing", HUD, 'safetyBadge.Visible = safety ~= ""', "safetyBadge.Visible = false", "test_adv", "broke"),
    ("HR status ignores the budget", EMP, "if payroll + role.wage > budget * income then", "if false then", "test_adv", "hr"),
    ("Join TOO_FAR shows only the error", EMP, 'elseif res.err == "TOO_FAR" then App.routeToClient(c, backLeft)', 'elseif res.err == "TOO_FAR" then Toast.show("error", Action.message(res.err))', "test_ui", "mid"),
    ("Join offered on the founder's own visit", EMP, "canJoin = not trip.hosted and not trip.founder", "canJoin = not trip.hosted", "test_adv", "garage_edge"),
    ("countdown looks like a clock (15:00)", EMP, '.. " · back in " .. Kit.countdown(backLeft)', '.. " · back in " .. Format.duration(backLeft)', "test_ui", "mid"),
    ("HUD compact title too small", HUD, "stepTitle.TextSize = if compact then 20 else 17", "stepTitle.TextSize = if compact then 17 else 17", "test_ui", "phone"),
    ("HUD compact boost lost", HUD, "local COMPACT_BOOST = 1.5", "local COMPACT_BOOST = 1", "test_ui", "phone"),
    ("briefing says 'day N' 40 min before 08:00", AST, " if at-clock<Ops.DAY and ahead<SOON_HOURS then return hm end\n", "", "test_adv", "midnight"),
    ("Money shows '+$0'", EMP, '\tif math.abs(n) < 0.5 then return "$0", C.dim end\n', "", "test_adv", "oldsave"),
    ("Money rates without an empty state", EMP, "runEmpty.Visible = ops == nil", "runEmpty.Visible = false", "test_adv", "oldsave"),
    ("'Needs a better model' with no live model", EMP, 'if anyLive then "Needs a better model (%d)" else "Needs a live model (%d)"', '"Needs a better model (%d)"', "test_adv", "garage_edge"),
    ("HUD progress cut off (exact form always)", HUD, "if textWidth(candidate, progressText.TextSize) <= room then", "if true then", "test_ui", "save"),
    ("reception without trips", BSS, 'for i=1,math.min(3,#trips) do table.insert(lines,"Trip  "..tripShort(trips[i])) end', "", "test_server", "mid"),
]


def run(test, state):
    cmd = [os.path.join(ROOT, "tools", "luau"), test + ".luau", "-a", GEN, state]
    p = subprocess.run(cmd, cwd=os.path.join(ROOT, "tests", "apps"), capture_output=True, text=True, timeout=900)
    out = p.stdout + p.stderr
    summary = [l for l in out.splitlines() if " passed, " in l and " failed" in l]
    failed = 0
    if summary:
        try:
            failed = int(summary[-1].split(" passed, ")[1].split(" failed")[0])
        except Exception:
            failed = 1
    return p.returncode, failed, (summary[-1] if summary else "no summary (crash)"), out


def manifest():
    subprocess.run([sys.executable, os.path.join(ROOT, "harness", "make_manifest.py"), "--src", WORK, "--gen",
                    os.path.join(ROOT, "harness", GEN)], check=True, capture_output=True)


def main():
    flt = sys.argv[1] if len(sys.argv) > 1 else ""
    if os.path.exists(WORK):
        shutil.rmtree(WORK)
    shutil.copytree(SRC, WORK)
    # the unmutated copy must pass
    manifest()
    base_ok = True
    for test, state in sorted({(m[4], m[5]) for m in MUTATIONS}):
        rc, failed, line, _ = run(test, state)
        if rc != 0 or failed != 0:
            base_ok = False
            print("BASELINE FAILS:", test, state, line)
    detected, missed = 0, 0
    for name, rel, old, new, test, state in MUTATIONS:
        if flt and flt not in name:
            continue
        path = os.path.join(WORK, rel)
        orig = open(path, encoding="utf-8").read()
        if orig.count(old) != 1:
            print("MUTATION TARGET NOT FOUND (%d hits): %s" % (orig.count(old), name))
            missed += 1
            continue
        open(path, "w", encoding="utf-8").write(orig.replace(old, new))
        try:
            manifest()
            rc, failed, line, _ = run(test, state)
        finally:
            open(path, "w", encoding="utf-8").write(orig)
        ok = rc != 0 or failed > 0
        print("%-9s %-46s %s %s -> %s" % ("detected" if ok else "MISSED", name, test, state, line))
        if ok:
            detected += 1
        else:
            missed += 1
    shutil.rmtree(WORK, ignore_errors=True)
    if not base_ok:
        missed += 1
    print("apps_negative: %d passed, %d failed" % (detected, missed))
    return 0 if missed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
