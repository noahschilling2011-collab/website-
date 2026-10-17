# Requests from package "grandhotel_design" (Meridian Grand rebuild - design, filed 2026-10-12 by the design critic)

The Meridian Grand rebuild (design/GRANDHOTEL_SPEC.md) is built after round 2b; nothing here is needed for round 2b to work.

## 1. itinerary - hotel provider hook for the "Your room" step (small, additive)
Context: design/GRANDHOTEL_SPEC.md §18.6 (Meridian Grand rebuild). The rebuild ships AFTER round 2b; its HotelService then owns
13 real rooms. So that the itinerary's hotel step can hand over without a later edit in your files, please add:

- `ItineraryService.setHotelProvider(fn: (player: Player, trip: {[string]: any}) -> {[string]: any}?)` - stores fn (nil clears it).
- In the hotel step: if a provider is set, call it in a `pcall` with the trip (fields the hotel uses if present: `clientName`
  (string), `companions` ({{name, role?, seed?}}), `returnAt` (server time of the booked return)). If it returns a table with
  `ok == true`, show "Your room: <name> <room>" in the banner / calendar and point the GPS at the `door` CFrame it returns; if it
  returns nil / not ok / errors, keep your own "Your room" marker exactly as you built it.
- Put your own fallback "Your room" marker / prompt at `CityPlan.INTL_HOTEL.reception` (or on the hotel's `ReceptionistPost`),
  not on other parts of today's hotel interior (`LiftFront`, `FloorSign`, `ReceptionDesk`, ...): the rebuild replaces them, while
  the reception point stays free and the `ReceptionistPost` stays.
- Please do not register the TripAction action name `"hotel"` with `DriverService.onTripAction` (it silently replaces an earlier
  handler); the hotel's HotelService registers `"hotel"` after round 2b.
- No money, no saved field, no new remote. The hotel registers its provider in HotelService.init (pcall'd optional require of
  ItineraryService), so both shipping orders work.
Test idea: a fake provider returning {ok = true, room = "1001", name = "Royal Penthouse", door = CFrame.new(...)} -> the banner text
and the GPS target use it; a provider that errors -> the itinerary falls back to its own marker.
STATUS: done by itinerary (ItineraryService.setHotelProvider(fn) - pcall'd with {clientName, companions, returnAt, tier}; ok -> "Your room: <name> <room>" banner + beacon at `door`; nil / not ok / error -> own owner-only "Check in" prompt at CityPlan.INTL_HOTEL.reception (CITY_HOTEL.reception in the region); no "hotel" TripAction registered; tests/itinerary/test_service.luau edge scenario: provider ok + failing provider)
