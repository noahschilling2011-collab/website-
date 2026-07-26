--[[
	AlarmState
	Wie laut es in einer Garage gerade zugeht.

	Jedes abmontierte Teil hebt den Zaehler der betroffenen Box. Aus dem Zaehler
	folgt ueber Config.ALARM_STEPS die Stufe, und die Stufe entscheidet, wieviel
	der Bestohlene ueber den Dieb erfaehrt:

		1  Richtung        "kommt von Sueden"
		2  Position        genaue Koordinate, der Marker steht auf dem Dieb
		3  serverweit      alle sehen es

	Damit ist Klauen eine Abwaegung: das vierte Teil aus derselben Box ist das
	wertvollste und das gefaehrlichste.

	Der Zustand steht BEWUSST nicht im Profil. Er gehoert zum laufenden Fenster,
	nicht zum Spielstand - beim Schliessen wird er ersatzlos weggeworfen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local AlarmState = {}
AlarmState.__index = AlarmState

function AlarmState.new(services)
	local self = setmetatable({}, AlarmState)
	self.Services = services
	self.plots = {} -- [plotIndex] = { count, level, lastAt, thief }
	return self
end

local function levelFor(count: number): number
	local level = 0
	for step, threshold in Config.ALARM_STEPS do
		if count >= threshold then
			level = step
		end
	end
	return level
end

-- Himmelsrichtung vom Bestohlenen zum Dieb. Auf Stufe 1 ist das alles, was er
-- bekommt - genug, um loszulaufen, zu wenig, um sicher zu treffen.
local function directionText(from: Vector3, to: Vector3): string
	local delta = to - from
	if delta.Magnitude < 1 then
		return "direkt bei dir"
	end
	local vertical = if delta.Z < 0 then "Norden" else "Sueden"
	local horizontal = if delta.X < 0 then "Westen" else "Osten"
	-- Nur die dominante Achse nennen, sonst klingt jede Meldung gleich.
	if math.abs(delta.X) > math.abs(delta.Z) * 1.6 then
		return horizontal
	end
	if math.abs(delta.Z) > math.abs(delta.X) * 1.6 then
		return vertical
	end
	return ("%s%s"):format(vertical, horizontal:lower())
end

function AlarmState:Level(plotIndex: number?): number
	if not plotIndex then
		return 0
	end
	local entry = self.plots[plotIndex]
	return entry and entry.level or 0
end

-- Wird gerufen, wenn ein Teil wirklich abmontiert wurde - nicht schon beim
-- Ansetzen. Ein abgebrochener Versuch loest keinen Alarm aus.
function AlarmState:Raise(plotIndex: number?, thief: Player)
	if not plotIndex then
		return
	end
	local entry = self.plots[plotIndex]
	if not entry then
		entry = { count = 0, level = 0, lastAt = 0 }
		self.plots[plotIndex] = entry
	end
	entry.count += 1
	entry.lastAt = os.clock()
	entry.thief = thief
	local level = levelFor(entry.count)
	if level ~= entry.level then
		entry.level = level
		self:_announce(plotIndex, entry)
	end
	self:_push(plotIndex, entry)
end

-- Eine Stufe faellt nach ALARM_DECAY Sekunden ohne neuen Diebstahl. Der
-- Zaehler faellt auf die Schwelle der neuen Stufe zurueck, nicht auf 0 - sonst
-- wartet man einfach ab und faengt bei null wieder an.
function AlarmState:Tick()
	local now = os.clock()
	for plotIndex, entry in self.plots do
		if entry.level > 0 and now - entry.lastAt >= Config.ALARM_DECAY then
			entry.level -= 1
			entry.count = Config.ALARM_STEPS[entry.level] or 0
			entry.lastAt = now
			self:_push(plotIndex, entry)
		end
	end
end

function AlarmState:Clear()
	for plotIndex in self.plots do
		self:_send(self.Services.GarageService:GetOwnerOfPlot(plotIndex), { level = 0, plotIndex = plotIndex })
	end
	self.plots = {}
end

function AlarmState:_send(userId: number?, payload)
	if not userId then
		return
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		Remotes.Get("AlarmUpdate"):FireClient(player, payload)
	end
end

-- Auf Stufe 3 wird es oeffentlich: das ist der Preis dafuer, eine Box
-- komplett auszuraeumen.
function AlarmState:_announce(plotIndex: number, entry)
	if entry.level < #Config.ALARM_STEPS then
		return
	end
	local ownerId = self.Services.GarageService:GetOwnerOfPlot(plotIndex)
	local owner = ownerId and Players:GetPlayerByUserId(ownerId)
	local text = if owner
		then ("Grossalarm in Box %d - %s wird ausgeraeumt!"):format(plotIndex, owner.DisplayName)
		else ("Grossalarm in Box %d - da raeumt jemand einen Leerstand leer!"):format(plotIndex)
	for _, player in Players:GetPlayers() do
		self.Services.EconomyService:Notify(player, text, "bad")
	end
end

function AlarmState:_push(plotIndex: number, entry)
	local ownerId = self.Services.GarageService:GetOwnerOfPlot(plotIndex)
	if not ownerId then
		return -- Leerstand hat niemanden, dem man etwas melden koennte
	end
	local owner = Players:GetPlayerByUserId(ownerId)
	local ownerRoot = owner and owner.Character and owner.Character:FindFirstChild("HumanoidRootPart")
	local thief = entry.thief
	local thiefRoot = thief and thief.Parent and thief.Character and thief.Character:FindFirstChild("HumanoidRootPart")

	local payload = { level = entry.level, plotIndex = plotIndex, count = entry.count }
	if entry.level >= 2 and thiefRoot then
		payload.position = (thiefRoot :: BasePart).Position
		payload.thief = thief.DisplayName
	elseif entry.level >= 1 and thiefRoot and ownerRoot then
		payload.direction = directionText((ownerRoot :: BasePart).Position, (thiefRoot :: BasePart).Position)
	end
	self:_send(ownerId, payload)
end

return AlarmState
