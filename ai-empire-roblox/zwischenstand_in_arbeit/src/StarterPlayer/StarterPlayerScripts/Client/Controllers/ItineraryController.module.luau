--!strict
-- ItineraryController (package "itinerary", client): what the founder and the players near him see of a business trip.
-- Main.client requires it and calls init() after PhoneController.init. Everything here is local; the server publishes
-- the state once per change (Notify "ITINERARY", Player attribute "Itinerary", ReplicatedStorage.CompanyItinerary).
--   * the itinerary banner (own trip only): top left, below the Roblox top bar, sliding under the drivers' ride panel /
--     the toasts when they overlap. Title, the plan line, a live timer (computed here from the server time it got:
--     "Boarding ends in 2:10"), progress dots for the steps, buttons from the server (Go / Not now / Cancel trip / Fly
--     home now / Call car now -> TripAction). Cancel trip and Fly home now ask "Sure?" first. The auto-trip countdown
--     ("Leaving in 7 s", a shrinking bar, Go now / Not this time). A collapse button keeps a chip: icon, title and the
--     step's one-line action ("Press Start meeting at the table") with its timer, else the timer, else the progress
--     dots. Touch: 44 pt targets on phone-sized screens (scale < COMPACT); gamepad: the buttons are Selectable.
--   * the beacon: a light column + distance label at the step's target (gate A1, the VIP stand, the meeting table, the
--     hotel reception, the boarding point home), hidden when the founder stands next to it.
--   * the companions (every client, within FOLLOW_NEAR of the camera, at most MAX_FOLLOWERS rigs in all): clones of the
--     real field rep / engineer templates walk behind the founder along his own trail (he went through those doors; the
--     height of each trail point + a ground ray at 2 Hz, so nobody floats on stairs or kerbs) whenever the server says
--     they are with him (attribute With, from ShowAt) and he is not held by a car or a flight (anchored). They fade in;
--     when they leave they fade out - at gate A1 during the boarding they walk the shuttle's boarding path into the
--     cabin (ShuttlePassengers.path) instead.
--   * the client team: while MeetingOn, two clones sit at the client office's meeting table (ItineraryMath.seatsFor:
--     the far chairs, the outer near chairs for a second founder's team - SeatSet) near the camera, talking once the
--     founder joined; at most MAX_TEAM_RIGS.
--   * LOD: full pose rate within POSE_NEAR studs of the camera, POSE_MID_HZ up to POSE_FAR, beyond only the root moves.
-- No animation assets (EmployeeController's procedural Motor6D poses), no physics, no network per frame.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local IM = require(Shared.ItineraryMath)
local FP = require(Shared.FlightPlan)
local Net = require(Shared.Net)
local Pax = require(script.Parent.ShuttlePassengers)
local State = require(script.Parent.StateController)
local Employee = require(script.Parent.EmployeeController)
local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Toast = require(UI.Toast)
local PhoneKit = require(UI.Phone.PhoneKit)

local C = Theme.colors
local F = Theme.font

local Controller = {}
Controller.ORDER = 23 -- above the HUD (10) and the guide (22), below the drivers' ride panel (24) and the open phone (28)
Controller.COMPACT = 0.9 -- UI scale below which the touch targets grow (72 design px = 44.6 pt at the 0.62 floor)
Controller.FOLLOW_NEAR = 220 -- companions are drawn within this distance of the camera
Controller.MAX_FOLLOWERS = 6 -- companion rigs drawn at once (all founders together)
Controller.MAX_TEAM_RIGS = 4 -- client team rigs drawn at once
Controller.CLIENTS_NEAR = 160 -- the client team is drawn within this distance of the camera
Controller.GAP = 3.4 -- studs between the founder and each companion along his trail
Controller.SPEED = 18 -- studs per second a companion catches up at most
Controller.TELEPORT = 45 -- further behind than this: the companion is put next to the founder
Controller.TRAIL_STEP = 1.2
Controller.TRAIL_MAX = 48
Controller.BEACON_HIDE = 9
Controller.CONFIRM = 3 -- seconds a "Sure?" button waits for the second tap
Controller.FADE_IN = 0.6 -- seconds a companion / client NPC takes to appear ...
Controller.FADE_OUT = 0.8 -- ... and to disappear (never popping in / out in front of the player)
Controller.BOARD_SPEED = 6 -- studs per second along the shuttle's boarding path
Controller.BOARD_MAX = 20 -- seconds a boarding walk may take at most
Controller.GROUND_HZ = 2 -- ground rays per second and companion
Controller.POSE_NEAR = 40
Controller.POSE_FAR = 120
Controller.POSE_MID_HZ = 24

local player = Players.LocalPlayer
local view: { [string]: any }? = nil
local collapsed = false
local userToggled: string? = nil -- the state the player folded / unfolded the banner in (his choice wins there)
local toggledSeq: any = nil -- ... for this trip only (a new trip starts with the defaults again)

------------------------------------------------------------------------------------------------ helpers
local function now(): number
	return workspace:GetServerTimeNow()
end
local function remote(): RemoteFunction?
	local ok, fn = pcall(function() return Net.getFunction("TripAction") end)
	return if ok then fn else nil
end
local function invoke(payload: { [string]: any }): { [string]: any }
	local fn = remote()
	if not fn then return { ok = false, err = "LOADING" } end
	local ok, res = pcall(function() return fn:InvokeServer(payload) end)
	if not ok or typeof(res) ~= "table" then return { ok = false, err = "SERVER_ERROR" } end
	return res
end
Controller._invoke = invoke
local MESSAGES: { [string]: string } = {
	NO_TRIP = "There is no business trip right now.",
	TRIP_OVER = "That visit is already over.",
	ALREADY_TRAVELLING = "You're already on a business trip.",
	ALREADY_RIDING = "Your car is already booked.",
	FLYING = "You're in the air right now.",
	TOO_FAR = "Walk to a pick-up point first: your HQ entrance, the airport kerb, a client office or the hotel.",
	NO_DRIVER = "No company driver can come right now.",
	RATE_LIMIT = "One moment please.",
	LOADING = "Still loading - try again in a moment.",
}
local function message(res: { [string]: any }): string
	if typeof(res.text) == "string" then return res.text end
	local err = if typeof(res.err) == "string" then res.err else ""
	return MESSAGES[err] or "That didn't work - try again in a moment."
end
local function rootOf(who: Player?): BasePart?
	local character = if who then who.Character else nil
	local r = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if r and r:IsA("BasePart") then r else nil
end
local function camPos(): Vector3
	local cam = workspace.CurrentCamera
	return if cam then cam.CFrame.Position else Vector3.zero
end

------------------------------------------------------------------------------------------------ banner
type Btn = { button: TextButton, id: string, confirmUntil: number }
type Banner = {
	gui: ScreenGui, root: Frame, scale: UIScale, panel: Frame, icon: Frame, glyph: Frame?, glyphKind: string, title: TextLabel, line: TextLabel,
	action: TextLabel, timer: TextLabel, dots: Frame, stepText: TextLabel, bar: Kit.Bar, buttons: { Btn }, collapse: TextButton, compact: boolean,
	folded: boolean, chipTimer: boolean, top: number, key: string,
}
local banner: Banner? = nil
local busy = false
local function bannerScale(gui: ScreenGui): number
	local h = gui.AbsoluteSize.Y
	if h <= 0 then
		local cam = workspace.CurrentCamera
		h = if cam then cam.ViewportSize.Y else 0
	end
	if h <= 0 then return 1 end
	return math.clamp(h / 600, 0.62, 1.2)
end
Controller.bannerScale = bannerScale
-- design-px sizes: normal / compact (phone-sized screens)
local function metrics(compact: boolean): { [string]: number }
	if compact then return { w = 470, chip = 470, icon = 54, title = 22, line = 18, timer = 20, btn = 72, btnText = 20, gap = 8, pad = 14, dot = 10, small = 16, act = 18 } end
	return { w = 380, chip = 350, icon = 44, title = 18, line = 15, timer = 16, btn = 44, btnText = 16, gap = 8, pad = 12, dot = 8, small = 13, act = 15 }
end
Controller.metrics = metrics
local ICON_COLOR: { [string]: Color3 } = {
	driver = Color3.fromRGB(236, 160, 64), map = Color3.fromRGB(64, 156, 236), team = Color3.fromRGB(129, 204, 162),
	desk = Color3.fromRGB(196, 170, 120), assistant = Color3.fromRGB(214, 120, 170), calendar = Color3.fromRGB(120, 200, 174),
}
local function closeBanner()
	if banner then banner.gui:Destroy(); banner = nil end
end
local layoutBanner: (b: Banner) -> ()
local function act(id: string)
	if busy then return end
	local v = view
	if not v then return end
	local payload: { [string]: any } = { action = if id == "decline" then "cancel" else id }
	if id == "go" and typeof(v.key) == "string" then payload.key = v.key end
	busy = true
	task.spawn(function()
		local res = invoke(payload)
		busy = false
		if not res.ok then
			Toast.show("error", message(res))
		elseif typeof(res.text) == "string" and id ~= "status" then
			Toast.show("success", res.text, 5)
		end
	end)
end
local function ensureBanner(): Banner?
	if banner then return banner end
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return nil end
	local gui = Instance.new("ScreenGui")
	gui.Name = "ItineraryBanner"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = Controller.ORDER
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local rootFrame = Instance.new("Frame")
	rootFrame.Name = "Root"
	rootFrame.BackgroundTransparency = 1
	rootFrame.Size = UDim2.fromScale(1, 1)
	rootFrame.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = rootFrame
	local panel = Kit.panel(rootFrame, UDim2.fromOffset(380, 150), UDim2.fromOffset(12, 10))
	panel.Name = "TripPanel"
	panel.BackgroundTransparency = 0.04
	local icon = Kit.frame(panel, UDim2.fromOffset(44, 44), UDim2.fromOffset(12, 12))
	icon.Name = "Icon"
	icon.BackgroundTransparency = 0
	icon.BackgroundColor3 = ICON_COLOR.calendar
	Kit.corner(icon, 22)
	local title = Kit.text(panel, "", 18, F.bold, C.text)
	title.Name = "Title"
	title.AutomaticSize = Enum.AutomaticSize.None
	title.TextTruncate = Enum.TextTruncate.AtEnd
	local dots = Kit.frame(panel, UDim2.fromOffset(200, 10))
	dots.Name = "Dots"
	local stepText = Kit.text(panel, "", 13, F.medium, C.muted)
	stepText.Name = "StepText"
	stepText.AutomaticSize = Enum.AutomaticSize.None
	stepText.TextTruncate = Enum.TextTruncate.AtEnd
	local line = Kit.text(panel, "", 15, F.regular, C.muted)
	line.Name = "Line"
	line.AutomaticSize = Enum.AutomaticSize.None
	line.TextWrapped = true
	line.TextYAlignment = Enum.TextYAlignment.Top
	line.TextTruncate = Enum.TextTruncate.AtEnd
	local action = Kit.text(panel, "", 15, F.medium, C.text)
	action.Name = "Action"
	action.AutomaticSize = Enum.AutomaticSize.None
	action.TextTruncate = Enum.TextTruncate.AtEnd
	action.Visible = false
	local timer = Kit.text(panel, "", 16, F.bold, C.text)
	timer.Name = "Timer"
	timer.AutomaticSize = Enum.AutomaticSize.None
	Theme.bindAccent(timer, "TextColor3")
	local bar = Kit.bar(panel, 6)
	bar.frame.Name = "Countdown"
	bar.frame.Visible = false
	local collapse = Kit.button(panel, "–", "ghost", UDim2.fromOffset(32, 32))
	collapse.Name = "Collapse"
	collapse.AnchorPoint = Vector2.new(1, 0)
	collapse.Selectable = true
	collapse.TextSize = 20
	Kit.onClick(collapse, function()
		local b = banner
		local v = view
		if not b or not v then return end
		collapsed = not b.folded
		userToggled = v.state
		toggledSeq = v.seq
		b.key = ""
		layoutBanner(b)
	end)
	gui.Parent = pg
	local b: Banner = { gui = gui, root = rootFrame, scale = scale, panel = panel, icon = icon, glyph = nil, glyphKind = "", title = title, line = line,
		action = action, timer = timer, dots = dots, stepText = stepText, bar = bar, buttons = {}, collapse = collapse, compact = false, folded = false,
		chipTimer = false, top = 10, key = "" }
	banner = b
	return b
end
-- the dots of the steps (done / current / to come)
local function drawDots(b: Banner, step: number, steps: number, mtr: { [string]: number })
	local n = math.max(0, math.min(steps, 9))
	local kids = b.dots:GetChildren()
	if #kids ~= n then
		b.dots:ClearAllChildren()
		for i = 1, n do
			local d = Kit.frame(b.dots, UDim2.fromOffset(mtr.dot, mtr.dot), UDim2.fromOffset((i - 1) * (mtr.dot + 6), 0))
			d.Name = "Dot" .. i
			d.BackgroundTransparency = 0
			Kit.corner(d, math.ceil(mtr.dot / 2))
		end
	end
	for i = 1, n do
		local d = b.dots:FindFirstChild("Dot" .. i)
		if d and d:IsA("Frame") then
			d.Size = UDim2.fromOffset(mtr.dot, mtr.dot)
			d.Position = UDim2.fromOffset((i - 1) * (mtr.dot + 6), 0)
			d.BackgroundColor3 = if i < step then C.muted elseif i == step then Theme.accent else C.raised
		end
	end
	b.dots.Size = UDim2.fromOffset(math.max(1, n * (mtr.dot + 6)), mtr.dot)
end
-- Collapsed = one chip (icon, title, the timer or the progress dots). On a phone-sized screen a step that needs no
-- decision starts collapsed (the player taps + for the details and the buttons); offers / the countdown never do.
-- While the drivers' ride panel is on screen (it carries the car's own Cancel) the banner folds too, so the player never
-- sees two cancel buttons stacked.
local rideShown = false
local function isCollapsed(b: Banner, v: { [string]: any }): boolean
	if v.state == "offer" or v.state == "countdown" then return false end
	if userToggled == v.state then return collapsed end
	return b.compact or rideShown
end
local function ridePanelShown(): boolean
	local pg = player:FindFirstChild("PlayerGui")
	local drive = pg and pg:FindFirstChild("DriveHUD")
	if not drive or (drive:IsA("ScreenGui") and not drive.Enabled) then return false end
	local panel = drive:FindFirstChild("RidePanel", true)
	if not panel or not panel:IsA("GuiObject") or not panel.Visible then return false end
	local s = panel.AbsoluteSize
	return s.X >= 4 and s.Y >= 4
end
layoutBanner = function(b: Banner)
	local v = view
	if not v then return end
	local mtr = metrics(b.compact)
	local folded = isCollapsed(b, v)
	local buttons: { any } = if typeof(v.buttons) == "table" then v.buttons else {}
	local key = table.concat({ tostring(v.title), tostring(v.line), tostring(v.action), tostring(v.state), tostring(v.icon), tostring(v.step), tostring(v.steps),
		tostring(#buttons), tostring(folded), tostring(b.compact), tostring(typeof(v.timerAt) == "number") }, "|")
	for _, bt in buttons do key ..= "|" .. tostring(bt.id) .. tostring(bt.text) end
	if key == b.key then return end
	b.key = key
	b.folded = folded
	local w = if folded then mtr.chip else mtr.w
	local pad = mtr.pad
	b.icon.Size = UDim2.fromOffset(mtr.icon, mtr.icon)
	b.icon.Position = UDim2.fromOffset(pad, pad)
	Kit.corner(b.icon, math.floor(mtr.icon / 2))
	local kind = if typeof(v.icon) == "string" then v.icon else "calendar"
	if kind ~= b.glyphKind or not b.glyph then
		if b.glyph then b.glyph:Destroy() end
		local g = PhoneKit.glyph(b.icon, kind, math.floor(mtr.icon * 0.62))
		g.AnchorPoint = Vector2.new(0.5, 0.5)
		g.Position = UDim2.fromScale(0.5, 0.5)
		b.glyph = g
		b.glyphKind = kind
		b.icon.BackgroundColor3 = ICON_COLOR[kind] or ICON_COLOR.calendar
	end
	local left = pad + mtr.icon + 12
	local collapseW = if b.compact then 56 else 32
	local canFold = v.state ~= "offer" and v.state ~= "countdown"
	b.collapse.Visible = canFold
	b.collapse.Size = UDim2.fromOffset(collapseW, collapseW)
	b.collapse.Position = UDim2.new(1, -8, 0, 8)
	b.collapse.Text = if folded then "+" else "–"
	b.title.Text = tostring(v.title or "")
	b.title.TextSize = mtr.title
	b.title.Position = UDim2.fromOffset(left, pad - 2)
	b.title.Size = UDim2.fromOffset(w - left - (if canFold then collapseW + 14 else 8), mtr.title + 6)
	local hasTimer = typeof(v.timerAt) == "number"
	local actionText = if typeof(v.action) == "string" then v.action else ""
	local steps = tonumber(v.steps) or 0
	local step = tonumber(v.step) or 0
	local showDots = steps > 0 and v.state ~= "offer" and v.state ~= "countdown"
	drawDots(b, step, steps, mtr)
	local row2 = pad + mtr.title + 10
	b.dots.Position = UDim2.fromOffset(left, row2 + 3)
	-- the folded chip's second row: the action (+ its timer at the right), else the timer, else the progress dots
	b.dots.Visible = showDots and not (folded and (hasTimer or actionText ~= ""))
	b.action.Visible = false
	b.chipTimer = false
	b.stepText.Visible = showDots and not folded
	b.stepText.TextSize = mtr.small
	b.stepText.Text = string.format("%d of %d · %s", step, steps, tostring(v.stepName or ""))
	b.stepText.Position = UDim2.fromOffset(left + steps * (mtr.dot + 6) + 6, row2 - 2)
	b.stepText.Size = UDim2.fromOffset(w - left - steps * (mtr.dot + 6) - pad - 6, mtr.small + 6)
	b.line.Visible = not folded
	b.timer.Visible = false
	b.bar.frame.Visible = false
	for _, bt in b.buttons do bt.button:Destroy() end
	table.clear(b.buttons)
	local y: number
	if folded then
		-- row 2 ends left of the "+" button (it reaches down into this row)
		local rowEnd = w - (if canFold then collapseW + 14 else pad)
		local timerW = if hasTimer and actionText ~= "" then math.floor(mtr.timer * 3) else 0
		if actionText ~= "" then
			b.action.Visible = true
			b.action.Text = actionText
			b.action.TextSize = mtr.act
			b.action.Position = UDim2.fromOffset(left, row2 - 2)
			b.action.Size = UDim2.fromOffset(rowEnd - left - timerW - (if timerW > 0 then 6 else 0), mtr.act + 6)
		end
		if hasTimer then
			b.timer.Visible = true
			b.timer.TextSize = mtr.timer
			b.chipTimer = actionText ~= ""
			b.timer.TextXAlignment = if b.chipTimer then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
			b.timer.Position = if b.chipTimer then UDim2.fromOffset(rowEnd - timerW, row2 - 2) else UDim2.fromOffset(left, row2 - 2)
			b.timer.Size = if b.chipTimer then UDim2.fromOffset(timerW, mtr.timer + 4) else UDim2.fromOffset(rowEnd - left, mtr.timer + 4)
		end
		y = pad + mtr.icon + pad
	else
		y = pad + mtr.icon + 10
		b.line.Text = tostring(v.line or "")
		b.line.TextSize = mtr.line
		b.line.Position = UDim2.fromOffset(pad, y)
		local lineH = math.floor(mtr.line * 2.5)
		b.line.Size = UDim2.fromOffset(w - 2 * pad, lineH)
		y += lineH + 4
		local countdown = v.state == "countdown"
		if countdown then
			b.bar.frame.Visible = true
			b.bar.frame.Position = UDim2.fromOffset(pad, y)
			b.bar.frame.Size = UDim2.fromOffset(w - 2 * pad, 6)
			y += 14
		end
		-- the timer shares the button row when there is one button (it stands left of it)
		local n = #buttons
		local timerBeside = hasTimer and n == 1
		if hasTimer then
			b.timer.Visible = true
			b.timer.TextXAlignment = Enum.TextXAlignment.Left
			b.timer.TextSize = mtr.timer
			if timerBeside then
				b.timer.Position = UDim2.fromOffset(pad, y + math.floor((mtr.btn - mtr.timer - 4) / 2))
				b.timer.Size = UDim2.fromOffset(math.floor((w - 2 * pad) * 0.56) - mtr.gap, mtr.timer + 4)
			else
				b.timer.Position = UDim2.fromOffset(pad, y)
				b.timer.Size = UDim2.fromOffset(w - 2 * pad, mtr.timer + 4)
				y += mtr.timer + 8
			end
		end
		if n > 0 then
			local rowX = pad
			local rowW = w - 2 * pad
			if n == 1 then
				-- one button: the right part of the row (less shouting than a full-width red bar)
				rowW = math.floor((w - 2 * pad) * 0.44)
				rowX = w - pad - rowW
			end
			local bw = math.floor((rowW - (n - 1) * mtr.gap) / n)
			for i, bt in buttons do
				local id = tostring(bt.id)
				local style: Kit.ButtonStyle = if id == "go" then "primary" elseif id == "decline" then "ghost" elseif id == "cancel" then "danger" else "secondary"
				local button = Kit.button(b.panel, tostring(bt.text or id), style, UDim2.fromOffset(bw, mtr.btn))
				button.Name = "Btn_" .. id
				button.Position = UDim2.fromOffset(rowX + (i - 1) * (bw + mtr.gap), y)
				button.TextSize = mtr.btnText
				button.Selectable = true
				local entry: Btn = { button = button, id = id, confirmUntil = 0 }
				table.insert(b.buttons, entry)
				Kit.onClick(button, function()
					-- leaving the trip asks once more (an accidental tap on the phone is easy)
					if (id == "cancel" or id == "leave") and v.state ~= "offer" and v.state ~= "countdown" then
						if os.clock() > entry.confirmUntil then
							entry.confirmUntil = os.clock() + Controller.CONFIRM
							button.Text = "Sure? Tap again"
							task.delay(Controller.CONFIRM, function()
								if button.Parent and os.clock() >= entry.confirmUntil then button.Text = tostring(bt.text or id) end
							end)
							return
						end
					end
					act(id)
				end)
			end
			y += mtr.btn
		end
		y += pad
	end
	b.panel.Size = UDim2.fromOffset(w, math.max(y, pad + mtr.icon + pad))
end
-- the banner slides below the drivers' ride panel and the toasts when they overlap it (all AbsolutePositions share one
-- screen space whatever insets the ScreenGuis use)
local function avoidTop(b: Banner): number
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return 10 end
	local scale = b.scale.Scale
	local rootY = b.root.AbsolutePosition.Y
	local x0 = b.panel.AbsolutePosition.X
	local x1 = x0 + b.panel.AbsoluteSize.X
	local top = 10
	local function avoid(obj: Instance?)
		if not obj or not obj:IsA("GuiObject") or not obj.Visible then return end
		local gui = obj:FindFirstAncestorOfClass("ScreenGui")
		if gui and not gui.Enabled then return end
		local p, s = obj.AbsolutePosition, obj.AbsoluteSize
		if s.X < 4 or s.Y < 4 then return end
		if p.X > x1 or p.X + s.X < x0 then return end
		top = math.max(top, (p.Y + s.Y - rootY + 8) / math.max(scale, 0.1))
	end
	local drive = pg:FindFirstChild("DriveHUD")
	if drive then avoid(drive:FindFirstChild("RidePanel", true)) end
	local topLayer = pg:FindFirstChild("AIEmpire_Top")
	if topLayer then avoid(topLayer:FindFirstChild("Toasts", true)) end
	return top
end
Controller._avoidTop = function(): number
	local b = banner
	return if b then avoidTop(b) else 0
end
local function updateBanner()
	local v = view
	if not v or v.closed then closeBanner(); return end
	local b = ensureBanner()
	if not b then return end
	local sc = bannerScale(b.gui)
	if sc ~= b.scale.Scale then
		b.scale.Scale = sc
		b.root.Size = UDim2.fromScale(1 / sc, 1 / sc)
	end
	local compact = sc < Controller.COMPACT
	if compact ~= b.compact then b.compact = compact; b.key = "" end
	local ride = ridePanelShown()
	if ride ~= rideShown then rideShown = ride; b.key = "" end
	layoutBanner(b)
	-- live timer / countdown from the server times in the view
	local t = now()
	if b.timer.Visible and typeof(v.timerAt) == "number" then
		b.timer.Text = if b.chipTimer then IM.mmss(v.timerAt - t) else tostring(v.timerLabel or "") .. " " .. IM.mmss(v.timerAt - t)
	end
	if v.state == "countdown" and typeof(v.countdownEnd) == "number" then
		local left = math.max(0, v.countdownEnd - t)
		b.bar.set(left / IM.COUNTDOWN)
		if b.timer.Visible then b.timer.Text = "Leaving in " .. math.ceil(left) .. " s" end
	end
	local top = avoidTop(b)
	if math.abs(top - b.top) > 0.5 then
		b.top = top
		b.panel.Position = UDim2.fromOffset(12, top)
	end
end

------------------------------------------------------------------------------------------------ beacon
type Beacon = { folder: Folder, part: Part, label: TextLabel, gui: BillboardGui, target: Vector3, name: string }
local beacon: Beacon? = nil
local function clearBeacon()
	if beacon then beacon.folder:Destroy(); beacon = nil end
end
local function setBeacon(target: any)
	if typeof(target) ~= "table" or typeof(target.pos) ~= "Vector3" then clearBeacon(); return end
	local pos: Vector3 = target.pos
	local name = if typeof(target.label) == "string" then target.label else "Destination"
	local b = beacon
	if b and (b.target - pos).Magnitude < 0.5 and b.name == name then return end
	clearBeacon()
	local folder = Instance.new("Folder")
	folder.Name = "ItineraryBeacon"
	local part = Instance.new("Part")
	part.Name = "Beacon"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(40, 1.6, 1.6)
	part.CFrame = CFrame.new(pos.X, pos.Y + 17, pos.Z) * CFrame.Angles(0, 0, math.pi / 2)
	part.Material = Enum.Material.Neon
	part.Transparency = 0.45
	part.Color = Theme.accent
	part.Parent = folder
	local gui = Instance.new("BillboardGui")
	gui.Name = "BeaconLabel"
	gui.Size = UDim2.fromOffset(240, 46)
	gui.AlwaysOnTop = true
	gui.StudsOffsetWorldSpace = Vector3.new(0, 23, 0)
	gui.Adornee = part
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.35
	label.Font = F.bold
	label.TextScaled = true
	label.Text = name
	label.Parent = gui
	folder.Parent = workspace
	beacon = { folder = folder, part = part, label = label, gui = gui, target = pos, name = name }
end
local function updateBeacon()
	local b = beacon
	if not b then return end
	local r = rootOf(player)
	if not r then return end
	local d = Vector3.new(r.Position.X - b.target.X, 0, r.Position.Z - b.target.Z).Magnitude
	local near = d <= Controller.BEACON_HIDE and math.abs(r.Position.Y - b.target.Y) < 12
	b.part.Transparency = if near then 1 else 0.45
	b.gui.Enabled = not near
	b.label.Text = b.name .. "\n" .. math.floor(d + 0.5) .. " studs"
end

------------------------------------------------------------------------------------------------ rigs
type Rig = { model: Model, root: BasePart, joints: { [string]: Motor6D }, parts: { BasePart }, seed: number, pos: Vector3, look: Vector3, alpha: number,
	groundY: number?, groundAt: number, poseAt: number, path: { Vector3 }?, walked: number }
local function cloneRig(template: Instance, parent: Instance): Rig?
	if not template:IsA("Model") then return nil end
	local m = template:Clone()
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then hum:Destroy() end
	local r = m:FindFirstChild("HumanoidRootPart")
	if not r or not r:IsA("BasePart") then m:Destroy(); return nil end
	local joints: { [string]: Motor6D } = {}
	local parts: { BasePart } = {}
	for _, d in m:GetDescendants() do
		if d:IsA("Motor6D") then joints[d.Name] = d
		elseif d:IsA("BasePart") then
			d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.Anchored = d == r
			if d ~= r then
				d.LocalTransparencyModifier = 1 -- fades in (setAlpha)
				table.insert(parts, d)
			end
		end
	end
	r.Anchored = true
	m.Parent = parent
	local seed = m:GetAttribute("PersonalitySeed")
	return { model = m, root = r, joints = joints, parts = parts, seed = if typeof(seed) == "number" then seed else 1, pos = r.Position, look = Vector3.new(0, 0, -1),
		alpha = 1, groundY = nil, groundAt = 0, poseAt = 0, path = nil, walked = 0 }
end
-- 0 = fully visible, 1 = hidden (LocalTransparencyModifier: client-local, the clones are client-only anyway)
local function setAlpha(rg: Rig, alpha: number)
	local a = math.clamp(alpha, 0, 1)
	if math.abs(a - rg.alpha) < 0.02 and a ~= 0 and a ~= 1 then return end
	if a == rg.alpha then return end
	rg.alpha = a
	for _, p in rg.parts do p.LocalTransparencyModifier = a end
end
-- pose LOD: every frame near the camera, POSE_MID_HZ further away, not at all beyond POSE_FAR
local function pose(rg: Rig, activity: string, sitting: boolean, walking: boolean, t: number, cam: Vector3)
	local d = (rg.root.Position - cam).Magnitude
	if d > Controller.POSE_FAR then return end
	if d > Controller.POSE_NEAR then
		if t < rg.poseAt then return end
		rg.poseAt = t + 1 / Controller.POSE_MID_HZ
	end
	for name, tr in Employee.pose(activity, sitting, walking, t, rg.seed) do
		local j = rg.joints[name]
		if j and j.Parent then j.Transform = tr end
	end
end
Controller._pose = pose
local clientFolder: Folder? = nil
local function folderOf(): Folder
	local f = clientFolder
	if f and f.Parent then return f end
	local nf = Instance.new("Folder")
	nf.Name = "ItineraryPeople"
	nf.Parent = workspace
	clientFolder = nf
	return nf
end
local rayParams: RaycastParams? = nil
-- the ground under a point (companions never float on stairs / kerbs): root height above the first solid surface,
-- nil when nothing is hit within reach (the trail point's own height is used then)
local function getRayParams(): RaycastParams
	local params = rayParams
	if params then return params end
	local np = RaycastParams.new()
	np.FilterType = Enum.RaycastFilterType.Exclude
	np.IgnoreWater = true
	rayParams = np
	return np
end
local function groundAt(p: Vector3, owner: Model?): number?
	local params = getRayParams()
	local exclude: { Instance } = { folderOf() }
	if owner then table.insert(exclude, owner) end
	local mine = player.Character
	if mine then table.insert(exclude, mine) end
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(p + Vector3.new(0, 2.5, 0), Vector3.new(0, -9, 0), params)
	if not hit then return nil end
	return hit.Position.Y + 3
end
Controller._groundAt = groundAt

------------------------------------------------------------------------------------------------ companions
-- leaving: nil (following) | "fade" | "board" (walking the shuttle's boarding path into the cabin, then gone)
type Group = { owner: number, folder: Instance, rigs: { Rig }, trail: { Vector3 }, leaving: string?, age: number }
local groups: { [number]: Group } = {}
type Team = { owner: number, rigs: { Rig }, key: string, set: number, leaving: boolean, age: number }
local teams: { [number]: Team } = {}
local function dropGroup(uid: number)
	local g = groups[uid]
	if not g then return end
	for _, rg in g.rigs do rg.model:Destroy() end
	groups[uid] = nil
end
local function dropTeam(uid: number)
	local tm = teams[uid]
	if not tm then return end
	for _, rg in tm.rigs do rg.model:Destroy() end
	teams[uid] = nil
end
-- the point `back` studs behind the founder along his trail (the newest point first)
local function trailPoint(trail: { Vector3 }, from: Vector3, back: number): (Vector3, Vector3)
	local prev = from
	local left = back
	for i = #trail, 1, -1 do
		local p = trail[i]
		local seg = (Vector3.new(p.X, 0, p.Z) - Vector3.new(prev.X, 0, prev.Z)).Magnitude
		if seg >= left and seg > 1e-3 then
			local f = left / seg
			local q = prev:Lerp(p, f)
			return q, (prev - p)
		end
		left -= seg
		prev = p
	end
	return prev, (from - prev)
end
Controller.trailPoint = trailPoint
-- The founder just boarded the shuttle at gate A1 (held, folder state airport / flight, boarding open): the shuttle's
-- own boarding path into the cabin (ShuttlePassengers.path), else nil (they fade where they stand).
local function boardingPath(f: Instance?, near: Vector3): { Vector3 }?
	if not f then return nil end
	local state = f:GetAttribute("State")
	if state ~= "airport" and state ~= "flight" then return nil end
	local gate = FP.HOME_GATES[1]
	if not gate or (Vector3.new(near.X - gate.X, 0, near.Z - gate.Z)).Magnitude > FP.GATE_RADIUS + 30 then return nil end
	local ok, pose0, st = pcall(FP.pose, workspace:GetServerTimeNow())
	if not ok or not pose0 or not st or st.dir ~= "out" or st.phase ~= "boarding" then return nil end
	local okP, path = pcall(Pax.path, true, pose0.cf, nil)
	if not okP or typeof(path) ~= "table" or #path < 2 then return nil end
	return path
end
local function leaveGroup(g: Group, how: string)
	if g.leaving then return end
	g.leaving = how
	g.age = 0
	if how == "board" then
		local path = boardingPath(g.folder, if g.rigs[1] then g.rigs[1].pos else Vector3.zero)
		if not path then g.leaving = "fade"; return end
		for _, rg in g.rigs do
			local own = table.clone(path)
			table.insert(own, 1, rg.pos)
			rg.path = own
			rg.walked = 0
		end
	end
end
local spotCache: { [string]: any } = {}
local function spotOf(key: string): IM.MeetingSpot?
	local c = spotCache[key]
	if c == nil then
		c = IM.meetingSpot(key) or false
		spotCache[key] = c
	end
	return if c then c else nil
end
local function wanted(): ({ [number]: Instance }, { [number]: Instance })
	local follow: { [number]: Instance } = {}
	local meet: { [number]: Instance } = {}
	local root = ReplicatedStorage:FindFirstChild("CompanyItinerary")
	if not root then return follow, meet end
	local t = now()
	local cam = camPos()
	local rigs, teamRigs = 0, 0
	for _, f in root:GetChildren() do
		local uid = f:GetAttribute("Owner")
		if typeof(uid) ~= "number" then continue end
		local owner = Players:GetPlayerByUserId(uid)
		local r = rootOf(owner)
		local showAt = f:GetAttribute("ShowAt")
		if f:GetAttribute("With") == true and r and not r.Anchored and (typeof(showAt) ~= "number" or t >= showAt)
			and (r.Position - cam).Magnitude <= Controller.FOLLOW_NEAR then
			local n = 0
			for _, c in f:GetChildren() do if string.match(c.Name, "^Companion%d$") then n += 1 end end
			-- the cap counts rigs, not founders (a group already drawn keeps its place)
			if groups[uid] and not groups[uid].leaving or rigs + n <= Controller.MAX_FOLLOWERS then
				follow[uid] = f
				rigs += n
			end
		end
		if f:GetAttribute("MeetingOn") == true then
			local key = f:GetAttribute("ClientKey")
			local spot = if typeof(key) == "string" then spotOf(key) else nil
			local seats = if spot then IM.seatsFor(spot, f:GetAttribute("SeatSet")) else {}
			if spot and #seats > 0 and (spot.table.Position - cam).Magnitude <= Controller.CLIENTS_NEAR and teamRigs + #seats <= Controller.MAX_TEAM_RIGS then
				meet[uid] = f
				teamRigs += #seats
			end
		end
	end
	return follow, meet
end
local function refreshPeople()
	local t = now()
	local follow, meet = wanted()
	local cam = camPos()
	for uid, g in groups do
		if follow[uid] and g.folder == follow[uid] and not g.leaving then continue end
		if g.leaving then continue end
		-- out of reach of the camera: gone at once (nobody sees it); else they leave visibly
		local near = g.rigs[1] ~= nil and (g.rigs[1].pos - cam).Magnitude <= Controller.FOLLOW_NEAR
		local f = g.folder
		local owner = Players:GetPlayerByUserId(uid)
		local r = rootOf(owner)
		if not near or not f.Parent then
			if not near then dropGroup(uid) else leaveGroup(g, "fade") end
		elseif r and r.Anchored and boardingPath(f, g.rigs[1].pos) then
			leaveGroup(g, "board")
		else
			leaveGroup(g, "fade")
		end
	end
	for uid, f in follow do
		local g: Group? = groups[uid]
		if g and (g.folder ~= f or g.leaving) then
			dropGroup(uid)
			g = nil
		end
		if not g then
			local owner = Players:GetPlayerByUserId(uid)
			local r = rootOf(owner)
			if not r then continue end
			local ng: Group = { owner = uid, folder = f, rigs = {}, trail = { r.Position }, leaving = nil, age = 0 }
			local i = 0
			for _, tpl in f:GetChildren() do
				if string.match(tpl.Name, "^Companion%d$") then
					local rg = cloneRig(tpl, folderOf())
					if rg then
						i += 1
						local back = r.CFrame * Vector3.new(i % 2 == 1 and 2.2 or -2.2, 0, Controller.GAP * i)
						rg.pos = Vector3.new(back.X, r.Position.Y, back.Z)
						rg.root.CFrame = CFrame.lookAt(rg.pos, rg.pos + r.CFrame.LookVector)
						table.insert(ng.rigs, rg)
					end
				end
			end
			groups[uid] = ng
		end
	end
	for uid, tm in teams do
		if meet[uid] and not tm.leaving then
			local f = meet[uid]
			local set = tonumber(f:GetAttribute("SeatSet")) or 1
			if set == tm.set then continue end
			dropTeam(uid) -- moved to other chairs: rebuilt below
		elseif not tm.leaving then
			local near = tm.rigs[1] ~= nil and (tm.rigs[1].root.Position - cam).Magnitude <= Controller.CLIENTS_NEAR
			if near then tm.leaving = true; tm.age = 0 else dropTeam(uid) end
		end
	end
	for uid, f in meet do
		local key = f:GetAttribute("ClientKey")
		local old: Team? = teams[uid]
		if old and old.leaving then dropTeam(uid); old = nil end
		if old or typeof(key) ~= "string" then continue end
		local spot = spotOf(key)
		if not spot then continue end
		local set = tonumber(f:GetAttribute("SeatSet")) or 1
		local seats = IM.seatsFor(spot, set)
		local tm: Team = { owner = uid, rigs = {}, key = key, set = set, leaving = false, age = 0 }
		local i = 0
		for _, tpl in f:GetChildren() do
			if string.match(tpl.Name, "^Client%d$") and i < #seats then
				local rg = cloneRig(tpl, folderOf())
				if rg then
					i += 1
					rg.root.CFrame = seats[i]
					rg.pos = seats[i].Position
					table.insert(tm.rigs, rg)
				end
			end
		end
		teams[uid] = tm
	end
end
Controller._refresh = refreshPeople
local function stepPeople(dt: number, t: number)
	local cam = camPos()
	for uid, g in groups do
		if g.leaving then
			g.age += dt
			local age = g.age
			local done = true
			for _, rg in g.rigs do
				local path = rg.path
				if g.leaving == "board" and path then
					-- along the shuttle's boarding path into the cabin; hidden inside (the cabin windows are opaque)
					rg.walked += Controller.BOARD_SPEED * dt
					local len = 0
					for k = 2, #path do len += (path[k] - path[k - 1]).Magnitude end
					if rg.walked < len then
						done = false
						local p, dir = Pax.along(path, rg.walked)
						local flat = Vector3.new(dir.X, 0, dir.Z)
						if flat.Magnitude > 1e-3 then rg.look = flat.Unit end
						rg.pos = p
						rg.root.CFrame = CFrame.lookAt(p, p + rg.look)
						pose(rg, "WALKING", false, true, t, cam)
						setAlpha(rg, 0)
					else
						setAlpha(rg, 1)
					end
				else
					local a = age / Controller.FADE_OUT
					setAlpha(rg, a)
					if a < 1 then done = false end
					pose(rg, "IDLE", false, false, t, cam)
				end
			end
			if done or age > Controller.BOARD_MAX then dropGroup(uid) end
			continue
		end
		local owner = Players:GetPlayerByUserId(uid)
		local r = rootOf(owner)
		if not r then dropGroup(uid); continue end
		local p = r.Position
		local last = g.trail[#g.trail]
		if not last or (Vector3.new(p.X, 0, p.Z) - Vector3.new(last.X, 0, last.Z)).Magnitude >= Controller.TRAIL_STEP or math.abs(p.Y - last.Y) > 2 then
			table.insert(g.trail, p)
			while #g.trail > Controller.TRAIL_MAX do table.remove(g.trail, 1) end
		end
		local character = if owner then owner.Character else nil
		for i, rg in g.rigs do
			local point = trailPoint(g.trail, p, Controller.GAP * i)
			local side = r.CFrame.RightVector * (if i % 2 == 1 then 1.2 else -1.2)
			-- the height of the trail point he walked (not his height now: stairs, kerbs, jumps), on the ground below it
			rg.groundAt -= dt -- (seconds until the next ground ray, frame time)
			if rg.groundAt <= 0 then
				rg.groundAt = 1 / Controller.GROUND_HZ
				rg.groundY = groundAt(Vector3.new(point.X + side.X, point.Y, point.Z + side.Z), character)
			end
			local y = point.Y
			local gy = rg.groundY
			if gy and gy > point.Y - 6 and gy < point.Y + 3 then y = gy end
			local target = Vector3.new(point.X + side.X, y, point.Z + side.Z)
			local delta = target - rg.pos
			local dist = Vector3.new(delta.X, 0, delta.Z).Magnitude
			local walking = false
			if dist > Controller.TELEPORT then
				rg.pos = target
			elseif dist > 0.15 then
				local stepLen = math.min(dist, Controller.SPEED * dt)
				rg.pos = rg.pos + Vector3.new(delta.X, 0, delta.Z).Unit * stepLen
				walking = stepLen / math.max(dt, 1e-3) > 0.8
				rg.look = Vector3.new(delta.X, 0, delta.Z).Unit
			else
				local toOwner = Vector3.new(p.X - rg.pos.X, 0, p.Z - rg.pos.Z)
				if toOwner.Magnitude > 0.5 then rg.look = rg.look:Lerp(toOwner.Unit, math.min(1, dt * 3)) end
			end
			rg.pos = Vector3.new(rg.pos.X, rg.pos.Y + (target.Y - rg.pos.Y) * math.min(1, dt * 8), rg.pos.Z)
			local look = if rg.look.Magnitude > 1e-3 then rg.look.Unit else Vector3.new(0, 0, -1)
			rg.root.CFrame = CFrame.lookAt(rg.pos, rg.pos + look)
			if rg.alpha > 0 then setAlpha(rg, rg.alpha - dt / Controller.FADE_IN) end
			pose(rg, "IDLE", false, walking, t, cam)
		end
	end
	local f = ReplicatedStorage:FindFirstChild("CompanyItinerary")
	for uid, tm in teams do
		local folder = if f then f:FindFirstChild("Itin_" .. tm.owner) else nil
		local joined = folder ~= nil and folder:GetAttribute("Joined") == true
		local done = true
		if tm.leaving then tm.age += dt end
		for _, rg in tm.rigs do
			if tm.leaving then
				local a = tm.age / Controller.FADE_OUT
				setAlpha(rg, a)
				if a < 1 then done = false end
			elseif rg.alpha > 0 then
				setAlpha(rg, rg.alpha - dt / Controller.FADE_IN)
			end
			pose(rg, if joined and not tm.leaving then "MEETING" else "IDLE", true, false, t, cam)
		end
		if tm.leaving and done then dropTeam(uid) end
	end
end
Controller._step = stepPeople
-- companions following / client NPCs seated now (not counting the ones fading out or boarding)
function Controller.counts(): (number, number)
	local a, b = 0, 0
	for _, g in groups do if not g.leaving then a += #g.rigs end end
	for _, tm in teams do if not tm.leaving then b += #tm.rigs end end
	return a, b
end
-- every rig in the world (also the ones leaving)
function Controller.rigCount(): number
	local n = 0
	for _, g in groups do n += #g.rigs end
	for _, tm in teams do n += #tm.rigs end
	return n
end
function Controller._groups(): { [number]: any } return groups end
function Controller._teams(): { [number]: any } return teams end

------------------------------------------------------------------------------------------------ state
local function apply(v: any)
	if typeof(v) ~= "table" then return end
	if v.closed then
		view = nil
		closeBanner()
		clearBeacon()
		return
	end
	if toggledSeq ~= nil and v.seq ~= toggledSeq then userToggled = nil; toggledSeq = nil end
	view = v
	setBeacon(v.target)
	updateBanner()
end
Controller._apply = apply
function Controller.view(): { [string]: any }? return view end
local function fetch()
	task.spawn(function()
		local res = invoke({ action = "status" })
		if res.ok and typeof(res.view) == "table" then apply(res.view) end
	end)
end

-- one client frame: banner / beacon 5x per second, the people lists 2x per second, the walkers every frame
local frameAcc, peopleAcc = 0, 0
function Controller._frame(dt: number)
	local t = now()
	frameAcc += dt
	peopleAcc += dt
	if view and frameAcc >= 0.2 then
		frameAcc = 0
		updateBanner()
		updateBeacon()
	end
	if peopleAcc >= 0.5 then
		peopleAcc = 0
		refreshPeople()
	end
	if next(groups) or next(teams) then stepPeople(dt, t) end
end

function Controller.init()
	State.onNotify(function(kind: string, payload: { [string]: any })
		if kind == "ITINERARY" then apply(payload) end
	end)
	player:GetAttributeChangedSignal("Itinerary"):Connect(function()
		local st = player:GetAttribute("Itinerary")
		if st == nil then
			if view then apply({ closed = true }) end
		elseif not view then
			fetch()
		end
	end)
	if player:GetAttribute("Itinerary") ~= nil then fetch() end
	RunService.Heartbeat:Connect(Controller._frame)
end

return Controller
