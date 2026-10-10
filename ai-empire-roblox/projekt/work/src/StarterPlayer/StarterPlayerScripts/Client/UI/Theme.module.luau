--!strict
-- Farben und Schriften ("Nachtlabor"): tiefe Tinte als Grund, helle Haarlinien als Struktur, die
-- Firmenfarbe als einziger Akzent (CTA, Auswahl, Live-Daten). Elemente melden sich mit bindAccent
-- (Instanz + Property) oder onAccent (Callback) an und werden beim Farbwechsel umgefärbt.

local Theme = {}

Theme.colors = {
	bg = Color3.fromRGB(15, 21, 23),
	panel = Color3.fromRGB(23, 31, 33),
	panel2 = Color3.fromRGB(30, 39, 41),
	raised = Color3.fromRGB(42, 52, 53),
	line = Color3.fromRGB(255, 255, 255), -- Haarlinien, immer mit hoher Transparenz
	text = Color3.fromRGB(238, 239, 231),
	muted = Color3.fromRGB(158, 173, 168),
	dim = Color3.fromRGB(117, 136, 132),
	good = Color3.fromRGB(129, 204, 162),
	bad = Color3.fromRGB(224, 137, 127),
	warn = Color3.fromRGB(224, 189, 122),
	black = Color3.fromRGB(0, 0, 0),
	white = Color3.fromRGB(255, 255, 255),
}

Theme.font = {
	regular = Enum.Font.BuilderSans,
	medium = Enum.Font.BuilderSansMedium,
	bold = Enum.Font.BuilderSansBold,
	black = Enum.Font.BuilderSansExtraBold,
	display = Enum.Font.BuilderSansExtraBold,
	mono = Enum.Font.RobotoMono, -- nur im Trainings-Log
}

Theme.DEFAULT_ACCENT = Color3.fromRGB(120, 200, 174)
Theme.accent = Theme.DEFAULT_ACCENT

type Binding = { inst: Instance, prop: string, mix: ((Color3) -> Color3)? }

local bindings: { Binding } = {}
local listeners: { (Color3) -> () } = {}

local function valueFor(binding: Binding): Color3
	return if binding.mix then binding.mix(Theme.accent) else Theme.accent
end

-- Instanz zuerst parenten, dann binden (unparented Instanzen werden beim nächsten Wechsel entfernt)
function Theme.bindAccent(inst: Instance, prop: string, mix: ((Color3) -> Color3)?)
	local binding: Binding = { inst = inst, prop = prop, mix = mix }
	table.insert(bindings, binding)
	local target: any = inst
	target[prop] = valueFor(binding)
	-- Rebuilt app cards must release their bindings immediately, even if the
	-- company's accent never changes again during this session.
	inst.Destroying:Once(function()
		local index = table.find(bindings, binding)
		if index then table.remove(bindings, index) end
	end)
end

function Theme.onAccent(callback: (Color3) -> ())
	table.insert(listeners, callback)
end

function Theme.setAccent(color: Color3)
	if color == Theme.accent then
		return
	end
	Theme.accent = color
	local kept: { Binding } = {}
	for _, binding in bindings do
		if binding.inst.Parent ~= nil then
			local target: any = binding.inst
			target[binding.prop] = valueFor(binding)
			table.insert(kept, binding)
		end
	end
	bindings = kept
	for _, callback in listeners do
		task.spawn(callback, color)
	end
end

-- Mischungen für bindAccent
function Theme.darker(amount: number): (Color3) -> Color3
	return function(color: Color3): Color3
		return color:Lerp(Theme.colors.black, amount)
	end
end

function Theme.lighter(amount: number): (Color3) -> Color3
	return function(color: Color3): Color3
		return color:Lerp(Theme.colors.white, amount)
	end
end

-- Akzent als dunkle Tönung einer Fläche (Hero-Flächen: Schätzung, Loss-Graph, Ergebnis)
function Theme.tint(amount: number): (Color3) -> Color3
	return function(color: Color3): Color3
		return color:Lerp(Theme.colors.panel, amount)
	end
end

function Theme.rgb(values: { number }): Color3
	return Color3.fromRGB(values[1] or 255, values[2] or 255, values[3] or 255)
end

return Theme
