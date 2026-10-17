--!strict
-- The "use it?" sheet of the shop package (SHOP_SPEC 5.3): a centred card over the Menu and the Model Studio before a
-- voucher is used (Eureka, Last Epoch, a boost) and after a context purchase ("Eureka received. Use it now?").
-- Built from Kit.blocker + Kit.panel + Kit.button in its own ScreenGui "AIEmpire_ShopSheet" (DisplayOrder 27: above
-- the Menu 20, the guide 22 and the Intro 25, below the toasts 30) with the Menu's design canvas and scale formula
-- (1254 x 520 on an iPhone, s = 0.598: 20 px text = 12 pt, 74 px buttons = 44 pt). No timer and no price on the sheet:
-- the Robux purchase window of Roblox is the purchase confirmation; this sheet only confirms the USE.
-- Modal for every input (fix round 1): the dim swallows taps and clicks; while open the sheet binds gamepad B (= cancel),
-- L1 / R1 (sunk) and Return / KeypadEnter (= the action) at a priority above the Model Studio (High) and the Menu
-- (Medium), so nothing behind it changes; with a gamepad the action button is selected and the card is a selection
-- group that stops at its edges. Computer.close() and Studio.close() close it.
-- API: UseSheet.mount(playerGui?), UseSheet.open(spec), UseSheet.close(), UseSheet.isOpen(), UseSheet.setBusy(bool),
-- UseSheet.frame() (tests).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local C = Theme.colors
local F = Theme.font

export type Row = { caption: string, value: string, tail: string? }
export type Spec = {
	icon: string?, -- Kit.icon kind
	title: string,
	sub: string?,
	rows: { Row },
	action: string, -- the primary button ("USE EUREKA", "START", "USE NOW")
	cancel: string?, -- "CANCEL" / "LATER"
	onAction: () -> (),
	onCancel: (() -> ())?,
}

local UseSheet = {}
UseSheet.ORDER = 27
UseSheet.CANVAS = Vector2.new(1254, 520)
UseSheet.WIDTH = 760
UseSheet.ACTION = "AIEmpireUseSheet"
UseSheet.PRIORITY = Enum.ContextActionPriority.High.Value + 1 -- above the Studio's High binding and the Menu's Medium
UseSheet.KEYS = { Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1, Enum.KeyCode.Return, Enum.KeyCode.KeypadEnter }

local gui: ScreenGui? = nil
local shade: TextButton? = nil
local card: Frame? = nil
local iconHolder: Frame? = nil
local titleLabel: TextLabel? = nil
local subLabel: TextLabel? = nil
local rowsFrame: Frame? = nil
local cancelButton: TextButton? = nil
local actionButton: TextButton? = nil
local current: Spec? = nil
local busy = false
local inputBound = false
local returnTo: GuiObject? = nil -- the gamepad selection before the sheet opened (given back on close when still shown)

-- the player plays with a gamepad right now: the same rule as Computer.padActive (this module cannot require Computer,
-- which requires it through ShopApp and ShopCore)
local function padActive(): boolean
	local ok, preferred = pcall(function(): any
		return (UserInputService :: any).PreferredInput
	end)
	if ok and typeof(preferred) == "EnumItem" then
		return preferred == Enum.PreferredInput.Gamepad
	end
	return UserInputService.GamepadEnabled and not UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end
UseSheet.padActive = padActive

local function cancelNow()
	local spec = current
	UseSheet.close()
	if spec and spec.onCancel then
		spec.onCancel()
	end
end

local function actNow()
	local spec = current
	if not spec or busy then
		return
	end
	spec.onAction()
end

-- B = cancel, Return = the action; L1 / R1 sunk; every state is sunk so nothing below the sheet sees the key
local function onSheetInput(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if not UseSheet.isOpen() then
		return Enum.ContextActionResult.Pass
	end
	if state == Enum.UserInputState.Begin then
		local key = input.KeyCode
		if key == Enum.KeyCode.ButtonB then
			cancelNow()
		elseif (key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter) and UserInputService:GetFocusedTextBox() == nil then
			actNow()
		end
	end
	return Enum.ContextActionResult.Sink
end

local function bindSheetInput()
	if inputBound then
		return
	end
	inputBound = true
	ContextActionService:BindActionAtPriority(UseSheet.ACTION, onSheetInput, false, UseSheet.PRIORITY, table.unpack(UseSheet.KEYS))
end

local function unbindSheetInput()
	if inputBound then
		inputBound = false
		ContextActionService:UnbindAction(UseSheet.ACTION)
	end
end

local function applyScale(g: ScreenGui, root: Frame, scale: UIScale)
	local A = g.AbsoluteSize
	local s = if A.X > 0 and A.Y > 0 then math.clamp(math.min(A.X / UseSheet.CANVAS.X, A.Y / UseSheet.CANVAS.Y), 0.5, 1.25) else 1
	scale.Scale = s
	root.Size = UDim2.fromScale(1 / s, 1 / s)
end

function UseSheet.mount(playerGui: Instance?)
	local parent = playerGui or Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not parent then
		return
	end
	local old = parent:FindFirstChild("AIEmpire_ShopSheet")
	if old then
		old:Destroy()
	end
	local g = Instance.new("ScreenGui")
	g.Name = "AIEmpire_ShopSheet"
	g.ResetOnSpawn = false
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	g.DisplayOrder = UseSheet.ORDER
	g.Enabled = false
	g.Parent = parent
	gui = g
	local root = Kit.frame(g)
	root.Name = "Root"
	local scale = Instance.new("UIScale")
	scale.Parent = root
	g:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		applyScale(g, root, scale)
	end)
	applyScale(g, root, scale)

	-- dim 62 % (taps on it do nothing: the sheet is answered with its buttons; no accidental use)
	local dim = Kit.blocker(root, C.black, 0.38)
	dim.Name = "SheetDim"
	dim.Selectable = false
	shade = dim

	local panel = Kit.panel(root, UDim2.fromOffset(UseSheet.WIDTH, 0), UDim2.fromScale(0.5, 0.5))
	panel.Name = "UseSheet"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.ZIndex = 2
	panel.Active = true
	-- gamepad: the selection stays on the card's two buttons
	panel.SelectionGroup = true
	panel.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	Kit.padding(panel, 22, 26, 22, 26)
	Kit.list(panel, 12)
	card = panel

	local head = Kit.frame(panel, UDim2.new(1, 0, 0, 76))
	head.Name = "Head"
	head.LayoutOrder = 1
	local tile = Kit.frame(head, UDim2.fromOffset(76, 76))
	tile.BackgroundTransparency = 0
	tile.BackgroundColor3 = C.raised
	Kit.corner(tile, 14)
	Kit.stroke(tile, 0.85)
	iconHolder = tile
	local t = Kit.text(head, "", 32, F.display, C.text)
	t.Name = "Title"
	t.AutomaticSize = Enum.AutomaticSize.None
	t.Size = UDim2.new(1, -96, 0, 40)
	t.Position = UDim2.fromOffset(96, 2)
	t.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel = t
	local sub = Kit.text(head, "", 22, F.medium, C.muted)
	sub.Name = "Sub"
	sub.AutomaticSize = Enum.AutomaticSize.None
	sub.Size = UDim2.new(1, -96, 0, 28)
	sub.Position = UDim2.fromOffset(96, 44)
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	subLabel = sub

	local rows = Kit.frame(panel, UDim2.fromScale(1, 0))
	rows.Name = "Rows"
	rows.LayoutOrder = 2
	rows.AutomaticSize = Enum.AutomaticSize.Y
	Kit.list(rows, 0)
	rowsFrame = rows

	local buttons = Kit.frame(panel, UDim2.new(1, 0, 0, 74))
	buttons.Name = "Buttons"
	buttons.LayoutOrder = 3
	-- CANCEL (secondary) and the action (primary, 1.4x wider), 74 px tall
	local gap = 14
	local cancel = Kit.button(buttons, "CANCEL", "secondary", UDim2.new(1 / 2.4, -gap / 2, 1, 0))
	cancel.Name = "SheetCancel"
	cancel.TextSize = 26
	cancel.Selectable = true
	cancelButton = cancel
	local action = Kit.button(buttons, "", "primary", UDim2.new(1.4 / 2.4, -gap / 2, 1, 0))
	action.Name = "SheetAction"
	action.AnchorPoint = Vector2.new(1, 0)
	action.Position = UDim2.fromScale(1, 0)
	action.TextSize = 26
	action.Selectable = true
	actionButton = action
	Kit.onClick(cancel, cancelNow)
	Kit.onClick(action, actNow)
end

local function row(parent: Instance, index: number, r: Row)
	local f = Kit.frame(parent, UDim2.fromScale(1, 0))
	f.Name = "Row" .. index
	f.LayoutOrder = index
	f.AutomaticSize = Enum.AutomaticSize.Y
	local line = Kit.divider(f)
	line.Position = UDim2.fromOffset(0, 0)
	local cap = Kit.text(f, string.upper(r.caption), 21, F.bold, C.muted)
	cap.Name = "Caption"
	cap.AutomaticSize = Enum.AutomaticSize.None
	cap.Size = UDim2.fromOffset(190, 46)
	cap.Position = UDim2.fromOffset(0, 1)
	local value = Kit.text(f, "", 23, F.medium, C.text)
	value.Name = "Value"
	value.RichText = true
	value.AutomaticSize = Enum.AutomaticSize.Y
	value.TextWrapped = true
	value.Size = UDim2.new(1, -200, 0, 0)
	value.Position = UDim2.fromOffset(200, 10)
	local tail = if r.tail and r.tail ~= "" then ` <font color="#{C.muted:ToHex()}" size="22">· {Kit.escape(r.tail)}</font>` else ""
	value.Text = Kit.escape(r.value) .. tail
	-- the row is at least 46 px tall; a 2-line value grows it (padding below the value)
	local min = Instance.new("UISizeConstraint")
	min.MinSize = Vector2.new(0, 46)
	min.Parent = f
	local bottom = Instance.new("UIPadding")
	bottom.PaddingBottom = UDim.new(0, 10)
	bottom.Parent = f
end

function UseSheet.open(spec: Spec)
	if not gui then
		UseSheet.mount(nil)
	end
	local g, rows, t, sub, tile, action, cancel = gui, rowsFrame, titleLabel, subLabel, iconHolder, actionButton, cancelButton
	if not g or not rows or not t or not sub or not tile or not action or not cancel then
		return
	end
	current = spec
	busy = false
	t.Text = spec.title
	sub.Text = spec.sub or ""
	sub.Visible = spec.sub ~= nil and spec.sub ~= ""
	t.Position = UDim2.fromOffset(96, if sub.Visible then 2 else 18)
	for _, child in tile:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local icon = Kit.icon(tile, spec.icon or "shop", 44)
	icon.frame.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.frame.Position = UDim2.fromScale(0.5, 0.5)
	icon.setColor(C.warn)
	for _, child in rows:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for i, r in spec.rows do
		row(rows, i, r)
	end
	action.Text = spec.action
	cancel.Text = spec.cancel or "CANCEL"
	Kit.setDisabled(action, false)
	g.Enabled = true
	bindSheetInput()
	if padActive() then
		local selected = GuiService.SelectedObject
		if selected and not g:IsAncestorOf(selected) then
			returnTo = selected
		end
		GuiService.SelectedObject = action
	end
end

function UseSheet.setBusy(on: boolean)
	busy = on
	local action = actionButton
	if action then
		Kit.setDisabled(action, on)
	end
end

function UseSheet.close()
	current = nil
	busy = false
	unbindSheetInput()
	local g = gui
	if g then
		g.Enabled = false
		local selected = GuiService.SelectedObject
		if selected and g:IsAncestorOf(selected) then
			-- give the selection back when that button is still on screen (else nothing: the page picks its own)
			local back = returnTo
			local shown = back ~= nil and back.Parent ~= nil and back.Visible
			GuiService.SelectedObject = if shown then back else nil
		end
	end
	returnTo = nil
end

function UseSheet.isOpen(): boolean
	local g = gui
	return g ~= nil and g.Enabled and current ~= nil
end

-- tests / previews
function UseSheet.frame(): Frame?
	return card
end
function UseSheet.spec(): Spec?
	return current
end

local _ = shade
return UseSheet
