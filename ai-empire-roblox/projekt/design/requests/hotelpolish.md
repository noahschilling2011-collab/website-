# Requests from package "hotelpolish" (guest house: lobby, rooms, breakfast, exterior identity)

## 1. BuildingPlan (owner: buildings / econ) — entrance position: NO change requested
Checked whether the guest-house entrance (`H0_LOBBY` door `D1`, face E, at z = 90, w = 8, autoslide) should move.
The house is boxed in on three sides: south facade z = 76 faces the Campus Arcade's last party wall at z = 72.6
(3.4 studs), west facade x = -141 is 1 stud inside the site edge, north faces the garden 100 studs from the
colonnade. The east door is the first thing a guest reaches after leaving the colonnade (18 studs up the
WestPath), so it stays. Instead the approach was dressed (ExteriorDesign, this package): the old way-sign post in
the alley removed (a hanging sign in the colonnade replaces it, bottom at y 9), deeper canopy over half the
WestPath with names on its front and south end, stone forecourt across the path, bay trees, three lamp posts in
the planting bed, built neon "GUEST HOUSE" letters on the south (over the arcade, seen from the plaza/street) and
west parapets. tests/hotelpolish checks the WestPath lane x -95..-89, z 72..125 is free at body height.

## 2. PlotService (owner: econ) — optional: keep the guest-house name signs in sync on a company rename
`Plot.refresh` updates `ReceptionSign` / `KitchenBrand` / `CompanyStele` with `setText`. If a company can be named
or renamed after the HQ was built, please add two unique boards to that table (both are a SurfaceGui with exactly
one TextLabel, so `setText` fits):
```lua
LobbyHouseSign = string.upper(company),   -- lobby back wall, above the built letters "GUEST HOUSE" (RoomKitsHotel)
ParapetNameBand = string.upper(company),  -- band under the south parapet letters (ExteriorDesign)
```
Without it the signs show the name at build time (every tier change rebuilds the office), which is correct as
long as the name is set before plan tier 2.
STATUS: done by corefix (PlotService.refresh: LobbyHouseSign and ParapetNameBand = upper-case company name)

## 3. For the hotel-guest NPC package (info, no change needed)
- Lobby waiting seats are still `H0_LOBBY_Wait1..4` (sofa 2 + two armchairs); the receptionist's greet point
  moved to (-105.6, 90.6) (building-local), the counter now runs z 95.0..103.4 at x -110..-108.5 with a second
  (empty) staff chair at (-113.4, 101.7). Every hop of post 13 is walkable for a radius-1.0 body
  (tests/hotelpolish, tests/life/test_routes.py, tests/buildings/test_geometry.py).

## 4. ExteriorDesign `garden()` (owner: lead / garden) — move the WestPath bench off the path's centre line
`Kit.bench(m, B, Kit.place(-92, 0.14, 150, "E"), 6, seed + 5)` puts the two seats (Office/Site/Garden/Seat, x -92.8..-91.2,
z 147..153) on the centre line of the WestPath (x -96..-88). Seen from the colonnade and from the guest-house entrance they
close the end of the view up the path as a dark box, and walkers have to step round them. Please move the bench onto the
planting bed beside the path, facing it:
```lua
Kit.bench(m, B, Kit.place(-86.6, 0.15, 150, "W"), 6, seed + 5) -- PlantingBed x -88..-82 (top 0.15); clear of the pavilion pier (z 142.75..145.25)
```
(any spot with x <= -96.5 or x >= -87.5 works; the bed at z 147..153 is free: nothing between x -88 and the pavilion glazing at -83.9).
hotelpolish does not edit `garden()` (outside its scope).

## 5. PlotService (owner: econ / corefix) — refresh the east-facade name band on a company rename
The pre-existing east-facade band `HouseNameBand` (ExteriorDesign, Kit.text: one SurfaceGui with one TextLabel) still shows the
build-time name after a rename. Please add one line to the `boards` table in `Plot.refresh`:
```lua
HouseNameBand = string.upper(company) .. "  ·  GUEST HOUSE",
```
Not requested (documented instead): the 12 room TVs' `WelcomePage` (3 TextLabels, "WELCOME" / "<company> Guest House" /
"Room 2xx") keep the build-time name until the building is rebuilt (every plan-tier change rebuilds the office); a
`FindFirstChild` refresh would only reach the first TV.

## 6. Info (no change needed) — approach changes in review round 2 (hotelpolish)
- Blade sign `BladeSign` (+ neon edge `BladeSignGlow`) on the guest house's south-east corner pier: x -96.4..-92.0, y 7.8..11.0,
  z 77.85..78.15, "GUEST / HOUSE" on both faces. It hangs low on purpose: the colonnade soffit (y 10.8, to z 72.6) leaves only
  y < ~11 at z 78 in view from the colonnade and the plaza.
- The colonnade hanging sign moved into the east half of the colonnade (x -91.8..-86.6, still y 9.0..10.4 at z 58, rods into
  the soffit) and now reads "GUEST HOUSE  ↑" (larger letters), so it no longer hides the blade sign from the plaza.
- Dark metal backing plates `SignBacking` behind the neon parapet letters (south z 75.16..75.24, west x -141.79..-141.71;
  the west letters are 0.18 deep now, x -141.98..-141.80).


## 7. Lead (notes_integration.md, round 2b) — entrance move: please DROP "Gästehaus-Eingang verlegen (BuildingPlan)"
hotelpolish requests no BuildingPlan change for the guest-house entrance (`H0_LOBBY` door `D1`, face E, at z 90). The
independent review of round 2 accepted the current side entrance (blade sign on the corner pier, canopy over half the
WestPath, lanterns, forecourt, three lamp posts, lit approach from the colonnade). Moving it would also move the
receptionist's greet point and the counter layout that the life route tests check. If the lead still wants the move,
please confirm explicitly so the two packages do not duplicate work.

## 8. Info (no change needed) — review round 3 (hotelpolish)
- Lobby: the 38 built brass letters are gone; "GUEST HOUSE" is a SurfaceGui line on the clear carrier `LobbyHouseWord`
  (static text, so it needs no refresh). `LobbyHouseSign` (company name, one TextLabel) is unchanged, so request 2 stays valid.
- The key rack (`KeyRack`) is a backlit key-cubby grid (SurfaceGui `KeyGrid`, one cubby per guest room with its number,
  taken from `Plan.rooms(tier)` at build time). A key tag hangs in about half of the cubbies. This is decoration only;
  nothing reads it. The hotel-guest package could later drive it from occupancy on the client.
- Guest rooms: curtains are 3.2 wide at u = D - 0.2, the desk moved to u = D - 1.6 and the window-side nightstand sits
  between the headboard and the curtain. The guest point (F * (10.6, 4.4)) and the housekeeping points (F * (12, 4.2)) did not move.
- Requests 4 (garden bench on the WestPath, lead/garden) and 5 (`HouseNameBand` in `Plot.refresh`, econ/corefix) are
  still open.
