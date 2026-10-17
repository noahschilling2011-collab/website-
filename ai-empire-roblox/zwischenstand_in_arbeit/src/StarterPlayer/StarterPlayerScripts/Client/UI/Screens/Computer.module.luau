--!strict
-- The Menu (ONBOARDING_SPEC B, menu package): one shell with 6 labelled entries in a rail (Home, Lab, Market, Clients,
-- Team, Shop), at most 5 sub-tabs per entry in the header and at most 2 levels. It replaces the old Computer window
-- (9 apps + 7 journey chips + 9 Company tabs); the module keeps its name and contract (B12): Computer.open / close /
-- toggle / isOpen / show, the root frame "Computer" (the Model Studio's host, LAB_SPEC 3.1) and the LabApp container.
--   * scale: the shell has its own UIScale with the Studio formula s = clamp(min(A.X/1254, A.Y/520), 0.5, 1.25)
--     (phone 0.598, canvas 1254 x 520; 1280x720 1.021, canvas 1254 x 648); text >= 20 px (12 pt), targets >= 74 px
--   * pages: native (Home; the Shop once the shop package rebuilds it) at the shell scale; Lab → Models at today's
--     UIRoot scale (LabApp's compact tokens); every other (legacy) page at max(UIRoot scale, 0.80) effective
--   * routes: Computer.open(appId, section) keeps every old (app, section) pair working (B9 table in ROUTES below)
--   * unlock waves + NEW badges from state (TutorialMath.unlockedKeys, empire.tutorial.seen); deep links never blocked
--   * "‹" = back one level (sub-tab → default, entry → Home, Home → close), "×" closes; gamepad L1 toggles, B = back
-- Page host API for the shop package (HANDOFF.md): Computer.registerPage(key, def) before mount replaces a page.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Format = require(ReplicatedStorage.Shared.Format)
local Types = require(ReplicatedStorage.Shared.Types)
local Net = require(ReplicatedStorage.Shared.Net)
local TutorialMath = require(ReplicatedStorage.Shared.TutorialMath)

local UI = script.Parent.Parent
local Client = UI.Parent
local StateController = require(Client.Controllers.StateController)
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local GoalText = require(UI.GoalText)
local LabApp = require(UI.Apps.LabApp)
local DataApp = require(UI.Apps.DataApp)
local ComputeApp = require(UI.Apps.ComputeApp)
local MarketApp = require(UI.Apps.MarketApp)
local StudioApp = require(UI.Apps.StudioApp)
local ArenaApp = require(UI.Apps.ArenaApp)
local CampusApp = require(UI.Apps.CampusApp)
local EmpireApp = require(UI.Apps.EmpireApp)
local ShopApp = require(UI.Apps.ShopApp)
local HomeApp = require(UI.Apps.HomeApp)
local ShopCore = require(UI.Shop.ShopCore)
local UseSheet = require(UI.Shop.UseSheet)

local C = Theme.colors
local F = Theme.font

type AppModule = { mount: (Frame, any) -> (), onShow: () -> () }
type PartModule = { mountPart: (Frame, string, any) -> { show: () -> () } }
export type PageKind = "native" | "models" | "legacy"
-- A page: one whole app (app) or stacked parts of the composite apps (parts = {{module, partId}}) in one scroll.
export type PartSpec = { mod: any, id: string }
export type PageDef = { name: string, kind: PageKind, app: AppModule?, parts: { PartSpec }?, line: string? }
export type Tab = { id: string, label: string }
export type Entry = { id: string, label: string, icon: string, line: string, tabs: { Tab } }

local Computer = {}

Computer.CANVAS = Vector2.new(1254, 520) -- design canvas (LAB_SPEC 3.2)
Computer.RAIL = 120
Computer.HEADER = 84
Computer.LEGACY_SCALE = 0.80 -- legacy pages: at least 0.80 effective (14 px -> 11.2 pt on an iPhone)
-- fix round 1 (review): until P3 gives the old pages native tokens, their text never goes below 14 px (x 0.80 =
-- 11.2 pt on an iPhone, above Apple's 11 pt floor); their 11-13 px captions, tags and notes are raised on mount
Computer.LEGACY_TEXT_MIN = 14

Computer.ENTRIES = {
	{ id = "home", label = "Home", icon = "home", line = "What to do next",
		tabs = { { id = "today", label = "Today" }, { id = "money", label = "Money" }, { id = "goals", label = "Goals" } } },
	{ id = "lab", label = "Lab", icon = "lab", line = "Build and train your AIs",
		tabs = { { id = "models", label = "Models" }, { id = "data", label = "Data" }, { id = "gpus", label = "GPUs" }, { id = "research", label = "Research" }, { id = "arena", label = "Test arena" } } },
	{ id = "market", label = "Market", icon = "tag", line = "Your AIs, prices and users",
		tabs = { { id = "myais", label = "My AIs" }, { id = "lines", label = "Lines" }, { id = "projects", label = "Projects" }, { id = "leaderboard", label = "Leaderboard" } } },
	{ id = "clients", label = "Clients", icon = "clients", line = "Business deals that pay every day",
		tabs = { { id = "clients", label = "Clients" }, { id = "receipts", label = "Receipts" } } },
	{ id = "team", label = "Team", icon = "team", line = "Staff, office and cars",
		tabs = { { id = "staff", label = "Staff" }, { id = "office", label = "Office" }, { id = "fleet", label = "Fleet" }, { id = "campus", label = "Campus" }, { id = "settings", label = "Settings" } } },
	{ id = "shop", label = "Shop", icon = "shop", line = "Optional extras for Robux. You can reach every office and every client without them.",
		-- shop package (SHOP_SPEC 5.1): 5 native sub-tabs; ShopApp.tabVisible hides empty ones (live: only listed items)
		tabs = { { id = "home", label = "Home" }, { id = "speedups", label = "Speed-ups" }, { id = "boosts", label = "Boosts" }, { id = "style", label = "Style" }, { id = "extras", label = "Extras" } } },
} :: { Entry }

local function part(mod: any, id: string): PartSpec
	return { mod = mod, id = id }
end
local PAGES: { [string]: PageDef } = {
	["home.today"] = { name = "Page_home_today", kind = "native", app = HomeApp :: any },
	["home.money"] = { name = "Page_home_money", kind = "legacy", parts = { part(EmpireApp, "homeMoney") } },
	["home.goals"] = { name = "Page_home_goals", kind = "legacy", parts = { part(EmpireApp, "homeGoals") } },
	["lab.models"] = { name = "lab", kind = "models", app = LabApp :: any },
	["lab.data"] = { name = "data", kind = "legacy", app = DataApp :: any },
	["lab.gpus"] = { name = "compute", kind = "legacy", app = ComputeApp :: any },
	["lab.research"] = { name = "Page_lab_research", kind = "legacy", parts = { part(EmpireApp, "research"), part(MarketApp, "access") } },
	["lab.arena"] = { name = "arena", kind = "legacy", app = ArenaApp :: any },
	["market.myais"] = { name = "market", kind = "legacy", parts = { part(MarketApp, "myais") } },
	["market.lines"] = { name = "Page_market_lines", kind = "legacy", parts = { part(MarketApp, "lines") } },
	["market.projects"] = { name = "studio", kind = "legacy", app = StudioApp :: any },
	["market.leaderboard"] = { name = "Page_market_leaderboard", kind = "legacy", parts = { part(MarketApp, "leaderboard"), part(EmpireApp, "board") } },
	["clients.clients"] = { name = "Page_clients_clients", kind = "legacy", parts = { part(EmpireApp, "clients") } },
	["clients.receipts"] = { name = "Page_clients_receipts", kind = "legacy", parts = { part(MarketApp, "receipts") } },
	["team.staff"] = { name = "Page_team_staff", kind = "legacy", parts = { part(EmpireApp, "team") } },
	["team.office"] = { name = "Page_team_office", kind = "legacy", parts = { part(EmpireApp, "office"), part(CampusApp, "building") } },
	["team.fleet"] = { name = "Page_team_fleet", kind = "legacy", parts = { part(CampusApp, "fleet") } },
	["team.campus"] = { name = "campus", kind = "legacy", parts = { part(CampusApp, "campus") } },
	["team.settings"] = { name = "Page_team_settings", kind = "legacy", parts = { part(EmpireApp, "settings") } },
	-- shop package (SHOP_SPEC 5.1): native pages, one ShopApp part each (ShopApp.mountPart)
	["shop.home"] = { name = "Page_shop_home", kind = "native", parts = { part(ShopApp, "home") } },
	["shop.speedups"] = { name = "Page_shop_speedups", kind = "native", parts = { part(ShopApp, "speedups") } },
	["shop.boosts"] = { name = "Page_shop_boosts", kind = "native", parts = { part(ShopApp, "boosts") } },
	["shop.style"] = { name = "Page_shop_style", kind = "native", parts = { part(ShopApp, "style") } },
	["shop.extras"] = { name = "Page_shop_extras", kind = "native", parts = { part(ShopApp, "extras") } },
}
Computer.PAGES = PAGES

-- Old (app, section) pairs -> page key (+ the section a Lab page still gets). B9.
local EMPIRE_SECTIONS: { [string]: string } = {
	overview = "home.today", clients = "clients.clients", contracts = "clients.clients", money = "home.money", team = "team.staff",
	research = "lab.research", milestones = "home.goals", office = "team.office", settings = "team.settings", board = "market.leaderboard",
}
local MARKET_SECTIONS: { [string]: string } = {
	myais = "market.myais", lines = "market.lines", leaderboard = "market.leaderboard", projects = "market.projects",
	access = "lab.research", receipts = "clients.receipts",
}
local CAMPUS_SECTIONS: { [string]: string } = { access = "team.campus", shops = "team.campus", fleet = "team.fleet", building = "team.office" }

local function entryDefOf(id: string): Entry?
	for _, entry in Computer.ENTRIES do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

-- (pageKey, labSection) for an old or new (app, section) pair; unknown ids land on Home
function Computer.route(appId: string?, section: string?): (string, string?)
	local app = appId or "home"
	if app == "empire" then
		return EMPIRE_SECTIONS[section or "overview"] or "home.today", nil
	elseif app == "home" then
		if section == "money" or section == "goals" then
			return "home." .. section, nil
		end
		return "home.today", nil
	elseif app == "lab" then
		if section == "research" or section == "data" or section == "gpus" or section == "arena" then
			return "lab." .. section, nil
		end
		return "lab.models", section
	elseif app == "data" then
		return "lab.data", nil
	elseif app == "compute" then
		return "lab.gpus", nil
	elseif app == "market" then
		return MARKET_SECTIONS[section or "myais"] or "market.myais", nil
	elseif app == "studio" then
		return "market.projects", nil
	elseif app == "arena" then
		return "lab.arena", nil
	elseif app == "campus" then
		return CAMPUS_SECTIONS[section or ""] or "team.campus", nil
	elseif app == "shop" then
		-- every Shop tab page "shop.<tab>" (the shop package adds its sub-tabs); default = the entry's first tab
		local key = "shop." .. (section or "")
		if PAGES[key] then
			return key, nil
		end
		local entry = entryDefOf("shop")
		return if entry then "shop." .. entry.tabs[1].id else "shop.home", nil
	elseif app == "clients" then
		return if section == "receipts" then "clients.receipts" else "clients.clients", nil
	elseif app == "team" then
		local key = "team." .. (section or "staff")
		return if PAGES[key] then key else "team.staff", nil
	end
	return "home.today", nil
end

-- the TutorialMath unlock key of a page / entry (every Shop tab "shop.<tab>" -> "shop": the Shop opens as a whole)
local function unlockKey(pageKey: string): string
	return if string.sub(pageKey, 1, 5) == "shop." then "shop" else pageKey
end
local function entryOf(pageKey: string): string
	return string.match(pageKey, "^([%w]+)") or "home"
end
local function entryDef(id: string): Entry?
	for _, entry in Computer.ENTRIES do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

-- page host API (shop package): replace or add a page before Computer.mount
function Computer.registerPage(key: string, def: PageDef)
	PAGES[key] = def
end

---------------------------------------------------------------------------- state

type Page = { key: string, def: PageDef, frame: Frame, scale: UIScale, parts: { { show: () -> () } }, mounted: boolean }
local root: Frame? = nil
local shell: Frame? = nil
local shellScale: UIScale? = nil
local dim: TextButton? = nil
local blur: BlurEffect? = nil
local pages: { [string]: Page } = {}
local current = "home.today"
local lastTab: { [string]: string } = {}
local opened = false
local openFilter: ((string?, string?) -> (string?, string?))? = nil
local deepUnlocked: { [string]: boolean } = {}
local seenLocal: { [string]: boolean } = {}
local pendingSeen: { string } = {}
local flushScheduled = false
local canvas = Computer.CANVAS
local paintAll: () -> () = function() end
local showLocked: (entry: Entry) -> () = function(_entry: Entry) end
local lockedShade: GuiObject? = nil
local onPageShown: { (key: string) -> () } = {}

-- the product of every UIScale from `inst` up to its ScreenGui (except `skip`)
local function designScale(inst: Instance, skip: UIScale?): number
	local s = 1
	local node: Instance? = inst
	while node do
		local u = node:FindFirstChildOfClass("UIScale")
		if u and u ~= skip then
			s *= u.Scale
		end
		node = node.Parent
	end
	return if s > 0 then s else 1
end

function Computer.isOpen(): boolean
	return opened
end

-- the player plays with a gamepad right now (selection only then: a PC with a pad plugged in keeps the mouse flow)
local function padActive(): boolean
	local ok, preferred = pcall(function(): any
		return (UserInputService :: any).PreferredInput
	end)
	if ok and typeof(preferred) == "EnumItem" then
		return preferred == Enum.PreferredInput.Gamepad
	end
	return UserInputService.GamepadEnabled and not UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end
Computer.padActive = padActive

function Computer.current(): string
	return current
end

-- guide redirect (ONBOARDING_SPEC A8): GuideController maps opens of Home / the Company app to the Studio design
-- view during guide steps 1-2
function Computer.setOpenFilter(fn: ((string?, string?) -> (string?, string?))?)
	openFilter = fn
end

-- listeners: a page became visible (GuideController rings, tips)
function Computer.onPageShown(fn: (key: string) -> ())
	table.insert(onPageShown, fn)
end

-- unlocked = by state (unlock waves) or opened through a deep link this session
function Computer.isUnlocked(pageKey: string): boolean
	local snapshot = StateController.snapshot
	local key = unlockKey(pageKey)
	if deepUnlocked[key] then
		return true
	end
	if not snapshot then
		return key == "home" or key == "home.today"
	end
	return TutorialMath.isUnlocked(snapshot.data, key)
end

local function entryUnlocked(entry: Entry): boolean
	if entry.id == "shop" then
		return Computer.isUnlocked("shop.home")
	end
	return Computer.isUnlocked(entry.id)
end

-- NEW badge: a SEEN key that is unlocked and not opened yet; none while the guide runs; never the Shop
function Computer.isNew(key: string): boolean
	local snapshot = StateController.snapshot
	if not snapshot or key == "shop" or string.sub(key, 1, 5) == "shop." then
		return false -- the Shop never gets a NEW badge (B5)
	end
	if not table.find(TutorialMath.SEEN_KEYS, key) or seenLocal[key] then
		return false
	end
	local data: any = snapshot.data
	if TutorialMath.active(data) then
		return false
	end
	local t = data.empire.tutorial
	if typeof(t) == "table" and typeof(t.seen) == "table" and t.seen[key] == true then
		return false
	end
	return Computer.isUnlocked(key)
end

local function flushSeen()
	flushScheduled = false
	if #pendingSeen == 0 then
		return
	end
	local keys = {}
	for i = 1, math.min(8, #pendingSeen) do
		table.insert(keys, pendingSeen[i])
	end
	for _ = 1, #keys do
		table.remove(pendingSeen, 1)
	end
	task.spawn(function()
		pcall(function()
			Net.getFunction("EmpireAction"):InvokeServer({ action = "tutorial", op = "seen", keys = keys })
		end)
	end)
	if #pendingSeen > 0 then
		flushScheduled = true
		task.delay(1.5, flushSeen)
	end
end

local function markSeen(key: string)
	if not table.find(TutorialMath.SEEN_KEYS, key) or seenLocal[key] then
		return
	end
	local snapshot = StateController.snapshot
	local t = if snapshot then (snapshot.data :: any).empire.tutorial else nil
	seenLocal[key] = true
	if typeof(t) == "table" and typeof(t.seen) == "table" and t.seen[key] == true then
		return
	end
	table.insert(pendingSeen, key)
	if not flushScheduled then
		flushScheduled = true
		task.delay(1.5, flushSeen)
	end
end

---------------------------------------------------------------------------- pages

local function pageTarget(kind: PageKind, s: number, P: number): number
	if kind == "native" then
		return s
	elseif kind == "models" then
		return P
	end
	return math.max(P, Computer.LEGACY_SCALE)
end

local function applyPageScale(page: Page)
	local r, sh = root, shell
	if not r or not sh then
		return
	end
	local s = designScale(sh) -- the shell's effective scale (UIRoot x shell UIScale)
	local P = designScale(r) -- UIRoot scale
	local m = pageTarget(page.def.kind, s, P) / s
	page.scale.Scale = m
	page.frame.Size = UDim2.fromScale(1 / m, 1 / m)
end

-- the legacy text floor (LEGACY_TEXT_MIN) on one object; TextScaled labels size themselves
local function floorText(obj: Instance)
	if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
		local t = obj :: any
		if not t.TextScaled and t.TextSize < Computer.LEGACY_TEXT_MIN then
			t.TextSize = Computer.LEGACY_TEXT_MIN
		end
	end
end
local function floorPage(frame: Instance)
	for _, d in frame:GetDescendants() do
		floorText(d)
	end
end
Computer.floorPage = floorPage

local function mountPage(page: Page, nav: any)
	if page.mounted then
		return
	end
	page.mounted = true
	local def = page.def
	if def.kind == "legacy" then
		-- rows built later (refreshes) get the floor once their builder has set their TextSize (deferred)
		page.frame.DescendantAdded:Connect(function(d: Instance)
			task.defer(floorText, d)
		end)
	end
	if def.app then
		def.app.mount(page.frame, nav)
	elseif def.parts then
		local scroll = Kit.scroll(page.frame)
		scroll.Name = "PageScroll"
		Kit.padding(scroll, 2, 14, 24, 2)
		Kit.list(scroll, 18)
		for i, spec in def.parts do
			local mod: PartModule = spec.mod
			local holder = Kit.frame(scroll, UDim2.fromScale(1, 0))
			holder.Name = "Part_" .. spec.id
			holder.LayoutOrder = i
			holder.AutomaticSize = Enum.AutomaticSize.Y
			table.insert(page.parts, mod.mountPart(holder, spec.id, nav))
		end
	end
	if def.kind == "legacy" then
		floorPage(page.frame)
	end
end

-- gamepad (fix round 1): the selection is lost when it is outside the Menu (a HUD button), on a hidden page (a Home
-- card that deep-linked away) or gone; then the new page's first selectable button takes it
local function selectionLost(): boolean
	local selected = GuiService.SelectedObject
	local frame = root
	if not selected or not frame or not frame:IsAncestorOf(selected) then
		return true
	end
	local node: Instance? = selected
	while node and node ~= frame do
		if node:IsA("GuiObject") and not (node :: GuiObject).Visible then
			return true
		end
		node = node.Parent
	end
	return false
end
local function firstSelectable(frame: Instance): GuiObject?
	local function shown(obj: Instance): boolean
		local node: Instance? = obj
		while node and node ~= frame do
			if node:IsA("GuiObject") and not (node :: GuiObject).Visible then
				return false
			end
			node = node.Parent
		end
		return true
	end
	for _, d in frame:GetDescendants() do
		if d:IsA("GuiButton") and d.Selectable and d:GetAttribute("Disabled") ~= true and shown(d) then
			return d
		end
	end
	return nil
end
Computer.firstSelectable = firstSelectable

-- shows `key` (and its entry) inside the open or closed Menu; Lab sections go to LabApp.openSection afterwards
local function selectPage(key: string)
	if not PAGES[key] then
		key = "home.today"
	end
	local switched = key ~= current
	current = key
	lastTab[entryOf(key)] = key
	for k, page in pages do
		page.frame.Visible = k == key
	end
	local page = pages[key]
	if page then
		applyPageScale(page)
		if switched then
			page.frame.Position = UDim2.fromOffset(0, 10)
			Kit.tween(page.frame, 0.25, { Position = UDim2.new() })
		end
		if page.def.app then
			page.def.app.onShow()
		end
		for _, part in page.parts do
			part.show()
		end
		if page.def.kind == "legacy" then
			floorPage(page.frame) -- a refresh may have set a small TextSize again
		end
	end
	markSeen(entryOf(key))
	markSeen(key)
	paintAll()
	for _, fn in onPageShown do
		task.spawn(fn, key)
	end
	-- gamepad: a page switched by a deep link (HUD Shop button, Home card, tip) gets the selection (after its parts
	-- rebuilt their buttons); a selection on the rail / header / Studio stays where the player put it
	if opened and page and padActive() then
		local frame = page.frame
		task.defer(function()
			if opened and current == key and selectionLost() and not UseSheet.isOpen() then
				local first = firstSelectable(frame)
				if first then
					GuiService.SelectedObject = first
				end
			end
		end)
	end
end

-- Old API: switch to an app's page (routes like Computer.open, without opening)
function Computer.show(appId: string, section: string?)
	local key, labSection = Computer.route(appId, section)
	selectPage(key)
	if labSection then
		LabApp.openSection(labSection)
	end
end

-- Opens the Menu on the page of (appId, section). Deep links are never blocked: a locked page opens and counts as
-- unlocked for this session. nil = Home (or the guide's redirect).
-- shows the shell (dim, blur, B = back) without choosing a page; false when the Menu is not mounted
local function openShell(): boolean
	local frame, shade, effect = root, dim, blur
	if not frame or not shade or not effect then
		return false
	end
	if not opened then
		opened = true
		frame.Visible = true
		shade.Visible = true
		shade.BackgroundTransparency = 1
		Kit.tween(shade, 0.25, { BackgroundTransparency = 0.32 })
		Kit.tween(effect, 0.3, { Size = 8 })
		Computer.bindInput()
	end
	return true
end

function Computer.open(appId: string?, section: string?)
	local filter = openFilter
	if filter then
		appId, section = filter(appId, section)
	end
	local key, labSection = Computer.route(appId, section)
	if appId ~= nil and not Computer.isUnlocked(key) then
		deepUnlocked[unlockKey(key)] = true
		deepUnlocked[entryOf(key)] = true
	end
	if not openShell() then
		return
	end
	if appId == nil and section == nil then
		key = "home.today"
	end
	selectPage(key)
	if labSection then
		LabApp.openSection(labSection)
	end
	-- gamepad: the first Home card (B6)
	if key == "home.today" and padActive() then
		local first = HomeApp.firstButton()
		if first then
			GuiService.SelectedObject = first
		end
	end
end

function Computer.close()
	local frame, shade, effect = root, dim, blur
	if not opened or not frame or not shade or not effect then
		return
	end
	UseSheet.close() -- shop fix round 1: a use sheet never stays over the world with nothing selected
	local locked = lockedShade
	if locked then
		locked.Visible = false
	end
	opened = false
	Computer.unbindInput()
	Kit.tween(shade, 0.18, { BackgroundTransparency = 1 })
	Kit.tween(effect, 0.18, { Size = 0 })
	local selected = GuiService.SelectedObject
	if selected and frame:IsAncestorOf(selected) then
		GuiService.SelectedObject = nil
	end
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

-- "‹" / gamepad B (B6): sub-tab other than the default -> the default; entry other than Home -> Home; Home -> close
function Computer.back()
	if UseSheet.isOpen() then
		UseSheet.close() -- (the sheet binds B itself above this; kept for the "‹" button path)
		return
	end
	local locked = lockedShade
	if locked and locked.Visible then
		locked.Visible = false -- B / ‹ first closes the "opens after your first launch" card
		return
	end
	local entryId = entryOf(current)
	local entry = entryDef(entryId)
	if entry and #entry.tabs > 1 then
		local default = entryId .. "." .. entry.tabs[1].id
		if current ~= default then
			selectPage(default)
			return
		end
	end
	if entryId ~= "home" then
		selectPage("home.today")
		return
	end
	Computer.close()
end

-- the page / route API apps use (Kit.Nav + route for the Home cards)
local function routeTo(route: string, modelId: string?)
	if route == "lab_design" then
		Computer.open("lab", "design")
	elseif route == "lab_train" then
		Computer.open("lab", "train")
	elseif route == "lab_release" then
		Computer.open("lab", "release")
		if modelId then
			LabApp.openRelease(modelId)
		end
	elseif string.sub(route, 1, 5) == "page:" then
		-- a page of the Menu itself (Home cards, tips, "All goals ›"): no guide redirect, it is an explicit choice
		local key = string.sub(route, 6)
		if not openShell() then
			return
		end
		if not Computer.isUnlocked(key) then
			deepUnlocked[unlockKey(key)] = true
			deepUnlocked[entryOf(key)] = true
		end
		selectPage(key)
	elseif string.sub(route, 1, 5) == "open:" then
		local app, section = string.match(string.sub(route, 6), "^([^/]*)/?(.*)$")
		Computer.open(if app and app ~= "" then app else nil, if section and section ~= "" then section else nil)
	end
end
Computer.routeTo = routeTo

---------------------------------------------------------------------------- input (B6)

local ACTION_TOGGLE = "AIEmpireMenu"
local ACTION_BACK = "AIEmpireMenuBack"
local backBound = false
local function onToggle(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	local snapshot = StateController.snapshot
	-- no Menu before a company exists (the Intro is on screen)
	if state ~= Enum.UserInputState.Begin or not snapshot or snapshot.data.company == nil then
		return Enum.ContextActionResult.Pass
	end
	Computer.toggle()
	return Enum.ContextActionResult.Sink
end
local function onBack(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not opened then
		return Enum.ContextActionResult.Pass
	end
	Computer.back()
	return Enum.ContextActionResult.Sink
end
function Computer.bindInput()
	if backBound then
		return
	end
	backBound = true
	-- Medium priority: the Model Studio's High-priority L1/R1/B binding wins while it is open (LAB_SPEC 3.5)
	ContextActionService:BindActionAtPriority(ACTION_BACK, onBack, false, Enum.ContextActionPriority.Medium.Value, Enum.KeyCode.ButtonB)
end
function Computer.unbindInput()
	if backBound then
		backBound = false
		ContextActionService:UnbindAction(ACTION_BACK)
	end
end

---------------------------------------------------------------------------- build

local function makeRailButton(parent: Instance, index: number, entry: Entry): (TextButton, () -> ())
	local button = Instance.new("TextButton")
	button.Name = "Rail_" .. entry.id
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Text = ""
	button.Size = UDim2.fromOffset(108, 78)
	button.LayoutOrder = index
	button.BackgroundColor3 = C.panel
	button.BackgroundTransparency = 1
	button.Selectable = true
	button.Parent = parent
	Kit.corner(button, 12)
	local bar = Kit.frame(button, UDim2.new(0, 5, 0, 44), UDim2.new(0, -6, 0.5, -22))
	bar.Name = "Bar"
	bar.BackgroundTransparency = 0
	Theme.bindAccent(bar, "BackgroundColor3")
	Kit.corner(bar, 3)
	local top = Kit.frame(button, UDim2.new(1, 0, 0, 38), UDim2.fromOffset(0, 6))
	local topList = Kit.list(top, 6, true)
	topList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local icon = Kit.icon(top, entry.icon, 36)
	icon.frame.LayoutOrder = 1
	local pill = Kit.text(top, "NEW", 21, F.bold, C.bg) -- 21 px x 0.598 = 12.6 pt on phones
	pill.Name = "NewPill"
	pill.LayoutOrder = 2
	pill.BackgroundTransparency = 0
	Theme.bindAccent(pill, "BackgroundColor3")
	Kit.corner(pill, 8)
	Kit.padding(pill, 1, 6, 1, 6)
	pill.Visible = false
	local label = Kit.text(button, entry.label, 20, F.bold, C.muted)
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -6)
	local function paint()
		local selected = entryOf(current) == entry.id
		local unlocked = entryUnlocked(entry)
		button.BackgroundColor3 = Theme.accent
		button.BackgroundTransparency = if selected then 0.82 else 1
		bar.Visible = selected
		label.TextColor3 = if selected then C.text else C.muted
		label.TextTransparency = if unlocked then 0 else 0.6
		local color = if entry.id == "shop" then C.warn elseif selected then Theme.accent else C.muted
		icon.setColor(if unlocked then color else C.dim)
		for _, d in icon.frame:GetDescendants() do
			if d:IsA("Frame") then
				d.BackgroundTransparency = if d.BackgroundTransparency >= 1 then 1 elseif unlocked then 0 else 0.6
			end
		end
		local new = false
		if unlocked and entry.id ~= "shop" then
			if Computer.isNew(entry.id) then
				new = true
			end
			for _, tab in entry.tabs do
				if Computer.isNew(entry.id .. "." .. tab.id) then
					new = true
				end
			end
		end
		pill.Visible = new
	end
	Kit.onClick(button, function()
		if not entryUnlocked(entry) then
			showLocked(entry)
			return
		end
		local key = lastTab[entry.id]
		if not key or not Computer.isUnlocked(key) then
			key = entry.id .. "." .. entry.tabs[1].id
		end
		selectPage(key)
	end)
	return button, paint
end

function Computer.mount(parent: Frame, dimLayer: Frame)
	local frame = Kit.frame(parent)
	frame.Name = "Computer"
	frame.Visible = false
	frame.ZIndex = 10
	root = frame

	-- dim in the inset-free layer (covers the top-bar strip too) and swallows taps; desktops: a click closes (B6)
	local shade = Kit.blocker(dimLayer, C.black, 1)
	shade.Visible = false
	dim = shade
	Kit.onClick(shade, function()
		if not Kit.isTouch() and opened then
			Computer.close()
		end
	end)

	local effect = Instance.new("BlurEffect")
	effect.Name = "AIEmpireBlur"
	effect.Size = 0
	effect.Parent = Lighting -- vom Client erstellt = existiert nur bei diesem Spieler
	blur = effect

	-- the shell: own UIScale (Studio formula), canvas 1254 x 520 on phones / 1254 x 648 at 1280 x 720
	local menu = Kit.frame(frame)
	menu.Name = "Menu"
	menu.ZIndex = 11
	menu.BackgroundTransparency = 0.03
	menu.BackgroundColor3 = C.bg
	menu.Active = true
	local scale = Instance.new("UIScale")
	scale.Parent = menu
	shell = menu
	shellScale = scale

	local RAIL, HEADER = Computer.RAIL, Computer.HEADER
	local rail = Kit.frame(menu, UDim2.new(0, RAIL, 1, 0))
	rail.Name = "Rail"
	rail.BackgroundTransparency = 0
	rail.BackgroundColor3 = C.panel
	local railList = Kit.list(rail, 6)
	railList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	railList.VerticalAlignment = Enum.VerticalAlignment.Center
	local railLine = Kit.frame(menu, UDim2.new(0, 1, 1, 0), UDim2.fromOffset(RAIL, 0))
	railLine.BackgroundTransparency = 0.93
	railLine.BackgroundColor3 = C.line

	-- header: ‹ · title (+ VIP) · sub-tabs · CASH · ×
	local header = Kit.frame(menu, UDim2.new(1, -RAIL, 0, HEADER), UDim2.fromOffset(RAIL, 0))
	header.Name = "Header"
	local back = Kit.button(header, "‹", "ghost", UDim2.fromOffset(76, 76))
	back.Name = "MenuBack"
	back.Position = UDim2.fromOffset(8, 4)
	back.TextSize = 40
	back.TextColor3 = C.text
	back.Selectable = true
	Kit.onClick(back, Computer.back)
	local titleRow = Kit.frame(header, UDim2.fromOffset(0, 76), UDim2.fromOffset(96, 4))
	titleRow.AutomaticSize = Enum.AutomaticSize.X
	local titleList = Kit.list(titleRow, 10, true)
	titleList.VerticalAlignment = Enum.VerticalAlignment.Center
	local title = Kit.text(titleRow, "Home", 32, F.display, C.text)
	title.Name = "MenuTitle"
	title.LayoutOrder = 1
	local vip = Kit.tag(titleRow, "VIP", C.warn, 2)
	vip.Name = "VipBadge"
	vip.TextSize = 20
	vip.Visible = false
	local tabsRow = Kit.frame(header, UDim2.fromOffset(0, 74), UDim2.fromOffset(0, 5))
	tabsRow.Name = "SubTabs"
	tabsRow.AutomaticSize = Enum.AutomaticSize.X
	Kit.list(tabsRow, 8, true)
	local close = Kit.button(header, "×", "ghost", UDim2.fromOffset(76, 76))
	close.Name = "MenuClose"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -8, 0, 4)
	close.TextSize = 36
	close.TextColor3 = C.text
	close.Selectable = true
	Kit.onClick(close, Computer.close)
	local cashBox = Kit.frame(header, UDim2.fromOffset(170, 76), UDim2.new(1, -96, 0, 4))
	cashBox.AnchorPoint = Vector2.new(1, 0)
	local cashCaption = Kit.text(cashBox, "CASH", 20, F.bold, C.muted)
	cashCaption.AnchorPoint = Vector2.new(1, 0)
	cashCaption.Position = UDim2.new(1, 0, 0, 6)
	local cash = Kit.text(cashBox, "$0", 28, F.bold, C.text)
	cash.Name = "MenuCash"
	cash.AnchorPoint = Vector2.new(1, 0)
	cash.Position = UDim2.new(1, 0, 0, 32)
	local headerLine = Kit.divider(header)
	headerLine.Position = UDim2.new(0, 0, 1, -1)

	-- content: the page host
	local content = Kit.frame(menu, UDim2.new(1, -RAIL - 1, 1, -HEADER), UDim2.fromOffset(RAIL + 1, HEADER))
	content.Name = "Content"
	content.ClipsDescendants = true
	Kit.padding(content, 10, 16, 10, 16)

	-- locked entry card (B5): "Market opens after your first launch." + GO TO LAB ›
	local lockShade = Instance.new("TextButton")
	lockShade.Name = "LockedShade"
	lockShade.AutoButtonColor = false
	lockShade.Text = ""
	lockShade.BorderSizePixel = 0
	lockShade.BackgroundColor3 = C.black
	lockShade.BackgroundTransparency = 0.45
	lockShade.Size = UDim2.new(1, -RAIL, 1, 0)
	lockShade.Position = UDim2.fromOffset(RAIL, 0)
	lockShade.ZIndex = 20
	lockShade.Visible = false
	lockShade.Parent = menu
	lockedShade = lockShade
	local lockCard = Kit.panel(lockShade, UDim2.fromOffset(640, 0), UDim2.fromScale(0.5, 0.5))
	lockCard.Name = "LockedCard"
	lockCard.AnchorPoint = Vector2.new(0.5, 0.5)
	lockCard.AutomaticSize = Enum.AutomaticSize.Y
	lockCard.ZIndex = 21
	Kit.padding(lockCard, 26, 28, 26, 28)
	Kit.list(lockCard, 14)
	local lockTitle = Kit.para(lockCard, "", 30, C.text, 1)
	lockTitle.Font = F.bold
	lockTitle.ZIndex = 22
	local lockText = Kit.para(lockCard, "Train your first AI and launch it. Then Market, Clients, Team and Shop open.", 22, C.muted, 2)
	lockText.ZIndex = 22
	local lockGo = Kit.button(lockCard, "GO TO LAB ›", "primary", UDim2.new(1, 0, 0, 74))
	lockGo.Name = "GoToLab"
	lockGo.LayoutOrder = 3
	lockGo.TextSize = 24
	lockGo.ZIndex = 22
	Kit.onClick(lockShade, function()
		lockShade.Visible = false
	end)
	Kit.onClick(lockGo, function()
		lockShade.Visible = false
		selectPage("lab.models")
	end)
	showLocked = function(entry: Entry)
		lockTitle.Text = entry.label .. " opens after your first launch."
		lockText.Text = if Computer.isUnlocked("lab.models") then "Train your first AI and launch it. Then Market, Clients, Team and Shop open." else "Train your first AI and launch it."
		lockShade.Visible = true
		if padActive() then
			GuiService.SelectedObject = lockGo
		end
	end

	-- apps get the Menu as their navigation (Kit.Nav + route)
	local nav = {
		show = function(appId: string)
			Computer.open(appId)
		end,
		close = Computer.close,
		isOpen = Computer.isOpen,
		route = routeTo,
	}

	-- rail entries
	local railPaint: { () -> () } = {}
	for index, entry in Computer.ENTRIES do
		local _, paint = makeRailButton(rail, index, entry)
		table.insert(railPaint, paint)
	end

	-- pages (every app is mounted now, as before: they listen to notifications such as TRAINING_COMPLETE)
	for key, def in PAGES do
		local pf = Kit.frame(content)
		pf.Name = def.name
		pf.Visible = false
		local ps = Instance.new("UIScale")
		ps.Name = "PageScale"
		ps.Parent = pf
		pages[key] = { key = key, def = def, frame = pf, scale = ps, parts = {}, mounted = false }
	end
	-- Lab first (LabApp.mount binds the reveal notifications), Home next, then the rest
	local order = { "lab.models", "home.today" }
	for key in PAGES do
		if key ~= "lab.models" and key ~= "home.today" then
			table.insert(order, key)
		end
	end
	for _, key in order do
		local page = pages[key]
		if page then
			local ok, err = pcall(function()
				mountPage(page, nav)
			end)
			if not ok then
				warn(`[Menu] page {key}: {err}`)
			end
		end
	end

	-- sub-tabs of the current entry (locked ones hidden), NEW pills, title (shrinks away when 5 tabs need the room)
	local tabButtons: { TextButton } = {}
	local tabSignature = ""
	local function paintTabs()
		local entry = entryDef(entryOf(current))
		if not entry then
			return
		end
		-- rebuilt only when the entry, the selected tab, the open tabs or a NEW pill change (no churn per snapshot)
		local sig = entry.id .. "|" .. current .. "|" .. tostring(vip.Visible) .. "|" .. tostring(math.floor(canvas.X)) .. "|" .. tostring(Theme.accent)
		for _, tab in entry.tabs do
			local key = entry.id .. "." .. tab.id
			sig ..= (if Computer.isUnlocked(key) then "1" else "0") .. (if Computer.isNew(key) then "n" else "-")
			sig ..= if entry.id == "shop" and not ShopApp.tabVisible(tab.id) then "h" else "" -- shop package: empty tab hidden
		end
		if sig == tabSignature then
			return
		end
		tabSignature = sig
		for _, b in tabButtons do
			b:Destroy()
		end
		table.clear(tabButtons)
		title.Text = entry.label
		local total = 0
		-- fix round 1 (review): a row with a single tab (e.g. the Shop's "coming soon" state: only Home) is not drawn
		local shownTabs = 0
		for _, tab in entry.tabs do
			local key = entry.id .. "." .. tab.id
			local hidden = entry.id == "shop" and key ~= current and not ShopApp.tabVisible(tab.id)
			if (Computer.isUnlocked(key) or key == current) and not hidden then
				shownTabs += 1
			end
		end
		if #entry.tabs > 1 and shownTabs > 1 then
			for i, tab in entry.tabs do
				local key = entry.id .. "." .. tab.id
				local hidden = entry.id == "shop" and key ~= current and not ShopApp.tabVisible(tab.id) -- shop package (5.1)
				if (Computer.isUnlocked(key) or key == current) and not hidden then
					local w = math.max(124, math.ceil(GoalText.textWidth(tab.label, 22)) + 40)
					local b = Kit.button(tabsRow, tab.label, "secondary", UDim2.fromOffset(w, 74))
					b.Name = "SubTab_" .. tab.id
					b.LayoutOrder = i
					b.TextSize = 22
					b.Selectable = true
					local on = key == current
					b.BackgroundColor3 = if on then Theme.accent:Lerp(C.panel, 0.78) else C.raised
					b.TextColor3 = if on then C.text else C.muted
					if on then
						Kit.stroke(b, 0.2, Theme.accent, 2)
					end
					if Computer.isNew(key) then
						local pill = Kit.text(b, "NEW", 21, F.bold, C.bg) -- 12.6 pt on phones
						pill.Name = "NewPill"
						pill.BackgroundTransparency = 0
						pill.BackgroundColor3 = Theme.accent
						pill.AnchorPoint = Vector2.new(1, 0)
						pill.Position = UDim2.new(1, 2, 0, -2) -- straddles the tab's top edge, stays under the top inset
						Kit.corner(pill, 7)
						Kit.padding(pill, 0, 5, 0, 5)
					end
					Kit.onClick(b, function()
						selectPage(key)
					end)
					table.insert(tabButtons, b)
					total += w + 8
				end
			end
		end
		-- header width: ‹ 96 + title + 16 + tabs + cash 170 + × 96 within the header width
		local width = canvas.X - RAIL
		local titleW = math.ceil(GoalText.textWidth(entry.label, 32) * 1.1) + (if vip.Visible then 70 else 0)
		local fits = 96 + titleW + 16 + total + 170 + 104 <= width
		titleRow.Visible = fits
		tabsRow.Position = UDim2.fromOffset(if fits then 96 + titleW + 16 else 96, 5)
	end

	paintAll = function()
		for _, paint in railPaint do
			paint()
		end
		paintTabs()
	end

	-- scale (Studio formula) + page scales
	local function applyScale()
		local A = frame.AbsoluteSize
		local P = designScale(frame)
		local s = if A.X > 0 and A.Y > 0 then math.clamp(math.min(A.X / Computer.CANVAS.X, A.Y / Computer.CANVAS.Y), 0.5, 1.25) else 1
		local k = s / P
		scale.Scale = k
		menu.Size = UDim2.fromScale(1 / k, 1 / k)
		canvas = if A.X > 0 and A.Y > 0 then Vector2.new(A.X / s, A.Y / s) else Vector2.new(1254, 648)
		for _, page in pages do
			applyPageScale(page)
		end
		paintTabs()
	end
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(applyScale)
	end)
	applyScale()

	-- gamepad L1 toggles the Menu in the world (B6); keyboard 1-6 pick an entry while it is open
	ContextActionService:BindActionAtPriority(ACTION_TOGGLE, onToggle, false, Enum.ContextActionPriority.Medium.Value, Enum.KeyCode.ButtonL1)
	local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six }
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not opened or UserInputService:GetFocusedTextBox() ~= nil or UseSheet.isOpen() then
			return
		end
		local index = table.find(KEYS, input.KeyCode)
		local entry = if index then Computer.ENTRIES[index] else nil
		if entry and entryUnlocked(entry) then
			selectPage(lastTab[entry.id] or (entry.id .. "." .. entry.tabs[1].id))
		end
	end)

	-- the "Eureka received. Use it now?" sheet only over an open Menu / Studio (else the grant toast)
	ShopCore.setHostOpen(Computer.isOpen)
	StateController.onChange(function(snapshot: Types.Snapshot)
		vip.Visible = ShopApp.owns(snapshot, "vip")
		if opened then
			paintAll()
		end
	end)
	Theme.onAccent(function()
		paintAll()
	end)

	RunService.RenderStepped:Connect(function()
		if opened then
			local value = StateController.money()
			cash.Text = Format.money(value)
			cash.TextColor3 = if value < 0 then C.bad else C.text
		end
	end)
	for _, page in pages do
		page.frame.Visible = page.key == current
	end
	paintAll()
end

-- the "Market opens after your first launch." card covers the page (the guide hides its ring meanwhile)
function Computer.lockedShown(): boolean
	local shade = lockedShade
	return opened and shade ~= nil and shade.Visible
end

-- tests / previews: the page frame of a key and the rail button of an entry
function Computer.pageFrame(key: string): Frame?
	local page = pages[key]
	return if page then page.frame else nil
end

function Computer.railButton(entryId: string): GuiObject?
	local s = shell
	if not s then
		return nil
	end
	local found = s:FindFirstChild("Rail_" .. entryId, true)
	return if found and found:IsA("GuiObject") then found else nil
end

return Computer
