--!strict
-- Company jet in the City Airport hangar + its 2 company pilots + the founder's private flights (round 2b, package
-- "guests_jet"). Stub pre-wired by the integration lead so the builders never touch the frozen Main.server:
--   * init()   runs once from Main.server after PhoneService.init and before SessionService.init;
--   * tick(dt) runs in Main.server's campus loop (every 0.05-0.25 s, inside a pcall).
-- Both are no-ops until the guests_jet package replaces this file; keep both signatures.
local JetService = {}
function JetService.init() end
function JetService.tick(_dt: number) end
return JetService
