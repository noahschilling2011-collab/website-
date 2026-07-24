--[[
	Signal
	Minimaler Ersatz fuer BindableEvents, damit Services sich gegenseitig
	benachrichtigen koennen, ohne sich zu kennen. Kein Tabellen-Serialisieren,
	Handler laufen in eigenen Threads.
]]

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	assert(type(fn) == "function", "Signal:Connect erwartet eine Funktion")
	local handlers = self._handlers
	table.insert(handlers, fn)
	local connection = {
		Connected = true,
	}
	function connection:Disconnect()
		if not self.Connected then
			return
		end
		self.Connected = false
		local index = table.find(handlers, fn)
		if index then
			table.remove(handlers, index)
		end
	end
	return connection
end

function Signal:Fire(...)
	-- Kopie, damit ein Disconnect waehrend des Feuerns nichts kaputt macht.
	local snapshot = table.clone(self._handlers)
	for _, fn in snapshot do
		task.spawn(fn, ...)
	end
end

function Signal:DisconnectAll()
	table.clear(self._handlers)
end

return Signal
