--!nolint
-- Roblox-Stubs + virtuelle Uhr, damit die echten Servermodule ausserhalb von
-- Studio laufen. SOURCES ist vorher definiert (vom Generator eingesetzt).

local errors = {}
local clock = 0
local waiters = {}
local seq = 0

local function record(err, co)
	local trace = ""
	pcall(function()
		trace = debug.traceback(co)
	end)
	table.insert(errors, tostring(err) .. "\n" .. trace)
end

local function resumeSafe(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		record(err, co)
	end
end

local function schedule(time, co)
	seq += 1
	table.insert(waiters, { time = time, co = co, seq = seq })
end

-- --------------------------------------------------------------- task/os --

task = {}

function task.wait(t)
	schedule(clock + (t or 0), coroutine.running())
	return coroutine.yield()
end

function task.spawn(fn, ...)
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	resumeSafe(co, ...)
	return co
end

function task.delay(t, fn, ...)
	local args = table.pack(...)
	local co = coroutine.create(function()
		fn(table.unpack(args, 1, args.n))
	end)
	schedule(clock + (t or 0), co)
	return co
end

function task.defer(fn, ...)
	local args = table.pack(...)
	local co = coroutine.create(function()
		fn(table.unpack(args, 1, args.n))
	end)
	schedule(clock, co)
	return co
end

local realOs = os
os = {
	clock = function()
		return clock
	end,
	time = realOs.time,
	date = realOs.date,
}

local warnings = {}
warn = function(...)
	local parts = {}
	for index = 1, select("#", ...) do
		parts[index] = tostring(select(index, ...))
	end
	table.insert(warnings, table.concat(parts, " "))
end

-- Verbotene Alt-APIs: wenn ein Modul sie doch benutzt, faellt das hier auf.
wait = function()
	error("wait() ist verboten -- task.wait() benutzen", 2)
end
spawn = function()
	error("spawn() ist verboten -- task.spawn() benutzen", 2)
end
delay = function()
	error("delay() ist verboten -- task.delay() benutzen", 2)
end

-- ---------------------------------------------------------------- Signal --

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local conn = { fn = fn, connected = true, owner = self }
	function conn:Disconnect()
		self.connected = false
	end
	table.insert(self.handlers, conn)
	return conn
end

function Signal:DisconnectAll()
	for _, conn in ipairs(self.handlers) do
		conn.connected = false
	end
	table.clear(self.handlers)
end

--[[
	Roblox startet jeden Handler auf einem eigenen Thread. Das nachzubilden ist
	wichtig: sonst wuerde ein WaitForChild im Handler den Aufrufer blockieren.
]]
function Signal:Fire(...)
	for _, conn in ipairs(table.clone(self.handlers)) do
		if conn.connected then
			task.spawn(conn.fn, ...)
		end
	end
end

-- ------------------------------------------------------------ Datentypen --

local Vector3Meta = {}
Vector3Meta.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	end
	if k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return Vector3.new(v.X / m, v.Y / m, v.Z / m)
	end
	return rawget(v, k)
end
Vector3Meta.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
Vector3Meta.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
Vector3Meta.__mul = function(a, b)
	if type(b) == "number" then
		return Vector3.new(a.X * b, a.Y * b, a.Z * b)
	end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3Meta.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
Vector3Meta.__tostring = function(v)
	return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
end

Vector3 = {}
function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3Meta)
end
Vector3.zero = Vector3.new(0, 0, 0)

Vector2 = {}
function Vector2.new(x, y)
	return { X = x or 0, Y = y or 0 }
end

Color3 = {}
function Color3.new(r, g, b)
	return { R = r or 0, G = g or 0, B = b or 0, Lerp = function(self, other, t)
		return Color3.new(
			self.R + (other.R - self.R) * t,
			self.G + (other.G - self.G) * t,
			self.B + (other.B - self.B) * t
		)
	end }
end
function Color3.fromRGB(r, g, b)
	return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end

-- Nur Position, keine Rotation. Reicht fuer Paket-Offsets im Harness.
local CFrameMeta = {}
CFrameMeta.__index = function(c, k)
	if k == "Position" or k == "p" then
		return rawget(c, "_p")
	end
	return rawget(c, k)
end
CFrameMeta.__mul = function(a, b)
	if getmetatable(b) == CFrameMeta then
		return CFrame.new(a._p + b._p)
	end
	return CFrame.new(a._p + b)
end

CFrame = {}
function CFrame.new(a, b, c)
	local p
	if type(a) == "table" then
		p = a
	else
		p = Vector3.new(a or 0, b or 0, c or 0)
	end
	return setmetatable({ _p = p }, CFrameMeta)
end

UDim = {}
function UDim.new(s, o)
	return { Scale = s or 0, Offset = o or 0 }
end

UDim2 = {}
function UDim2.new(xs, xo, ys, yo)
	return { X = UDim.new(xs, xo), Y = UDim.new(ys, yo) }
end
function UDim2.fromOffset(x, y)
	return UDim2.new(0, x, 0, y)
end
function UDim2.fromScale(x, y)
	return UDim2.new(x, 0, y, 0)
end

TweenInfo = {}
function TweenInfo.new(...)
	return { ... }
end

-- Permissives Enum: jedes Enum.Foo.Bar liefert einen Stub mit Name.
local enumItemMeta = {
	__tostring = function(item)
		return "Enum." .. item.EnumType .. "." .. item.Name
	end,
}
Enum = setmetatable({}, {
	__index = function(_, enumType)
		local holder = setmetatable({}, {
			__index = function(t, itemName)
				local item = setmetatable({ Name = itemName, EnumType = enumType, Value = 0 }, enumItemMeta)
				rawset(t, itemName, item)
				return item
			end,
		})
		return holder
	end,
})

Random = {}
function Random.new(seed)
	local state = seed or 12345
	local rng = {}
	-- Deterministischer LCG, damit Laeufe reproduzierbar sind.
	local function nextRaw()
		state = (1103515245 * state + 12345) % 2147483648
		return state / 2147483648
	end
	function rng:NextNumber(a, b)
		local r = nextRaw()
		if a == nil then
			return r
		end
		return a + r * (b - a)
	end
	function rng:NextInteger(a, b)
		return math.floor(a + nextRaw() * (b - a + 1 - 1e-9))
	end
	return rng
end

-- -------------------------------------------------------------- Instances --

local CLASS_PARENTS = {
	Part = "BasePart",
	SpawnLocation = "Part",
	BasePart = "PVInstance",
	Model = "PVInstance",
	PVInstance = "Instance",
	Folder = "Instance",
	Humanoid = "Instance",
	ProximityPrompt = "Instance",
	RemoteEvent = "Instance",
	Decal = "Instance",
	WeldConstraint = "Instance",
	BillboardGui = "Instance",
	TextLabel = "GuiObject",
	Frame = "GuiObject",
	TextButton = "GuiObject",
	GuiObject = "Instance",
	Sound = "Instance",
	ModuleScript = "Instance",
	Script = "Instance",
}

local EVENT_NAMES = {
	Triggered = true,
	TriggerEnded = true,
	OnServerEvent = true,
	OnClientEvent = true,
	CharacterAdded = true,
	CharacterRemoving = true,
	PlayerAdded = true,
	PlayerRemoving = true,
	Destroying = true,
	Ended = true,
	Heartbeat = true,
	Changed = true,
	Completed = true,
	MouseEnter = true,
	MouseLeave = true,
	Activated = true,
}

local instanceMethods = {}
local instanceMeta = {
	__index = function(t, key)
		local props = rawget(t, "_props")
		local value = props[key]
		if value ~= nil then
			return value
		end
		if EVENT_NAMES[key] then
			local signal = Signal.new()
			props[key] = signal
			return signal
		end
		return instanceMethods[key]
	end,
	__newindex = function(t, key, value)
		if key == "Parent" then
			instanceMethods.SetParent(t, value)
			return
		end
		rawget(t, "_props")[key] = value
	end,
	__tostring = function(t)
		return rawget(t, "_props").Name or "Instance"
	end,
}

local function makeInstance(className, name)
	local self = setmetatable({
		_props = { ClassName = className, Name = name or className },
		_children = {},
		_attributes = {},
		_destroyed = false,
	}, instanceMeta)
	return self
end

function instanceMethods.SetParent(self, parent)
	local props = rawget(self, "_props")
	local old = props.Parent
	if old then
		local siblings = rawget(old, "_children")
		local index = table.find(siblings, self)
		if index then
			table.remove(siblings, index)
		end
	end
	props.Parent = parent
	if parent then
		table.insert(rawget(parent, "_children"), self)
	end
end

function instanceMethods:GetChildren()
	return table.clone(rawget(self, "_children"))
end

function instanceMethods:FindFirstChild(name)
	for _, child in ipairs(rawget(self, "_children")) do
		if child.Name == name then
			return child
		end
	end
	return nil
end

function instanceMethods:FindFirstChildOfClass(className)
	for _, child in ipairs(rawget(self, "_children")) do
		if child.ClassName == className then
			return child
		end
	end
	return nil
end

function instanceMethods:WaitForChild(name, _timeout)
	local found = instanceMethods.FindFirstChild(self, name)
	if found then
		return found
	end
	-- Im Harness existiert der Baum vollstaendig, bevor Module laden.
	error(string.format("WaitForChild(%q) an %s: nicht vorhanden", tostring(name), tostring(self)), 2)
end

function instanceMethods:IsA(className)
	local current = self.ClassName
	while current do
		if current == className then
			return true
		end
		current = CLASS_PARENTS[current]
	end
	return false
end

function instanceMethods:SetAttribute(key, value)
	rawget(self, "_attributes")[key] = value
end

function instanceMethods:GetAttribute(key)
	return rawget(self, "_attributes")[key]
end

function instanceMethods:Destroy()
	if rawget(self, "_destroyed") then
		return
	end
	rawset(self, "_destroyed", true)

	for _, child in ipairs(table.clone(rawget(self, "_children"))) do
		instanceMethods.Destroy(child)
	end

	-- Roblox trennt beim Destroy alle Verbindungen zu den Events der Instanz.
	for _, value in pairs(rawget(self, "_props")) do
		if type(value) == "table" and getmetatable(value) == Signal then
			value:DisconnectAll()
		end
	end

	instanceMethods.SetParent(self, nil)
end

-- RemoteEvent-Verkehr: FireClient landet im Postfach des Spielers, damit der
-- Test-Client genau das sieht, was ein echter Client saehe.
local inboxes = {}

function instanceMethods:FireClient(player, ...)
	local inbox = inboxes[player]
	if not inbox then
		return
	end
	local handler = inbox[self.Name]
	if handler then
		task.spawn(handler, ...)
	end
end

function instanceMethods:FireAllClients(...)
	for player, inbox in pairs(inboxes) do
		local handler = inbox[self.Name]
		if handler then
			task.spawn(handler, ...)
		end
	end
end

function instanceMethods:FireServer(...)
	self.OnServerEvent:Fire(...)
end

Instance = {}
function Instance.new(className, parent)
	local inst = makeInstance(className)
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- --------------------------------------------------------------- Services --

local services = {}

local function makeService(className, name)
	local service = makeInstance(className, name or className)
	services[name or className] = service
	return service
end

local ReplicatedStorage = makeService("ReplicatedStorage")
local ServerScriptService = makeService("ServerScriptService")
local Players = makeService("Players")
local SoundService = makeService("SoundService")
local RunService = makeService("RunService")
local TweenService = makeService("TweenService")
local Workspace = makeService("Workspace")
services.Workspace = Workspace

workspace = Workspace
function Workspace:GetServerTimeNow()
	return clock
end

local playerList = {}
function Players:GetPlayers()
	return table.clone(playerList)
end

function RunService:IsServer()
	return true
end
function RunService:IsClient()
	return false
end

game = {
	GetService = function(_, name)
		local service = services[name]
		if not service then
			error("GetService: unbekannter Dienst " .. tostring(name), 2)
		end
		return service
	end,
	Workspace = Workspace,
}

-- ---------------------------------------------------------------- require --

local moduleCache = {}

local realRequire = require
require = function(target)
	if type(target) ~= "table" then
		return realRequire(target)
	end

	local key = rawget(target, "_props").SourceKey
	if not key then
		error("require: " .. tostring(target) .. " ist kein Modul im Harness", 2)
	end

	if moduleCache[key] ~= nil then
		return moduleCache[key]
	end

	local source = SOURCES[key]
	if not source then
		error("require: keine Quelle fuer " .. key, 2)
	end

	local chunk, err = loadstring("local script = ...\n" .. source, "@" .. key)
	if not chunk then
		error("Syntaxfehler in " .. key .. ": " .. tostring(err), 2)
	end

	local result = chunk(target)
	moduleCache[key] = result
	return result
end

-- ------------------------------------------------------------------ Export --

Harness = {
	errors = errors,
	warnings = warnings,
	inboxes = inboxes,
	playerList = playerList,
	services = services,
	Signal = Signal,
	makeInstance = makeInstance,

	now = function()
		return clock
	end,

	--[[
		Laesst die virtuelle Uhr bis zum Zeitpunkt laufen.
	]]
	pump = function(untilTime)
		while true do
			local best, bestIndex
			for index, waiter in ipairs(waiters) do
				if
					not best
					or waiter.time < best.time
					or (waiter.time == best.time and waiter.seq < best.seq)
				then
					best, bestIndex = waiter, index
				end
			end

			if not best or best.time > untilTime then
				clock = math.max(clock, untilTime)
				return
			end

			table.remove(waiters, bestIndex)
			clock = math.max(clock, best.time)
			resumeSafe(best.co)
		end
	end,

	makeModule = function(name, parent, sourceKey)
		local module = makeInstance("ModuleScript", name)
		rawget(module, "_props").SourceKey = sourceKey
		module.Parent = parent
		return module
	end,

	makeFolder = function(name, parent)
		local folder = makeInstance("Folder", name)
		folder.Parent = parent
		return folder
	end,

	addPlayer = function(name, userId, position)
		local player = makeInstance("Player", name)
		player.UserId = userId
		player.DisplayName = name
		player.Parent = Players

		local character = makeInstance("Model", name)
		local root = makeInstance("Part", "HumanoidRootPart")
		root.Position = position
		root.CFrame = CFrame.new(position)
		root.Parent = character
		local torso = makeInstance("Part", "UpperTorso")
		torso.Position = position
		torso.CFrame = CFrame.new(position)
		torso.Parent = character
		local humanoid = makeInstance("Humanoid", "Humanoid")
		humanoid.Parent = character
		character.Parent = Workspace

		player.Character = character
		inboxes[player] = {}
		table.insert(playerList, player)

		Players.PlayerAdded:Fire(player)
		task.defer(function()
			player.CharacterAdded:Fire(character)
		end)
		return player
	end,

	removePlayer = function(player)
		local index = table.find(playerList, player)
		if index then
			table.remove(playerList, index)
		end
		Players.PlayerRemoving:Fire(player)
		inboxes[player] = nil
		player.Parent = nil
	end,

	--[[
		Registriert einen Client-Handler fuer ein RemoteEvent.
	]]
	onClient = function(player, remoteName, handler)
		inboxes[player][remoteName] = handler
	end,
}
