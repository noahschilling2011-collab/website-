--!nocheck
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_gj")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
M.loadTree(manifest, sources)
M.quiet = true
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1; print("ok    " .. name) else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end
local t0 = os.clock()
require("./sep_check")(M, M.G, check, { step = tonumber(args[2]) or 6 })
print(string.format("probe_sepcheck: %d passed, %d failed (%.1f s)", pass, failc, os.clock() - t0))
