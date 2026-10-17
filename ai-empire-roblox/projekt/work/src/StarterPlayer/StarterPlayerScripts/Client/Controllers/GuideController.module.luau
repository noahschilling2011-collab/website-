--!strict
-- "First steps" guide driver (ONBOARDING_SPEC A, menu package). Runs TutorialMath.step on state, Studio-mode,
-- Menu and input changes and drives: the HUD guide card (HUD.setGuide), the Menu's Home guide card
-- (HomeApp.setGuide), the ring / dim / chip layer (Screens/Guide), the world pointer to the founder computer
-- (step 1: Highlight + Beam + BillboardGui, client only), the redirect of the founder computer / C key to the Studio
-- design view during steps 1-2 (Computer.setOpenFilter), one-time tips (A12) and the EmpireAction "tutorial" ops
-- (step / done / skip / tip; the server validates them and they never change money or unlocks).
-- Never blocks: the guide never sets a gamepad selection in the world (A10) and never pauses anything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local TutorialMath = require(ReplicatedStorage.Shared.TutorialMath)
local ModelConfig = require(ReplicatedStorage.Shared.Config.ModelConfig)
local ModelMath = require(ReplicatedStorage.Shared.ModelMath)
local Types = require(ReplicatedStorage.Shared.Types)

local Client = script.Parent.Parent
local StateController = require(script.Parent.StateController)
local UI = Client.UI
local Theme = require(UI.Theme)
local Toast = require(UI.Toast)
local HUD = require(UI.Screens.HUD)
local Guide = require(UI.Screens.Guide)
local Computer = require(UI.Screens.Computer)
local HomeApp = require(UI.Apps.HomeApp)
local LabApp = require(UI.Apps.LabApp)
local Studio = require(UI.Lab.Studio)

local C = Theme.colors

local GuideController = {}

GuideController.TIP_GAP = 90 -- at most one tip per 90 s (A12)
GuideController.TIP_QUIET = 60 -- no tip in the first 60 s after the guide
GuideController.TIP_SECONDS = 10
GuideController.POINTER_NEAR = 10 -- the beam shows only while the player is farther away (studs)

type View = TutorialMath.View

local player = Players.LocalPlayer
local view: View? = nil
local greetingStart: number? = nil
local greetingOver = false
local sentStep: { [number]: boolean } = {}
local doneSent = false
local incomeAt: number? = nil
local celebrated = false
local subKey = ""
local subSince = 0
local usedRing: { [string]: boolean } = {} -- "<sub>|<target>" rings already pressed / left
local dimmed: { [string]: boolean } = {} -- first contacts already dimmed
local wasActive: boolean? = nil
local guideEndedAt = -math.huge
local lastTipAt = -math.huge
local tipPending: { [string]: boolean } = {}
local tipShown: { [string]: boolean } = {}
local studioDesigns = 0
local lastStudioMode = "closed"
local primaryEdge: string? = nil
local pointer: { highlight: Highlight?, beam: Beam?, a0: Attachment?, a1: Attachment?, billboard: BillboardGui? } = {}
local ringConn: RBXScriptConnection? = nil
local ringObj: GuiObject? = nil
local running = false

---------------------------------------------------------------------------- server ops (never through
-- ActionController: its per-remote busy lock must not make the player's own EmpireAction taps answer BUSY)

local function op(payload: { [string]: any })
	payload.action = "tutorial"
	task.spawn(function()
		pcall(function()
			Net.getFunction("EmpireAction"):InvokeServer(payload)
		end)
	end)
end
GuideController._op = op

---------------------------------------------------------------------------- helpers

local function inputKind(): TutorialMath.InputKind
	local ok, preferred = pcall(function(): any
		return (UserInputService :: any).PreferredInput
	end)
	if ok and typeof(preferred) == "EnumItem" then
		if preferred == Enum.PreferredInput.Gamepad then
			return "pad"
		elseif preferred == Enum.PreferredInput.KeyboardAndMouse then
			return "pc"
		elseif preferred == Enum.PreferredInput.Touch then
			return "touch"
		end
	end
	if UserInputService.GamepadEnabled and not UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "pad"
	end
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return "touch"
	end
	return "pc"
end

local function studioPart(name: string): GuiObject?
	local rootFrame = Studio.root
	if not rootFrame then
		return nil
	end
	local found = rootFrame:FindFirstChild(name, true)
	return if found and found:IsA("GuiObject") then found else nil
end

-- what the Studio's Primary says on the Review (cash edge, A3)
local function readPrimary(): string?
	if Studio.mode ~= "design" then
		return primaryEdge
	end
	local primary = studioPart("Primary")
	if primary and primary:IsA("TextButton") and primary.Visible then
		local text = primary.Text
		if string.sub(text, 1, 6) == "NEED $" then
			primaryEdge = "needCash"
		elseif string.sub(text, 1, 18) == "NEED TRAINING DATA" then
			primaryEdge = "needData"
		else
			primaryEdge = nil
		end
	end
	return primaryEdge
end

local function uiState(snapshot: Types.Snapshot): TutorialMath.Ui
	local done, total = StateController.trainingWork()
	return {
		computerOpen = Computer.isOpen(),
		studioOpen = Studio.isOpen(),
		studioMode = Studio.mode,
		revealed = LabApp.wasRevealed,
		inputKind = inputKind(),
		greetingOver = greetingOver,
		displayName = player.DisplayName,
		assistant = TutorialMath.assistantName(player.UserId),
		trainingEta = StateController.trainingEta(),
		trainingFrac = if total > 0 then done / total else 0,
		studioPrimary = readPrimary(),
		serverTime = snapshot.serverTime,
		menuHome = Computer.isOpen() and Computer.current() == "home.today",
	}
end
GuideController.uiState = uiState

-- abstract target id -> the GuiObject to ring (nil = nothing to ring right now)
function GuideController.resolve(target: string?): GuiObject?
	if target == nil then
		return nil
	end
	if target == "guide_action" then
		if Computer.isOpen() then
			return nil
		end
		return HUD.guideTargets().action
	elseif target == "menu_lab" then
		if not Computer.isOpen() or Studio.isOpen() or Computer.lockedShown() then
			return nil
		end
		local page = Computer.current()
		if page == "home.today" then
			return HomeApp.guideButton()
		elseif page == "lab.models" then
			local labFrame = Computer.pageFrame("lab.models")
			local v = view
			local name = if v and v.step == 4 then "Launch" else "DesignNewModel"
			local found = if labFrame then labFrame:FindFirstChild(name, true) else nil
			if found and found:IsA("GuiObject") and not (Studio.root and found:IsDescendantOf(Studio.root :: Instance)) then
				return found
			end
			return nil
		end
		return Computer.railButton("lab")
	end
	-- Studio targets, looked up by name under the frame "ModelStudio" (the Lab home has its own "Launch")
	if not Studio.isOpen() then
		return nil
	end
	return studioPart(target)
end

---------------------------------------------------------------------------- world pointer (A8, step 1 only)

local function clearPointer()
	local list: { Instance? } = { pointer.highlight, pointer.beam, pointer.a0, pointer.a1, pointer.billboard }
	for i = 1, 5 do
		local inst = list[i]
		if inst then
			inst:Destroy() -- destroyed, never disabled: a disabled Highlight still takes one of 255 slots
		end
	end
	pointer = {}
end

-- The player's own founder computer: the ownerComputer prompt inside the own Office (workspace.Plots.Plot_NN.Office,
-- PlotService). Cached: GuideController.update runs 5 times a second, so the office is scanned at most every
-- TERMINAL_RESCAN seconds and only while no valid terminal is cached (never a scan of the whole workspace).
GuideController.TERMINAL_RESCAN = 2
local terminalCache: BasePart? = nil
local terminalScanAt = -math.huge
local function scanTerminal(): BasePart?
	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, plot in plots:GetChildren() do
		local office = plot:FindFirstChild("Office")
		if office and office:GetAttribute("OwnerUserId") == player.UserId then
			local fallback: BasePart? = nil
			for _, d in office:GetDescendants() do
				if d:IsA("ProximityPrompt") and d:GetAttribute("CampusAction") == "ownerComputer" and d.Parent and d.Parent:IsA("BasePart") then
					if d:GetAttribute("Value") == "empire" then
						return d.Parent :: BasePart
					end
					fallback = d.Parent :: BasePart
				end
			end
			return fallback
		end
	end
	return nil
end
local function founderTerminal(): BasePart?
	local cached = terminalCache
	if cached and cached.Parent and cached:IsDescendantOf(workspace) then
		return cached
	end
	terminalCache = nil
	local now = os.clock()
	if now - terminalScanAt < GuideController.TERMINAL_RESCAN then
		return nil
	end
	terminalScanAt = now
	terminalCache = scanTerminal()
	return terminalCache
end

local function ensurePointer()
	local terminal = founderTerminal()
	if not terminal then
		clearPointer()
		return
	end
	if pointer.highlight and pointer.highlight.Adornee == terminal then
		return
	end
	clearPointer()
	local highlight = Instance.new("Highlight")
	highlight.Name = "GuideHighlight"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 0
	highlight.OutlineColor = C.warn
	highlight.Adornee = terminal
	highlight.Parent = terminal
	pointer.highlight = highlight
	local a1 = Instance.new("Attachment")
	a1.Name = "GuideTarget"
	a1.Parent = terminal
	pointer.a1 = a1
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GuidePointer"
	billboard.Adornee = terminal
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(250, 34)
	billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	billboard.MaxDistance = 120
	billboard.Parent = terminal
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = C.bg
	label.BackgroundTransparency = 0.1
	label.TextColor3 = C.text
	label.RichText = true
	label.Font = Enum.Font.BuilderSansBold
	label.TextSize = 16
	label.Text = string.format('<font color="#%02X%02X%02X">●</font> Founder computer · opens the Lab', math.floor(C.warn.R * 255 + 0.5), math.floor(C.warn.G * 255 + 0.5), math.floor(C.warn.B * 255 + 0.5))
	label.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = label
	pointer.billboard = billboard
end

local function updateBeam()
	local a1 = pointer.a1
	local character = player.Character
	local hrp = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not a1 or not hrp or not hrp:IsA("BasePart") then
		return
	end
	local far = (hrp.Position - a1.WorldPosition).Magnitude > GuideController.POINTER_NEAR
	if far and not pointer.beam then
		local a0 = Instance.new("Attachment")
		a0.Name = "GuideFrom"
		a0.Parent = hrp
		pointer.a0 = a0
		local beam = Instance.new("Beam")
		beam.Name = "GuideBeam"
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.FaceCamera = true
		beam.Width0 = 0.4
		beam.Width1 = 0.4
		beam.Segments = 12
		beam.CurveSize0 = 3
		beam.Color = ColorSequence.new(C.warn)
		beam.Transparency = NumberSequence.new(0.3, 0.8)
		beam.Parent = hrp
		pointer.beam = beam -- no Texture id: if an untextured Beam is too faint in Studio, drop it [A]
	elseif not far and pointer.beam then
		local beam, a0 = pointer.beam, pointer.a0
		if beam then
			beam:Destroy()
		end
		if a0 then
			a0:Destroy()
		end
		pointer.beam = nil
		pointer.a0 = nil
	end
end

---------------------------------------------------------------------------- actions

local function runAction(v: View)
	local action = v.action
	if not action then
		return
	end
	if action.route == "lab_design" then
		Computer.open("lab", "design")
	elseif action.route == "lab_train" then
		Computer.open("lab", "train")
	elseif action.route == "lab_release" then
		Computer.open("lab", "release")
		if action.modelId then
			LabApp.openRelease(action.modelId)
		end
	elseif action.route == "done" then
		if not doneSent then
			doneSent = true
			op({ op = "done" })
		end
	end
end
GuideController.runAction = runAction

local function skip()
	op({ op = "skip" })
	view = nil
	HUD.setGuide(nil)
	HomeApp.setGuide(nil)
	Guide.clear()
	clearPointer()
end
GuideController.skip = skip

---------------------------------------------------------------------------- tips (A12)

-- tip texts stay <= 36 characters when they carry SHOW ME (2 lines on a phone: column <= 271 pt, A2.1)
type Tip = { key: string, text: string, show: (() -> ())? }
local function tipCandidates(snapshot: Types.Snapshot): { Tip }
	local data: any = snapshot.data
	local live: any = snapshot.live
	local out: { Tip } = {}
	local staff = 0
	for _, n in data.empire.employees do
		staff += tonumber(n) or 0
	end
	if staff >= 1 then
		table.insert(out, { key = "team", text = "HR hires for you. Meet them in Team.", show = function() Computer.routeTo("page:team.staff") end })
	end
	local phoneGui = player:FindFirstChild("PlayerGui")
	local phoneButton = if phoneGui then phoneGui:FindFirstChild("PhoneButton", true) else nil
	local badge = if phoneButton then phoneButton:FindFirstChild("Badge") else nil
	if badge and badge:IsA("GuiObject") and badge.Visible and phoneButton and phoneButton:IsA("GuiObject") then
		local target: GuiObject = phoneButton
		table.insert(out, { key = "phone", text = "New message on your company phone.", show = function()
			Guide.setRing(target)
			task.delay(6, function()
				if Guide.ringTarget() == target then
					Guide.setRing(nil)
				end
			end)
		end })
	end
	local ops = live.ops
	if typeof(ops) == "table" and typeof(ops.trips) == "table" and next(ops.trips) ~= nil then
		table.insert(out, { key = "clients", text = "A signed client pays every day.", show = function() Computer.routeTo("page:clients.clients") end })
	end
	local capacity, load, waitlist = tonumber(live.capacity) or 0, tonumber(live.load) or 0, tonumber(live.waitlist) or 0
	if (capacity > 0 and load / capacity >= 0.85) or waitlist > 0 then
		table.insert(out, { key = "gpus", text = "Servers almost full: buy more GPUs.", show = function() Computer.routeTo("page:lab.gpus") end })
	end
	-- a live model, and VRAM and data allow a bigger size
	local fleet = ModelMath.fleet(data.gpus)
	local stock = ModelMath.dataSummary(data.data)
	for _, id in data.modelOrder do
		local m = data.models[id]
		local size = if m and m.status == "live" then ModelConfig.getSize(m.sizeId) else nil
		if size then
			for _, bigger in ModelConfig.SIZES do
				if bigger.vram > size.vram and bigger.vram <= fleet.vram and stock.total >= ModelConfig.TRAINING.minTokens then
					table.insert(out, { key = "successor", text = "Train v2: it takes over v1's users.", show = function() Computer.open("lab") end })
					break
				end
			end
			break
		end
	end
	if tipPending.design_steps then
		table.insert(out, { key = "design_steps", text = "Chips 1–5 let you design every part yourself.", show = nil })
	end
	return out
end

local tipCheckAt = -math.huge
local function maybeTip(snapshot: Types.Snapshot)
	local data: any = snapshot.data
	local t = data.empire.tutorial
	if typeof(t) ~= "table" or t.tipsOff == true or TutorialMath.active(data) then
		return
	end
	local now = os.clock()
	if Computer.isOpen() or now - guideEndedAt < GuideController.TIP_QUIET or now - lastTipAt < GuideController.TIP_GAP then
		return
	end
	-- at most one candidate pass per second, and none once every tip was shown or saved
	if now - tipCheckAt < 1 then
		return
	end
	tipCheckAt = now
	local tips = if typeof(t.tips) == "table" then t.tips else {}
	local left = false
	for _, key in TutorialMath.TIP_KEYS do
		if not tips[key] and not tipShown[key] then
			left = true
			break
		end
	end
	if not left then
		return
	end
	local training = data.training
	if training and training.event and training.event.pending then
		return
	end
	for _, tip in tipCandidates(snapshot) do
		if not tips[tip.key] and not tipShown[tip.key] then
			tipShown[tip.key] = true
			lastTipAt = now
			HUD.setTip(tip.text, tip.show, GuideController.TIP_SECONDS)
			op({ op = "tip", key = tip.key })
			return
		end
	end
end

---------------------------------------------------------------------------- the update

local function clearRing()
	if ringConn then
		ringConn:Disconnect()
		ringConn = nil
	end
	ringObj = nil
	Guide.setRing(nil)
end

function GuideController.update()
	local snapshot = StateController.snapshot
	if not snapshot or not snapshot.data.company then
		return
	end
	local data: any = snapshot.data
	local active = TutorialMath.active(data)
	if wasActive == true and not active then
		guideEndedAt = os.clock()
		local t = data.empire.tutorial
		if typeof(t) == "table" and t.done == true then
			HUD.setComplete(5)
			Toast.show("success", "New in your Menu: Market, Clients, Team", 5)
		end
	end
	wasActive = active
	-- the 2nd Studio design open queues the design-steps tip (shown later in the world)
	if Studio.mode == "design" and lastStudioMode ~= "design" then
		studioDesigns += 1
		if studioDesigns >= 2 or (tonumber(data.stats.modelsTrained) or 0) >= 1 then
			tipPending.design_steps = true
		end
	end
	lastStudioMode = Studio.mode
	if not active then
		if view ~= nil then
			view = nil
			HUD.setGuide(nil)
			HomeApp.setGuide(nil)
			Guide.clear()
			clearPointer()
		end
		maybeTip(snapshot)
		return
	end
	if greetingStart == nil then
		greetingStart = os.clock()
	elseif not greetingOver and os.clock() - greetingStart >= TutorialMath.GREETING_SECONDS then
		greetingOver = true
	end
	local v = TutorialMath.step(data, snapshot.live, uiState(snapshot))
	view = v
	HUD.setGuide(v)
	HomeApp.setGuide(v)
	if not v then
		Guide.clear()
		clearPointer()
		return
	end
	-- progress ops: a new maximum step (funnel steps 3..7 on the server)
	local saved = tonumber(data.empire.tutorial and data.empire.tutorial.step) or 0
	if v.step >= 2 and v.step > saved and not sentStep[v.step] then
		sentStep[v.step] = true
		op({ op = "step", n = v.step })
	end
	if v.step == 5 and v.sub == "income" then
		if not sentStep[6] then
			sentStep[6] = true
			op({ op = "step", n = 6 })
		end
		-- fix round 1 (review): the "First income!" burst and the 120 s auto-done start only once the player can see the
		-- card: the HUD column is hidden while the Menu (or the Studio's NOW LIVE inside it) is open, so both wait
		if not Computer.isOpen() then
			if not celebrated then
				celebrated = true
				HUD.celebrate()
			end
			incomeAt = incomeAt or os.clock()
		end
		if incomeAt and not doneSent and os.clock() - (incomeAt :: number) >= TutorialMath.DONE_AFTER_INCOME then
			doneSent = true
			op({ op = "done" })
		end
	end
	-- the ring: one target, after its delay, never again once pressed or left
	local key = v.sub .. "|" .. tostring(v.target)
	if key ~= subKey then
		subKey = key
		subSince = os.clock()
	end
	local target = GuideController.resolve(v.target)
	local ready = os.clock() - subSince >= v.delay
	if target and ready and not usedRing[key] then
		if ringObj ~= target then
			clearRing()
			ringObj = target
			Guide.setRing(target)
			if target:IsA("GuiButton") and v.target ~= "Primary" then
				-- pressing the ringed button uses the ring up (Primary counts only when the sub-step changes)
				ringConn = (target :: GuiButton).Activated:Connect(function()
					usedRing[key] = true
					clearRing()
				end)
			end
			-- the first-contact dim (steps 1, 2 buyData / start, 4 launch)
			if v.dim and not dimmed[key] then
				dimmed[key] = true
				local holes: { GuiObject } = {}
				if v.target == "guide_action" then
					local refs = HUD.guideTargets()
					for _, k in { "card", "row" } do
						local obj = refs[k]
						if obj then
							table.insert(holes, obj)
						end
					end
				end
				Guide.dim(holes)
			end
		end
	elseif not target or usedRing[key] then
		if ringObj then
			clearRing()
		end
	end
	-- chip (world steps only, left of the HUD column)
	if v.chip and target and not Computer.isOpen() then
		Guide.setChip(v.chip, HUD.guideTargets().column)
	else
		Guide.setChip(nil, nil)
	end
	-- world pointer: step 1 while the Computer is closed
	if v.step == 1 and not Computer.isOpen() then
		ensurePointer()
		updateBeam()
	else
		clearPointer()
	end
end

-- guide steps 1-2: the founder computer, the C key and Menu open the Studio design view (A8)
local function openFilter(appId: string?, section: string?): (string?, string?)
	local snapshot = StateController.snapshot
	local v = view
	if not snapshot or not v or v.step > 2 or not TutorialMath.active(snapshot.data) then
		return appId, section
	end
	local home = appId == nil or (appId == "home" and section == nil) or (appId == "empire" and (section == nil or section == "overview"))
	if home then
		return "lab", "design"
	end
	return appId, section
end
GuideController.openFilter = openFilter

function GuideController.view(): View?
	return view
end

function GuideController.init()
	if running then
		return
	end
	running = true
	HUD.setGuideHandlers({ action = runAction, skip = skip })
	HomeApp.setGuideHandler(runAction)
	Computer.setOpenFilter(openFilter)
	Computer.onPageShown(function()
		GuideController.update()
	end)
	StateController.onChange(function()
		GuideController.update()
	end)
	UserInputService.InputBegan:Connect(function()
		if greetingStart ~= nil then
			greetingOver = true
		end
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		GuideController.update()
	end)
	local clock = 0
	RunService.Heartbeat:Connect(function(dt: number)
		clock += dt
		if clock >= 0.2 then
			clock = 0
			GuideController.update()
		end
	end)
end

-- tests: forget the session memory
function GuideController._reset()
	view = nil
	greetingStart = nil
	greetingOver = false
	table.clear(sentStep)
	doneSent = false
	incomeAt = nil
	celebrated = false
	subKey = ""
	table.clear(usedRing)
	table.clear(dimmed)
	wasActive = nil
	tipCheckAt = -math.huge
	table.clear(tipShown)
	table.clear(tipPending)
	lastTipAt = -math.huge
	guideEndedAt = -math.huge
	terminalCache = nil
	terminalScanAt = -math.huge
	clearRing()
	clearPointer()
end

return GuideController
