--!strict
-- Der Computer im Büro: ein Fenster mit Sidebar (Company, Lab, Data, Compute, Market, ..., Shop).
-- Öffnet über den Laptop-Prompt, den COMPUTER-Button im HUD oder die Taste C.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Format = require(ReplicatedStorage.Shared.Format)
local Types = require(ReplicatedStorage.Shared.Types)
local Journey=require(ReplicatedStorage.Shared.JourneyMath)
local ModelMath = require(ReplicatedStorage.Shared.ModelMath)
local HardwareConfig = require(ReplicatedStorage.Shared.Config.HardwareConfig)

local UI = script.Parent.Parent
local Client = UI.Parent
local StateController = require(Client.Controllers.StateController)
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local LabApp = require(UI.Apps.LabApp)
local DataApp = require(UI.Apps.DataApp)
local ComputeApp = require(UI.Apps.ComputeApp)
local MarketApp = require(UI.Apps.MarketApp)
local StudioApp=require(UI.Apps.StudioApp)
local ArenaApp=require(UI.Apps.ArenaApp)
local CampusApp=require(UI.Apps.CampusApp)
local EmpireApp = require(UI.Apps.EmpireApp)
local ShopApp = require(UI.Apps.ShopApp)

local C = Theme.colors
local F = Theme.font

type AppModule = { mount: (Frame, Kit.Nav) -> (), onShow: () -> () }
type Entry = { id: string, app: AppModule, container: Frame, status: TextLabel, paint: () -> () }

local APPS: { { id: string, label: string, app: AppModule } } = {
	{ id = "empire", label = "Company", app = EmpireApp },
	{ id = "lab", label = "Models", app = LabApp },
	{ id = "data", label = "Datasets", app = DataApp },
	{ id = "compute", label = "Hardware", app = ComputeApp },
	{ id = "market", label = "Market", app = MarketApp },
	{ id = "studio", label = "Projects", app = StudioApp },
	{ id = "arena", label = "Test arena", app = ArenaApp },
	{ id = "campus", label = "Campus", app = CampusApp },
	{ id = "shop", label = "Shop", app = ShopApp },
}

local SIDEBAR = 196
local HEADER = 64
local FLOW = 66

local Computer = {}

local root: Frame? = nil
local dim: TextButton? = nil
local windowScale: UIScale? = nil
local blur: BlurEffect? = nil
local entries: { Entry } = {}
local current = "empire"
local opened = false
local moneyLabel: TextLabel? = nil

local function entryOf(id: string): Entry?
	for _, entry in entries do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

function Computer.isOpen(): boolean
	return opened
end

function Computer.show(appId: string)
	local target = entryOf(appId)
	if not target then
		return
	end
	local switched = current ~= appId
	current = appId
	for _, entry in entries do
		entry.container.Visible = entry.id == appId
		entry.paint()
	end
	if switched then
		-- kurze Antwort auf den Klick: neue App gleitet 10 px nach oben ein
		target.container.Position = UDim2.fromOffset(0, 10)
		Kit.tween(target.container, 0.25, { Position = UDim2.new() })
	end
	target.app.onShow()
end

function Computer.open(appId: string?,section: string?)
	local frame, shade, scale, effect = root, dim, windowScale, blur
	if not frame or not shade or not scale or not effect then
		return
	end
	if not opened then
		opened = true
		frame.Visible = true
		shade.Visible = true
		shade.BackgroundTransparency = 1
		Kit.tween(shade, 0.25, { BackgroundTransparency = 0.32 })
		scale.Scale = 0.96
		Kit.tween(scale, 0.32, { Scale = 1 }, Enum.EasingStyle.Back)
		Kit.tween(effect, 0.3, { Size = 8 })
	end
	Computer.show(appId or current)
 if section then local target=entryOf(appId or current);if target then local app=target.app :: any;if app.openSection then app.openSection(section) end end end
end

function Computer.close()
	local frame, shade, effect = root, dim, blur
	if not opened or not frame or not shade or not effect then
		return
	end
	opened = false
	Kit.tween(shade, 0.18, { BackgroundTransparency = 1 })
	Kit.tween(effect, 0.18, { Size = 0 })
	task.delay(0.18, function()
		if not opened then
			frame.Visible = false
			shade.Visible = false
		end
	end)
end

function Computer.toggle()
	if opened then
		Computer.close()
	else
		Computer.open()
	end
end

local function statusFor(id: string, snapshot: Types.Snapshot): (string, Color3)
	local data = snapshot.data
	if id == "empire" then
		return "Team · Research · Goals", C.dim
	elseif id == "lab" then
		local training = data.training
		if training then
			if training.event and training.event.pending then
				return "Decision needed", C.warn
			end
			return "Training " .. Format.percent(training.workDone / training.workTotal), Theme.accent
		end
		local ready = 0
		for _, model in data.models do
			if model.status == "trained" then
				ready += 1
			end
		end
		if ready > 0 then
			return `{ready} ready to launch`, C.good
		end
		return "Design and train", C.dim
	elseif id == "data" then
		return Format.tokens(ModelMath.dataSummary(data.data).total) .. " tokens", C.dim
	elseif id == "compute" then
		local fleet = ModelMath.fleet(data.gpus)
		return `{fleet.slotsUsed} of {HardwareConfig.slots(data.empire)} compute slots`, C.dim
	end
	if id=="campus" then return "Cards · Fleet · Stores",C.dim end
	if id=="shop" then return ShopApp.status(snapshot) end
	if id=="studio" then return tostring(#data.empire.projectOrder).." projects",C.dim end
	if id=="arena" then return tostring(data.empire.arenaBest).." best points",C.dim end
	local live = 0
	for _, model in data.models do
		if model.status == "live" then
			live += 1
		end
	end
	if live == 0 then
		return "Nothing live yet", C.dim
	end
	return `{Format.compact(snapshot.live.users)} users`, C.good
end

local function headerStatus(snapshot: Types.Snapshot): (string, Color3)
	local data = snapshot.data
	local training = data.training
	if training then
		if training.event and training.event.pending then
			return "Training paused: decision needed", C.warn
		end
		return "Training " .. Format.percent(training.workDone / training.workTotal), Theme.accent
	end
	local live = 0
	for _, model in data.models do
		if model.status == "live" then
			live += 1
		end
	end
	if live > 0 then
		return `{live} model{if live == 1 then "" else "s"} live`, C.good
	end
	return "No model live yet", C.dim
end

local function buildNavButton(sidebar: Frame, index: number, id: string, label: string): (TextLabel, () -> ())
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Text = ""
	button.Size = UDim2.new(1, 0, 0, 58)
	button.LayoutOrder = index
	button.BackgroundColor3 = C.raised
	button.BackgroundTransparency = 1
	button.Parent = sidebar
	Kit.corner(button, 12)

	-- Akzent-Strich = aktuelle Auswahl
	local bar = Kit.frame(button, UDim2.new(0, 3, 0, 24), UDim2.new(0, 0, 0.5, -12))
	bar.BackgroundTransparency = 0
	Theme.bindAccent(bar, "BackgroundColor3")
	Kit.corner(bar, 2)

	local icon = Kit.icon(button, id, 18)
	icon.frame.AnchorPoint = Vector2.new(0, 0.5)
	icon.frame.Position = UDim2.new(0, 16, 0.5, 0)
	local title = Kit.text(button, label, 16, F.bold, C.text)
	title.Position = UDim2.fromOffset(48, 10)
	local status = Kit.text(button, "", 12, F.medium, C.dim)
	status.Position = UDim2.fromOffset(48, 32)
	status.Size = UDim2.new(1, -54, 0, 16)
	status.AutomaticSize = Enum.AutomaticSize.None
	status.TextTruncate = Enum.TextTruncate.AtEnd

	local function paint()
		local selected = current == id
		button.BackgroundTransparency = if selected then 0 else 1
		bar.Visible = selected
		title.TextColor3 = if selected then C.text else C.muted
		icon.setColor(if selected then Theme.accent else C.dim)
	end
	Theme.onAccent(function()
		paint()
	end)
	Kit.onClick(button, function()
		Computer.show(id)
	end)
	paint()
	return status, paint
end

function Computer.mount(parent: Frame, dimLayer: Frame)
	local frame = Kit.frame(parent)
	frame.Name = "Computer"
	frame.Visible = false
	frame.ZIndex = 10
	root = frame

	-- Abdunkeln liegt in einer randlosen Ebene (deckt auch den Topbar-Streifen ab) und schluckt Klicks
	local shade = Kit.blocker(dimLayer, C.black, 1)
	shade.Visible = false
	dim = shade

	local effect = Instance.new("BlurEffect")
	effect.Name = "AIEmpireBlur"
	effect.Size = 0
	effect.Parent = Lighting -- vom Client erstellt = existiert nur bei diesem Spieler
	blur = effect

	local window = Kit.panel(frame, UDim2.new(1, -40, 1, -28), UDim2.fromScale(0.5, 0.5))
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.ZIndex = 11
	window.BackgroundColor3 = C.bg
	window.BackgroundTransparency = 0.03
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(1180, 740)
	constraint.Parent = window
	local scale = Instance.new("UIScale")
	scale.Parent = window
	windowScale = scale

	-- Kopfzeile: Firma + Live-Status links, Geld + Schließen rechts
	local header = Kit.frame(window, UDim2.new(1, 0, 0, HEADER))
	local logoBox = Kit.frame(header, UDim2.fromOffset(38, 38), UDim2.new(0, 18, 0.5, -19))
	logoBox.BackgroundTransparency = 0.72
	Theme.bindAccent(logoBox, "BackgroundColor3")
	Kit.corner(logoBox, 10)
	local logo = Kit.text(logoBox, "", 20, F.regular)
	logo.AnchorPoint = Vector2.new(0.5, 0.5)
	logo.Position = UDim2.fromScale(0.5, 0.5)
	-- name + VIP badge share a horizontal row, so the badge never needs pixel measuring
	local titleRow = Kit.frame(header, UDim2.fromOffset(0, 22), UDim2.fromOffset(68, 12))
	titleRow.AutomaticSize = Enum.AutomaticSize.X
	local titleLayout = Instance.new("UIListLayout")
	titleLayout.FillDirection = Enum.FillDirection.Horizontal
	titleLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	titleLayout.SortOrder = Enum.SortOrder.LayoutOrder
	titleLayout.Padding = UDim.new(0, 10)
	titleLayout.Parent = titleRow
	local title = Kit.text(titleRow, "AI Empire", 16, F.bold, C.text)
	title.LayoutOrder = 1
	local status = Kit.text(header, "", 13, F.medium, C.dim)
	status.Position = UDim2.fromOffset(68, 34)
	-- VIP Founder game pass: small badge right of the company name (ShopService live.shop)
	local vip = Kit.tag(titleRow, "VIP", C.warn, 2)
	vip.Name = "VipBadge"
	vip.Visible = false
	local money = Kit.text(header, "$0", 18, F.display, C.text)
	money.AnchorPoint = Vector2.new(1, 0.5)
	money.Position = UDim2.new(1, -72, 0.5, 0)
	moneyLabel = money
	local close = Kit.button(header, "×", "ghost", UDim2.fromOffset(40, 40))
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -16, 0.5, 0)
	Kit.onClick(close, Computer.close)
	local headerLine = Kit.divider(header)
	headerLine.Position = UDim2.new(0, 0, 1, -1)

	-- Sidebar
	local sidebar = Kit.frame(window, UDim2.new(0, SIDEBAR, 1, -HEADER), UDim2.fromOffset(0, HEADER))
	Kit.padding(sidebar, 14, 10, 14, 12)
	Kit.list(sidebar, 4)
	local sidebarScale = Instance.new("UIScale")
	sidebarScale.Parent = sidebar
	-- nav buttons are 58 px + 4 px gap, plus the sidebar padding (8 apps needed ~512 px)
	local sidebarNeed = #APPS * 62 + 22
	-- AbsoluteSize is in screen pixels (includes UIRoot's UIScale); compare in design pixels
	local function designScale(inst: Instance): number
		local s = 1
		local node: Instance? = inst
		while node do
			local u = node:FindFirstChildOfClass("UIScale")
			if u and u ~= sidebarScale then
				s *= u.Scale
			end
			node = node.Parent
		end
		return if s > 0 then s else 1
	end
	local function fitSidebar()
		local designHeight = window.AbsoluteSize.Y / designScale(window)
		sidebarScale.Scale = math.min(1, math.max(0.55, (designHeight - HEADER - 24) / sidebarNeed))
	end
	window:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitSidebar)
	fitSidebar()
	local sideLine = Kit.frame(window, UDim2.new(0, 1, 1, -HEADER), UDim2.fromOffset(SIDEBAR, HEADER))
	sideLine.BackgroundTransparency = 0.93
	sideLine.BackgroundColor3 = C.line

	-- The seven physical departments use the same permanent flow in Company OS.
 local flow=Kit.frame(window,UDim2.new(1,-SIDEBAR-1,0,FLOW),UDim2.fromOffset(SIDEBAR+1,HEADER));flow.Name="AIJourney"
 local labels={};local buttons={}
 for i,def in Journey.STEPS do
  local b=Kit.button(flow,def.label,"ghost",UDim2.new(1/7,-4,0,28));b.Position=UDim2.new((i-1)/7,2,0,4);b.TextSize=12;b.Name="Journey_"..def.id;buttons[i]=b
  Kit.onClick(b,function()Computer.open(def.app,def.section)end)
 end
 local hint=Kit.text(flow,"",12,F.medium,C.dim);hint.Position=UDim2.fromOffset(12,38);hint.Size=UDim2.new(1,-24,0,20);hint.AutomaticSize=Enum.AutomaticSize.None;hint.TextTruncate=Enum.TextTruncate.AtEnd
 local function paintFlow()
  local snapshot=StateController.snapshot;if not snapshot then return end
  local progress=Journey.progress(snapshot.data,StateController.ui)
  for i,b in buttons do b.Text=(if progress.done[i] then "✓ " else "")..Journey.STEPS[i].label;b.BackgroundColor3=if i==progress.index then Theme.accent:Lerp(C.panel,.72) else C.panel;b.BackgroundTransparency=if i==progress.index then 0 else 1;b.TextColor3=if progress.done[i] then C.good elseif i==progress.index then C.text else C.dim end
  hint.Text=progress.hint;hint.TextColor3=if progress.missingVram>0 then C.warn else C.dim
 end
 StateController.onChange(paintFlow);StateController.onUiChange(paintFlow)
 -- Inhalt
 local content = Kit.frame(window, UDim2.new(1, -SIDEBAR - 1, 1, -HEADER-FLOW), UDim2.fromOffset(SIDEBAR + 1, HEADER+FLOW))
	content.ClipsDescendants = true
	Kit.padding(content, 20, 20, 0, 24)

	local nav: Kit.Nav = {
		show = function(appId: string)
			Computer.open(appId)
		end,
		close = Computer.close,
		isOpen = Computer.isOpen,
	}

	for index, def in APPS do
		local container = Kit.frame(content)
		container.Name = def.id
		container.Visible = false
		local statusLabel, paint = buildNavButton(sidebar, index, def.id, def.label)
		table.insert(entries, {
			id = def.id,
			app = def.app,
			container = container,
			status = statusLabel,
			paint = paint,
		})
		def.app.mount(container, nav)
	end

	StateController.onChange(function(snapshot)
		for _, entry in entries do
			local text, color = statusFor(entry.id, snapshot)
			entry.status.Text = text
			entry.status.TextColor3 = color
		end
		local company = snapshot.data.company
		title.Text = if company then company.name else "AI Empire"
		logo.Text = if company then company.logo else ""
		local text, color = headerStatus(snapshot)
		status.Text = text
		status.TextColor3 = color
		vip.Visible = ShopApp.owns(snapshot, "vip")
	end)

	RunService.RenderStepped:Connect(function()
		local label = moneyLabel
		if opened and label then
			local value = StateController.money()
			label.Text = Format.money(value)
			label.TextColor3 = if value < 0 then C.bad else C.text
		end
	end)
end

return Computer
