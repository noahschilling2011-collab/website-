--[[
	Garage Heist - Client-Bootstrap

	Der Client baut die Oberflaeche, hoert auf die Remotes und schickt
	Anfragen. Er rechnet nichts aus, was mit Geld zu tun hat - alle Zahlen in
	diesem Ordner sind Kopien vom Server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local Store = require(script.Store)
local Theme = require(script.UI.Theme)
local Toast = require(script.UI.Toast)
local HUD = require(script.UI.HUD)
local GarageMenu = require(script.UI.GarageMenu)
local ShopMenu = require(script.UI.ShopMenu)
local DailyPanel = require(script.UI.DailyPanel)
local DismountBar = require(script.UI.DismountBar)
local InfoPanel = require(script.UI.InfoPanel)
local AdminPanel = require(script.UI.AdminPanel)
local EffectController = require(script.Controllers.EffectController)
local InputController = require(script.Controllers.InputController)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local root = Theme.Root(playerGui)

-- Ladezustand: bleibt stehen, bis der erste Snapshot da ist. Vorher zeigt die
-- Oberflaeche sonst Nullen an, als waere das Profil leer.
local loading = Theme.panel({
	Name = "Loading",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0.7, 0, 0, 90),
	ZIndex = 30,
	Parent = root,
})
Theme.constrain(loading, Vector2.new(260, 90), Vector2.new(420, 90))
local loadingLabel = Theme.label({
	Text = "Spielstand wird geladen ...",
	Size = UDim2.fromScale(1, 1),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	TextWrapped = true,
	ZIndex = 31,
	Parent = loading,
})

local function hideLoading()
	loading.Visible = false
end

Toast.Init(root)
GarageMenu.Init(root)
ShopMenu.Init(root)
DailyPanel.Init(root)
DismountBar.Init(root)
AdminPanel.Init(root)

-- Beide Panels haengen rechts: die Rangliste unter der Knopfleiste, das Radar
-- darunter mit Abstand zur Trage-Leiste. Groessen in Skalen, damit im
-- Hochformat nichts aus dem Bild laeuft.
-- Rangliste rechts unter der Knopfleiste, Radar links unter der Cash-Anzeige.
-- Beide in Skalen, damit im Hochformat nichts aus dem Bild laeuft; die
-- Groessengrenzen stehen in InfoPanel.
local leaderPanel = InfoPanel.new(
	root,
	"Rangliste",
	UDim2.new(1, -16, 0, 280),
	UDim2.new(0.26, 0, 0.30, 0),
	Vector2.new(1, 0)
)
local radarPanel = InfoPanel.new(
	root,
	"Heist Radar",
	UDim2.new(0, 16, 0, 200),
	UDim2.new(0.26, 0, 0.22, 0),
	Vector2.new(0, 0)
)

local function renderLeaderboard()
	local board = Store.leaderboard
	local lines = { "-- Teuerste Garage --" }
	for rank, entry in board.richest do
		table.insert(lines, ("%d. %s  %s"):format(rank, entry.name, Util.FormatCash(entry.value)))
	end
	table.insert(lines, "")
	table.insert(lines, "-- Geklaute Teile heute --")
	for rank, entry in board.thieves do
		table.insert(lines, ("%d. %s  %d"):format(rank, entry.name, entry.value))
	end
	leaderPanel:SetLines(lines)
end

HUD.Init(root, {
	toggleGarage = function()
		GarageMenu.Toggle()
	end,
	toggleShop = function()
		ShopMenu.Toggle()
	end,
	toggleDaily = function()
		DailyPanel.Toggle()
	end,
	toggleLeaderboard = function()
		leaderPanel:Toggle()
		if leaderPanel:IsVisible() then
			renderLeaderboard()
		end
	end,
})

InputController.Start({ garage = GarageMenu })
EffectController.Start()

-- Remotes -----------------------------------------------------------------
Remotes.Get("ProfileSync").OnClientEvent:Connect(function(snapshot)
	hideLoading()
	Store.Set("snapshot", snapshot)
end)

Remotes.Get("CashUpdate").OnClientEvent:Connect(function(payload)
	Store.Set("cash", payload)

	-- Das Werkstatt-Menue rechnet Kaufbarkeit gegen snapshot.cash. Der
	-- Snapshot kommt aber nur bei einer Zustandsaenderung (Kauf, Reparatur,
	-- Diebstahl) - Kasse leeren und Tagesbelohnung schicken nur ein
	-- CashUpdate. Ohne diese Zeilen steht im HUD 206 und der 150er-Knopf ist
	-- trotzdem grau. Reine Anzeige: der Kauf wird auf dem Server ohnehin neu
	-- geprueft.
	local snapshot = Store.snapshot
	if snapshot and snapshot.cash ~= payload.cash then
		snapshot.cash = payload.cash
		snapshot.pile = payload.pile
		Store.Set("snapshot", snapshot)
	end
end)

Remotes.Get("HeistState").OnClientEvent:Connect(function(payload)
	Store.Set("heist", payload)
end)

Remotes.Get("Notify").OnClientEvent:Connect(function(payload)
	Toast.Show(payload.text, payload.kind)
end)

Remotes.Get("CarryState").OnClientEvent:Connect(function(payload)
	Store.Set("carry", payload and payload.part or nil)
end)

Remotes.Get("DismountProgress").OnClientEvent:Connect(function(payload)
	DismountBar.Handle(payload)
end)

Remotes.Get("DailyState").OnClientEvent:Connect(function(payload)
	Store.Set("daily", payload)
end)

Remotes.Get("ShopState").OnClientEvent:Connect(function(payload)
	Store.Set("shop", payload)
end)

Remotes.Get("LeaderboardUpdate").OnClientEvent:Connect(function(payload)
	Store.Set("leaderboard", payload)
	if leaderPanel:IsVisible() then
		renderLeaderboard()
	end
end)

Remotes.Get("RadarPing").OnClientEvent:Connect(function(entries)
	local lines = {}
	for rank, entry in entries do
		table.insert(lines, ("%d. %s: %s (%s)"):format(rank, entry.owner, entry.tierName, Util.FormatCash(entry.value)))
	end
	radarPanel:SetLines(lines)
	radarPanel:ShowFor(75)
end)

-- Erststart ---------------------------------------------------------------
-- Die Einfuehrung uebernimmt Onboarding: Intro-Karte, Zielbalken, Weltmarker.
-- Ein Menue, das sich von allein ueber die Karte legt, waere schlechter als
-- ein Marker, der auf die Werkbank zeigt.
task.spawn(function()
	-- Beim Start kann der Server den Handler noch nicht gesetzt haben.
	local snapshot
	for attempt = 1, 4 do
		local ok, result = pcall(function()
			return Remotes.Get("GetSnapshot"):InvokeServer()
		end)
		if ok and result then
			snapshot = result
			break
		end
		loadingLabel.Text = ("Spielstand wird geladen ... (Versuch %d)"):format(attempt + 1)
		task.wait(attempt)
	end
	if not snapshot then
		loadingLabel.Text = "Spielstand kommt nicht an. Verlasse das Spiel und tritt neu bei."
		return
	end

	hideLoading()
	Store.Set("snapshot", snapshot)
	Store.Set("cash", {
		cash = snapshot.cash,
		pile = snapshot.pile,
		rate = snapshot.rate,
		autoCollect = snapshot.passes and snapshot.passes.AutoCollect or false,
	})
end)
