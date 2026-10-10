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

export type ColorDef = { id: string, rgb: { number } }
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

function CompanyConfig.getColor(id: string): ColorDef?
	for _, color in CompanyConfig.COLORS do
		if color.id == id then
			return color
		end
	end
	return nil
end

function CompanyConfig.isLogo(glyph: string): boolean
	return table.find(CompanyConfig.LOGOS, glyph) ~= nil
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
