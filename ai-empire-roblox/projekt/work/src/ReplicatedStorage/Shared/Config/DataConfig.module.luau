--!strict
-- Trainingsdaten: Typen, kaufbare Pakete, kostenloses Scrapen.
-- Phase 1: General/Code/Math. Bilder, Synthetic, Scientific kommen mit Phase 2/9 als neue TYPES.

export type DataTypeDef = { id: string, label: string }
export type PackDef = {
	id: string,
	type: string,
	label: string,
	tokens: number,
	quality: number, -- 0..1
	price: number,
}

local DataConfig = {}

DataConfig.TYPES = {
	{ id = "general", label = "General Text" },
	{ id = "code", label = "Code" },
	{ id = "math", label = "Math" },
} :: { DataTypeDef }

DataConfig.PACKS = {
	{ id = "web_chunk", type = "general", label = "Web Crawl Chunk", tokens = 1e9, quality = 0.35, price = 1_200 },
	{ id = "web_xl", type = "general", label = "Web Crawl XL", tokens = 1e10, quality = 0.38, price = 10_000 },
	{ id = "books", type = "general", label = "Books & Wiki", tokens = 1e9, quality = 0.82, price = 6_000 },
	{ id = "repos", type = "code", label = "Public Repos", tokens = 1e9, quality = 0.5, price = 2_500 },
	{ id = "code_curated", type = "code", label = "Curated Code", tokens = 2e9, quality = 0.86, price = 16_000 },
	{ id = "math_basic", type = "math", label = "Math Problems", tokens = 5e8, quality = 0.6, price = 2_000 },
	{ id = "math_olympiad", type = "math", label = "Olympiad Set", tokens = 1e9, quality = 0.9, price = 10_000 },
} :: { PackDef }

-- Gratis, aber langsam und schlecht: der Notausgang, wenn das Geld weg ist
DataConfig.SCRAPE = { type = "general", tokens = 8e7, quality = 0.3, cooldown = 30 }

DataConfig.MAX_BUY = 10 -- max. Pakete pro Kauf-Anfrage

function DataConfig.getPack(id: string): PackDef?
	for _, pack in DataConfig.PACKS do
		if pack.id == id then
			return pack
		end
	end
	return nil
end

function DataConfig.isType(id: string): boolean
	for _, t in DataConfig.TYPES do
		if t.id == id then
			return true
		end
	end
	return false
end

return DataConfig
