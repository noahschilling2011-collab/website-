--!strict
-- The founder's business-trip itinerary: the assistant books, the driver brings you, a colleague travels along,
-- everything at the destination is planned (round 2b, package "itinerary"). Stub pre-wired by the integration lead
-- so the builders never touch the frozen Main.server:
--   * init()   runs once from Main.server after DriverService.init (before SessionService.init);
--   * tick(dt) runs in Main.server's campus loop (every 0.05-0.25 s, inside a pcall).
-- The remote "TripAction" {action = go | cancel | leave | ride | status, ...} (Net.FUNCTIONS) is created by
-- Remote.setup and bound by this service (or DriverService). No-ops until the itinerary package replaces this file;
-- keep both signatures.
local ItineraryService = {}
function ItineraryService.init() end
function ItineraryService.tick(_dt: number) end
return ItineraryService
