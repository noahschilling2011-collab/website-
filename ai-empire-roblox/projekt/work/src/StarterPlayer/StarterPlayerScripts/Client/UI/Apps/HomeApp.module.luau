--!strict
-- Menu → Home → Today (ONBOARDING_SPEC B4, menu package): "What to do next" with up to 3 action cards (pure
-- HomeApp.cards, unit-tested), a live strip (cash, net, users, live models, training, the daily grant) and, on
-- desktops, a Goals row. A native Menu page: design px at the Menu's own scale (text >= 20 px = 12 pt on an iPhone,
-- buttons 74 px = 44 pt). Never a Shop card. The guide card mirrors the HUD guide card (GuideController hands its
-- TutorialMath view to HomeApp.setGuide).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local EmpireConfig = require(Shared.Config.EmpireConfig)
local ModelConfig = require(Shared.Config.ModelConfig)
local EmpireMath = require(Shared.EmpireMath)
local ModelMath = require(Shared.ModelMath)
local TutorialMath = require(Shared.TutorialMath)
local ShopMath = require(Shared.ShopMath) -- shop package: boost captions in the live strip (SHOP_SPEC 5.2.7)
local Format = require(Shared.Format)
local Types = require(Shared.Types)

local UI = script.Parent.Parent
local Client = UI.Parent
local StateController = require(Client.Controllers.StateController)
local ActionController = require(Client.Controllers.ActionController)
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Toast = require(UI.Toast)
local GoalText = require(UI.GoalText)

local C = Theme.colors
local F = Theme.font

type Snapshot = Types.Snapshot

export type Card = {
	key: string, -- dedupe key (route + target)
	kind: string, -- "urgent" | "guide" | "ready" | "goal" | "idea"
	caption: string,
	title: string,
	line: string,
	button: string,
	route: string, -- "guide" | "collect" | "lab_design" | "lab_train" | "lab_release" | "page:<entry>.<tab>" | "open:<app>/<section>"
	modelId: string?,
}
export type CardUi = { guide: any?, money: number? }

local HomeApp = {}

HomeApp.MAX_CARDS = 3

local nav: any = nil
local guideView: any = nil
local guideAction: ((view: any) -> ())? = nil
local render: () -> () = function() end
local cardButtons: { TextButton } = {}

-- route of a next-goal view (GoalText.describe) and its button label
local function goalRoute(view: any): (string, string)
	local app, section = view.app, view.section
	if app == "lab" then
		if section == "release" then
			return "lab_release", "LAUNCH ›"
		elseif view.training then
			return "lab_train", "WATCH ›"
		end
		return "open:lab/" .. (section or ""), "OPEN LAB ›"
	elseif app == "market" then
		return "open:market/", "OPEN MARKET ›"
	elseif app == "empire" then
		if section == "clients" then
			return "open:empire/clients", "OPEN CLIENTS ›"
		elseif section == "office" then
			return "open:empire/office", "OPEN OFFICE ›"
		elseif section == "settings" then
			return "open:empire/settings", "OPEN SETTINGS ›"
		elseif section == "research" then
			return "open:empire/research", "OPEN RESEARCH ›"
		end
		return "open:empire/" .. (section or ""), "OPEN ›"
	end
	return "open:" .. tostring(app) .. "/" .. (section or ""), "OPEN ›"
end

local function modelLabel(m: any): string
	return tostring(m.name) .. " v" .. tostring(m.version or 1)
end

local function firstWith(data: any, status: string): any
	for _, id in data.modelOrder do
		local m = data.models[id]
		if m and m.status == status then
			return m
		end
	end
	return nil
end

-- The cards of Home → Today, first 3 distinct in this priority (B4): urgent, the guide, ready, the next goal (not
-- while the guide shows), fillers. Pure: snapshot + ui in, cards out. Never a Shop card.
function HomeApp.cards(snapshot: Snapshot, ui: CardUi?): { Card }
	local data: any = snapshot.data
	local live: any = snapshot.live
	local e = data.empire
	local u: CardUi = ui or {}
	local money = if typeof(u.money) == "number" then u.money :: number else (tonumber(data.money) or 0)
	local out: { Card } = {}
	local seen: { [string]: boolean } = {}
	local function add(card: Card)
		if #out >= HomeApp.MAX_CARDS or seen[card.key] then
			return
		end
		seen[card.key] = true
		table.insert(out, card)
	end

	-- 1. urgent
	local training = data.training
	if training and training.event and training.event.pending then
		local def = ModelConfig.getEvent(training.event.id)
		add({ key = "lab_train", kind = "urgent", caption = "DECISION", title = "Decide: " .. (if def then def.title else "training event"),
			line = "If you wait, the default is picked.", button = "DECIDE ›", route = "lab_train" })
	end
	if money < 0 then
		add({ key = "page:team.settings", kind = "urgent", caption = "WARNING", title = "Cash below $0 · lower costs",
			line = "Raise prices or set the HR budget lower.", button = "OPEN SETTINGS ›", route = "page:team.settings" })
	end
	local capacity, load, waitlist = tonumber(live.capacity) or 0, tonumber(live.load) or 0, tonumber(live.waitlist) or 0
	if capacity > 0 and waitlist > 0 and load / capacity >= 0.95 then
		add({ key = "page:lab.gpus", kind = "urgent", caption = "SERVERS", title = "Servers full · buy a GPU",
			line = Format.compact(waitlist) .. " users are waiting.", button = "OPEN GPUS ›", route = "page:lab.gpus" })
	end

	-- 2. the guide (same title, line and action as the HUD card; step 1 uses the Menu line)
	local guide = u.guide
	local guiding = guide ~= nil and guide.card ~= false
	if guiding and guide then
		local action = guide.action
		add({ key = if action then action.route .. (action.modelId or "") else "guide", kind = "guide",
			caption = string.format("FIRST STEPS · %d/%d", guide.step, TutorialMath.STEPS), title = guide.title,
			line = guide.line, button = if action then action.label else "", route = "guide", modelId = if action then action.modelId else nil })
	end

	-- 3. ready
	local trained = firstWith(data, "trained")
	if trained then
		add({ key = "lab_release" .. trained.id, kind = "ready", caption = "READY", title = "Launch " .. modelLabel(trained),
			line = "Its Launch Day is ready.", button = "LAUNCH ›", route = "lab_release", modelId = trained.id })
	end
	local total, count = TutorialMath.claimable(data)
	if total > 0 then
		local name = ""
		for _, q in EmpireConfig.QUESTS do
			if not e.quests[q.id] and EmpireMath.progress(data, q) >= q.target then
				name = q.name
				break
			end
		end
		add({ key = "collect", kind = "ready", caption = "READY", title = "Collect $" .. Format.int(total),
			line = if count == 1 then "Goal done: " .. name .. "." else string.format("%d goals done.", count), button = "COLLECT", route = "collect" })
	end
	local office = math.clamp(math.floor(tonumber(e.office) or 1), 1, #EmpireConfig.OFFICES)
	local nextOffice = EmpireConfig.OFFICES[office + 1]
	if nextOffice and money >= nextOffice.price and (office > 1 or (tonumber(e.contractsCompleted) or 0) >= 1) then
		add({ key = "page:team.office", kind = "ready", caption = "READY", title = "Move to " .. nextOffice.name,
			line = string.format("%d desks, %d product lines.", nextOffice.staff, ModelMath.productSlots(office + 1)), button = "MOVE ›", route = "page:team.office" })
	end
	local fresh = 0
	if typeof(e.applicants) == "table" then
		for _, a in e.applicants do
			if typeof(a) == "table" and a.st == "new" then
				fresh += 1
			end
		end
	end
	if fresh > 0 then
		add({ key = "page:team.staff", kind = "ready", caption = "PEOPLE", title = string.format("Meet %d applicant%s", fresh, if fresh == 1 then "" else "s"),
			line = "Invite one for an interview.", button = "OPEN TEAM ›", route = "page:team.staff" })
	end

	-- 4. the next goal (worded like the HUD card), not while the guide card shows
	if not guiding then
		local view = GoalText.describe(snapshot, nil)
		if view.id ~= "done" and view.id ~= "decision" then
			local route, label = goalRoute(view)
			local key = if route == "lab_release" then "lab_release" .. tostring(view.releaseId) else route
			add({ key = key, kind = "goal", caption = "NEXT GOAL", title = view.title, line = if view.shortProgress ~= "" then view.shortProgress else view.body,
				button = label, route = route, modelId = view.releaseId })
		end
	end

	-- 5. fillers (never during the guide, never invented)
	if not TutorialMath.active(data) then
		local liveModel = firstWith(data, "live")
		if training == nil and (tonumber(data.stats.modelsTrained) or 0) >= 1 then
			add({ key = "lab_design", kind = "idea", caption = "IDEA", title = "Train a new AI",
				line = if liveModel then "A successor takes over 90 % of " .. modelLabel(liveModel) .. "'s users." else "Design your next model in the Studio.",
				button = if liveModel then "SUCCESSOR ›" else "DESIGN ›", route = "lab_design" })
		end
		local hr = e.hr
		local auto = typeof(hr) ~= "table" or hr.auto ~= false
		local free = EmpireConfig.OFFICES[office].staff - EmpireMath.staff(e)
		if not auto and free > 0 then
			add({ key = "page:team.staff", kind = "idea", caption = "IDEA", title = "Hire",
				line = string.format("%d free desk%s.", free, if free == 1 then "" else "s"), button = "OPEN TEAM ›", route = "page:team.staff" })
		end
		local fleet = ModelMath.fleet(data.gpus)
		local biggest = 0
		for _, m in data.models do
			local size = ModelConfig.getSize(m.sizeId)
			if size then
				biggest = math.max(biggest, size.vram)
			end
		end
		for _, size in ModelConfig.SIZES do
			if size.vram > biggest and size.vram > fleet.vram then
				add({ key = "page:lab.gpus", kind = "idea", caption = "IDEA", title = "Buy GPUs",
					line = string.format("%s needs %d GB more VRAM.", size.label, size.vram - fleet.vram), button = "OPEN GPUS ›", route = "page:lab.gpus" })
				break
			end
		end
	end
	return out
end

-- the live strip values (pure): cash, net per day, users, live models, training state, daily grant amount or nil
function HomeApp.strip(snapshot: Snapshot, money: number?): { [string]: any }
	local data: any = snapshot.data
	local live: any = snapshot.live
	local liveCount = 0
	for _, m in data.models do
		if m.status == "live" then
			liveCount += 1
		end
	end
	local training = data.training
	local trainingText = "idle"
	if training then
		if training.event and training.event.pending then
			trainingText = "decide"
		else
			trainingText = Format.percent((tonumber(training.workDone) or 0) / math.max(1, tonumber(training.workTotal) or 1))
		end
	end
	local e = data.empire
	local day = math.floor((tonumber(snapshot.serverTime) or 0) / 86400)
	local daily = if typeof(e.daily) == "table" then e.daily else { day = -1, streak = 0 }
	local dailyAmount: number? = nil
	if (tonumber(daily.day) or -1) < day then
		local streak = if daily.day == day - 1 then math.min(7, (tonumber(daily.streak) or 0) + 1) else 1
		dailyAmount = 1000 + (streak - 1) * 500
	end
	-- shop package (SHOP_SPEC 5.2.7): while a boost runs, the TRAINING cell reads "×1.5 · 9 min" (Overclock) and the
	-- NET caption "NET · KEYNOTE 12 MIN"; not tappable, never an offer
	local netCaption = "NET"
	local keynoteLeft = ShopMath.boostLeft(data, "keynote")
	if keynoteLeft > 0 then
		netCaption = `NET · KEYNOTE {math.ceil(keynoteLeft / 60)} MIN`
	end
	local overclockLeft = ShopMath.boostLeft(data, "overclock")
	if overclockLeft > 0 and training and not (training.event and training.event.pending) then
		trainingText = `×1.5 · {math.ceil(overclockLeft / 60)} min`
	end
	-- fix round 1 (review): before the first income, while the guide runs, the garage upkeep is muted ("NET · UPKEEP")
	local revenue = tonumber((snapshot.live :: any).revenue) or 0
	-- (cash below $0 is a real warning: plain NET in red then)
	local upkeepOnly = TutorialMath.active(data) and revenue <= 0 and (tonumber((snapshot.live :: any).cost) or 0) > 0
		and (money or tonumber(data.money) or 0) >= 0
	if upkeepOnly and keynoteLeft <= 0 then
		netCaption = "NET · UPKEEP"
	end
	return {
		netCaption = netCaption,
		netMuted = upkeepOnly,
		cash = Format.money(money or tonumber(data.money) or 0),
		net = (function(): string
			local n = (tonumber(live.revenue) or 0) - (tonumber(live.cost) or 0)
			return if n == 0 then "$0/day" else Format.perDay(n) -- never "+$0"
		end)(),
		netPositive = (tonumber(live.revenue) or 0) >= (tonumber(live.cost) or 0),
		users = Format.compact(tonumber(live.users) or 0),
		live = if liveCount == 1 then "1 model" else tostring(liveCount) .. " models",
		training = trainingText,
		daily = dailyAmount,
	}
end

-- the guide view changes up to 5 times a second: the cards re-render only while Home is on screen (onShow renders)
local pageFrame: Frame? = nil
local function onScreen(): boolean
	local node: Instance? = pageFrame
	if node == nil then
		return false
	end
	while node do
		if node:IsA("GuiObject") and not (node :: GuiObject).Visible then
			return false
		end
		if node:IsA("LayerCollector") then
			return true
		end
		node = node.Parent
	end
	return false
end

local guideSig = ""
local function signature(view: any): string
	if view == nil then
		return ""
	end
	local action = view.action
	return table.concat({ tostring(view.step), tostring(view.sub), tostring(view.title), tostring(view.line), tostring(view.card),
		tostring(view.collect), if action then tostring(action.label) .. tostring(action.modelId) else "" }, "|")
end

function HomeApp.setGuide(view: any)
	local sig = signature(view)
	local changed = sig ~= guideSig
	guideSig = sig
	guideView = view
	if changed and onScreen() then
		render()
	end
end

function HomeApp.setGuideHandler(fn: (view: any) -> ())
	guideAction = fn
end

-- the guide card's button (ring target "menu_lab" on Home) and the first card button (gamepad selection)
function HomeApp.guideButton(): TextButton?
	for _, b in cardButtons do
		if b.Parent and b:GetAttribute("Guide") == true and b.Visible then
			return b
		end
	end
	return nil
end

function HomeApp.firstButton(): TextButton?
	local b = cardButtons[1]
	return if b and b.Parent and b.Visible then b else nil
end

-- conservative greedy word wrap (bold glyphs ~0.58 em, a space counted as a glyph): over-estimating only costs a
-- line of card text, under-estimating would let a wrapped title run into the line below it
local TITLE_EM = 0.58
local function wrappedLines(text: string, glyph: number, width: number): number
	local lines, used = 1, 0
	for word in string.gmatch(text, "%S+") do
		local w = (utf8.len(word) or #word) * glyph
		if used == 0 then
			used = w
		elseif used + glyph + w <= width then
			used += glyph + w
		else
			lines += 1
			used = w
		end
	end
	return lines
end

local function runRoute(card: Card)
	local navigation = nav
	if card.route == "guide" then
		local fn, view = guideAction, guideView
		if fn and view then
			fn(view)
		end
	elseif card.route == "collect" then
		task.spawn(function()
			local ok, result = ActionController.call("ClaimQuest", { all = true })
			if ok and typeof(result.total) == "number" and result.total > 0 then
				Toast.show("success", TutorialMath.collectText(result.total, if typeof(result.claimed) == "table" then #result.claimed else 0), 4)
			end
		end)
	elseif navigation then
		navigation.route(card.route, card.modelId)
	end
end

local ICONS: { [string]: string } = { urgent = "compute", guide = "lab", ready = "market", goal = "home", idea = "lab" }

function HomeApp.mount(parent: Frame, navigation: any)
	nav = navigation
	local page = Kit.frame(parent)
	page.Name = "HomeToday"
	pageFrame = page
	local list = Kit.list(page, 0)
	list.Padding = UDim.new(0, 8)

	-- fix round 1 (review): 44 px (was 34) so the 74 px "All goals ›" target starts at the page clip, not 10 px above
	-- it (phone total 10 + 44 + 8 + 262 + 14 + 98 = 436 px, the B4 budget)
	local top = Kit.frame(page, UDim2.new(1, 0, 0, 44))
	top.LayoutOrder = 1
	local line = Kit.text(top, "What to do next", 22, F.medium, C.muted)
	line.AnchorPoint = Vector2.new(0, 0.5)
	line.Position = UDim2.fromScale(0, 0.5)
	local all = Instance.new("TextButton")
	all.Name = "AllGoals"
	all.AutoButtonColor = false
	all.BackgroundTransparency = 1
	all.Text = "All goals ›"
	all.TextSize = 22
	all.Font = F.bold
	all.TextXAlignment = Enum.TextXAlignment.Right
	all.Size = UDim2.fromOffset(170, 74)
	all.AnchorPoint = Vector2.new(1, 0.5)
	all.Position = UDim2.new(1, 0, 0.5, 5)
	all.Selectable = true
	all.Parent = top
	Theme.bindAccent(all, "TextColor3")
	Kit.onClick(all, function()
		if nav then
			nav.route("page:home.goals")
		end
	end)

	local row = Kit.frame(page, UDim2.new(1, 0, 0, 262))
	row.Name = "Cards"
	row.LayoutOrder = 2
	local rowList = Kit.list(row, 14, true)
	rowList.VerticalAlignment = Enum.VerticalAlignment.Top
	type CardView = { frame: Frame, caption: TextLabel, icon: Kit.Icon, title: TextLabel, line: TextLabel, primary: TextButton, secondary: TextButton }
	local cardUis: { CardView } = {}
	local shown: { Card } = {}
	for i = 1, HomeApp.MAX_CARDS do
		local f = Kit.frame(row, UDim2.new(1 / 3, -28 / 3, 1, 0))
		f.Name = "Card" .. i
		f.LayoutOrder = i
		f.BackgroundTransparency = 0
		f.BackgroundColor3 = C.panel2
		Kit.corner(f, 14)
		Kit.stroke(f, 0.9)
		Kit.padding(f, 18, 20, 18, 20)
		local captionRow = Kit.frame(f, UDim2.new(1, 0, 0, 28))
		local icon = Kit.icon(captionRow, "home", 24)
		icon.frame.Position = UDim2.fromOffset(0, 2)
		local caption = Kit.text(captionRow, "", 20, F.bold, C.muted)
		caption.Position = UDim2.fromOffset(34, 1)
		local title = Kit.text(f, "", 28, F.bold, C.text)
		title.Name = "Title"
		title.AutomaticSize = Enum.AutomaticSize.None
		title.Size = UDim2.new(1, 0, 0, 64)
		title.Position = UDim2.fromOffset(0, 38)
		title.TextWrapped = true
		title.TextYAlignment = Enum.TextYAlignment.Top
		title.TextTruncate = Enum.TextTruncate.AtEnd
		local body = Kit.text(f, "", 22, F.regular, C.muted)
		body.Name = "Line"
		body.AutomaticSize = Enum.AutomaticSize.None
		body.Size = UDim2.new(1, 0, 0, 54)
		body.Position = UDim2.fromOffset(0, 104)
		body.TextWrapped = true
		body.TextYAlignment = Enum.TextYAlignment.Top
		body.TextTruncate = Enum.TextTruncate.AtEnd
		-- the first card's button is primary, the others secondary (Kit styles are fixed at creation: two buttons)
		local primary = Kit.button(f, "", "primary", UDim2.new(1, 0, 0, 74))
		primary.AnchorPoint = Vector2.new(0, 1)
		primary.Position = UDim2.fromScale(0, 1)
		primary.TextSize = 24
		primary.Name = "Action"
		primary.Selectable = true
		local secondary = Kit.button(f, "", "secondary", UDim2.new(1, 0, 0, 74))
		secondary.AnchorPoint = Vector2.new(0, 1)
		secondary.Position = UDim2.fromScale(0, 1)
		secondary.TextSize = 24
		secondary.Name = "Action"
		secondary.Selectable = true
		for _, b in { primary, secondary } do
			Kit.onClick(b, function()
				local card = shown[i]
				if card then
					runRoute(card)
				end
			end)
		end
		cardUis[i] = { frame = f, caption = caption, icon = icon, title = title, line = body, primary = primary, secondary = secondary }
	end

	-- live strip: CASH · NET · USERS · LIVE · TRAINING (+ DAILY +$X while the grant waits)
	local strip = Kit.frame(page, UDim2.new(1, 0, 0, 98))
	strip.Name = "LiveStrip"
	strip.LayoutOrder = 3
	strip.BackgroundTransparency = 0
	strip.BackgroundColor3 = C.panel2
	Kit.corner(strip, 14)
	Kit.stroke(strip, 0.9)
	Kit.padding(strip, 12, 12, 12, 22)
	local stripList = Kit.list(strip, 30, true)
	stripList.VerticalAlignment = Enum.VerticalAlignment.Center
	local values: { [string]: TextLabel } = {}
	local captions: { [string]: TextLabel } = {}
	for i, def in { { "cash", "CASH" }, { "net", "NET" }, { "users", "USERS" }, { "live", "LIVE" }, { "training", "TRAINING" } } do
		local cell = Kit.frame(strip, UDim2.new(0, 0, 1, 0))
		cell.AutomaticSize = Enum.AutomaticSize.X
		cell.LayoutOrder = i
		Kit.list(cell, 2).VerticalAlignment = Enum.VerticalAlignment.Center
		local cap = Kit.text(cell, def[2], 20, F.bold, C.muted)
		cap.LayoutOrder = 1
		local value = Kit.text(cell, "", 28, F.bold, C.text)
		value.Name = "Value_" .. def[1]
		value.LayoutOrder = 2
		values[def[1]] = value
		captions[def[1]] = cap
	end
	local daily = Kit.button(strip, "DAILY", "secondary", UDim2.fromOffset(220, 74))
	daily.Name = "Daily"
	daily.LayoutOrder = 9
	daily.TextSize = 22
	daily.Selectable = true
	Kit.onClick(daily, function()
		task.spawn(function()
			local ok = ActionController.call("ClaimDaily", {})
			if ok then
				Toast.show("success", "Daily grant collected! +15 research points")
			end
		end)
	end)

	-- desktop only: GOALS · n of 12 done, bar, next goal and its reward
	local goals = Kit.frame(page, UDim2.new(1, 0, 0, 76))
	goals.Name = "GoalsRow"
	goals.LayoutOrder = 4
	goals.BackgroundTransparency = 0
	goals.BackgroundColor3 = C.panel2
	goals.Visible = false
	Kit.corner(goals, 14)
	Kit.stroke(goals, 0.9)
	Kit.padding(goals, 0, 22, 0, 22)
	local goalsLabel = Kit.text(goals, "", 24, F.bold, C.text)
	goalsLabel.AnchorPoint = Vector2.new(0, 0.5)
	goalsLabel.Position = UDim2.fromScale(0, 0.5)
	goalsLabel.RichText = true
	local goalsBar = Kit.bar(goals, 10)
	goalsBar.frame.AnchorPoint = Vector2.new(0, 0.5)
	goalsBar.frame.Position = UDim2.new(0, 330, 0.5, 0)
	goalsBar.frame.Size = UDim2.new(0.4, 0, 0, 10)
	local goalsNext = Kit.text(goals, "", 22, F.regular, C.muted)
	goalsNext.AnchorPoint = Vector2.new(1, 0.5)
	goalsNext.Position = UDim2.fromScale(1, 0.5)
	goalsNext.TextXAlignment = Enum.TextXAlignment.Right

	render = function()
		local snapshot = StateController.snapshot
		if not snapshot or not snapshot.data.company then
			return
		end
		-- design px per screen px (the shell's UIScale chain)
		local scale = 1
		local node: Instance? = parent
		while node do
			local u = node:FindFirstChildOfClass("UIScale")
			if u then
				scale *= u.Scale
			end
			node = node.Parent
		end
		scale = math.max(0.01, scale)
		-- the extra desktop height holds the Goals row (canvas taller than the phone's 520)
		local tall = parent.AbsoluteSize.Y > 0 and parent.AbsoluteSize.Y / scale > 480
		goals.Visible = tall
		row.Size = UDim2.new(1, 0, 0, if tall then 290 else 262)
		local cards = HomeApp.cards(snapshot, { guide = guideView, money = StateController.money() })
		shown = cards
		table.clear(cardButtons)
		for i, ui in cardUis do
			local card = cards[i]
			ui.frame.Visible = card ~= nil
			if card then
				ui.caption.Text = card.caption
				ui.caption.TextColor3 = if card.kind == "urgent" then C.warn else C.muted
				ui.icon.setColor(if card.kind == "urgent" then C.warn elseif card.kind == "guide" then Theme.accent else C.dim)
				ui.title.Text = card.title
				ui.line.Text = card.line
				-- the line sits right under the title (1 or 2 lines); on the phone a 2-line title leaves room for one
				-- line only, so the text never runs into the button (or the guide ring around it)
				local innerWidth = ui.frame.AbsoluteSize.X / scale - 40
				local oneLine = innerWidth > 0 and wrappedLines(card.title, 28 * TITLE_EM, innerWidth) <= 1
				ui.title.Size = UDim2.new(1, 0, 0, if oneLine then 34 else 64)
				ui.line.Position = UDim2.fromOffset(0, if oneLine then 78 else 106)
				ui.line.Size = UDim2.new(1, 0, 0, if oneLine or tall then 54 else 27)
				local primary = i == 1
				ui.primary.Visible = primary and card.button ~= ""
				ui.secondary.Visible = not primary and card.button ~= ""
				local b = if primary then ui.primary else ui.secondary
				b.Text = card.button
				b:SetAttribute("Guide", card.route == "guide")
				table.insert(cardButtons, b)
				ui.primary:SetAttribute("Guide", primary and card.route == "guide")
				ui.secondary:SetAttribute("Guide", (not primary) and card.route == "guide")
			end
		end
		local strip = HomeApp.strip(snapshot, StateController.money())
		values.cash.Text = strip.cash
		values.net.Text = strip.net
		captions.net.Text = strip.netCaption or "NET" -- shop package (5.2.7)
		values.net.TextColor3 = if strip.netMuted then C.muted elseif strip.netPositive then C.good else C.bad
		values.users.Text = strip.users
		values.live.Text = strip.live
		values.training.Text = strip.training
		daily.Visible = strip.daily ~= nil
		daily.Text = if strip.daily then "DAILY +" .. Format.money(strip.daily) else "DAILY"
		local done, nextQuest = 0, nil
		for _, q in EmpireConfig.QUESTS do
			if snapshot.data.empire.quests[q.id] then
				done += 1
			elseif nextQuest == nil then
				nextQuest = q
			end
		end
		goalsLabel.Text = string.format('<font color="#9EADA8">GOALS</font>   %d of %d done', done, #EmpireConfig.QUESTS)
		goalsBar.set(done / #EmpireConfig.QUESTS)
		goalsNext.Text = if nextQuest then "Next: " .. nextQuest.name .. " · +" .. Format.money(nextQuest.reward) else "Every goal done"
	end
	StateController.onChange(function()
		if onScreen() then
			render()
		end
	end)
	-- the desktop Goals row depends on the page height, known only after the first layout
	parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(function()
			if onScreen() then
				render()
			end
		end)
	end)
	render()
end

function HomeApp.onShow()
	render()
end

return HomeApp
