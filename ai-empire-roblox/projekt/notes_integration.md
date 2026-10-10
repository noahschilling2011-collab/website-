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
