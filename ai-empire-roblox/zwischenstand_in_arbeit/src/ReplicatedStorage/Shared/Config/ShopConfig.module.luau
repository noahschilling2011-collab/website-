--!strict
-- Robux shop catalogue: what players can spend Robux on. Read by ShopService (server: receipts,
-- game passes, vouchers) and ShopApp (the "Shop" app in the computer).
--
-- HOW TO TURN THE SHOP ON (game owner)
--   1. Publish the place. Open https://create.roblox.com -> Creations -> this experience.
--   2. Monetization -> Developer Products -> create one product per PRODUCTS entry you want to sell
--      (name, description, icon and Robux price are set there).
--   3. Monetization -> Passes -> create one pass per PASSES entry and put it on sale.
--   4. Copy each numeric Product ID / Pass ID into `id = ...` below and publish again.
--   * id = 0 means: hidden in the shop and never prompted. With every id at 0 the Shop app only
--     says "Shop coming soon".
--   * The price shown in the game always comes from Roblox (GetProductInfoAsync), never from this
--     file. The Robux numbers in the comments are only suggestions.
--   * Nothing here is a paid random item (no loot boxes, no gambling). Do not add any without odds
--     and a PolicyService check.
--   * Some items depend on features of other systems and stay hidden until those exist:
--     headhunter needs a redeem handler (ShopService.setRedeemHandler, RecruitingService),
--     limo needs a CampusConfig.CARS entry with pass = "limo" (VehicleService),
--     investor needs the market to apply ShopService.revenueMultiplier (MarketService).
--   * Developer product ids must never be reused for something else: pending receipts for an id
--     are granted as whatever this file says at the moment they are processed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EmpireConfig = require(ReplicatedStorage.Shared.Config.EmpireConfig)
local CampusConfig = require(ReplicatedStorage.Shared.Config.CampusConfig)

export type ProductKind = "cash" | "voucher" | "tip"
export type Product = {
	key: string,
	id: number, -- Developer Product id from create.roblox.com (0 = hidden)
	kind: ProductKind,
	name: string,
	desc: string,
	share: number?, -- cash: share of the next office price (see ShopConfig.cashFor)
	voucher: string?, -- voucher: the VOUCHERS key one purchase adds
}
export type Pass = {
	key: string,
	id: number, -- Pass id from create.roblox.com (0 = hidden)
	name: string,
	desc: string,
}
export type Voucher = { key: string, name: string, desc: string }

local ShopConfig = {}

ShopConfig.PRODUCTS = {
	-- Company cash. Fixed share of the NEXT office price, so it can't be inflated by timing a
	-- purchase. Packs save minutes, not hours.
	{ key = "seed", id = 0, kind = "cash", share = 0.25, name = "Seed round", desc = "Company cash worth a quarter of your next office." }, -- share tuned by CORE_SPEC; suggested 49 Robux
	{ key = "seriesA", id = 0, kind = "cash", share = 0.75, name = "Series A", desc = "Company cash worth three quarters of your next office." }, -- share tuned by CORE_SPEC; suggested 129 Robux
	{ key = "seriesB", id = 0, kind = "cash", share = 2.0, name = "Series B", desc = "Company cash worth twice your next office." }, -- share tuned by CORE_SPEC; suggested 299 Robux
	-- Vouchers: the purchase only adds a voucher; the player redeems it later under the normal game
	-- rules, so a grant can never fail half-way.
	{ key = "headhunter", id = 0, kind = "voucher", voucher = "headhunter", name = "Headhunter", desc = "A headhunter finds you one outstanding job applicant. Redeem the voucher whenever you like." }, -- suggested 39 Robux
	{ key = "party", id = 0, kind = "voucher", voucher = "party", name = "Team party", desc = "Balloons, a banner and sparkles in front of your headquarters. Just for fun." }, -- suggested 25 Robux
	-- Tips: a thank-you, nothing else.
	{ key = "tip", id = 0, kind = "tip", name = "Supporter tip", desc = "Say thanks to the developer. You get a thank-you note, nothing else." }, -- suggested 25 Robux
	{ key = "bigTip", id = 0, kind = "tip", name = "Big supporter tip", desc = "A bigger thank-you to the developer. Nothing else changes." }, -- suggested 100 Robux
} :: { Product }

ShopConfig.PASSES = {
	{ key = "vip", id = 0, name = "VIP Founder", desc = "A gold VIP tag above your character and a VIP badge in your computer. Cosmetic." }, -- suggested 149 Robux
	{ key = "limo", id = 0, name = "Executive Limo", desc = "Adds the Executive Limo to your company fleet. Cosmetic." }, -- suggested 199 Robux
	{ key = "founderSuite", id = 0, name = "Founder Suite", desc = "A brass and leather lounge with a fire bowl on your private founder terrace. Cosmetic." }, -- suggested 199 Robux
	{ key = "investor", id = 0, name = "Investor Relations", desc = "It never changes anyone else's market share." }, -- suggested 349 Robux
} :: { Pass }

ShopConfig.VOUCHERS = {
	{ key = "headhunter", name = "Headhunter voucher", desc = "One outstanding job applicant." },
	{ key = "party", name = "Team party voucher", desc = "A party in front of your headquarters." },
} :: { Voucher }

ShopConfig.CASH = {
	minimum = 2_000, -- CORE_SPEC 11.7: smallest pack (also used when the next office is free)
	topFactor = 1.0, -- CORE_SPEC 11.7: at the last stage the base is the last office price x this
	step = 100, -- amounts are rounded to this
}
ShopConfig.INVESTOR_MULTIPLIER = 1.10 -- CORE_SPEC 11.7: own MARKET revenue x this, after shares (never B2B)
ShopConfig.PARTY_SECONDS = 180 -- how long a team party stays up
ShopConfig.RECEIPTS_KEPT = 100 -- processed purchase ids kept per player (newest)
ShopConfig.SESSION_WAIT_SECONDS = 45 -- a receipt that arrives while the player is still loading waits this long
ShopConfig.PASS_RETRY_SECONDS = 60 -- failed game-pass ownership checks are retried after this
ShopConfig.PASS_RETRIES = 5
ShopConfig.RECHECK_SECONDS = 20 -- "status" with recheck=true asks Roblox again at most this often
ShopConfig.VOUCHER_MAX = 999

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
