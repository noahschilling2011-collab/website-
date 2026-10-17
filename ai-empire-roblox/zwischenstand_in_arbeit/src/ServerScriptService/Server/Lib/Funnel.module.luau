--!strict
-- Onboarding funnel analytics (ONBOARDING_SPEC A11, menu package). Server only, published games only:
-- AnalyticsService "Events can only be sent from the server and in published games", so Studio sends nothing.
-- Each step is sent once per session (the funnel only counts the first instance anyway). Failures are swallowed:
-- analytics must never break gameplay. A skipped guide is a custom event, not a funnel step (skipping a step would
-- mark the earlier ones complete).
--   1 Joined · 2 Company created · 3 Lab opened · 4 Training started · 5 Model trained · 6 Model launched ·
--   7 First income · 8 Guide finished
local AnalyticsService = game:GetService("AnalyticsService")
local RunService = game:GetService("RunService")

local Funnel = {}

Funnel.NAMES = { "Joined", "Company created", "Lab opened", "Training started", "Model trained", "Model launched", "First income", "Guide finished" }

local sent: { [Player]: { [number]: boolean } } = setmetatable({}, { __mode = "k" }) :: any
local log: { { kind: string, step: number?, name: string, value: number? } } = {} -- last calls (tests read Funnel.log)
Funnel.log = log
local studio: boolean? = nil

local function enabled(): boolean
	if studio == nil then
		local ok, value = pcall(function(): boolean
			return RunService:IsStudio()
		end)
		studio = not ok or value == true
	end
	return studio == false
end

local function remember(entry: { kind: string, step: number?, name: string, value: number? })
	table.insert(log, entry)
	if #log > 64 then
		table.remove(log, 1)
	end
end

-- Funnel step n (1..8) for this player, once per session.
function Funnel.step(player: Player, n: number, name: string?)
	if typeof(n) ~= "number" or n ~= math.floor(n) or n < 1 or n > #Funnel.NAMES then
		return
	end
	local memo = sent[player]
	if not memo then
		memo = {}
		sent[player] = memo
	end
	if memo[n] then
		return
	end
	memo[n] = true
	local label = name or Funnel.NAMES[n]
	remember({ kind = "step", step = n, name = label })
	if not enabled() then
		return
	end
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, n, label)
	end)
end

-- A custom event (e.g. "TutorialSkipped" with the step it was skipped at).
function Funnel.custom(player: Player, name: string, value: number?)
	remember({ kind = "custom", name = name, value = value })
	if not enabled() then
		return
	end
	pcall(function()
		AnalyticsService:LogCustomEvent(player, name, value or 1)
	end)
end

-- tests: forget the per-session memo and the Studio check
function Funnel._reset(isStudio: boolean?)
	table.clear(sent :: any)
	table.clear(log)
	studio = isStudio
end

return Funnel
