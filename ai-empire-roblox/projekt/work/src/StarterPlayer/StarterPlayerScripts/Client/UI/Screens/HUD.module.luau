--!strict
-- HUD rechts oben (links oben gehört dem Roblox-Chat):
--   Glas-Panel (Firma, Geld, Nutzer, Reputation), "Next goal"-Karte, COMPUTER-Button
-- The "Next goal" card (CORE_SPEC 8.2) always shows ONE goal: EmpireMath.nextGoal(data, live) gives the goal,
-- its progress (have / need) and the ETA in minutes; this module only words it and adds the concrete hint from
-- real state (journey step, client trip, Save mode, research, Lab level). A pending training decision is the
-- only thing shown instead of the goal (it auto-resolves within seconds). A tap opens the relevant app.
-- Phones (small HUD scale, UIRoot < COMPACT_SCALE): the whole column gets its own UIScale COMPACT_BOOST and larger
-- compact text, so the goal title reads at about 13 pt and the progress at about 11 pt on an iPhone in landscape
-- (UIRoot 0.432 x 1.5), and the buttons are real touch targets (>= 44 pt); the card drops its hint line and shows the
-- step name in the progress text instead. The column is 300 design px wide at -16 from the right edge; the lane it
-- takes (300 x boost + 16, in HUD-layer px) is published as the HUD frame's attribute "LaneWidth" for the company
-- phone (Screens/Phone should keep left of it; design/requests/apps.md #4).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage.Shared
local CompanyConfig = require(Shared.Config.CompanyConfig)
local EmpireConfig = require(Shared.Config.EmpireConfig)
local ModelConfig = require(Shared.Config.ModelConfig)
local EmpireMath = require(Shared.EmpireMath)
local CompanyOps = require(Shared.CompanyOps)
local ModelMath = require(Shared.ModelMath)
local TutorialMath = require(Shared.TutorialMath)
local ShopConfig = require(Shared.Config.ShopConfig)
local Format = require(Shared.Format)
local Types = require(Shared.Types)

local UI = script.Parent.Parent
local Client = UI.Parent
local StateController = require(Client.Controllers.StateController)
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Toast = require(UI.Toast)
local ActionController = require(Client.Controllers.ActionController)
local Computer = require(UI.Screens.Computer)
local LabApp = require(UI.Apps.LabApp)
local GoalText = require(UI.GoalText)

local C = Theme.colors
local F = Theme.font

type Snapshot = Types.Snapshot
export type GoalView = GoalText.GoalView

local WIDTH = 300 -- Screens/Phone.HUD_WIDTH depends on this width and the 16 px margin (x COMPACT_BOOST on phones)
local MARGIN = 16
local COMPACT_SCALE = 0.62 -- UIRoot scale below which the HUD is drawn compact (phones in landscape)
local COMPACT_BOOST = 1.5 -- the column's own UIScale in compact mode (0.432 x 1.5 = 0.65 on an iPhone 12-14)
local TOUCH_BUTTON = 70 -- compact touch buttons: 70 x 1.5 x 0.432 = 45 pt (Apple's 44 pt minimum)
local GUIDE_GAP = 10 -- guide row: gap between [Collect $X] and the ringed action (ring pad 6 + stroke 3 < 10)

-- width of a bold button label in px (caps are wider than lower case; GoalText.textWidth is a flat 0.55 em)
local function labelWidth(text: string, size: number): number
	local em = 0
	for _, code in utf8.codes(text) do
		local ch = utf8.char(code)
		if string.match(ch, "^%u$") then
			em += 0.68
		elseif string.match(ch, "^%l$") then
			em += 0.5
		elseif string.match(ch, "^%d$") then
			em += 0.56
		elseif ch == " " or ch == "," or ch == "." then
			em += 0.28
		else
			em += 0.5
		end
	end
	return em * size
end

local HUD = {}
HUD.WIDTH = WIDTH
HUD.MARGIN = MARGIN
HUD.COMPACT_BOOST = COMPACT_BOOST

local root: Frame? = nil

-- the goal wording lives in UI/GoalText (shared with the Menu's Home cards); these aliases keep HUD's API
local textWidth = GoalText.textWidth
HUD.textWidth = GoalText.textWidth
HUD.etaText = GoalText.etaText
HUD.describe = GoalText.describe
HUD.safetyText = GoalText.safetyText

local function travelState(): string?
	local player = Players.LocalPlayer
	local ok, value = pcall(function(): any
		return (player :: any):GetAttribute("TravelState")
	end)
	return if ok and typeof(value) == "string" then value else nil
end

-- The guide card (ONBOARDING_SPEC A2.1, menu package): GuideController hands a TutorialMath view to HUD.setGuide;
-- nil = the normal "Next goal" card. Handlers come from GuideController (HUD.setGuideHandlers).
export type GuideHandlers = { action: (view: any) -> (), skip: () -> () }
local guideView: any = nil
local guideHandlers: GuideHandlers? = nil
local completeUntil = 0 -- os.clock() until which the caption reads "GUIDE COMPLETE ✓"
local tipText: string? = nil
local tipAction: (() -> ())? = nil
local tipUntil = 0
local refreshGuide: () -> () = function() end
local refs: { [string]: GuiObject } = {}

function HUD.setGuideHandlers(handlers: GuideHandlers)
	guideHandlers = handlers
end

-- GuideController hands a fresh view up to 5 times a second: the card is re-laid out only when what it shows changes
local guideSig = ""
local function guideSignature(view: any): string
	if view == nil then
		return ""
	end
	local action = view.action
	return table.concat({ tostring(view.step), tostring(view.sub), tostring(view.title), tostring(view.text), tostring(view.card),
		tostring(view.collect), string.format("%.2f", tonumber(view.frac) or 0),
		if action then tostring(action.label) .. "/" .. tostring(action.style) else "" }, "|")
end

function HUD.setGuide(view: any)
	guideView = view
	local sig = guideSignature(view)
	if sig ~= guideSig then
		guideSig = sig
		refreshGuide()
	end
end

function HUD.guide(): any
	return guideView
end

-- "GUIDE COMPLETE ✓" over the normal goal for `seconds` (A12 hand-off)
function HUD.setComplete(seconds: number)
	completeUntil = os.clock() + seconds
	refreshGuide()
	task.delay(seconds + 0.05, function()
		refreshGuide()
	end)
end

-- one-time tip line in the card (A12): shown `seconds` or until tapped; showMe = optional deep link
function HUD.setTip(text: string?, showMe: (() -> ())?, seconds: number?)
	tipText = text
	tipAction = showMe
	tipUntil = if text then os.clock() + (seconds or 10) else 0
	refreshGuide()
	if text then
		task.delay((seconds or 10) + 0.05, function()
			if tipText == text and os.clock() >= tipUntil then
				tipText = nil
				refreshGuide()
			end
		end)
	end
end

-- GuiObjects the guide layer rings / dims (nil when hidden): action, card, row, cash, skip, column
function HUD.guideTargets(): { [string]: GuiObject? }
	local out: { [string]: GuiObject? } = {}
	for key, inst in refs do
		out[key] = inst
	end
	local action = refs.action
	local warn, secondary = refs.actionWarn, refs.actionSecondary
	if warn and warn.Visible then
		action = warn
	elseif secondary and secondary.Visible then
		action = secondary
	end
	out.action = if action and action.Visible then action else nil
	return out
end

-- tap "Collect $X": every finished goal at once (ClaimQuest {all = true}), one toast "+$X from N goals"
function HUD.collect()
	task.spawn(function()
		local ok, result = ActionController.call("ClaimQuest", { all = true })
		local total = if ok and typeof(result.total) == "number" then result.total else 0
		local claimed = if ok and typeof(result.claimed) == "table" then #result.claimed else 0
		if total > 0 then
			Toast.show("success", TutorialMath.collectText(total, claimed), 4)
		end
	end)
end

-- The touch jump-button guard (fix round 1, review: A2.1's 271 pt limit assumes the classic jump button; the newer
-- ability-control variant of Roblox's PlayerModule sits at y 233-305 on an iPhone, inside the column's lane). While
-- the HUD shows, about twice a second: when the column comes closer than JUMP_GAP to the visible jump button
-- (PlayerGui.TouchGui.TouchControlFrame.JumpButton, made by the PlayerModule), the whole column moves left of it, so
-- no HUD button ever sits on the jump button. The classic button (top 279 pt, column bottom <= 271 pt) needs no shift.
-- HUD.checkJumpButton() runs the check now and returns the shift in HUD-layer px (0 = none); the frame attributes
-- "JumpShift" and "LaneWidth" (the company phone keeps left of the lane) include it.
HUD.JUMP_GAP = 8 -- screen px between the column and the jump button
local jumpGuardHook: () -> number = function(): number
	return 0
end
function HUD.checkJumpButton(): number
	return jumpGuardHook()
end

-- the step-5 "First income!" burst (A4): <= 24 small frames from the cash label towards the left and up; with
-- reduced motion only a flash of the cash label
local celebrateHook: () -> () = function() end
function HUD.celebrate()
	celebrateHook()
end

local function reducedMotion(): boolean
	local ok, value = pcall(function(): any
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and value == true
end

-- Shop button rule (B11): after the first launch, once the guide is done or skipped, and only while the shop has
-- something to show (an id set on a live server, or the Studio owner preview); never during the guide
function HUD.shopButtonAllowed(data: any): boolean
	if typeof(data) ~= "table" or (tonumber(data.stats and data.stats.modelsReleased) or 0) < 1 then
		return false
	end
	if TutorialMath.active(data) then
		return false
	end
	local studio = false
	pcall(function()
		studio = RunService:IsStudio()
	end)
	return studio or ShopConfig.anyListed()
end

function HUD.mount(parent: Frame, devAllowed: boolean, onDev: () -> ())
	local frame = Kit.frame(parent)
	frame.Name = "HUD"
	frame.Visible = false
	root = frame

	local column = Kit.frame(frame, UDim2.fromOffset(WIDTH, 0), UDim2.new(1, -MARGIN, 0, 12))
	column.Name = "Column"
	column.AnchorPoint = Vector2.new(1, 0)
	column.AutomaticSize = Enum.AutomaticSize.Y
	local layout = Kit.list(column, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	-- phones: the column's own scale (around its top-right anchor), see COMPACT_BOOST
	local boost = Instance.new("UIScale")
	boost.Name = "CompactBoost"
	boost.Parent = column
	frame:SetAttribute("LaneWidth", WIDTH + MARGIN)
	refs.column = column

	-- Firma und Zahlen in einem Glas-Panel: Geld groß, Nutzer und Reputation als Nebenwerte (desktop)
	local panel = Kit.panel(column, UDim2.new(1, 0, 0, 0))
	panel.Name = "Panel"
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.LayoutOrder = 1
	Kit.padding(panel, 12, 14, 12, 12)
	Kit.list(panel, 10)

	local identity = Kit.frame(panel, UDim2.new(1, 0, 0, 40))
	identity.LayoutOrder = 1
	local logoBox = Kit.frame(identity, UDim2.fromOffset(40, 40))
	logoBox.BackgroundTransparency = 0.72
	Theme.bindAccent(logoBox, "BackgroundColor3")
	Kit.corner(logoBox, 11)
	local logo = Kit.text(logoBox, "", 22, F.regular)
	logo.AnchorPoint = Vector2.new(0.5, 0.5)
	logo.Position = UDim2.fromScale(0.5, 0.5)
	local nameLabel = Kit.text(identity, "", 17, F.bold, C.text)
	nameLabel.AutomaticSize = Enum.AutomaticSize.None
	nameLabel.Size = UDim2.new(1, -52, 0, 22)
	nameLabel.Position = UDim2.fromOffset(52, 1)
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	local rankLabel = Kit.text(identity, "", 13, F.bold, C.muted)
	rankLabel.AutomaticSize = Enum.AutomaticSize.None
	rankLabel.Size = UDim2.new(1, -52, 0, 16)
	rankLabel.Position = UDim2.fromOffset(52, 23)
	rankLabel.TextTruncate = Enum.TextTruncate.AtEnd
	Theme.bindAccent(rankLabel, "TextColor3", Theme.lighter(0.3))

	Kit.divider(panel, 2)
	local moneyRow = Kit.frame(panel, UDim2.new(1, 0, 0, 26))
	moneyRow.LayoutOrder = 3
	local moneyValue = Kit.text(moneyRow, "$0", 22, F.display, C.text)
	moneyValue.AnchorPoint = Vector2.new(0, 0.5)
	moneyValue.Position = UDim2.fromScale(0, 0.5)
	local moneySub = Kit.text(moneyRow, "", 13, F.bold, C.dim)
	moneySub.Name = "NetPerDay"
	moneySub.AnchorPoint = Vector2.new(1, 0.5)
	moneySub.Position = UDim2.fromScale(1, 0.5)
	local statsRow = Kit.frame(panel, UDim2.new(1, 0, 0, 18))
	statsRow.LayoutOrder = 4
	local usersValue = Kit.text(statsRow, "0 users", 14, F.medium, C.muted)
	local repValue = Kit.text(statsRow, "Reputation 0", 14, F.medium, C.muted)
	repValue.AnchorPoint = Vector2.new(1, 0)
	repValue.Position = UDim2.fromScale(1, 0)

	-- Phones (L1, A2.2): the compact panel 300 x 80: logo 52, company name, cash + "+$X/day". Users, reputation and
	-- the rank line live in Menu → Home and Market on phones.
	local mini = Kit.panel(column, UDim2.new(1, 0, 0, 80))
	mini.Name = "CompactPanel"
	mini.LayoutOrder = 1
	mini.Visible = false
	Kit.padding(mini, 10, 16, 10, 16)
	local miniLogo = Kit.frame(mini, UDim2.fromOffset(52, 52), UDim2.new(0, 0, 0.5, 0))
	miniLogo.AnchorPoint = Vector2.new(0, 0.5)
	miniLogo.BackgroundTransparency = 0.72
	Theme.bindAccent(miniLogo, "BackgroundColor3")
	Kit.corner(miniLogo, 12)
	local miniGlyph = Kit.text(miniLogo, "", 28, F.regular)
	miniGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
	miniGlyph.Position = UDim2.fromScale(0.5, 0.5)
	local miniName = Kit.text(mini, "", 22, F.bold, C.text)
	miniName.Name = "CompanyName"
	miniName.AutomaticSize = Enum.AutomaticSize.None
	miniName.Size = UDim2.new(1, -64, 0, 26)
	miniName.Position = UDim2.fromOffset(64, 0)
	miniName.TextTruncate = Enum.TextTruncate.AtEnd
	local miniMoneyRow = Kit.frame(mini, UDim2.new(1, -64, 0, 32), UDim2.fromOffset(64, 28))
	Kit.list(miniMoneyRow, 8, true).VerticalAlignment = Enum.VerticalAlignment.Bottom
	local miniCash = Kit.text(miniMoneyRow, "$0", 28, F.bold, C.text)
	miniCash.Name = "Cash"
	miniCash.LayoutOrder = 1
	local miniNet = Kit.text(miniMoneyRow, "+$0/day", 19, F.medium, C.dim)
	miniNet.Name = "NetPerDay"
	miniNet.LayoutOrder = 2
	local miniBadge = Kit.tag(miniMoneyRow, "", C.bad, 3)
	miniBadge.Name = "CompactBadge"
	miniBadge.TextSize = 19
	miniBadge.Visible = false
	refs.cash = miniCash

	local badges = Kit.frame(column, UDim2.new(1, 0, 0, 0))
	badges.AutomaticSize = Enum.AutomaticSize.Y
	badges.LayoutOrder = 2
	local badgeLayout = Kit.list(badges, 6, true)
	badgeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	local travelBadge = Kit.tag(badges, "Abroad · Port Meridian", C.muted, 1)
	travelBadge.Name = "TravelBadge"
	travelBadge.Visible = false
	local saveBadge = Kit.tag(badges, "Saving off (Studio test)", C.warn, 2)
	saveBadge.Visible = false
	local safetyBadge = Kit.tag(badges, "", C.bad, 0)
	safetyBadge.Name = "Safety"
	safetyBadge.Visible = false
	-- desktop badges at 14 px (12.9 px on 1280x720; Kit.tag's 11 px read at 10 px there); phones hide this row
	for _, b in { travelBadge, saveBadge, safetyBadge } do
		b.TextSize = 14
	end

	-- Next goal: one goal with progress and ETA; a tap opens the matching app (guide mode: the step's action)
	local step = Instance.new("TextButton")
	step.Name = "NextGoal"
	step.AutoButtonColor = false
	step.Text = ""
	step.BorderSizePixel = 0
	step.Size = UDim2.new(1, 0, 0, 0)
	step.AutomaticSize = Enum.AutomaticSize.Y
	step.LayoutOrder = 3
	step.BackgroundColor3 = C.panel
	step.BackgroundTransparency = 0.02
	step.Selectable = true
	step.Parent = column
	Kit.corner(step, 14)
	local stepStroke = Kit.stroke(step, 0.87)
	stepStroke.Color = C.line
	local stepPadding = Kit.padding(step, 12, 14, 13, 14)
	local stepLayout = Kit.list(step, 5)
	refs.card = step
	local captionRow = Kit.frame(step, UDim2.new(1, 0, 0, 16))
	captionRow.LayoutOrder = 1
	local stepCaption = Kit.text(captionRow, "Next goal", 13, F.medium, C.muted)
	stepCaption.Name = "Caption"
	stepCaption.AnchorPoint = Vector2.new(0, 0.5)
	stepCaption.Position = UDim2.fromScale(0, 0.5)
	Theme.bindAccent(stepCaption, "TextColor3")
	local saveTag = Kit.tag(captionRow, "Save mode", C.warn)
	saveTag.Name = "SaveMode"
	saveTag.AnchorPoint = Vector2.new(1, 0.5)
	saveTag.Position = UDim2.fromScale(1, 0.5)
	saveTag.Visible = false
	local stepTitle = Kit.para(step, "", 17, C.text, 2)
	stepTitle.Name = "Title"
	stepTitle.Font = F.bold
	local stepBody = Kit.para(step, "", 14, C.muted, 3)
	stepBody.Name = "Hint"
	local stepBar = Kit.bar(step, 6, 4)
	stepBar.frame.Name = "Progress"
	local progressRow = Kit.frame(step, UDim2.new(1, 0, 0, 16))
	progressRow.Name = "ProgressRow"
	progressRow.LayoutOrder = 5
	local progressText = Kit.text(progressRow, "", 13, F.medium, C.muted)
	progressText.Name = "Have"
	progressText.AutomaticSize = Enum.AutomaticSize.None
	progressText.Size = UDim2.new(1, -60, 1, 0)
	progressText.TextTruncate = Enum.TextTruncate.AtEnd
	local etaText = Kit.text(progressRow, "", 13, F.bold, C.text)
	etaText.Name = "Eta"
	etaText.AnchorPoint = Vector2.new(1, 0)
	etaText.Position = UDim2.fromScale(1, 0)
	etaText.TextXAlignment = Enum.TextXAlignment.Right
	Theme.bindAccent(etaText, "TextColor3", Theme.lighter(0.25))
	-- tip line (A12): one-time hints in the same card
	local tipRow = Kit.frame(step, UDim2.new(1, 0, 0, 0))
	tipRow.Name = "TipRow"
	tipRow.AutomaticSize = Enum.AutomaticSize.Y
	tipRow.LayoutOrder = 7
	tipRow.Visible = false
	local tipLabel = Kit.para(tipRow, "", 14, C.text, 1)
	tipLabel.Name = "Tip"
	tipLabel.RichText = true

	-- guide body (A2.1): caption "FIRST STEPS · n/5" + Skip, 5-segment bar, title, "{A}: line" (2 lines on phones)
	local guideBody = Kit.frame(step, UDim2.new(1, 0, 0, 0))
	guideBody.Name = "GuideBody"
	guideBody.AutomaticSize = Enum.AutomaticSize.Y
	guideBody.LayoutOrder = 6
	guideBody.Visible = false
	Kit.list(guideBody, 0)
	local guideCaptionRow = Kit.frame(guideBody, UDim2.new(1, 0, 0, 26))
	guideCaptionRow.LayoutOrder = 1
	local guideCaption = Kit.text(guideCaptionRow, "FIRST STEPS · 1/5", 19, F.bold, C.text)
	guideCaption.Name = "GuideCaption"
	guideCaption.AnchorPoint = Vector2.new(0, 0.5)
	guideCaption.Position = UDim2.fromScale(0, 0.5)
	Theme.bindAccent(guideCaption, "TextColor3")
	-- Skip: 20 px muted underlined text centred on the caption line (never on the step bar); the invisible hit box
	-- is 96 x 68 (44 pt on phones) and spills 21 px up (panel padding / gap) and 21 px down (bar, title), never
	-- into the action row
	local skip = Instance.new("TextButton")
	skip.Name = "GuideSkip"
	skip.AutoButtonColor = false
	skip.BackgroundTransparency = 1
	skip.BorderSizePixel = 0
	skip.RichText = true
	skip.Text = "<u>Skip</u>"
	skip.TextSize = 20
	skip.Font = F.medium
	skip.TextColor3 = C.muted
	skip.TextXAlignment = Enum.TextXAlignment.Right
	skip.TextYAlignment = Enum.TextYAlignment.Center
	skip.Size = UDim2.fromOffset(96, 68)
	skip.AnchorPoint = Vector2.new(1, 0.5)
	skip.Position = UDim2.fromScale(1, 0.5)
	skip.Selectable = true
	skip.ZIndex = 3
	skip.Parent = guideCaptionRow
	refs.skip = skip
	Kit.onClick(skip, function()
		local h = guideHandlers
		if h then
			h.skip()
		end
	end)
	local gap1 = Kit.frame(guideBody, UDim2.new(1, 0, 0, 4))
	gap1.LayoutOrder = 2
	local segments = Kit.frame(guideBody, UDim2.new(1, 0, 0, 8))
	segments.Name = "GuideSteps"
	segments.LayoutOrder = 3
	local segFrames: { { track: Frame, fill: Frame } } = {}
	for i = 1, TutorialMath.STEPS do
		local track = Kit.frame(segments, UDim2.new(0.2, -24 / 5, 1, 0), UDim2.new((i - 1) * 0.2, (i - 1) * 6 / 5, 0, 0))
		track.BackgroundTransparency = 0.9
		track.BackgroundColor3 = C.white
		track.ClipsDescendants = true
		Kit.corner(track, 4)
		local fill = Kit.frame(track, UDim2.fromScale(0, 1))
		fill.BackgroundTransparency = 0
		Theme.bindAccent(fill, "BackgroundColor3")
		Kit.corner(fill, 4)
		segFrames[i] = { track = track, fill = fill }
	end
	local gap2 = Kit.frame(guideBody, UDim2.new(1, 0, 0, 6))
	gap2.LayoutOrder = 4
	local guideTitle = Kit.text(guideBody, "", 27, F.bold, C.text)
	guideTitle.Name = "GuideTitle"
	guideTitle.AutomaticSize = Enum.AutomaticSize.None
	guideTitle.Size = UDim2.new(1, 0, 0, 32)
	guideTitle.TextTruncate = Enum.TextTruncate.AtEnd
	guideTitle.LayoutOrder = 5
	local gap3 = Kit.frame(guideBody, UDim2.new(1, 0, 0, 4))
	gap3.LayoutOrder = 6
	local guideLine = Kit.text(guideBody, "", 19, F.regular, C.text)
	guideLine.Name = "GuideLine"
	guideLine.RichText = true
	guideLine.TextWrapped = true
	guideLine.TextYAlignment = Enum.TextYAlignment.Top
	guideLine.AutomaticSize = Enum.AutomaticSize.None
	guideLine.Size = UDim2.new(1, 0, 0, 48)
	guideLine.TextTruncate = Enum.TextTruncate.AtEnd
	guideLine.LayoutOrder = 7

	local current: GoalView? = nil
	local function runGuideAction()
		local view, h = guideView, guideHandlers
		if view and view.action and h then
			h.action(view)
		end
	end
	Kit.onClick(step, function()
		if guideView ~= nil and guideView.card ~= false then
			runGuideAction()
			return
		end
		if tipText and tipAction and os.clock() < tipUntil then
			local fn = tipAction
			tipText = nil
			refreshGuide()
			if fn then
				fn()
			end
			return
		end
		local target = current
		if not target then
			return
		end
		Computer.open(target.app, target.section)
		local releaseId = target.releaseId
		if releaseId then
			LabApp.openRelease(releaseId)
		end
	end)

	-- buttons: [Collect $X] [Menu] [Shop] (normal) or [Collect $X] [guide action] (guide mode). On phones one row of
	-- touch-sized buttons (the column must stay clear of the jump button, A2.1).
	local buttonRow = Kit.frame(column, UDim2.new(1, 0, 0, 0))
	buttonRow.Name = "Buttons"
	buttonRow.AutomaticSize = Enum.AutomaticSize.Y
	buttonRow.LayoutOrder = 4
	local buttonLayout = Kit.list(buttonRow, 8)
	refs.row = buttonRow
	local reward = Kit.button(buttonRow, "Collect", "secondary", UDim2.new(1, 0, 0, 48))
	reward.Name = "RewardReady"
	reward.LayoutOrder = 1
	reward.TextSize = 14
	reward.TextWrapped = true
	reward.Visible = false
	reward.Selectable = true
	Kit.onClick(reward, HUD.collect)
	refs.collect = reward

	-- the Menu button (P2: "Menu", always opens Home; Computer redirects to the Studio during guide steps 1-2)
	local computerButton = Kit.button(buttonRow, "Menu", "primary", UDim2.new(1, 0, 0, 50))
	computerButton.Name = "OpenCompany"
	computerButton.LayoutOrder = 2
	computerButton.TextSize = 17
	computerButton.Selectable = true
	Kit.onClick(computerButton, Computer.toggle)
	if UserInputService.KeyboardEnabled then
		local keycap = Kit.frame(computerButton, UDim2.fromOffset(26, 24), UDim2.new(1, -12, 0.5, 0))
		keycap.AnchorPoint = Vector2.new(1, 0.5)
		keycap.BackgroundTransparency = 0.82
		keycap.BackgroundColor3 = C.bg
		Kit.corner(keycap, 6)
		local key = Kit.text(keycap, "C", 13, F.bold, C.bg)
		key.AnchorPoint = Vector2.new(0.5, 0.5)
		key.Position = UDim2.fromScale(0.5, 0.5)
	end
	-- Shop (B11): gold bag + "Shop", only by HUD.shopButtonAllowed
	local shopButton = Kit.button(buttonRow, "", "secondary", UDim2.new(0, 110, 0, 50))
	shopButton.Name = "ShopButton"
	shopButton.LayoutOrder = 3
	shopButton.Visible = false
	shopButton.Selectable = true
	local shopInner = Kit.frame(shopButton, UDim2.fromScale(0, 1), UDim2.fromScale(0.5, 0))
	shopInner.AnchorPoint = Vector2.new(0.5, 0)
	shopInner.AutomaticSize = Enum.AutomaticSize.X
	Kit.list(shopInner, 8, true).VerticalAlignment = Enum.VerticalAlignment.Center
	local bag = Kit.icon(shopInner, "shop", 22)
	bag.frame.LayoutOrder = 1
	bag.setColor(C.warn)
	local shopLabel = Kit.text(shopInner, "Shop", 17, F.bold, C.warn)
	shopLabel.LayoutOrder = 2
	Kit.onClick(shopButton, function()
		Computer.open("shop")
	end)
	-- guide action in three styles (primary, gold for DECIDE, secondary for WATCH); one shows at a time
	local function actionButton(style: Kit.ButtonStyle, key: string): TextButton
		local b = Kit.button(buttonRow, "", style, UDim2.new(1, 0, 0, 50))
		b.Name = "GuideAction"
		b.LayoutOrder = 4
		b.Visible = false
		b.Selectable = true
		b.TextWrapped = true
		Kit.onClick(b, runGuideAction)
		refs[key] = b
		return b
	end
	local actionPrimary = actionButton("primary", "action")
	local actionWarn = actionButton("warn", "actionWarn")
	-- DECIDE is the one urgent button: solid gold with dark text (Kit's "warn" tint reads like a disabled button over
	-- a bright sky), the same gold as the ring
	actionWarn.BackgroundColor3 = C.warn
	actionWarn.BackgroundTransparency = 0
	actionWarn.TextColor3 = C.bg
	actionWarn:SetAttribute("BaseBg", 0)
	local actionSecondary = actionButton("secondary", "actionSecondary")
	-- guide row labels keep a small inner margin, so a long label wraps instead of touching the button edge
	for _, b in { actionPrimary, actionWarn, actionSecondary, reward } do
		Kit.padding(b, 0, 4, 0, 4)
	end
	if devAllowed then
		local dev = Kit.button(column, "DEV TOOLS", "ghost", UDim2.fromOffset(110, 30))
		dev.LayoutOrder = 6
		dev.TextSize = 12
		Kit.onClick(dev, onDev)
	end

	-- Phones: the whole HUD layer is scaled down a lot (UIRoot), so the column gets its own UIScale (COMPACT_BOOST),
	-- the compact panel replaces the glass panel, the goal card drops its hint line and the buttons become touch
	-- sized. Read the scale of the HUD layer (sibling UIScale of this frame's parent).
	local compact = false
	local shopShown = false
	local claimTotal = 0
	local function layoutButtons()
		local touch = compact and Kit.isTouch()
		local h = if touch then TOUCH_BUTTON elseif compact then 56 else 50
		local guiding = guideView ~= nil and guideView.card ~= false
		local action: TextButton? = nil
		if guiding then
			local style = if guideView.action then guideView.action.style else nil
			action = if style == "warn" then actionWarn elseif style == "secondary" then actionSecondary else actionPrimary
		end
		for _, b in { actionPrimary, actionWarn, actionSecondary } do
			b.Visible = guiding and b == action and guideView.action ~= nil
		end
		computerButton.Visible = not guiding
		shopButton.Visible = not guiding and shopShown
		local rowH = if compact then h else 50
		buttonLayout.Padding = UDim.new(0, 8)
		if compact or guiding then
			buttonLayout.FillDirection = Enum.FillDirection.Horizontal
		else
			buttonLayout.FillDirection = Enum.FillDirection.Vertical
		end
		if guiding then
			-- GUIDE_GAP between the two buttons: the 6 px ring (+3 px stroke) around one never covers the other
			buttonLayout.Padding = UDim.new(0, GUIDE_GAP)
			local hasCollect = reward.Visible
			-- phones: 19 px = 12.3 pt at the compact scale (the 12 pt floor); desktops a little larger
			local actionSize = if compact then 19 else 17
			local collectSize = if compact then 19 else 16
			for _, b in { actionPrimary, actionWarn, actionSecondary } do
				b.TextSize = actionSize
			end
			reward.TextSize = collectSize
			if action and action.Visible and hasCollect then
				-- split by label length (each side at least 40 %), so "SEE YOUR AI ›" and "Collect $12,300" both fit
				local wa = labelWidth(action.Text, actionSize) + 8
				local wc = labelWidth(reward.Text, collectSize) + 8
				local share = math.clamp(wc / (wa + wc), 0.4, 0.6)
				reward.Size = UDim2.new(share, -GUIDE_GAP * share, 0, rowH)
				action.Size = UDim2.new(1 - share, -GUIDE_GAP * (1 - share), 0, rowH)
			elseif action and action.Visible then
				action.Size = UDim2.new(1, 0, 0, rowH)
			elseif hasCollect then
				reward.Size = UDim2.new(1, 0, 0, rowH)
			end
		elseif compact then
			-- one row: [Collect $X] [Menu] [Shop]
			local shopW = if shopShown then 104 else 0
			local gaps = (if shopShown then 8 else 0) + (if reward.Visible then 8 else 0)
			shopButton.Size = UDim2.new(0, shopW, 0, h)
			if reward.Visible then
				reward.Size = UDim2.new(0.5, -(shopW + gaps) / 2, 0, h)
				computerButton.Size = UDim2.new(0.5, -(shopW + gaps) / 2, 0, h)
			else
				computerButton.Size = UDim2.new(1, -(shopW + gaps), 0, h)
			end
			-- 19 px = 12.3 pt; beside the Shop button "Collect $X" wraps to two lines inside the 70 px button
			reward.TextSize = 19
			computerButton.TextSize = 20
		else
			-- desktops: every target >= 44 px after the HUD scale (48 px x 0.92)
			reward.Size = UDim2.new(1, 0, 0, 48)
			reward.TextSize = 15
			computerButton.Size = UDim2.new(1, 0, 0, h)
			shopButton.Size = UDim2.new(1, 0, 0, 48)
			computerButton.TextSize = 17
		end
	end
	-- the jump-button guard (HUD.checkJumpButton above): the shift in HUD-layer px
	local jumpShift = 0
	local function jumpButton(): GuiObject?
		local layer = frame:FindFirstAncestorWhichIsA("ScreenGui")
		local playerGui = if layer then layer.Parent else nil
		local touchGui = if playerGui then playerGui:FindFirstChild("TouchGui") else nil
		if not touchGui or not touchGui:IsA("ScreenGui") or not touchGui.Enabled then
			return nil
		end
		local controls = touchGui:FindFirstChild("TouchControlFrame")
		local jump = if controls then controls:FindFirstChild("JumpButton") else nil
		if not jump or not jump:IsA("GuiObject") then
			return nil
		end
		local node: Instance? = jump
		while node and node ~= touchGui do
			if node:IsA("GuiObject") and not (node :: GuiObject).Visible then
				return nil
			end
			node = node.Parent
		end
		if jump.AbsoluteSize.X <= 0 or jump.AbsoluteSize.Y <= 0 then
			return nil
		end
		return jump
	end
	local function guardJump(): number
		local shift = 0
		local jump = jumpButton()
		local scale = parent:FindFirstChildOfClass("UIScale")
		local k = if scale then scale.Scale else 1
		local cs = column.AbsoluteSize
		if jump and k > 0 and cs.X > 0 then
			local jp, js = jump.AbsolutePosition, jump.AbsoluteSize
			local top = column.AbsolutePosition.Y
			local gap = HUD.JUMP_GAP
			-- the column's right edge without a shift (the frame's right edge - MARGIN), in screen px
			local right = frame.AbsolutePosition.X + frame.AbsoluteSize.X - MARGIN * k
			local left = right - cs.X
			local vertical = top < jp.Y + js.Y + gap and top + cs.Y + gap > jp.Y
			local horizontal = left < jp.X + js.X + gap and right + gap > jp.X
			if vertical and horizontal then
				shift = math.ceil((right - (jp.X - gap)) / k)
			end
		end
		if shift ~= jumpShift then
			jumpShift = shift
			column.Position = UDim2.new(1, -MARGIN - shift, 0, 12)
			frame:SetAttribute("LaneWidth", WIDTH * boost.Scale + MARGIN + shift)
		end
		frame:SetAttribute("JumpShift", shift)
		return shift
	end
	jumpGuardHook = guardJump
	local function applyCompact()
		local scale = parent:FindFirstChildOfClass("UIScale")
		compact = scale ~= nil and scale.Scale < COMPACT_SCALE
		boost.Scale = if compact then COMPACT_BOOST else 1
		frame:SetAttribute("LaneWidth", WIDTH * boost.Scale + MARGIN + jumpShift)
		frame:SetAttribute("Compact", compact)
		layout.Padding = UDim.new(0, if compact then 6 else 8)
		panel.Visible = not compact
		mini.Visible = compact
		stepTitle.TextSize = if compact then 20 else 17
		-- 19 px x 0.648 = 12.3 pt on phones, 14 px x 0.92 = 12.9 px on desktops
		stepCaption.TextSize = if compact then 19 else 14
		-- phones: every HUD text >= 19 px (12.3 pt at the compact scale)
		progressText.TextSize = if compact then 19 else 13
		etaText.TextSize = if compact then 19 else 13
		progressRow.Size = UDim2.new(1, 0, 0, if compact then 24 else 16)
		-- the Save mode tag reads >= 12 pt on phones (19 px x 0.648) and >= 12 px on desktops (14 px x 0.92)
		saveTag.TextSize = if compact then 19 else 14
		captionRow.Size = UDim2.new(1, 0, 0, if compact then 26 else 20)
		usersValue.TextSize = if compact then 16 else 14
		repValue.TextSize = if compact then 16 else 14
		statsRow.Size = UDim2.new(1, 0, 0, if compact then 20 else 18)
		moneySub.TextSize = if compact then 15 else 13
		rankLabel.TextSize = if compact then 14 else 13
		tipLabel.TextSize = if compact then 19 else 14
		shopLabel.TextSize = if compact then 19 else 17
		-- phones: the guide line keeps 2 lines (48 px); desktops may take 3
		guideLine.AutomaticSize = if compact then Enum.AutomaticSize.None else Enum.AutomaticSize.Y
		guideLine.Size = if compact then UDim2.new(1, 0, 0, 48) else UDim2.new(1, 0, 0, 24)
		refreshGuide()
	end

	-- normal vs guide mode of the card; the row; Skip; "GUIDE COMPLETE ✓"; the tip line
	refreshGuide = function()
		local view = guideView
		local guiding = view ~= nil and view.card ~= false
		local tipOn = tipText ~= nil and os.clock() < tipUntil and not guiding
		guideBody.Visible = guiding
		-- phones: a tip takes the caption line's place ("TIP" says what the card shows), so a 2-line title + 2-line
		-- tip still ends above the jump button (column <= 271 pt, A2.1)
		captionRow.Visible = not guiding and not (compact and tipOn)
		stepTitle.Visible = not guiding
		stepBody.Visible = not guiding and not compact and not tipOn and stepBody.Text ~= ""
		stepBar.frame.Visible = not guiding and current ~= nil and current.fraction ~= nil
		progressRow.Visible = not guiding and current ~= nil and (current.progress ~= "" or current.eta ~= "")
		tipRow.Visible = tipOn
		-- a tip with a deep link says so: tapping the card is its SHOW ME (A12)
		local showMe = if tipOn and tipAction then string.format('  <font color="#%02X%02X%02X"><b>SHOW ME ›</b></font>', math.floor(Theme.accent.R * 255 + 0.5), math.floor(Theme.accent.G * 255 + 0.5), math.floor(Theme.accent.B * 255 + 0.5)) else ""
		tipLabel.Text = if tipOn then "<b>TIP</b>  " .. Kit.escape(tipText or "") .. showMe else ""
		stepLayout.Padding = UDim.new(0, if guiding then 0 else 5)
		if guiding then
			stepPadding.PaddingTop = UDim.new(0, 10)
			stepPadding.PaddingBottom = UDim.new(0, 10)
		else
			stepPadding.PaddingTop = UDim.new(0, if compact then 9 else 12)
			stepPadding.PaddingBottom = UDim.new(0, if compact then 10 else 13)
		end
		if view and guiding then
			guideCaption.Text = `FIRST STEPS · {view.step}/{TutorialMath.STEPS}`
			guideTitle.Text = view.title
			local accent = Theme.accent
			local hex = string.format("#%02X%02X%02X", math.floor(accent.R * 255 + 0.5), math.floor(accent.G * 255 + 0.5), math.floor(accent.B * 255 + 0.5))
			guideLine.Text = `<font color="{hex}"><b>{Kit.escape(view.speaker)}:</b></font> {Kit.escape(view.text)}`
			for i, seg in segFrames do
				if i < view.step then
					seg.track.BackgroundTransparency = 0
					seg.track.BackgroundColor3 = Theme.accent
					seg.fill.Size = UDim2.fromScale(0, 1)
				elseif i == view.step then
					seg.track.BackgroundTransparency = 0.72
					seg.track.BackgroundColor3 = Theme.accent
					seg.fill.Size = UDim2.fromScale(math.clamp(view.frac or 0.35, 0, 1), 1)
				else
					seg.track.BackgroundTransparency = 0.9
					seg.track.BackgroundColor3 = C.white
					seg.fill.Size = UDim2.fromScale(0, 1)
				end
			end
			for _, b in { actionPrimary, actionWarn, actionSecondary } do
				b.Text = if view.action then view.action.label else ""
			end
			local collect = view.collect
			reward.Visible = collect ~= nil and collect > 0
			reward.Text = if collect then "Collect $" .. Format.int(collect) else "Collect"
			stepStroke.Color = Theme.accent
			stepStroke.Transparency = 0.6
		else
			-- normal mode: [Collect $X] while goals wait (two lines when the Shop button shares the phone row)
			reward.Visible = claimTotal > 0
			reward.Text = (if compact and shopShown then "Collect\n$" else "Collect $") .. Format.int(claimTotal)
			if os.clock() < completeUntil then
				stepCaption.Text = TutorialMath.TEXTS.complete
				stepCaption.TextColor3 = C.good
			elseif current then
				stepCaption.Text = current.caption
				stepCaption.TextColor3 = if current.warn then C.warn else Theme.accent
			end
		end
		layoutButtons()
	end

	local layerScale = parent:FindFirstChildOfClass("UIScale")
	if layerScale then
		layerScale:GetPropertyChangedSignal("Scale"):Connect(applyCompact)
	end
	applyCompact()

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not frame.Visible then
			return
		end
		if input.KeyCode == Enum.KeyCode.C then
			Computer.toggle()
		end
	end)

	StateController.onChange(function(snapshot: Snapshot)
		local data = snapshot.data
		local info = data.company
		frame.Visible = info ~= nil and frame:GetAttribute("Hidden") ~= true
		if not info then
			return
		end
		logo.Text = info.logo
		miniGlyph.Text = info.logo
		nameLabel.Text = info.name
		miniName.Text = info.name
		local stage = EmpireConfig.OFFICES[math.clamp(math.floor(tonumber(data.empire.office) or 1), 1, #EmpireConfig.OFFICES)]
		rankLabel.Text = CompanyConfig.rankFor(data.stats.peakUsers) .. "  ·  " .. (string.gsub(stage.name, "Headquarters", "HQ"))
		repValue.Text = `Reputation {string.format("%.0f", info.reputation)}`
		saveBadge.Visible = not snapshot.saveEnabled
		local travel = travelState()
		travelBadge.Visible = travel ~= nil
		travelBadge.Text = if travel == "flying" then "IN THE AIR" elseif travel == "abroad" then "ABROAD · PORT MERIDIAN" else ""
		local safety = HUD.safetyText(snapshot)
		safetyBadge.Text = string.upper(safety)
		safetyBadge.Visible = safety ~= ""
		badges.Visible = not compact and (travelBadge.Visible or saveBadge.Visible or safetyBadge.Visible)
		-- phones: an important badge (cash below $0, travelling) replaces the "+$X/day" line of the compact panel (the
		-- column has no room for a badge row above the jump button); the Studio-only "Saving off" badge is desktop only
		local badgeText, badgeColor = "", C.bad
		if safety ~= "" then
			badgeText = "CASH < $0"
		elseif travel ~= nil then
			badgeText, badgeColor = (if travel == "flying" then "IN THE AIR" else "ABROAD"), C.muted
		end
		miniBadge.Visible = compact and badgeText ~= ""
		miniBadge.Text = badgeText
		miniBadge.TextColor3 = badgeColor
		local badgeStroke = miniBadge:FindFirstChildOfClass("UIStroke")
		if badgeStroke then
			badgeStroke.Color = badgeColor
		end
		miniNet.Visible = not miniBadge.Visible
		claimTotal = TutorialMath.claimable(data)
		shopShown = HUD.shopButtonAllowed(data)

		-- money per game day (CORE_SPEC 6: the UI shows running money per game day)
		local live = snapshot.live
		local net = live.revenue - live.cost
		-- fix round 1 (review): before the first income the guide's very first screen must not read as "losing": the
		-- garage upkeep shows muted with the word "upkeep" while the guide runs (still the honest number); cash below $0
		-- is a real warning and stays red (CASH BELOW $0 badge, apps garage_edge)
		local upkeepOnly = TutorialMath.active(data) and live.revenue <= 0 and net < 0 and (tonumber(data.money) or 0) >= 0
		if upkeepOnly then
			moneySub.Text = Format.perDay(net) .. " upkeep"
			moneySub.TextColor3 = C.muted
		elseif live.revenue > 0 or live.cost > 0 then
			moneySub.Text = Format.perDay(net)
			moneySub.TextColor3 = if net >= 0 then C.good else C.bad
		else
			moneySub.Text = "no income yet"
			moneySub.TextColor3 = C.dim
		end
		-- the compact phone panel has no room for the word (204 px beside the cash): the muted colour carries it there
		miniNet.Text = Format.perDay(net)
		miniNet.TextColor3 = if upkeepOnly then C.muted elseif net > 0 then C.good elseif net < 0 then C.bad else C.dim

		local view = HUD.describe(snapshot, StateController.ui)
		current = view
		stepCaption.Text = view.caption
		stepCaption.TextColor3 = if view.warn then C.warn else Theme.accent
		saveTag.Visible = view.saving
		stepTitle.Text = view.title
		stepBody.Text = view.body
		if view.fraction and not view.training then
			stepBar.set(view.fraction :: number)
		end
		etaText.Text = view.eta
		-- the progress text takes what the ETA leaves: the first form that fits (desktop text, phone text, shortest)
		-- phones measure per glyph class (+12 % margin): the flat 0.55 em of textWidth over-reserves the 19 px ETA
		-- and would truncate "Trust 0 %" next to "back in 1 min 20 s"
		local function measure(text: string, size: number): number
			return if compact then labelWidth(text, size) * 1.12 else textWidth(text, size)
		end
		local etaWidth = if view.eta == "" then 0 else math.ceil(measure(view.eta, etaText.TextSize)) + 10
		progressText.Size = UDim2.new(1, -etaWidth, 1, 0)
		local room = WIDTH - stepPadding.PaddingLeft.Offset - stepPadding.PaddingRight.Offset - etaWidth
		local choice = view.shortProgress
		local candidates: { string } = if compact then { view.compactProgress } else { view.progress, view.compactProgress }
		for _, candidate in candidates do
			if measure(candidate, progressText.TextSize) <= room then
				choice = candidate
				break
			end
		end
		progressText.Text = choice
		stepStroke.Color = if view.warn then C.warn else C.line
		stepStroke.Transparency = if view.warn then 0.45 else 0.87
		refreshGuide()
	end)

	-- the step-5 burst (A4)
	celebrateHook = function()
		local origin = if compact then miniCash else moneyValue
		if reducedMotion() then
			origin.TextColor3 = C.good
			task.delay(1.2, function()
				origin.TextColor3 = C.text
			end)
			return
		end
		local colors = { C.good, C.warn, C.bad, Theme.accent, C.white }
		local burst = Kit.frame(frame, UDim2.fromOffset(1, 1))
		burst.Name = "Celebration"
		local a, p = origin.AbsolutePosition, frame.AbsolutePosition
		local s = parent:FindFirstChildOfClass("UIScale")
		local k = if s and s.Scale > 0 then s.Scale else 1
		burst.Position = UDim2.fromOffset((a.X - p.X) / k, (a.Y - p.Y) / k)
		for i = 1, 24 do
			local bit = Kit.frame(burst, UDim2.fromOffset(5, 9))
			bit.BackgroundTransparency = 0
			bit.BackgroundColor3 = colors[(i - 1) % #colors + 1]
			Kit.corner(bit, 2)
			local angle = math.rad(110 + (i * 37) % 70) -- left and up, away from the column
			local dist = 60 + (i * 53) % 120
			Kit.tween(bit, 1.4, { Position = UDim2.fromOffset(math.cos(angle) * dist, -math.sin(angle) * dist), BackgroundTransparency = 1 })
		end
		task.delay(1.5, function()
			burst:Destroy()
		end)
	end

	-- Zahlen gleiten zum Zielwert (Geld läuft zwischen den Snapshots weiter)
	local shownMoney, shownUsers = 0, 0
	local jumpCheckedAt = -math.huge
	RunService.RenderStepped:Connect(function(dt: number)
		local snapshot = StateController.snapshot
		column.Visible = not Computer.isOpen() -- im Computer stehen dieselben Zahlen in der Kopfzeile
		if not snapshot or not frame.Visible then
			return
		end
		if os.clock() - jumpCheckedAt >= 0.5 then
			jumpCheckedAt = os.clock()
			guardJump()
		end
		local alpha = math.min(1, dt * 8)
		local money = StateController.money()
		shownMoney = if math.abs(money - shownMoney) > 1e8 then money else shownMoney + (money - shownMoney) * alpha
		moneyValue.Text = Format.money(shownMoney)
		moneyValue.TextColor3 = if shownMoney < 0 then C.bad else C.text
		miniCash.Text = Format.money(shownMoney)
		local users = snapshot.live.users
		shownUsers = if math.abs(users - shownUsers) > 1e7 then users else shownUsers + (users - shownUsers) * alpha
		usersValue.Text = `{Format.compact(shownUsers)} users`
		local view = current
		if guideView == nil and view and view.training and stepBar.frame.Visible then
			local done, total = StateController.trainingWork()
			local fraction = if total > 0 then done / total else 0
			stepBar.set(fraction)
			progressText.Text = string.format("Training %d %%", math.floor(fraction * 100))
			local eta = StateController.trainingEta()
			etaText.Text = if eta > 0 and eta < math.huge then Kit.countdown(eta) .. " left" else ""
		end
	end)

	-- Benachrichtigungen vom Server
	StateController.onNotify(function(kind: string, payload: { [string]: any })
		if kind == "TRAINING_EVENT" then
			if Computer.isOpen() then
				return -- das Lab zeigt die Entscheidung ohnehin groß an
			end
			local def = if typeof(payload.eventId) == "string" then ModelConfig.getEvent(payload.eventId) else nil
			Toast.show("warn", `Training paused: {if def then def.title else "decision needed"}. Open the Lab to decide.`, 5)
		elseif kind == "TRAINING_COMPLETE" then
			if not Computer.isOpen() then -- bei offenem Computer erscheint das Ergebnis direkt im Lab
				-- lab request #1 (LAB_SPEC 4.14): no score here, the reveal keeps it a surprise
				Toast.show("success", "Training complete! Tap the goal card for the reveal.", 5)
			end
		elseif kind == "MODEL_LIVE" then
			if not Computer.isOpen() then
				Toast.show("success", "Your model is live. Users are coming in!")
			end
		elseif kind == "RANK_UP" then
			local rank = if typeof(payload.rank) == "string" then payload.rank else "new rank"
			Toast.show("success", `Rank up! Your company is now a {rank}.`, 6)
		end
	end)
end

-- Während des Intros ausblenden
function HUD.setHidden(hidden: boolean)
	local frame = root
	if not frame then
		return
	end
	frame:SetAttribute("Hidden", hidden)
	local snapshot = StateController.snapshot
	frame.Visible = not hidden and snapshot ~= nil and snapshot.data.company ~= nil
end

return HUD
