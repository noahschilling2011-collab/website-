--!strict
-- Company chauffeurs, visible fleet rides and the VIP limo in Port Meridian (round 2b, package "drivers"). Stub
-- pre-wired by the integration lead so the builders never touch the frozen Main.server:
--   * init()   runs once from Main.server after JetService.init (after PhoneService.init, before SessionService.init);
--   * tick(dt) runs in Main.server's campus loop (every 0.05-0.25 s, inside a pcall).
-- The remote "TripAction" (Net.FUNCTIONS) is reserved for ItineraryService / DriverService. Both functions are no-ops
-- until the drivers package replaces this file; keep both signatures.
local DriverService = {}
function DriverService.init() end
function DriverService.tick(_dt: number) end
return DriverService
