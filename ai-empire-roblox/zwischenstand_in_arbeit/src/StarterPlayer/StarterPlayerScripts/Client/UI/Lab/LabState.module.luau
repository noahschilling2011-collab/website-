--!strict
-- Client memory of the Model Studio (LAB_SPEC 5.1/7): the planned product line, the name and look being
-- designed, the line planned for each started model, and which trained models still wait for their reveal.
-- Session memory by design (lost on rejoin): Launch Day then falls back to the model's saved plan / best fit,
-- and trained models count as revealed. Size, focus and plan stay in StateController.ui (DataApp and
-- JourneyMath read them).

local LabState = {}

LabState.lineId = "general" -- planned product line (release target)
LabState.name = "" -- "" = pick a NAME_IDEAS name on the first open
LabState.colorId = nil :: string? -- chosen card colour (CompanyConfig.COLORS id); nil = the skill-focus colour
LabState.emblem = nil :: number? -- chosen emblem (index into CompanyConfig.LOGOS); nil = the company logo
LabState.step = 1
LabState.plannedLine = {} :: { [string]: string } -- modelId -> target planned in the Studio
LabState.reveals = {} :: { [string]: { [string]: any } } -- modelId -> TRAINING_COMPLETE payload, until revealed

LabState.NAME_IDEAS = { "Nova", "Atlas", "Echo", "Pulse", "Quill", "Sage", "Orbit", "Flux", "Iris", "Vega", "Lumen", "Spark" }

local nameIndex = 0

-- Next entry of NAME_IDEAS (RANDOM NAME button and the first open)
function LabState.nextName(): string
	if nameIndex == 0 then
		nameIndex = math.random(1, #LabState.NAME_IDEAS)
	else
		nameIndex = nameIndex % #LabState.NAME_IDEAS + 1
	end
	return LabState.NAME_IDEAS[nameIndex]
end

-- A model that finished training in this session and was not revealed yet.
function LabState.wasRevealed(modelId: string): boolean
	return LabState.reveals[modelId] == nil
end

function LabState.markRevealed(modelId: string)
	LabState.reveals[modelId] = nil
end

-- Reads a TRAINING_COMPLETE payload defensively (LAB_SPEC 6.1: every field type-checked, missing = hidden).
function LabState.storeReveal(payload: { [string]: any })
	local id = payload.modelId
	if typeof(id) ~= "string" then
		return
	end
	local clean: { [string]: any } = { modelId = id }
	for _, key in { "overall", "previousBest", "expected", "before" } do
		if typeof(payload[key]) == "number" and payload[key] == payload[key] then
			clean[key] = payload[key]
		end
	end
	if typeof(payload.refinement) == "boolean" then
		clean.refinement = payload.refinement
	end
	for _, key in { "eventId", "outcome" } do
		if typeof(payload[key]) == "string" then
			clean[key] = payload[key]
		end
	end
	LabState.reveals[id] = clean
end

-- "<colorId>:<emblemIndex>" for StartTraining, or nil when the player kept the defaults.
function LabState.look(defaultEmblem: number): string?
	if LabState.colorId == nil and LabState.emblem == nil then
		return nil
	end
	local colorId = LabState.colorId
	if colorId == nil then
		return nil -- an emblem alone needs a colour; the Studio always sets both together
	end
	return `{colorId}:{LabState.emblem or defaultEmblem}`
end

return LabState
