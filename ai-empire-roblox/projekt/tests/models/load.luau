--!nocheck
-- Loader for the models suites: the real work/src tree (manifest from harness/make_manifest.py) in the mock,
-- plus an optional "econ overlay": the CORE_SPEC patches of the OTHER core package (econ: MarketConfig,
-- MarketMath, EmpireMath, MarketService, CompanyOps, ...) from agents/design_final/economy/patches_final.luau,
-- applied in memory ONLY where work/src does not have them yet. That lets the models code be tested against
-- the binding design while the econ package is still landing; once econ is done the overlay applies nothing.
-- Patches that target a models file (AIModelService, ModelMath, ModelConfig, ...) are never applied: those
-- changes are the models package's own code under test. work/src is never written.
--   local L = require("./load")(genDir, { overlay = true|false })  -> { M = mock, applied = n, skipped = n, notes = {...} }
local MINE = {
	["ServerScriptService/Server/Services/AIModelService.module.luau"] = true,
	["ServerScriptService/Server/Services/PricingService.module.luau"] = true,
	["ReplicatedStorage/Shared/ModelMath.module.luau"] = true,
	["ReplicatedStorage/Shared/PricingMath.module.luau"] = true,
	["ReplicatedStorage/Shared/Config/ModelConfig.module.luau"] = true,
}

-- patches whose anchor stays in the file after econ applied them its own way: "done" when this text exists
local DONE = {
	["Config.OFFICES = {"] = "Garage Lab",
	["Config.CONTRACTS = {"] = "Config.CONTRACTS = {}",
	["function MarketMath.tick("] = "MarketMath.agePenalty",
	["function MarketConfig.isTarget"] = "PRODUCT_SLOTS",
	["function Empire.init()"] = "function Empire.labLevel",
}

local function present(src, text)
	return string.find(src, text, 1, true) ~= nil
end

-- first `n` characters of the replacement that are not whitespace-only lines: a cheap "already done" marker
local function marker(text, n)
	local t = string.gsub(text, "^%s+", "")
	return string.sub(t, 1, n)
end

return function(gen, opt)
	opt = opt or {}
	local M = require("../../harness/mock")
	local manifest = require(gen .. "/manifest")
	local sources = require(gen .. "/sources")
	local info = { M = M, applied = 0, skipped = 0, notes = {} }
	if opt.overlay ~= false then
		local list = require("../../agents/design_final/economy/patches_final")({})
		for _, p in list do
			if p[1] == "@new" then
				local file = p[2]
				if sources[file] == nil then
					local path = {}
					for seg in string.gmatch((string.gsub(file, "%.module%.luau$", "")), "[^/]+") do table.insert(path, seg) end
					table.insert(manifest, { path = path, class = "ModuleScript", file = file })
					sources[file] = p[3]
					info.applied += 1
					table.insert(info.notes, "new " .. file)
				else
					info.skipped += 1
				end
			elseif MINE[p[1]] then
				info.skipped += 1
			elseif p[5] == "range" then
				local src = sources[p[1]]
				local s1 = src and string.find(src, p[2], 1, true)
				local e1 = s1 and string.find(src, p[3], s1 + 1, true)
				if s1 and e1 and not present(src, marker(p[4], 80)) and not (DONE[p[2]] and present(src, DONE[p[2]])) then
					sources[p[1]] = string.sub(src, 1, s1 - 1) .. p[4] .. string.sub(src, e1)
					info.applied += 1
					table.insert(info.notes, "range " .. p[1])
				else
					info.skipped += 1
					table.insert(info.notes, "skip range " .. p[1])
				end
			else
				local src = sources[p[1]]
				local s, e = nil, nil
				if src then s, e = string.find(src, p[2], 1, true) end
				if s and not present(src, p[3]) and not (DONE[p[2]] and present(src, DONE[p[2]])) then
					sources[p[1]] = string.sub(src, 1, s - 1) .. p[3] .. string.sub(src, e + 1)
					info.applied += 1
					table.insert(info.notes, "patch " .. p[1])
				else
					info.skipped += 1
					table.insert(info.notes, "skip " .. p[1] .. (if s then " (done)" else " (anchor gone)") .. ": " .. string.sub(string.gsub(p[2], "%s+", " "), 1, 50))
				end
			end
		end
	end
	M.loadTree(manifest, sources)
	M.quiet = true
	return info
end
