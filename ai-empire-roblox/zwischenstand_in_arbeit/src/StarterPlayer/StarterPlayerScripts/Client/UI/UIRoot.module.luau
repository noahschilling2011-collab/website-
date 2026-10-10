--!strict
-- Fünf ScreenGuis übereinander: HUD, Dim, Overlay (Computer), Intro (randlos), Top (Toasts, Debug).
-- Jede hat einen Root-Frame mit UIScale: das UI wird für 1280x720 entworfen und passend skaliert,
-- damit es auf Handy und großem Monitor gleich aussieht. CoreUISafeInsets hält es aus der Roblox-
-- Topbar und aus Notches heraus.

local Players = game:GetService("Players")

local UIRoot = {}

local DESIGN = Vector2.new(1280, 720)
local MIN_SCALE = 0.3
local MAX_SCALE = 1.25

type Layer = { gui: ScreenGui, root: Frame, scale: UIScale }

local function scaleFor(size: Vector2): number
	if size.X <= 0 or size.Y <= 0 then
		return 1
	end
	return math.clamp(math.min(size.X / DESIGN.X, size.Y / DESIGN.Y), MIN_SCALE, MAX_SCALE)
end

local function applyScale(layer: Layer)
	local s = scaleFor(layer.gui.AbsoluteSize)
	layer.scale.Scale = s
	layer.root.Size = UDim2.fromScale(1 / s, 1 / s)
end

local function makeLayer(playerGui: Instance, name: string, order: number, insets: Enum.ScreenInsets?): Frame
	local existing = playerGui:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = insets or Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = order
	gui.Parent = playerGui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = root

	local layer: Layer = { gui = gui, root = root, scale = scale }
	applyScale(layer)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		applyScale(layer)
	end)
	return root
end

-- Rückgabe: hud, dim (randlos: Abdunkeln hinter dem Computer, auch unter der Topbar),
-- overlay (Computer), intro (randlos), top (Toasts, Debug)
function UIRoot.init(): (Frame, Frame, Frame, Frame, Frame)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local hud = makeLayer(playerGui, "AIEmpire_HUD", 10)
	local dim = makeLayer(playerGui, "AIEmpire_Dim", 19, Enum.ScreenInsets.None)
	local overlay = makeLayer(playerGui, "AIEmpire_Overlay", 20)
	local intro = makeLayer(playerGui, "AIEmpire_Intro", 25, Enum.ScreenInsets.None)
	local top = makeLayer(playerGui, "AIEmpire_Top", 30)
	return hud, dim, overlay, intro, top
end

return UIRoot
