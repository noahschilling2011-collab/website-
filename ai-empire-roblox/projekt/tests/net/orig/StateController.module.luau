--!strict
-- Hält den letzten Snapshot vom Server und verteilt Änderungen an die UI.
-- Zwischen zwei Snapshots (1 s) rechnet der Client Geld und Trainingsfortschritt mit denselben
-- Formeln weiter, damit Zahlen flüssig laufen. Wahrheit bleibt immer der Server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local ModelMath = require(ReplicatedStorage.Shared.ModelMath)
local EmpireMath = require(ReplicatedStorage.Shared.EmpireMath)
local Workforce=require(ReplicatedStorage.Shared.WorkforceMath)

local StateController = {}

StateController.snapshot = nil :: Types.Snapshot?
StateController.receivedAt = 0

-- Auswahl im Lab, die auch DATA/COMPUTE für ihre Vorschau nutzen
StateController.ui = {
	sizeId = "s100m",
	focusId = "balanced",
	recipeId = "steady",
}

local changeListeners: { (Types.Snapshot) -> () } = {}
local notifyListeners: { (string, { [string]: any }) -> () } = {}
local uiListeners: { () -> () } = {}

local MAX_EXTRAPOLATE = 3 -- Sekunden; danach lieber stehen bleiben als raten

local function safeCall(label: string, fn: () -> ())
	local ok, err = pcall(fn :: () -> any)
	if not ok then
		warn(`[State] {label}: {err}`)
	end
end

local apply: (Types.Snapshot) -> ()

-- Regelmäßige Snapshots lassen unveränderte staffProfiles weg (SessionService.snapshot);
-- wir behalten die letzte Kopie. Fehlt sie (erstes Event verpasst), einmal den vollen Stand holen.
local fullPending = false
local function fetchProfiles()
	if fullPending then
		return
	end
	fullPending = true
	task.spawn(function()
		local ok, result = pcall(function(): any
			return Net.getFunction("RequestState"):InvokeServer({})
		end)
		fullPending = false
		if not (ok and typeof(result) == "table" and result.ok == true and typeof(result.state) == "table") then
			return
		end
		local full = result.state.data
		local current = StateController.snapshot
		local empire = if current then current.data.empire else nil
		if current and typeof(empire) == "table" and empire.staffProfiles == nil and typeof(full) == "table" and typeof(full.empire) == "table" then
			empire.staffProfiles = full.empire.staffProfiles
			apply(current)
		end
	end)
end

local function mergeOmitted(snapshot: Types.Snapshot)
	local empire = snapshot.data.empire
	if typeof(empire) ~= "table" or not empire.staffProfilesOmitted then
		return
	end
	empire.staffProfilesOmitted = nil
	local previous = StateController.snapshot
	local before = if previous then previous.data.empire else nil
	if typeof(before) == "table" and typeof(before.staffProfiles) == "table" then
		empire.staffProfiles = before.staffProfiles
	else
		fetchProfiles()
	end
end

apply = function(snapshot: Types.Snapshot)
	mergeOmitted(snapshot)
	StateController.snapshot = snapshot
 Workforce.set(snapshot.data.empire,snapshot.live.workforce)
	StateController.receivedAt = os.clock()
	for _, listener in changeListeners do
		safeCall("onChange", function()
			listener(snapshot)
		end)
	end
end

function StateController.onChange(listener: (Types.Snapshot) -> ())
	table.insert(changeListeners, listener)
	local current = StateController.snapshot
	if current then
		safeCall("onChange", function()
			listener(current)
		end)
	end
end

function StateController.onNotify(listener: (string, { [string]: any }) -> ())
	table.insert(notifyListeners, listener)
end

function StateController.onUiChange(listener: () -> ())
	table.insert(uiListeners, listener)
end

function StateController.setSelection(sizeId: string, focusId: string)
	local ui = StateController.ui
	if ui.sizeId == sizeId and ui.focusId == focusId then
		return
	end
	ui.sizeId = sizeId
	ui.focusId = focusId
	for _, listener in uiListeners do
		safeCall("onUiChange", listener)
	end
end

function StateController.setRecipe(id: string)
	StateController.ui.recipeId=id
	for _,fn in uiListeners do safeCall("UI recipe",fn) end
end

function StateController.elapsed(): number
	return math.min(MAX_EXTRAPOLATE, os.clock() - StateController.receivedAt)
end

-- Geld inkl. laufender Einnahmen seit dem letzten Snapshot
function StateController.money(): number
	local snapshot = StateController.snapshot
	if not snapshot then
		return 0
	end
	return snapshot.data.money + (snapshot.live.revenue - snapshot.live.cost) * StateController.elapsed()
end

-- (erledigte Arbeit, Gesamtarbeit) mit Vorhersage; pausiert bei offener Entscheidung
function StateController.trainingWork(): (number, number)
	local snapshot = StateController.snapshot
	local training = if snapshot then snapshot.data.training else nil
	if not snapshot or not training then
		return 0, 1
	end
	local event = training.event
	if event and event.pending then
		return training.workDone, training.workTotal
	end
	local rate = EmpireMath.trainingRate(snapshot.data.gpus, training.workTotal, snapshot.data.empire)
	return math.min(training.workTotal, training.workDone + rate * StateController.elapsed()), training.workTotal
end

-- Restsekunden des laufenden Trainings
function StateController.trainingEta(): number
	local snapshot = StateController.snapshot
	local training = if snapshot then snapshot.data.training else nil
	if not snapshot or not training then
		return 0
	end
	local done, total = StateController.trainingWork()
	local rate = EmpireMath.trainingRate(snapshot.data.gpus, training.workTotal, snapshot.data.empire)
	return if rate > 0 then (total - done) / rate else 0
end

function StateController.init()
	Net.getEvent("State").OnClientEvent:Connect(function(snapshot: any)
		if typeof(snapshot) == "table" then
			apply(snapshot :: Types.Snapshot)
		end
	end)
	Net.getEvent("Notify").OnClientEvent:Connect(function(kind: any, payload: any)
		if typeof(kind) ~= "string" then
			return
		end
		local data: { [string]: any } = if typeof(payload) == "table" then payload else {}
		for _, listener in notifyListeners do
			safeCall("onNotify " .. kind, function()
				listener(kind, data)
			end)
		end
	end)

	-- Erster Stand aktiv anfragen (falls das erste State-Event vor unserem Listener kam)
	task.spawn(function()
		local requestState = Net.getFunction("RequestState")
		for attempt = 1, 60 do
			if StateController.snapshot then
				return
			end
			local ok, result = pcall(function(): any
				return requestState:InvokeServer({})
			end)
			if ok and typeof(result) == "table" and result.ok == true and typeof(result.state) == "table" then
				if not StateController.snapshot then
					apply(result.state :: Types.Snapshot)
				end
				return
			end
			task.wait(math.min(2, 0.5 * attempt))
		end
	end)
end

return StateController
