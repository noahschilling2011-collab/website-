--[[
	DismountBar
	Der Fortschrittsbalken beim Abmontieren. Der Balken ist reine Anzeige: der
	Server misst die vier Sekunden selbst und schickt "start", "cancel" oder
	"done". Wer hier herumpfuscht, klaut trotzdem nichts schneller.
]]

local RunService = game:GetService("RunService")

local Theme = require(script.Parent.Theme)

local DismountBar = {}

function DismountBar.Init(root: Frame)
	local frame = Theme.panel({
		Name = "DismountBar",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.72),
		Size = UDim2.new(0.7, 0, 0, 64),
		Visible = false,
		Parent = root,
	})
	Theme.constrain(frame, Vector2.new(240, 64), Vector2.new(340, 64))
	Theme.padding(10).Parent = frame

	local label = Theme.label({
		Text = "Abmontieren ...",
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		Parent = frame,
	})

	local track = Theme.create("Frame", {
		BackgroundColor3 = Theme.Colors.panelAlt,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 26),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = frame,
	}, { Theme.corner(8) })

	local fill = Theme.create("Frame", {
		BackgroundColor3 = Theme.Colors.accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
		Parent = track,
	}, { Theme.corner(8) })

	DismountBar._refs = { frame = frame, label = label, fill = fill }
	DismountBar._endsAt = 0
	DismountBar._duration = 0

	RunService.RenderStepped:Connect(function()
		if not frame.Visible then
			return
		end
		local remaining = math.max(0, DismountBar._endsAt - os.clock())
		local progress = DismountBar._duration > 0 and (1 - remaining / DismountBar._duration) or 0
		fill.Size = UDim2.new(math.clamp(progress, 0, 1), 0, 1, 0)
	end)
	return DismountBar
end

function DismountBar.Handle(payload)
	local refs = DismountBar._refs
	if not refs or type(payload) ~= "table" then
		return
	end
	if payload.state == "start" then
		DismountBar._duration = payload.duration or 4
		DismountBar._endsAt = os.clock() + DismountBar._duration
		refs.label.Text = ("Abmontieren: %s"):format(payload.label or "Teil")
		refs.fill.Size = UDim2.new(0, 0, 1, 0)
		refs.frame.Visible = true
	else
		refs.frame.Visible = false
	end
end

return DismountBar
