--!strict
-- The Model Studio (LAB_SPEC 3): a full-screen takeover inside the Computer window, modelled on the Design
-- Studio of "Build a Phone Empire". Modes: closed | design | training | reveal | launch | live.
--   * host = the Computer root frame (found by name: LabApp cannot require Computer), so Computer.close() and
--     every app switch hide it; the Studio then closes itself (input unbound, touch controls restored)
--   * own UIScale: a 1254 x 520 design canvas on an iPhone in landscape (1 px = 0.598 pt), 1254 x 648 at
--     1280 x 720; compact class when the main area is below 440 px
--   * input: tiles and bar buttons are Selectable; Return = primary button (no text box focused);
--     gamepad L1/R1 = previous/next step, B = back (ContextActionService, bound only while open)
--   * while open on a touch screen the thumbstick/jump controls are switched off (GuiService.TouchControlsEnabled)
--   * opens only while the Computer is open and the Lab is the shown app: a remote reply that arrives after the player
--     closed the Computer (× while STARTING…) must not re-bind input or switch the touch controls off again
--   * gamepad: the root is a SelectionGroup that stops at its edges (nothing behind the opaque Studio is reachable)
--   * Studio.token() changes on every open/close: a mode that waits for a remote reply checks it before switching
-- The modes live in DesignSteps (design), Stages (training, reveal, live) and LaunchDay (launch).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Format = require(ReplicatedStorage.Shared.Format)
local Types = require(ReplicatedStorage.Shared.Types)

local UI = script.Parent.Parent
local Client = UI.Parent
local StateController = require(Client.Controllers.StateController)
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Parts = require(script.Parent.StudioParts)

local C = Theme.colors
local F = Theme.font

export type View = {
	frame: Frame,
	title: string?, -- top bar title; nil = ceremony layout (centre caption, no title, no ×)
	show: (opts: any) -> (),
	hide: () -> (),
	refresh: (snapshot: Types.Snapshot) -> (),
	focus: () -> GuiObject?, -- gamepad selection after a mode / step change
	primary: () -> (), -- Return key
	back: () -> (), -- gamepad B
	step: ((delta: number) -> ())?, -- gamepad L1 / R1
	setClass: (compact: boolean) -> (),
}

local Studio = {}

Studio.mode = "closed"
Studio.compact = true
Studio.canvas = Vector2.new(1254, 520)
Studio.nav = nil :: Kit.Nav?
Studio.root = nil :: Frame?
Studio.body = nil :: Frame?
Studio.onClosed = {} :: { () -> () }
Studio.ACTION = "AIEmpireStudio"

local container: Frame? = nil
local host: GuiObject? = nil
local views: { [string]: View } = {}
local builders: { [string]: (any) -> View } = {}
local current: View? = nil
local touchSaved: boolean? = nil
local bound = false

local scale: UIScale? = nil
local lastCanvas = Vector2.new(1254, 520)
local generation = 0
local bannerButton: TextButton? = nil
local bannerAction: (() -> ())? = nil
local closeButton: TextButton? = nil
local titleLabel: TextLabel? = nil
local subLabel: TextLabel? = nil
local centerCaption: TextLabel? = nil
local centerTitle: TextLabel? = nil
local cashCaption: TextLabel? = nil
local cashLabel: TextLabel? = nil

-- registered by LabApp so this module never requires the mode modules at load time
function Studio.register(mode: string, builder: (any) -> View)
	builders[mode] = builder
end

local function designScale(inst: Instance): number
	local s = 1
	local node: Instance? = inst
	while node do
		local u = node:FindFirstChildOfClass("UIScale")
		if u and u ~= scale then
			s *= u.Scale
		end
		node = node.Parent
	end
	return if s > 0 then s else 1
end

local function applyScale()
	local root, h, uiScale = Studio.root, host, scale
	if not root or not h or not uiScale then
		return
	end
	local a = h.AbsoluteSize
	local p = designScale(h)
	local s = if a.X > 0 and a.Y > 0 then math.clamp(math.min(a.X / 1254, a.Y / 520), 0.5, 1.25) else 1
	local k = s / p
	uiScale.Scale = k
	root.Size = UDim2.fromScale(1 / k, 1 / k)
	local canvas = if a.X > 0 and a.Y > 0 then Vector2.new(a.X / s, a.Y / s) else Vector2.new(1254, 648)
	Studio.canvas = canvas
	local compact = canvas.Y - 184 < 440
	local resized = (canvas - lastCanvas).Magnitude > 1
	lastCanvas = canvas
	if compact ~= Studio.compact or resized then
		-- a class change, or a new canvas size in the same class (the regular card grows with the preview zone)
		Studio.compact = compact
		for _, view in views do
			view.setClass(compact)
		end
	end
end

local function cashText(): string
	return Parts.money(math.floor(StateController.money()))
end

-- Top bar: title block (normal modes) or a centred two-line caption (ceremonies)
function Studio.setTitle(title: string?, subtitle: string?)
	local t, s, cc, ct, x = titleLabel, subLabel, centerCaption, centerTitle, closeButton
	if not t or not s or not cc or not ct or not x then
		return
	end
	local ceremony = title == nil
	local banner = bannerButton
	local bannerOn = banner ~= nil and bannerAction ~= nil and not ceremony
	if banner then
		banner.Visible = bannerOn
	end
	t.Visible = not ceremony and not bannerOn
	s.Visible = not ceremony and not bannerOn
	x.Visible = not ceremony
	cc.Visible = ceremony
	ct.Visible = ceremony
	if title then
		t.Text = title
	end
	local snapshot = StateController.snapshot
	local company = if snapshot then snapshot.data.company else nil
	s.Text = subtitle or `{if company then company.name else "Your company"} · time keeps running`
	local cash, cap = cashLabel, cashCaption
	if cash and cap then
		local right = if ceremony then -16 else -102
		cash.Position = UDim2.new(1, right - 300, 0, 34)
		cap.Position = UDim2.new(1, right - 300, 0, 8)
	end
end

function Studio.setCenter(caption: string, title: string, color: Color3?)
	local cc, ct = centerCaption, centerTitle
	if cc and ct then
		cc.Text = caption
		cc.TextColor3 = color or C.muted
		ct.Text = title
	end
end

local function build()
	local frameHost = host
	if Studio.root or not frameHost then
		return
	end
	local root = Kit.frame(frameHost)
	root.Name = "ModelStudio"
	root.ZIndex = 30
	root.Visible = false
	root.BackgroundTransparency = 0
	root.BackgroundColor3 = C.bg
	root.Active = true -- swallows clicks that would reach the Computer window underneath
	-- gamepad: selection stays inside the Studio (the Lab home's tiles behind it are still Selectable)
	root.SelectionGroup = true
	root.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = root
	scale = uiScale
	Studio.root = root
	-- faint vignette: the stage feel of the reference (top lighter, bottom darker)
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new(C.panel:Lerp(C.bg, 0.4), C.bg)
	shade.Parent = root

	-- top bar
	local lab = Parts.button(root, "‹ LAB", "ghost", UDim2.fromOffset(16, 8), UDim2.fromOffset(140, 74), 24)
	lab.Name = "BackToLab"
	lab.TextColor3 = C.text
	Kit.onClick(lab, function()
		Studio.close()
	end)
	titleLabel = Parts.label(root, "Model Studio", 32, F.display, C.text, UDim2.fromOffset(172, 8), UDim2.fromOffset(340, 40))
	subLabel = Parts.label(root, "", 20, F.medium, C.muted, UDim2.fromOffset(172, 50), UDim2.fromOffset(340, 26))
	-- "Nova v2 ready · REVEAL ›": a finished training while the player designs or launches something else takes the
	-- title's place (left of the toast lane) instead of switching modes under the player's finger
	local banner = Parts.button(root, "", "primary", UDim2.fromOffset(172, 8), UDim2.fromOffset(330, 74), 22)
	banner.Name = "ReadyBanner"
	banner.Visible = false
	bannerButton = banner
	Kit.onClick(banner, function()
		local fn = bannerAction
		if fn then
			fn()
		end
	end)
	-- ceremony caption ("INTRODUCING / Nova v2", "NOW LIVE / Consumer Chat"): left, where the title sits, so the
	-- top-centre toast lane stays free (a toast must not cover the model's name; Toast.hold is request lab #5)
	local cc = Parts.label(root, "", 22, F.bold, C.muted, UDim2.fromOffset(172, 6), UDim2.fromOffset(330, 28))
	cc.Name = "CenterCaption"
	centerCaption = cc
	local ct = Parts.label(root, "", 44, F.display, C.text, UDim2.fromOffset(172, 32), UDim2.fromOffset(330, 54))
	ct.Name = "CenterTitle"
	ct.TextScaled = true -- long names shrink instead of running into the toast lane
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = 44
	fit.MinTextSize = 24
	fit.Parent = ct
	centerTitle = ct
	cashCaption = Parts.label(root, "CASH", 20, F.bold, C.muted, UDim2.new(1, -402, 0, 8), UDim2.fromOffset(300, 24), Enum.TextXAlignment.Right)
	local cash = Parts.label(root, "$0", 30, F.display, C.text, UDim2.new(1, -402, 0, 34), UDim2.fromOffset(300, 40), Enum.TextXAlignment.Right)
	cash.Name = "Cash"
	cashLabel = cash
	local x = Parts.button(root, "×", "ghost", UDim2.new(1, -90, 0, 8), UDim2.fromOffset(74, 74), 34)
	x.Name = "CloseComputer"
	x.TextColor3 = C.text
	closeButton = x
	Kit.onClick(x, function()
		local nav = Studio.nav
		Studio.close()
		if nav then
			nav.close()
		end
	end)

	local body = Kit.frame(root, UDim2.new(1, 0, 1, -102), UDim2.fromOffset(0, 94))
	body.Name = "Body"
	Studio.body = body

	frameHost:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(applyScale)
	end)
	frameHost:GetPropertyChangedSignal("Visible"):Connect(function()
		if not frameHost.Visible and Studio.mode ~= "closed" then
			Studio.close()
		end
	end)
	local labFrame = container
	if labFrame then
		labFrame:GetPropertyChangedSignal("Visible"):Connect(function()
			if not labFrame.Visible and Studio.mode ~= "closed" then
				Studio.close()
			end
		end)
	end
	applyScale()
end

local function viewFor(mode: string): View?
	local view = views[mode]
	if view then
		return view
	end
	local builder = builders[mode]
	local body = Studio.body
	if not builder or not body then
		return nil
	end
	local made: View = builder(Studio)
	made.frame.Visible = false
	made.setClass(Studio.compact)
	views[mode] = made
	return made
end

function Studio.select(obj: GuiObject?)
	if obj and UserInputService.GamepadEnabled then
		GuiService.SelectedObject = obj
	end
end

local function onAction(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local view = current
	if state ~= Enum.UserInputState.Begin or not view or Studio.mode == "closed" then
		return Enum.ContextActionResult.Pass
	end
	if input.KeyCode == Enum.KeyCode.ButtonB then
		view.back()
		return Enum.ContextActionResult.Sink
	end
	local stepBy = view.step
	if stepBy and (input.KeyCode == Enum.KeyCode.ButtonL1 or input.KeyCode == Enum.KeyCode.ButtonR1) then
		stepBy(if input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1)
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function bindInput()
	if bound then
		return
	end
	bound = true
	ContextActionService:BindActionAtPriority(Studio.ACTION, onAction, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1, Enum.KeyCode.ButtonB)
	if UserInputService.TouchEnabled and touchSaved == nil then
		touchSaved = GuiService.TouchControlsEnabled
		GuiService.TouchControlsEnabled = false
	end
end

local function unbindInput()
	if bound then
		bound = false
		ContextActionService:UnbindAction(Studio.ACTION)
	end
	local saved = touchSaved
	if saved ~= nil then
		touchSaved = nil
		GuiService.TouchControlsEnabled = saved
	end
end

function Studio.refresh()
	local view = current
	local snapshot = StateController.snapshot
	if view and snapshot and Studio.mode ~= "closed" then
		view.refresh(snapshot)
	end
	local cash = cashLabel
	if cash then
		cash.Text = cashText()
		cash.TextColor3 = if StateController.money() < 0 then C.bad else C.text
	end
end

-- Changes on every open and close: a mode that waits for a remote reply compares it before it switches modes.
function Studio.token(): number
	return generation
end

-- Can the Studio be shown now? Only inside an open Computer that shows the Lab.
local function hostReady(): boolean
	local nav = Studio.nav
	if nav and not nav.isOpen() then
		return false
	end
	local labFrame = container
	if labFrame and not labFrame.Visible then
		return false
	end
	return true
end

-- The top-bar banner (nil text = hidden). Shown in the normal modes; ceremonies keep their centre caption.
function Studio.setBanner(text: string?, onTap: (() -> ())?)
	build()
	local banner = bannerButton
	if not banner then
		return
	end
	bannerAction = if text then onTap else nil
	banner.Text = text or ""
	local view = current
	Studio.setTitle(if view then view.title else "Model Studio", nil)
	if view and view.title then
		local t = titleLabel
		if t then
			t.Text = view.title
		end
	end
end

function Studio.bannerShown(): boolean
	local banner = bannerButton
	return banner ~= nil and banner.Visible
end

-- Opens (or switches) the Studio to `mode`. opts go to the mode's show(). Ignored while the Computer is closed or
-- shows another app (a late remote reply must not re-open it behind the player's back).
function Studio.open(mode: string, opts: any?)
	if not hostReady() then
		return
	end
	build()
	local root = Studio.root
	if not root then
		return
	end
	local view = viewFor(mode)
	if not view then
		return
	end
	local previous = current
	if previous and previous ~= view then
		previous.hide()
		previous.frame.Visible = false
	end
	Studio.mode = mode
	current = view
	generation += 1
	root.Visible = true
	view.frame.Visible = true
	Studio.setTitle(view.title, nil)
	bindInput()
	applyScale()
	view.show(opts or {})
	Studio.refresh()
	Studio.select(view.focus())
end

function Studio.isOpen(): boolean
	return Studio.mode ~= "closed"
end

function Studio.current(): View?
	return current
end

-- Back to the Lab home (every choice stays in StateController.ui / LabState).
function Studio.close()
	local view = current
	current = nil
	if view then
		view.hide()
		view.frame.Visible = false
	end
	local wasOpen = Studio.mode ~= "closed"
	Studio.mode = "closed"
	generation += 1
	local root = Studio.root
	if root then
		root.Visible = false
	end
	unbindInput()
	if wasOpen and UserInputService.GamepadEnabled then
		-- back on the Lab home: its DESIGN NEW MODEL tile takes the selection (nil when the Lab is not shown)
		local labFrame = container
		local design = if labFrame and labFrame.Visible then labFrame:FindFirstChild("DesignNewModel", true) else nil
		GuiService.SelectedObject = if design and design:IsA("GuiObject") then design else nil
	end
	if wasOpen then
		for _, callback in Studio.onClosed do
			task.spawn(callback)
		end
	end
end

function Studio.init(labContainer: Frame, navigation: Kit.Nav)
	container = labContainer
	Studio.nav = navigation
	local computer = labContainer:FindFirstAncestor("Computer")
	host = if computer and computer:IsA("GuiObject") then computer else labContainer
	StateController.onChange(function()
		if Studio.mode ~= "closed" then
			Studio.refresh()
		end
	end)
	StateController.onUiChange(function()
		if Studio.mode ~= "closed" then
			Studio.refresh()
		end
	end)
	Theme.onAccent(function()
		if Studio.mode ~= "closed" then
			Studio.refresh()
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		local view = current
		if processed or not view or Studio.mode == "closed" then
			return
		end
		if (input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter) and UserInputService:GetFocusedTextBox() == nil then
			view.primary()
		end
	end)
	-- live cash in the top bar while open; the text is only formatted when the whole-dollar value changes
	-- (no string per frame when the cash stands still)
	local lastValue = math.huge
	game:GetService("RunService").RenderStepped:Connect(function()
		local cash = cashLabel
		if Studio.mode == "closed" or not cash then
			lastValue = math.huge
			return
		end
		local value = math.floor(StateController.money())
		if value ~= lastValue then
			lastValue = value
			cash.Text = Parts.money(value)
		end
	end)
end

-- Short helpers shared by the modes
Studio.money = Parts.money
Studio.duration = Format.duration

return Studio
