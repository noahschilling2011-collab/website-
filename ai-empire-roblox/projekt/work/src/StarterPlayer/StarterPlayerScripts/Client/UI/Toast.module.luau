--!strict
-- Kurze Meldungen oben mittig. Immer nur eine: neue ersetzt alte. Bei offenem Computer liegt sie
-- in der leeren Mitte der Kopfzeile und verdeckt keinen Inhalt. Gleicher Text verlängert nur.

local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)

local C = Theme.colors
local F = Theme.font

export type Kind = "info" | "success" | "error" | "warn"

local Toast = {}

local MAX_VISIBLE = 1
local container: Frame? = nil
local active: { { text: string, frame: Frame, expires: number } } = {}
local counter = 0

local function colorOf(kind: Kind): Color3
	if kind == "success" then
		return C.good
	elseif kind == "error" then
		return C.bad
	elseif kind == "warn" then
		return C.warn
	end
	return Theme.accent
end

function Toast.mount(parent: Instance)
	local holder = Kit.frame(parent, UDim2.fromOffset(440, 0), UDim2.new(0.5, 0, 0, 16))
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.Name = "Toasts"
	holder.ZIndex = 50
	local layout = Kit.list(holder, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	container = holder
end

local function dismiss(entry: { text: string, frame: Frame, expires: number })
	local index = table.find(active, entry)
	if index then
		table.remove(active, index)
	end
	local frame = entry.frame
	Kit.tween(frame, 0.25, { BackgroundTransparency = 1 })
	for _, child in frame:GetDescendants() do
		if child:IsA("TextLabel") then
			Kit.tween(child, 0.25, { TextTransparency = 1 })
		elseif child:IsA("Frame") then
			Kit.tween(child, 0.25, { BackgroundTransparency = 1 })
		elseif child:IsA("UIStroke") then
			Kit.tween(child, 0.25, { Transparency = 1 })
		end
	end
	task.delay(0.3, function()
		frame:Destroy()
	end)
end

function Toast.show(kind: Kind, text: string, seconds: number?)
	local holder = container
	if not holder then
		return
	end
	local duration = seconds or 3
	for _, entry in active do
		if entry.text == text then
			entry.expires = os.clock() + duration
			return
		end
	end
	if #active >= MAX_VISIBLE then
		dismiss(active[1])
	end

	counter += 1
	local color = colorOf(kind)
	local frame = Kit.frame(holder, UDim2.fromScale(1, 0))
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = counter
	frame.BackgroundTransparency = 0.04
	frame.BackgroundColor3 = C.bg
	frame.ZIndex = 50
	Kit.corner(frame, 12)
	Kit.stroke(frame, 0.6, color)
	Kit.padding(frame, 11, 16, 11, 16)
	Kit.list(frame, 10, true)

	local dot = Kit.dot(frame, color, 8) -- Statusfarbe: Erfolg, Fehler, Warnung, Info
	dot.LayoutOrder = 1
	dot.ZIndex = 51
	local label = Kit.text(frame, text, 15, F.medium, C.text)
	label.LayoutOrder = 2
	label.ZIndex = 51
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.new(1, -18, 0, 0)
	label.TextWrapped = true

	local scale = Instance.new("UIScale")
	scale.Scale = 0.92
	scale.Parent = frame
	Kit.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)

	local entry = { text = text, frame = frame, expires = os.clock() + duration }
	table.insert(active, entry)
	task.spawn(function()
		while table.find(active, entry) do
			if os.clock() >= entry.expires then
				dismiss(entry)
				return
			end
			task.wait(0.2)
		end
	end)
end

return Toast
