--!strict
-- Hält den letzten Snapshot vom Server und verteilt Änderungen an die UI.
-- Zwischen zwei Snapshots (0.5-1 s) rechnet der Client Geld und Trainingsfortschritt mit denselben
-- Formeln weiter, damit Zahlen flüssig laufen. Wahrheit bleibt immer der Server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local ModelMath = require(ReplicatedStorage.Shared.ModelMath)
local EmpireMath = require(ReplicatedStorage.Shared.EmpireMath)
local Workforce=require(ReplicatedStorage.Shared.WorkforceMath)
local StatePatch = require(ReplicatedStorage.Shared.StatePatch)
local ShopMath = require(ReplicatedStorage.Shared.ShopMath) -- shop package: Overclock in the training estimate

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

-- State updates (SessionService): the first message and every RequestState answer are FULL
-- snapshots; regular updates are DELTAS (StatePatch) against the snapshot numbered `base`. We rebuild a
-- complete snapshot from them, so StateController.snapshot always looks like a full snapshot.
-- A delta whose base we don't have (missed message, out of order) is kept and the full state is fetched
-- once; buffered deltas that continue the full snapshot's chain are applied afterwards.
local seq: number? = nil -- seq of StateController.snapshot (nil = unknown, e.g. a snapshot without seq)
local pending: { Types.StateDelta } = {}
local MAX_PENDING = 20
local fullPending = false

local function publish(snapshot: Types.Snapshot)
	StateController.snapshot = snapshot
	Workforce.set(snapshot.data.empire, snapshot.live.workforce)
	StateController.receivedAt = os.clock()
	for _, listener in changeListeners do
		safeCall("onChange", function()
			listener(snapshot)
		end)
	end
end

local function patched(current: Types.Snapshot, delta: Types.StateDelta): Types.Snapshot
	local root = StatePatch.apply({ data = current.data, live = current.live }, delta.patch :: any)
	return {
		seq = delta.seq,
		saveEnabled = delta.saveEnabled,
		serverTime = delta.serverTime,
		data = root.data,
		live = root.live,
	}
end

-- Applies buffered deltas that continue the current chain (drops the ones already covered)
local function drain(snapshot: Types.Snapshot): Types.Snapshot
	table.sort(pending, function(a, b)
		return a.seq < b.seq
	end)
	local kept: { Types.StateDelta } = {}
	for _, delta in pending do
		if seq ~= nil and delta.base == seq then
			snapshot = patched(snapshot, delta)
			seq = delta.seq
		elseif seq == nil or delta.seq > seq then
			table.insert(kept, delta)
		end
	end
	pending = kept
	return snapshot
end

local receiveFull: (Types.Snapshot) -> ()

local function requestFull()
	if fullPending then
		return
	end
	fullPending = true
	task.spawn(function()
		local ok, result = pcall(function(): any
			return Net.getFunction("RequestState"):InvokeServer({})
		end)
		fullPending = false
		if ok and typeof(result) == "table" and result.ok == true and typeof(result.state) == "table" then
			receiveFull(result.state :: Types.Snapshot)
		end
	end)
end

receiveFull = function(snapshot: Types.Snapshot)
	local number = snapshot.seq
	if typeof(number) == "number" then
		if seq ~= nil and StateController.snapshot ~= nil and number <= seq then
			return -- older than what we already show
		end
		seq = number
	else
		seq = nil -- snapshot without numbering: deltas cannot continue it
		table.clear(pending)
	end
	publish(drain(snapshot))
	if #pending > 0 then
		requestFull() -- still a gap after this full snapshot
	end
end

local function receiveDelta(delta: Types.StateDelta)
	local current = StateController.snapshot
	if current and seq ~= nil and delta.base == seq then
		local snapshot = patched(current, delta)
		seq = delta.seq
		publish(drain(snapshot))
		return
	end
	if seq ~= nil and delta.seq <= seq then
		return -- already covered (duplicate / older than the last full snapshot)
	end
	table.insert(pending, delta)
	if #pending > MAX_PENDING then
		table.remove(pending, 1)
	end
	requestFull()
end

local function receive(message: any)
	if typeof(message) ~= "table" then
		return
	end
	if typeof(message.patch) == "table" and typeof(message.seq) == "number" and typeof(message.base) == "number" then
		receiveDelta(message :: Types.StateDelta)
	elseif typeof(message.data) == "table" and typeof(message.live) == "table" then
		receiveFull(message :: Types.Snapshot)
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
	local rate = StateController.trainingRate(snapshot)
	return math.min(training.workTotal, training.workDone + rate * StateController.elapsed()), training.workTotal
end

-- the running training's rate with Overclock (SHOP_SPEC 5.2.5: x ShopMath.trainingFactor, the 12 s floor kept)
function StateController.trainingRate(snapshot: Types.Snapshot): number
	local training = snapshot.data.training
	if not training then
		return 0
	end
	local rate = EmpireMath.trainingRate(snapshot.data.gpus, training.workTotal, snapshot.data.empire)
	local seconds = (tonumber(snapshot.data.empire.seconds) or 0) + StateController.elapsed()
	return ShopMath.boostRate(snapshot.data, training.workTotal, rate, seconds)
end

-- Restsekunden des laufenden Trainings
function StateController.trainingEta(): number
	local snapshot = StateController.snapshot
	local training = if snapshot then snapshot.data.training else nil
	if not snapshot or not training then
		return 0
	end
	local done, total = StateController.trainingWork()
	local rate = StateController.trainingRate(snapshot)
	return if rate > 0 then (total - done) / rate else 0
end

function StateController.init()
	Net.getEvent("State").OnClientEvent:Connect(receive)
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
				receiveFull(result.state :: Types.Snapshot) -- ignored if a newer State event came first
				return
			end
			task.wait(math.min(2, 0.5 * attempt))
		end
	end)
end

return StateController
