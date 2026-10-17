--!strict
-- Robux shop catalogue: what players can spend Robux on. Read by ShopService (server: receipts,
-- game passes, vouchers), ShopMath (shared rules: caps, offers, savings) and the Shop pages of the Menu
-- (ShopApp). SHOP_SPEC (shop package): 23 items in 5 tabs (home, speedups, boosts, style, extras).
--
-- HOW TO TURN THE SHOP ON (game owner; the full German guide is SHOP_SPEC 11)
--   1. Publish the place. Open https://create.roblox.com -> Creations -> this experience.
--   2. Monetization -> Developer Products -> create one product per PRODUCTS entry you want to sell. Copy the
--      name and the description (`desc`) below exactly; the Robux price is yours to choose (the numbers in the
--      comments are only suggestions). Eureka, Last Epoch, Keynote Boost, Overclock and the three cash packs (Seed
--      round, Series A, Series B): set them to "Unlisted" (they only make sense from the game's own buttons).
--   3. Monetization -> Passes -> create one pass per PASSES entry ONLY when its `ready` is not false: passes
--      always show in the Roblox shop, so a pass is created only once its feature works in the game.
--   4. Copy each numeric Product ID / Pass ID into `id = ...` below and publish again.
--   * id = 0 means: hidden in the shop and never prompted. With every id at 0 the Shop says "Shop coming soon".
--   * The price shown in the game always comes from Roblox (GetProductInfoAsync), never from this file.
--   * Nothing here is a paid random item (no loot boxes, no gambling, no luck). Do not add any.
--   * Cash packs (seed, seriesA, seriesB) are 10 % / 20 % / 30 % of the next office price, each size at most
--     once per office (owner decision S1, 2026-10-12). The server enforces it: a second receipt of the same size in
--     one office is never refused, but its cash is saved as a credit and paid at the next office (ShopService
--     payPackCredits), so no office ever gets two packs of one size, wherever they were bought. Headhunter always
--     finds the same kind of applicant (skill 4, smallest team, fixed salary ask: SHOP_SPEC 3.12), so it is not a
--     paid random item.
--   * Some items depend on features of other systems and stay hidden until those exist:
--     a voucher needs its redeem handler (ShopService.setRedeemHandler), limo needs a CampusConfig.CARS entry
--     with pass = "limo", investor needs the market to apply ShopService.revenueMultiplier.
--   * Developer product ids must never be reused for something else: pending receipts for an id
--     are granted as whatever this file says at the moment they are processed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EmpireConfig = require(ReplicatedStorage.Shared.Config.EmpireConfig)
local CampusConfig = require(ReplicatedStorage.Shared.Config.CampusConfig)

export type ProductKind = "cash" | "voucher" | "tip"
export type Tab = "speedups" | "boosts" | "style" | "extras"
export type Product = {
	key: string,
	id: number, -- Developer Product id from create.roblox.com (0 = hidden)
	kind: ProductKind,
	name: string,
	desc: string, -- the in-game text = the Creator Hub description (cash: a pattern, see ShopMath.cashText)
	tag: string, -- the chip next to the name
	tab: Tab, -- the Shop sub-tab
	section: string?, -- the section inside the tab (Style / Extras)
	share: number?, -- cash: share of the next office price (see ShopConfig.cashFor)
	voucher: string?, -- voucher: the VOUCHERS key one purchase adds
	ready: boolean?, -- false = its feature is not in the game yet: never sold (phase 2/3)
}
export type Pass = {
	key: string,
	id: number, -- Pass id from create.roblox.com (0 = hidden)
	name: string,
	desc: string,
	tag: string,
	tab: Tab,
	section: string?,
	ready: boolean?, -- false = never sold yet (its feature ships in a later phase)
	includes: { string }?, -- a bundle: the passes it contains (Shop.owns honours them)
}
export type Voucher = { key: string, name: string, desc: string }

local ShopConfig = {}

ShopConfig.PRODUCTS = {
	-- Company cash (owner decision S1): a share of the NEXT office price, so it can't be inflated by timing a
	-- purchase. Packs are a share of the next office price, one of each per office (SHOP_SPEC S1); Unlisted.
	{ key = "seed", id = 0, kind = "cash", share = 0.10, tag = "Company cash", tab = "extras", section = "cash",
		name = "Seed round", desc = "+{amount} company cash now: {share} the {office} price. One per office." }, -- suggested 25 Robux, Unlisted
	{ key = "seriesA", id = 0, kind = "cash", share = 0.20, tag = "Company cash", tab = "extras", section = "cash",
		name = "Series A", desc = "+{amount} company cash now: {share} the {office} price. One per office." }, -- suggested 45 Robux, Unlisted
	{ key = "seriesB", id = 0, kind = "cash", share = 0.30, tag = "Company cash", tab = "extras", section = "cash",
		name = "Series B", desc = "+{amount} company cash now: {share} the {office} price. One per office." }, -- suggested 75 Robux, Unlisted
	-- Vouchers: the purchase only adds a voucher; the player redeems it later under the normal game rules, so a
	-- grant can never fail half-way and a refusal keeps the voucher.
	{ key = "eureka", id = 0, kind = "voucher", voucher = "eureka", tag = "Speed-up", tab = "speedups", name = "Eureka",
		desc = "Finishes one research project or one Lab level right now. Covers its research points and its wait. You still pay its $ price. Every Eureka button in the game shows the time it saves." }, -- suggested 15 Robux, Unlisted
	{ key = "lastEpoch", id = 0, kind = "voucher", voucher = "lastEpoch", tag = "Speed-up", tab = "speedups", name = "Last Epoch",
		desc = "Finishes your running AI training now, with the same chances as waiting: a training event, if one comes, is decided first. Saves the time left; the button shows how much." }, -- suggested 9 Robux, Unlisted
	{ key = "keynote", id = 0, kind = "voucher", voucher = "keynote", tag = "Boost", tab = "boosts", name = "Keynote Boost",
		desc = "+20 % on your app and API income for 15 minutes of play. Business clients are not boosted. Other players are never affected. Up to 4 a day." }, -- suggested 35 Robux, Unlisted
	{ key = "overclock", id = 0, kind = "voucher", voucher = "overclock", tag = "Boost", tab = "boosts", name = "Overclock",
		desc = "Your AI training runs 1.5× as fast for 15 minutes of play (never under 12 seconds per run). Up to 4 a day." }, -- suggested 19 Robux, Unlisted
	{ key = "fireworks", id = 0, kind = "voucher", voucher = "fireworks", tag = "Cosmetic", tab = "style", section = "shows", name = "Rooftop Fireworks",
		desc = "45 seconds of fireworks in your company colour above your HQ. Everyone nearby sees them. Just for fun." }, -- suggested 19 Robux, Listed
	{ key = "headhunter", id = 0, kind = "voucher", voucher = "headhunter", tag = "Helper", tab = "extras", section = "helper", name = "Headhunter",
		desc = "One applicant with skill 4 of 5 applies, for your smallest team. Redeem when a desk is free; the voucher is kept until then." }, -- suggested 39 Robux (deterministic since SHOP_SPEC 3.12, RecruitingService.headhunt)
	{ key = "party", id = 0, kind = "voucher", voucher = "party", tag = "Cosmetic", tab = "style", section = "shows", name = "Team party",
		desc = "Balloons, a banner and sparkles in front of your HQ for 3 minutes. Just for fun." }, -- suggested 25 Robux
	-- Tips: a thank-you, nothing else.
	{ key = "tip", id = 0, kind = "tip", tag = "Tip", tab = "extras", section = "support", name = "Supporter tip",
		desc = "Say thanks to the developer. You get a thank-you note, nothing else." }, -- suggested 25 Robux
	{ key = "bigTip", id = 0, kind = "tip", tag = "Tip", tab = "extras", section = "support", name = "Big supporter tip",
		desc = "A bigger thank-you to the developer. Nothing else changes." }, -- suggested 100 Robux
} :: { Product }

ShopConfig.PASSES = {
	{ key = "vip", id = 0, tag = "Cosmetic", tab = "style", section = "founder", name = "VIP Founder",
		desc = "A gold VIP tag above your character and a VIP badge in your Menu." }, -- suggested 149 Robux
	{ key = "limo", id = 0, tag = "Car + perk", tab = "extras", section = "perks", name = "Executive Limo",
		desc = "A limousine for your fleet (top speed 78 when you drive; the free car does 64). VIP helicopter transfers are free (normally $2,500)." }, -- suggested 199 Robux
	{ key = "founderSuite", id = 0, tag = "Cosmetic", tab = "style", section = "founder", name = "Founder Suite",
		desc = "A brass and leather lounge with a fire bowl on your founder terrace. Appears from Founder Headquarters on." }, -- suggested 199 Robux
	{ key = "investor", id = 0, tag = "Gameplay bonus", tab = "extras", section = "perks", name = "Investor Relations",
		desc = "+10 % on your app and API income. Business clients are not boosted. Other players are never affected. Adds to a Keynote Boost (+30 % together)." }, -- suggested 349 Robux
	{ key = "identityKit", id = 0, tag = "Cosmetic", tab = "style", section = "look", name = "Identity Kit",
		desc = "8 extra company colours and 6 extra logo marks for your company and AI models. GPU racks change at once; HQ trim, cars and jet at their next build." }, -- suggested 59 Robux
	{ key = "serverGlow", id = 0, tag = "Cosmetic", tab = "style", section = "look", name = "Server Glow",
		desc = "Your GPU racks run a slow light wave in your company colour instead of a steady glow. Visitors see it too." }, -- suggested 45 Robux
	{ key = "stageLights", id = 0, tag = "Cosmetic", tab = "style", section = "shows", name = "Stage Lights",
		desc = "Light sweeps and confetti in your company colour when your new AI is revealed. Only you see it." }, -- suggested 39 Robux
	{ key = "aiGallery", id = 0, tag = "Cosmetic", tab = "style", section = "look", name = "AI Gallery", ready = false, -- phase 3 (lobby anchor, buildings)
		desc = "A lobby wall with framed cards of your 3 best AI models and a neon sign with your company name. Updates by itself." }, -- suggested 65 Robux
	{ key = "teamHoodies", id = 0, tag = "Cosmetic", tab = "style", section = "look", name = "Team Hoodies", ready = false, -- phase 3 (staff rigs)
		desc = "Your hired team wears hoodies in your company colour with your logo. Operations staff keep their uniforms." }, -- suggested 75 Robux
	{ key = "roboBuddy", id = 0, tag = "Cosmetic", tab = "style", section = "founder", name = "Robo Buddy", ready = false, -- phase 3 (robot model)
		desc = "A small hovering robot in your company colour follows you around the world. Just for fun." }, -- suggested 95 Robux
	{ key = "styleCollection", id = 0, tag = "Bundle", tab = "style", section = "bundle", name = "Style Collection",
		includes = { "identityKit", "serverGlow", "stageLights" },
		desc = "Identity Kit, Server Glow and Stage Lights in one pass. Looks only. Already own one of them? Then buy the others one by one." }, -- suggested 109 Robux
} :: { Pass }

ShopConfig.VOUCHERS = {
	{ key = "headhunter", name = "Headhunter voucher", desc = "One skill-4 applicant for your smallest team." },
	{ key = "party", name = "Team party voucher", desc = "A party in front of your headquarters." },
	{ key = "eureka", name = "Eureka", desc = "Finishes one research project or one Lab level." },
	{ key = "lastEpoch", name = "Last Epoch", desc = "Finishes your running AI training." },
	{ key = "keynote", name = "Keynote Boost", desc = "+20 % app and API income for 15 minutes of play." },
	{ key = "overclock", name = "Overclock", desc = "Training 1.5× as fast for 15 minutes of play." },
	{ key = "fireworks", name = "Rooftop Fireworks", desc = "45 seconds of fireworks above your HQ." },
} :: { Voucher }

ShopConfig.CASH = {
	minimum = 2_000, -- CORE_SPEC 11.7: smallest pack (also used when the next office is free)
	topFactor = 1.0, -- CORE_SPEC 11.7: at the last stage the base is the last office price x this
	step = 100, -- amounts are rounded to this
	oncePerOffice = true, -- S1: each size at most once per office (data.shop.packs[key] = office of the purchase)
}
ShopConfig.INVESTOR_MULTIPLIER = 1.10 -- CORE_SPEC 11.7: own MARKET revenue x this, after shares (never B2B)
ShopConfig.PARTY_SECONDS = 180 -- how long a team party stays up
ShopConfig.FIREWORKS_SECONDS = 45 -- how long the rooftop fireworks run
ShopConfig.RECEIPTS_KEPT = 100 -- processed purchase ids kept per player (newest)
ShopConfig.SESSION_WAIT_SECONDS = 45 -- a receipt that arrives while the player is still loading waits this long
ShopConfig.PASS_RETRY_SECONDS = 60 -- failed game-pass ownership checks are retried after this
ShopConfig.PASS_RETRIES = 5
ShopConfig.RECHECK_SECONDS = 20 -- "status" with recheck=true asks Roblox again at most this often
ShopConfig.VOUCHER_MAX = 999

-- Timed boosts (SHOP_SPEC 3.3): vouchers started by the player. Time = company play time (empire.seconds: +dt per
-- tick while online, frozen offline), so a boost never runs out while the player is away.
export type BoostDef = { seconds: number, revenue: number?, training: number? }
ShopConfig.BOOSTS = {
	keynote = { seconds = 900, revenue = 0.20 }, -- +20 % own market (app + API) revenue, after shares, never B2B
	overclock = { seconds = 900, training = 1.5 }, -- training x1.5 (the 12 s minimum per run stays)
} :: { [string]: BoostDef }
ShopConfig.BOOST_MAX_LEFT = 3600 -- at most 60 min of one boost left at once (a start is refused above 2,700 s left)
ShopConfig.DAILY = { keynote = 4, overclock = 4, lastEpoch = 10 } :: { [string]: number } -- redeems per UTC day
ShopConfig.REBRAND_COOLDOWN = 60 -- seconds between two free colour / logo changes (runtime only)
ShopConfig.EUREKA_MIN_SAVING = 30 -- no Robux (buy) Eureka button for a smaller saving (an owned one always shows)
ShopConfig.LAST_EPOCH_MIN_LEFT = 20 -- no Robux (buy) Last Epoch button with less training time left
ShopConfig.FEATURED = { "styleCollection", "identityKit", "vip", "founderSuite", "roboBuddy", "aiGallery" } -- cosmetics only
ShopConfig.TABS = { "speedups", "boosts", "style", "extras" }

local function finiteNumber(value: any): number?
	local n = tonumber(value)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return n
end

-- Base for cash packs: the price of the office after `office` (the stage index). At the last stage
-- there is no next office, so the last price times CASH.topFactor is used.
function ShopConfig.cashBase(office: number): number
	local offices = EmpireConfig.OFFICES
	local index = math.clamp(math.floor(finiteNumber(office) or 1), 1, #offices)
	local nextOffice = offices[index + 1]
	if nextOffice then
		return finiteNumber(nextOffice.price) or 0
	end
	return (finiteNumber(offices[#offices].price) or 0) * ShopConfig.CASH.topFactor
end

-- Company cash one purchase of a cash product grants at stage `office`.
function ShopConfig.cashFor(def: Product, office: number): number
	local step = ShopConfig.CASH.step
	local amount = math.floor((def.share or 0) * ShopConfig.cashBase(office) / step + 0.5) * step
	return math.max(ShopConfig.CASH.minimum, amount)
end

function ShopConfig.product(key: string): Product?
	for _, def in ShopConfig.PRODUCTS do
		if def.key == key then
			return def
		end
	end
	return nil
end

-- Only listed products (id > 0) are found by id.
function ShopConfig.productById(id: number): Product?
	if typeof(id) ~= "number" or id <= 0 then
		return nil
	end
	for _, def in ShopConfig.PRODUCTS do
		if def.id == id then
			return def
		end
	end
	return nil
end

function ShopConfig.pass(key: string): Pass?
	for _, def in ShopConfig.PASSES do
		if def.key == key then
			return def
		end
	end
	return nil
end

function ShopConfig.passById(id: number): Pass?
	if typeof(id) ~= "number" or id <= 0 then
		return nil
	end
	for _, def in ShopConfig.PASSES do
		if def.id == id then
			return def
		end
	end
	return nil
end

function ShopConfig.voucher(key: string): Voucher?
	for _, def in ShopConfig.VOUCHERS do
		if def.key == key then
			return def
		end
	end
	return nil
end

-- the product that sells voucher `key` (nil for a voucher no longer sold)
function ShopConfig.productForVoucher(key: string): Product?
	for _, def in ShopConfig.PRODUCTS do
		if def.kind == "voucher" and def.voucher == key then
			return def
		end
	end
	return nil
end

-- the bundles that contain pass `key`
function ShopConfig.bundlesOf(key: string): { Pass }
	local out: { Pass } = {}
	for _, def in ShopConfig.PASSES do
		local list = def.includes
		if list and table.find(list, key) then
			table.insert(out, def)
		end
	end
	return out
end

-- true when at least one product or pass has an id (otherwise the app shows "Shop coming soon")
function ShopConfig.anyListed(): boolean
	for _, def in ShopConfig.PRODUCTS do
		if def.id > 0 then
			return true
		end
	end
	for _, def in ShopConfig.PASSES do
		if def.id > 0 then
			return true
		end
	end
	return false
end

-- The limo pass needs a car that VehicleService gates with ShopService.owns(..., "limo").
function ShopConfig.limoCarExists(): boolean
	for _, car in CampusConfig.CARS do
		if (car :: any).pass == "limo" then
			return true
		end
	end
	return false
end

return ShopConfig
