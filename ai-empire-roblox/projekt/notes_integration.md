# Integration TODO (lead)
- [x] Snapshot size: delta snapshots omit unchanged staffProfiles; client merges (tests/lead/test_snapshot.luau 13/13)
- [ ] StaffX attr differs between plot/rot dumps on fallback employees — check StaffAssignment stores local coords
- [ ] RoomKitsWork warnings: "Desk in door zone", "BoardStand outside the room"
- [ ] WC cubicle interiors unreachable for agent radius 1.3 (check cubicle size)
- [ ] Light budget 150 binding (Interior) — decide
- [ ] Ops station 4 missing at tier 3 (garage security booth?) — RoomKitsSpecial
- [x] Safe-loader in HeadquartersDesign stays (pcall per generator = a broken generator never kills the office; warnings logged)
- [ ] analyze_diff over whole tree; pack; final harness all tiers; renders review (own)
- [ ] Studio test list + report
- [x] Access leak visitor lounge -> atrium (x=-22, z -20..-16): Layout open faces now only open towards same access class (wall stub added)
- [x] HeadquartersDesign generator list typed (analyzer noise gone)
- [x] Skylight railing g 1.6 -> 1.0 (5 studs clear before roof lobby doors)
- [x] Hole check tests/lead/holes.py: tier 1 + 4 = 0 sq studs; negative test detects atrium/shaft/stair; district trenches 0
- [x] Runtime review (agent): 0 crash/exploit; fixed: applicant expiry after rejoin (a.at reset), retry-phase walk-off, workstation reservations carried across staff rebuild (Workstations.reset/scan), LabApp Toast require, EmpireApp asking price = hireCost*ask, ViewportSize connection leaks. Regression tests in people_harness/test_people.luau (2144 pass; negative test confirms detection)
## NEXT: company logic redesign (user request 2026-10-03): day 20 min kept, almost everything automatic, early-game income too low, cars for field staff + boss, customer trips + hotel cost, company hotel on site, talk to everyone, chef + real lunch, several live models, staff really working
- [x] net package integrated: run_all includes net suites; DebugService reset live-wipe → give to shop pkg owner (DebugService) after phase1
- [x] life + talk packages done (resumed). Integrated: run_all +talk +life suites; EmployeeRigDesign uniforms for Hotel Reception/Housekeeping/Cleaner/Mailroom; CampusMath ops-staff surnames (unique, k stride #list+1 past hired range); sandbox copies agents/life/orig
- [ ] open from life: StaffAssignment optional posts 13/14 (buildings pkg), DoorService remote barrier (later), parked EVs in bays 02/04 collidable vs future fleet parking, LOD-wake walks ignore movers cap (rare), ops wages (CORE_SPEC)
- [ ] open from talk: hotel attrs HotelGuests/HotelRooms + room purposes for hotel kinds (after buildings), ops wage config (CORE_SPEC), Dialogue lines for Cleaner/Mailroom (generic now)
- [ ] NEXT after blender exterior workflow: aircraft INTERIORS (cockpit: 2 pilot seats, panels/displays, sidesticks, thrust levers, overhead panel; cabin 320: seat rows, aisle, bins, galley, lavs, lights; 380: two decks, stairs, business/first upstairs; seat positions in manifest for Roblox Seat placement; car interior check). Show interior renders to user.
- [x] GUI preview tool (tools/guiprev) built; shop UI bugs fixed by lead: header order (productGroup), "✓ Owned" readable (C.good), investor desc no duplicate, Computer VIP badge in a horizontal row (no AbsoluteSize unit mix), fitSidebar in design px, journey highlight visible (BackgroundTransparency), Kit shop icon. tests/shop: 146/0 + 46/0 (new header-order check)
- [ ] open UI: phone text small (UIRoot designs for 1280x720 → 0.432 on 844x390) needs responsive phone layout; add shop + world + talk + life + buildings suites to run_all (shop run.sh; world run.sh; buildings tests)

## 2026-10-04 06:2x — Blender-Sichtprüfung Flughafen (airport_aerial.png, airport_terminal.png)
Render treu, aber der Flughafen selbst ist kahl -> Pflicht für world stage 2 / flight package:
- Terminal: flaches graues Riesendach ohne Gliederung; Vorfahrt ohne Schilder, Autos, Taxis, Menschen; Innenraum (Check-in, Sicherheitskontrolle, Gates, Lounge) prüfen/ausbauen.
- Prozedurale Flugzeuge = Kastenrumpf + flache Flügel -> durch Skyliner320/380-Meshes ersetzen (oder prozedural deutlich runder: Rumpf aus Zylindern, Nase/Heck verjüngt).
- Vorfeld leer: Fluggastbrücken, Vorfeldfahrzeuge (Tankwagen, Gepäckschlepper, Treppen), Markierungen/Standplatzlinien, Rollweg-Beleuchtung.
- Hinter der Piste endet die Karte als graue Fläche -> Gelände/Zaun/Bäume/Wasserkante als Abschluss.

## 2026-10-04 06:5x — Blender-Sichtprüfung Gästehaus (out/blenderprev/hotel/)
Zimmer (R01, R11) und Frühstücksraum sehen ordentlich aus. Schwach:
- Lobby H0_LOBBY wirkt leer/klein: winziger Empfangstresen, großes braunes Paneel ohne Text, ein Gepäckwagen-Gestell, kaum Sitzgruppe -> Lobby aufwerten (längerer Tresen mit Rückwand + Logo, Sofagruppe, Teppich, Pendelleuchten, Gepäckwagen, Schlüssel-/Infodisplay).
- Eingang (Ostseite x=-98) liegt in einer ~14-Stud-Gasse zwischen HQ und Gästehaus, Schild blockiert die Sicht -> Eingang zur offenen Seite (West-Pfad/Nord) oder Vorplatz mit Vordach.
- Allgemein: Innenräume im Render dunkel -> in Roblox (Future) prüfen, ggf. mehr SurfaceLights.

## 2026-10-04 07:3x — Flughafen-Innenraum (CityBuilder ~Z.590-628)
Funktional vorhanden (Check-in-Prompt -> Flug, Security 3 Spuren, Abflugtafel, Gates A1-A3 + Sitze + Boarding-Desk, Café-Tresen, Kiosk, Jet Bridges als Deko), aber 600x100-Stud-Halle fast leer:
-> Shops/Duty-free, Sitzlandschaften, Business-Lounge, Gepäckwagen, Pflanzen, Säulen/Deckenstruktur, Wegweiser, NPC-Passagiere (client-side), Ankunft mit Gepäckband.

## 2026-10-04 08:1x — Phase 2 gestartet
- CORE_SPEC.md fertig (robust-Basis + Grafts, 59 Sim-Läufe). run_all um shop/world/buildings erweitert: 46 Suites grün (RUNALL_TAG=lead).
- Prewire: Port Meridian aus CityBuilder in MetroBuilder.module.luau extrahiert (Weltdump vorher/nachher identisch, 4702 Instanzen); CityLifeController-Stub + Main.client init. Baseline: agents/stable/src_p2_base_0805.
- Laufend: wt91k2120 (phase2-core: econ + models → verify sim/save_net/conformance → corefix), wjowc3grd (world: airport + metro), w5d7xiyql (world: flight + hotelpolish), wpnicvjru (Blender vehicles).
- Ownership: econ = CompanyOps, Econ-Services, Configs, Template, Net, Main.server(tick order), Office-Index-Zeilen in Building-Services, StaffService(nur Arrival/Mapping/keine Geldschreibzugriffe); models = AIModelService/ModelMath/ModelConfig/LabApp/MarketApp; airport = CityBuilder(ohne PM)/CityPlan(additiv); metro = MetroBuilder/CityLifeController/MetroPlan; flight = CityService/TravelController/AircraftModel/ShuttleService/EmployeeRigDesign(Pilot); hotelpolish = RoomKitsHotel/ExteriorDesign(Gästehaus).
- Danach Welle 2: hr (StaffService sichtbar, Abwesenheit, Nachtschicht, Azubis+Ausbilder, Recruiting/Headhunter), clients (sichtbare Fahrten/Fuhrpark/Chauffeure/Meetings/Hotelnächte), hotel_jet (Gäste im Gästehaus, Jet im Hangar + Flüge), phone (Diensthandy + KI-Chat TextGenerator/Demo), apps (Empire/Compute/Next-goal-HUD), compute visuals (Rack-Fehler + IT-Weg).

## 2026-10-04 11:2x — Nutzerwunsch 24 (Geschäftsreise-Itinerar) in LOGIC_BRIEF aufgenommen
Assistentin bucht, Fahrer holt ab, Mitarbeiter reist mit, Shuttle/Jet, VIP-Limo, Meeting + Hotel geplant, Rückflug gebucht. Default: Angebot mit 1 Tipp, Einstellung "immer automatisch" (Default AUS). Welle 2: clients (Itinerar + Assistentin + Meeting), flight-API (prepaid + Begleiter), drivers/limo, phone. Laufendes flight-Paket kennt das noch nicht → in Welle 2 nachziehen.

## 2026-10-04 18:3x — Phase-2-Core fertig, Runde 2a gestartet
- phase2-core abgeschlossen: econ + models gebaut, 3 Verifier (save_net, sim, conformance), corefix: alle Blocker/Majors in eigenen Dateien gefixt; Real-Code-Sim = CORE_SPEC §9 (min 5–10: 8,444 vs 8,442 $/min; Stufen 10.3/31.7/83.0/166.6). Offene Requests: design/requests/corefix.md (#1 Uhr, #2 HUD, #3 Assistent, #4 EmpireApp, #5 Screens, #6 Ticket $700 in CityPlan → nach airport-Ende vom Lead, #7 Security, #10 ComputeApp).
- Lead: run_all um econ_*/corefix/corefix_ui/models erweitert; sandbox.py kopiert tools/guiprev (statt Symlink).
- Zwischenstand-Datei verschickt: out/AIEmpire_Stand_2026-10-04_abend.rbxlx (Snapshot agents/stable/snap_1750, 39/39 Suites grün, Roundtrip OK).
- Prewire: PhoneService/PhoneController-Stubs + Net "PhoneAction" + Main-Init. Baseline Runde 2a: agents/stable/src_r2a_base_1830.
- Runde 2a läuft (wyj1j1hra): staffops (eine Uhr, Abwesenheiten, Nachtschicht, Azubis + Training Lead, IT repariert Racks, Auto-HR sichtbar), phone (Diensthandy + KI-Chat TextGenerator/Demo, Anrufe/Kalender/News, Hooks für Fahrer/Itinerar), apps (Next-goal-HUD, Assistent-Briefing, EmpireApp Clients/P&L/Settings/Azubis/Jet, ComputeApp, Screens).
- Runde 2b (nach Ende der Welt-Pakete): itinerary (Wunsch 24 + Fahrer/Chauffeure + sichtbare Kundenfahrten/Fuhrpark + VIP-Limo + Meetings + Hotelnächte + Hotelgäste-NPCs + Firmenjet sichtbar mit Firmenpiloten), Passagiere im Terminal, Gästehaus-Eingang verlegen (BuildingPlan), Kosten Fahrer/Handy erst ab Existenz (jetzt erledigt: Handy kommt in 2a, Fahrer in 2b).

## 2026-10-10 09:xx — Wochenlimit zurückgesetzt, Jobs fortgesetzt, Sicherung
- Fortgesetzt: round2a (wf_f9c49f01-b0c: staffops/apps finish + phone review/fix), world (wf_572d93c4-4d9 metro+airport fix, wf_cdd42b37-6de flight+hotelpolish fix).
- Sicherung an Nutzer geschickt: out/backup/AIEmpire_Projekt_Backup_2026-10-10.tar.gz + out/AIEmpire_Stand_2026-10-10.rbxlx (Zwischenstand, Roundtrip OK, run_all NICHT gelaufen). Snapshot agents/stable/snap_1010.
- Runde 2b vorbereitet: agents/stable/round2b.js (Integrate → drivers ∥ guests_jet → itinerary nach drivers → verify). Integrate triagiert ALLE offenen Requests (≈50 Abschnitte ohne STATUS; u. a. corefix #6 Ticket $700, phone #1 empire.prefs, phone #3 Chat-Button, run_all-Zeilen für airport/metro/flight/hotelpolish/staffops/phone/apps/talk/shop/net/world) und prewired DriverService/JetService/ItineraryService + Drive/Guest/Jet/ItineraryController + Net "TripAction".
- Entscheidungen: Gästehaus-Eingang NICHT verlegen (hotelpolish #7, Zugang wurde in hotelpolish-Runde 2 gelöst). Fahrer existieren genau ab dem Stand, ab dem CompanyOps sie bezahlt (Ops.DRIVER 1 ab Stufe 2, 2 ab Stufe 4) → Kosten-Inkonsistenz ohne Econ-Änderung gelöst.
- Start von 2b erst, wenn alle drei laufenden Workflows fertig sind (CPU: max 2 Agenten pro Workflow, 4 CPUs).
- 10.10.: Projekt ins Repo noahschilling2011-collab/website- hochgeladen: Branch claude/ai-empire-roblox-tycoon, Ordner ai-empire-roblox/ (2 rbxlx, Beschreibung, projekt/ = Backup-Inhalt snap_1010), Draft-PR #18 (abonniert). Künftige Stände dort als Commit nachziehen (projekt/work/src aktualisieren + neue rbxlx).
- 10.10. 10:4x — Nutzerwunsch 25: KI-Erstellungsbildschirm (LabApp creator) viel besser, nach Vorbild Roblox-Handy-Hersteller-Spiele. Workflow w720lho30 (wf_68439794-eb7): Research (Roblox-Handy-Spiele, andere Creation-Games, Code) → 3 Designs → Judge → design/LAB_SPEC.md + HTML-Mockups out/lab_design/*.png → Critic. Bau erst nach Freigabe durch den Nutzer als eigenes Paket "lab" (LabApp/ModelsUI/MarketApp + ggf. ModelMath/AIModelService mit Sim-Nachweis). round2b.js: Integrate rührt LabApp/MarketApp/ModelsUI nicht an, phone #3 → lab.
- 10.10. 11:50–15:10 Session-Limit. 15:2x: Resume der 3 Bau-Workflows gestoppt, weil Resume Präfix-Semantik hat (nach dem ersten geänderten agent()-Aufruf läuft alles live → fertige fix:staffops/fix:airport/review:apps wären doppelt gelaufen). Stattdessen Fortsetzungs-Workflows: A wog5ml3ub (fix phone+apps), B wqmwf3cuy (fix metro+flight+hotelpolish); Briefs in agents/<k>/BRIEF_fix.md + agents/<k>/REVIEW_last.json (aus den Journals). Lab-Design wy9yxnlby normal fortgesetzt (judge/spec/critique). LEHRE: bei Teil-Abbrüchen immer Fortsetzungs-Skript nur mit den fehlenden Agenten, nie Skript editieren + resume.
- Erledigt laut Journals: fix:staffops (alle Review-Punkte außer 2 fremden Dateien: IT in Datenhalle = BuildingPlan-Request #1, TalkPanel-Top = talk), fix:airport. Round2a/World danach komplett, sobald A/B fertig.
- 10.10. 15:4x — Nutzer bestätigt: KI-Erstellung wie "Build a Phone Empire" (DEVTEC STUDIOS) einbauen, ohne extra Freigabe. Bauplan agents/stable/lab_build.js (build:lab → review function/economy/save ∥ review UX/visual → fix → verify → ggf. fix2). Start sobald Lab-Design (LAB_SPEC.md + Mockups) fertig. Lab besitzt LabApp/ModelsUI/MarketApp/UI/Lab/*/ModelConfig/ModelMath/PricingMath/AIModelService(+PricingService)/tests/models/tests/lab; Kit/Theme read-only (apps-Fix läuft). round2b-Integrate fasst diese Dateien nicht an.
- 10.10. 17:0x — Lab-Design fertig (Sieger phone_maker 'Model Studio', 6 Schritte + Review, LAB_SPEC.md 927 Z., 19 Mockup-PNGs, Critic: 13 Probleme behoben, Tap-Ziele ≥44 pt, Text ≥12 pt, Schnellstart 3 Taps). 4 Mockups an Nutzer geschickt. Lab-Bau gestartet: wzyyrm1at (wf_971152ca-074). round2a komplett (A fertig: phone 226/0 + UI-Suites, negative 59/59; apps negative 57/57; run_all 47/47).
- 10.10. ~17:00 — B fertig: metro (alle 18 Findings, PM 5,253 Teile = Budget fast voll, 28 frei; Tests grün, run_all 47/47), flight (9 voll, 3 teilweise, 2 offen bei airport: Flutmasten/Hold-Short-Schilder/Windsack im Flügelweg; run_all-Zeilen fehlen), hotelpolish fertig. Round2a + Welt damit abgeschlossen.
- Snapshot agents/stable/snap_1655 (vor Lab-Edits und vor round2b). run_all darauf läuft (b8o000ut8 → agents/stable/snap_1655_runall.txt). Wenn grün: rbxlx packen + ins Repo (PR #18) als neuer geprüfter Stand.
- Round 2b gestartet: wiz5q3uu8 (wf_c03a1790-02a). Lab-Bau parallel: wzyyrm1at.
- Offene Fremd-Requests für integrate: airport (Flutmasten/Hold-Short/Windsack aus Flügelweg, ABROAD-Rect größer, Terminal-Walkgraph #7), BuildingPlan IT darf in Compute (staffops #1), TalkPanel-Top (staffops 3b), run_all-Zeilen aller Pakete.
- 10.10. 17:1x — Nutzerwunsch 26: Video/Bilder 'Fahrer holt dich ab'. Fahrer existiert noch nicht (drivers-Paket in round2b nach integrate). NACH drivers-Fix: eigener Render-Job: echte Fahrt (DrivePlan-Route + Timeline) im Mock in ~96 Zeitpunkten abtasten, je Frame Welt-Dump mit Auto/Fahrer/Spieler, blenderprev Cycles 960x540 ~16spp, ffmpeg (/usr/bin/ffmpeg) → out/drivers/fahrer_abholung.mp4 + 4 Standbilder (Fahrer am HQ-Eingang, Einsteigen, Fahrt, Flughafen-Kerb). Ehrlich beschriften: Render aus Spieldaten, keine Studio-Aufnahme, keine Animationen der Rigs.
- 10.10. 17:1x — snap_1655 run_all 47/47 grün → out/AIEmpire_Stand_2026-10-10_abend.rbxlx (Roundtrip OK, 141 Skripte) + src/docs/tests ins Repo (Commit 51f6cfa, PR #18 Beschreibung aktualisiert). Morgen-Zwischenstand aus dem Repo entfernt. Airport-Innenbilder (entry/checkin/foodcourt/lounge/gate) an Nutzer geschickt.
- 10.10. 17:2x — Nutzer fragt nach Flugzeug innen. Stand: Cockpit (Piloten-Mützen füllen das Bild, dunkel, Scheibenpfosten mittig) + Fensterplatz-Kamera; Kabine nur 6 CabinSeats, keine Sitzreihen/Gang/Gepäckfächer/Galley. GEPLANT (Paket 'cabin', NACH round2b guests_jet wegen AircraftModel-Ownership): echte Kabine 320/380/bizjet (Sitzreihen 3-3 bzw. 3-4-3, Gang, Gepäckfächer, Leselicht, Bordscreens, Galley, Business-Reihe vorn), Cockpit-Kamera Jump-Seat weiter hinten/höher, Kabinen-Kamera + Blender-Renders. Außerdem offen: Blender-FBX (assets/vehicles) verbessern + ins Repo mit IMPORT_IN_ROBLOX.md (Nutzer-Antwort ausstehend).

## 2026-10-10 18:xx — Integrate (Runde 2b, Schritt 1) fertig
- Triage aller offenen Request-Abschnitte (86): 32 done by integrate, 39 already done, 6 dropped, 9 deferred (drivers 2, guests_jet 3, itinerary 2, lab 2). Jede Zeile "STATUS: ... (integrate: ...)" in design/requests/*.md.
- Angewendet u. a.: Ticket $700 (CityPlan, Test in tests/world/test_cityplan), empire.prefs {autoTrips=false} (EmpireMath.new + Template-Cleaner, kein DATA_VERSION-Bump, Migrationstests), SERVE_POWER, Fault-ETA, nightShift per Rolle (atomar), Pin/Skip mit `on`, Ledger "cars"/"shop", Gartenbank + HouseNameBand, IT darf in Compute (BuildingPlan), TalkPanel unter der Top-Bar, Ops.graduate räumt verwaiste Azubi-Einträge, Training-Lead-Uniform, ShadowOf in Dialogen, Raum-Zwecke Garage/Gästehaus, urgent markDirty bei Prompts, Debug-Shop-Buttons, Flughafen: Flutmasten/Hold-Short-Schilder/Windsack aus dem Flügelweg (clearance 18/0, 0 pending), Terminal-Laufgraph (Magazinständer kürzer, Meeting-Point versetzt; metro_paths 0 pending), Welt-Budgets pro Zone in agents/world/world_check.py, Airport-Exterior-Budget 2.000.
- Lead-Entscheidung staffops #10: sichtbare Ops-Posten = bezahlte Posten (EmployeeConfig.POST_FROM_STAGE, CORE_SPEC 5.5; Stufe 2: 8, 3: 12+2, 4: 14+2, 5: 16+2). Testanpassungen (beabsichtigt): staff_harness/test_staff (Ops-Zahl, Warnung), tests/life/test_life (unbezahlte Jobs erscheinen unter ihrer Stufe NICHT), tests/buildings/test_build (t1 = 8 = STAGES[2].ops).
- Gästehaus-Eingang wird NICHT verlegt (hotelpolish #7) — aus dem 2b-Plan gestrichen.
- CORE_SPEC: Abschnitt "Decisions (integrate, 2026-10-10)" angehängt (corefix #12, staffops #5/#7/#10, prefs, offene Punkte HR-Ziel/Work-Items/Computer-Touch-Scale).
- run_all um airport, metro (5), flight (5), world_check/entrances/metro_reach, hotelpolish, staffops (14), phone (5), apps (18) erweitert: 99 Suites; sandbox.py kopiert agents/airport + agents/world Skripte.
- Prewire 2b: JetService/DriverService/ItineraryService (init + tick, Main.server nach PhoneService, Reihenfolge Jet → Driver → Itinerary, tick in der Campus-Schleife), Drive/Guest/Jet/ItineraryController (Main.client nach PhoneController), Net "TripAction".
- Lab-Paket lief parallel (eigene Dateien, nicht angefasst); phone #3 und apps #8 an lab.
- Baseline: agents/stable/src_r2b_base. Logs: agents/integrate/ (runall_1/2, harness_1, world_dump_1, clearance1).
- 10.10. 18:41 — Sicherung ins Repo (Commit 30eaca5): zwischenstand_in_arbeit/ (src/tests/design WIP 18:41, Pläne inkl. round2b.js/lab_build.js/Workflow-Skripte/Briefs, Recherche) + assets/vehicles (Blender 320/380/CityCar ohne _scratch/_research). Stand Workflows: integrate fertig (Triage, run_all grün mit allen Paket-Suites, Prewire), drivers + guests_jet bauen, lab bei GUI-Renders.
- 10.10. 19:50–20:10 Session-Limit #2 (lab build + drivers/guests_jet Builds abgebrochen). 20:12: round2b resumed (w2d3wum9c, integrate gecacht, RESUME-Note für drivers/guests_jet), lab neu gestartet mit RESUME-Note (wdnoetpta, wf_840483a3-525). Integrate-Ergebnis: 86 Request-Abschnitte triagiert (32 done/39 already/6 dropped/9 deferred), run_all 99 Suites grün (233,105 Checks), Harness ok, Ticket $700, empire.prefs, Prewire + Snapshot src_r2b_base. Entscheidung staffops #10: sichtbare Ops-Posten = bezahlt (Stufe 2: 8 Posten).
- 10.10. 20:2x — Nutzerwunsch 27: detailreiche Blender-Limousine (ExecutiveLimo) für Fahrer/Flughafen. Workflow wtg13v9f3 (wf_ca88dc6a-71b): model → critique → fix → verify (→ fix2). Ziel assets/vehicles/executivelimo/ (FBX/OBJ, manifest mit Anker/Scharnieren, Renders, README+Import). Spielanbindung als Request in design/requests/drivers.md; nach drivers-Fix einbauen (Mesh wenn ReplicatedStorage.Assets.Vehicles.ExecutiveLimo vorhanden, sonst Teile-Limo).
- 10.10. 21:4x — Nutzerwunsch 28: Tutorial (erste KI rausbringen), Menü einfacher, Robux-Shop (existiert: ShopService/ShopApp/ShopConfig, alle ids=0 bis Owner sie anlegt). Design-Workflow wnlhm0goa (wf_cb981e20-042) → design/ONBOARDING_SPEC.md + Mockups out/onboarding_design/. Bau erst NACH Lab-Fertigstellung (Tutorial führt durchs Model Studio); Paket 'onboarding' besitzt dann Computer/HUD/Intro/Tutorial-UI/ShopApp/ShopService/ShopConfig/AssistantService-Zeilen + empire.tutorial (Template additiv mit Migrationstest). Meridian-Grand-Renders: Hintergrund-Agent → out/meridian_grand/.
- 11.10. 06:1x — Session-Limit #3 (~22:30–01:10 UTC), danach idle bis 06:11. Neu gestartet: round2b we3iug40e (integrate gecacht, drivers/guests_jet mit RESUME), lab wxdjc04s4 (build+reviews gecacht, fix:lab mit RESUME), limo w78pwrfr1 (model mit RESUME), onboarding design wey1k04t6 (research gecacht), Meridian-Agent per SendMessage fortgesetzt.
- 11.10. 07:1x — Nutzerwunsch 29: Robux-Forschungs-Skip + viel größerer Shop, Ideen von Build a Phone Empire übernehmen, aber eigene KI-Produkte (keine kopierten Namen/Texte/Bilder). Design-Workflow wahk8kpuy (wf_968568b6-1d6) → design/SHOP_SPEC.md + out/shop_design/. Bau zusammen mit onboarding (ONBOARDING_SPEC + SHOP_SPEC) nach Lab-Ende. Wirtschafts-Leitplanken: Zahler schneller, Nicht-Zahler unverändert, Caps, Sim mit Nicht-/Leicht-/Viel-Zahler.

## 07:35 UTC – Meridian Grand Renders fertig (out/meridian_grand/hotel_1..4.png), an User geschickt
Ehrliche Bewertung: wirkt wie Bürobau. Geplantes Paket "grandhotel" (NACH Runde 2b, da drivers ggf. CityBuilder/Vorplatz anfasst):
- Fassade: Sockel/Podium, Säulen, Gesims, Balkone/Rücksprünge, Sprossen oben; Fenster mit MetroNightGlow taggen (aktuell 0)
- Eingang: Vordach groß (Porte-cochère), Drehtür/Türen, Stufen, Fahnen, Pflanzkübel, Vorfahrt-Spur (passt zu Limo-Drop-off), Doorman-NPC + Gepäckwagen
- Lobby: verkleinern/zonieren, Teppiche, Kronleuchter, Säulen, Bar/Café, bessere Möbel (keine Würfel), Bodenbelag
- Helipad: von unten sichtbar machen oder Lift-Teleport ehrlich kennzeichnen

## 07:40 UTC – User-Wunsch 30: Meridian Grand: "Zimmer die richtig krass sein müssen", Wellness-Etage, Hotel-Mitarbeiter
- Design-Workflow wjnb2xm5b / wf_026d3e6f-48f (scout code+research → 3 Vorschläge wow/iphone/life → 2 Judges → design/GRANDHOTEL_SPEC.md + out/grandhotel_design/plan_*.png → Critic)
- Build ERST nach Runde 2b (Konflikt: drivers pm_hotel Drop-off, itinerary "Your room"-Marker im Meridian Grand). Danach Paket(e) laut Spec.
- Ehrlich an User: großes Paket, Risiko Performance iPhone (10 Etagen Innenleben) → Spec muss faken/streamen wo nötig.

## 07:52 UTC – Onboarding-Design fertig (wf_cb981e20-042): design/ONBOARDING_SPEC.md (Critic: 21 Fixes, Abschnitt 0.6), out/onboarding_design/phone_1..9 + desktop_1..2 neu gerendert
- Offene Owner-Entscheidungen (0.3): Series A/B Cash-Pack-Cap (0.5x/1.0x nächster Bürопreis, ändert CORE_SPEC 11.7), Robux-Preise, Firmennamen-Ideen, kompaktes Phone-Panel
- Vor Build: Shop-v2-Design (wf_968568b6-1d6, inkl. Forschung-Überspringen) abwarten und in Spec mergen; Build erst nach lab (Studio-Dateien) → dann User einmal zu Cap/Preisen fragen
- tests/apps/test_ui.luau:116-121 prüft den Bug (Goal→Datasets) – muss im Build umgeschrieben werden
- Grandhotel-Research: PM hat 40/40 echte Lights → Glow per Neon/NightGlow/Client-Lights; Teile 5.253/20.000; Terrain-Wasser für echtes Schwimmen

## 11:15 UTC – Limit-Treffer ~08:00 (reset 11:10). Alles fortgesetzt:
- lab wu1cr4cvt (resume wf_840483a3-525: build/reviews/fix1 cached, verify:lab live)
- round2b w6s1jrnfd (resume wf_c03a1790-02a: integrate+build:drivers cached; build:guests_jet + review:drivers live)
- shop v2 wsph1afbp (resume wf_968568b6-1d6: research cached, design live)
- grandhotel CONTINUATION w10mtnijb / wf_25a5df47-499 (script ai-empire-grandhotel-design-cont.js: research als Konstante, scout:code mit RESUME) – weil scout:code VOR research in Aufrufreihenfolge lag
- limo ww9y6t5iq (resume wf_ca88dc6a-71b: nichts cached, model:limo mit RESUME live)
- Check-in 8 in 90 min

## 12:00 UTC – LAB FERTIG (wf_840483a3-525): verify:lab verdict good, 0 blocking; run_all 99/99 (233,105 checks) beim Verifier; 45/45 Mutationen; Balance 12/12 PASS byte-identisch
- Release-Snapshot agents/stable/snap_lab_1150 = src_r2b_base + LabApp + UI/Lab/* (ohne Runde-2b-WIP). run_all + pack + roundtrip läuft (bwr55i4uu) → out/rel1150/AIEmpire_Stand_2026-10-11_ki-studio.rbxlx → Repo/PR #18
- 7 Lab-PNGs an User geschickt
- Offene lab-Requests (design/requests/lab.md #1-8): HUD-Toast ohne Score, JourneyMath section, Toast.hold, kompaktes Computer-Chrome → ins onboarding-Paket (besitzt HUD/Computer)
