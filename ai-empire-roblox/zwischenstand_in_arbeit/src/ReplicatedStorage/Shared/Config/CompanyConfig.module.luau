--!strict
-- Firmengründung: Logos, Farben, Spezialisierungen, Ränge.

export type Specialization = {
	id: string,
	name: string,
	desc: string,
	statBonus: { [string]: number }?,
	serveCostMult: number?, -- Multiplikator auf Inferenzkosten
	breakthroughMult: number?, -- Multiplikator auf die Breakthrough-Chance im Training
	enterpriseRevenueMult: number?, -- Multiplikator auf Umsatz aus Enterprise-Segmenten
}

export type ColorDef = { id: string, rgb: { number }, pass: string? }
export type RankDef = { name: string, minUsers: number }

local CompanyConfig = {}

CompanyConfig.LOGOS = { "◈", "▰", "◒", "⊞", "△", "⦿", "//", "N" } :: { string }

CompanyConfig.COLORS = {
	{ id = "cyan", rgb = { 120, 200, 174 } },
	{ id = "violet", rgb = { 176, 162, 208 } },
	{ id = "emerald", rgb = { 116, 173, 143 } },
	{ id = "amber", rgb = { 224, 189, 122 } },
	{ id = "rose", rgb = { 202, 148, 148 } },
	{ id = "blue", rgb = { 134, 171, 198 } },
	{ id = "orange", rgb = { 213, 157, 118 } },
	{ id = "lime", rgb = { 170, 186, 132 } },
} :: { ColorDef }

-- Identity Kit (SHOP_SPEC 3.5, shop package): 8 extra colours and 6 extra logo marks for owners of the "identityKit"
-- game pass (or the Style Collection bundle). A separate list, so default and random picks (Intro, Studio) never pick
-- a paid colour; Kit logos come after LOGOS, so a saved model look (emblem index into allLogos) keeps its meaning.
-- Ids are letters only (ModelMath.parseLook). Readability rule (binding): the company colour is the accent of the
-- whole UI and primary buttons draw Theme bg (15,21,23) text on it, so every Kit colour has a WCAG contrast >= 7.0
-- against bg and a CIE76 delta E >= 20 to every free and every other Kit colour (tests/shop2 T11).
CompanyConfig.KIT_COLORS = {
	{ id = "silver", rgb = { 196, 202, 206 }, pass = "identityKit" },
	{ id = "gold", rgb = { 236, 186, 64 }, pass = "identityKit" },
	{ id = "pink", rgb = { 240, 128, 150 }, pass = "identityKit" },
	{ id = "sky", rgb = { 116, 182, 246 }, pass = "identityKit" },
	{ id = "coral", rgb = { 248, 140, 104 }, pass = "identityKit" },
	{ id = "lilac", rgb = { 206, 158, 238 }, pass = "identityKit" },
	{ id = "mint", rgb = { 172, 248, 172 }, pass = "identityKit" },
	{ id = "aqua", rgb = { 100, 220, 240 }, pass = "identityKit" },
} :: { ColorDef }
CompanyConfig.KIT_LOGOS = { "✦", "⬢", "◆", "✚", "◐", "⌬" } :: { string }
CompanyConfig.KIT_PASS = "identityKit"

-- Intro name box (ONBOARDING_SPEC A7, owner decision O3, menu package): fictional names, one is prefilled at
-- random and the dice rolls another. The player may type over it; the server's CreateCompany filter still applies.
CompanyConfig.COMPANY_NAME_IDEAS = {
	"Nimbus Labs", "Bright Circuit", "Polar Minds", "Quiet Spark AI", "Little Robot Co", "Moonbeam AI", "Pixel Brain", "Kite Labs",
} :: { string }

-- Spezialisierung = kleiner Startbonus, keine Sackgasse.
CompanyConfig.SPECIALIZATIONS = {
	{
		id = "general",
		name = "General AI",
		desc = "Balanced. +2 on every core stat.",
		statBonus = { reasoning = 2, coding = 2, math = 2, creativity = 2, knowledge = 2, reliability = 2 },
	},
	{ id = "coding", name = "Coding AI", desc = "+6 Coding on every model.", statBonus = { coding = 6 } },
	{ id = "creative", name = "Creative AI", desc = "+6 Creativity on every model.", statBonus = { creativity = 6 } },
	{
		id = "efficient",
		name = "Efficient AI",
		desc = "-25% serving costs, +6 Efficiency.",
		statBonus = { efficiency = 6 },
		serveCostMult = 0.75,
	},
	{
		id = "research",
		name = "Research Lab",
		desc = "Training breakthroughs 60% more likely.",
		-- später: zusätzlich schnellere Forschung, sobald Phase 2 (Research Tree) existiert
		breakthroughMult = 1.6,
	},
	{
		id = "enterprise",
		name = "Enterprise AI",
		desc = "+25% revenue from businesses.",
		enterpriseRevenueMult = 1.25,
	},
} :: { Specialization }

-- Rang nach Spitzen-Nutzerzahl. später (Phase 6): Bewertung/Umsatz einbeziehen
CompanyConfig.RANKS = {
	{ name = "Garage Startup", minUsers = 0 },
	{ name = "Startup", minUsers = 5_000 },
	{ name = "Scale-Up", minUsers = 100_000 },
	{ name = "Unicorn", minUsers = 1_000_000 },
	{ name = "Tech Giant", minUsers = 10_000_000 },
	{ name = "AI Leader", minUsers = 50_000_000 },
} :: { RankDef }

function CompanyConfig.getSpec(id: string): Specialization?
	for _, spec in CompanyConfig.SPECIALIZATIONS do
		if spec.id == id then
			return spec
		end
	end
	return nil
end

-- free colours first, then the Identity Kit colours (a saved Kit colour keeps rendering after a refund, R9)
function CompanyConfig.getColor(id: string): ColorDef?
	for _, color in CompanyConfig.COLORS do
		if color.id == id then
			return color
		end
	end
	for _, color in CompanyConfig.KIT_COLORS do
		if color.id == id then
			return color
		end
	end
	return nil
end

function CompanyConfig.isLogo(glyph: string): boolean
	return table.find(CompanyConfig.LOGOS, glyph) ~= nil or table.find(CompanyConfig.KIT_LOGOS, glyph) ~= nil
end

function CompanyConfig.isKitColor(id: any): boolean
	if typeof(id) ~= "string" then
		return false
	end
	for _, color in CompanyConfig.KIT_COLORS do
		if color.id == id then
			return true
		end
	end
	return false
end

function CompanyConfig.isKitLogo(glyph: any): boolean
	return typeof(glyph) == "string" and table.find(CompanyConfig.KIT_LOGOS, glyph) ~= nil
end

-- LOGOS then KIT_LOGOS: a model look's emblem index points into this list (1..#LOGOS free, then Kit)
function CompanyConfig.allLogos(): { string }
	local out = table.clone(CompanyConfig.LOGOS)
	for _, glyph in CompanyConfig.KIT_LOGOS do
		table.insert(out, glyph)
	end
	return out
end

function CompanyConfig.rankFor(peakUsers: number): string
	local name = CompanyConfig.RANKS[1].name
	for _, rank in CompanyConfig.RANKS do
		if peakUsers >= rank.minUsers then
			name = rank.name
		end
	end
	return name
end

return CompanyConfig
