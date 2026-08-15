--[[
	BankService.lua

	Einzahlen und Abfangen.

	Einzahlen: Balance.Bank.DepositSeconds ununterbrochen im Radius.
	Erfolg -> restlicher Cash wird Banked, Heat sinkt um Balance.Bank.HeatRelief.
	Weglaufen oder Respawn brechen ab, ohne dass etwas passiert.

	Abfangen (Dokument 3.2): waehrend der acht Sekunden ist der Einzahlende fuer
	alle sichtbar markiert -- weiss, laut 4.2 genau fuer diesen Zustand
	reserviert -- und traegt einen Prompt. Wer ihn ausloest, nimmt die Haelfte:

	  - Der Abfaenger bekommt sie auf Cash, nicht auf Banked. Er muss sie selbst
	    noch heimbringen.
	  - Der Abfaenger bekommt +25 Heat. Bankcamping wird dadurch von allein
	    teuer.
	  - 45 s Sperre bis zum naechsten Versuch, pro Spieler.
	  - Der Bestohlene verliert nur die Haelfte, seine Einzahlung laeuft mit dem
	    Rest zu Ende. Kein Totalverlust -- das waere Frust statt Spannung.

	Genau EIN Abfangen pro Einzahlung. "Der Bestohlene verliert nur die Haelfte"
	waere sonst nach drei Abfaengern eine Haelfte von einer Haelfte von einer
	Haelfte.

	Einzahlen ist auch mit getragenem Auftrag erlaubt -- der Auftrag bleibt
	dabei bestehen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Balance"))

local Modules = script.Parent
local MapBuilder = require(Modules:WaitForChild("MapBuilder"))
local PlayerState = require(Modules:WaitForChild("PlayerState"))
local RoundManager = require(Modules:WaitForChild("RoundManager"))

local BankService = {}

local running = false

-- [Player] = { token, intercepted, marker, highlight, prompt }
-- Eigene Buchfuehrung, damit das Aufraeumen nicht davon abhaengt, ob
-- PlayerState den Spieler beim Verlassen schon vergessen hat.
local deposits: { [Player]: any } = {}
-- [ProximityPrompt] = Player -- wer zahlt an diesem Prompt gerade ein
local promptOwner: { [ProximityPrompt]: Player } = {}

local onInterceptTriggered

-- ------------------------------------------------------------- Markierung --

local function unmark(player: Player)
	local deposit = deposits[player]
	if not deposit then
		return
	end

	if deposit.prompt then
		promptOwner[deposit.prompt] = nil
		deposit.prompt:Destroy()
		deposit.prompt = nil
	end
	if deposit.marker then
		deposit.marker:Destroy()
		deposit.marker = nil
	end
	if deposit.highlight then
		deposit.highlight:Destroy()
		deposit.highlight = nil
	end
end

--[[
	Weisses Leuchten, Schild ueber dem Kopf und Abfang-Prompt. Fuer alle
	sichtbar -- das ist der ganze Zweck.
]]
local function mark(player: Player, deposit)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "CashoutDepositHighlight"
	highlight.FillColor = Color3.fromRGB(255, 255, 255)
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.FillTransparency = Balance.Intercept.HighlightFill
	highlight.Adornee = character
	highlight.Parent = character
	deposit.highlight = highlight

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CashoutDepositMarker"
	billboard.Size = UDim2.fromOffset(200, 44)
	billboard.StudsOffset = Vector3.new(0, Balance.Intercept.MarkerHeight, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 400
	billboard.Adornee = root
	billboard.Parent = root
	deposit.marker = billboard

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.3
	label.Text = "ZAHLT EIN"
	label.Parent = billboard

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CashoutInterceptPrompt"
	prompt.ActionText = "Abfangen"
	prompt.ObjectText = player.DisplayName
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Balance.Intercept.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	deposit.prompt = prompt

	promptOwner[prompt] = player
	prompt.Triggered:Connect(function(triggeringPlayer)
		onInterceptTriggered(prompt, triggeringPlayer)
	end)
end

-- --------------------------------------------------------------- Abfangen --

function onInterceptTriggered(prompt: ProximityPrompt, thief: Player)
	if not RoundManager.IsRunning() then
		return
	end

	local victim = promptOwner[prompt]
	if not victim or victim == thief then
		return
	end

	local thiefState = PlayerState.Get(thief)
	if not thiefState or PlayerState.IsSpectating(thief) then
		return
	end
	if not PlayerState.ConsumeAction(thief, "Intercept") then
		return
	end

	local deposit = deposits[victim]
	if not deposit or deposit.intercepted then
		return
	end

	if not PlayerState.CanIntercept(thief) then
		PlayerState.Notify(thief, "warn", "Abfangen noch gesperrt.")
		return
	end

	local victimPosition = PlayerState.GetPosition(victim)
	if not victimPosition or not PlayerState.IsNear(thief, victimPosition, Balance.Intercept.Radius) then
		return
	end

	local taken = PlayerState.TakeCashShare(victim, Balance.Intercept.SplitFraction)
	if taken <= 0 then
		PlayerState.Notify(thief, "warn", "Nichts abzufangen.")
		return
	end

	-- Genau einmal pro Einzahlung, und die Markierung verschwindet sofort.
	deposit.intercepted = true
	unmark(victim)

	PlayerState.MarkIntercept(thief)
	PlayerState.AddCash(thief, taken)
	PlayerState.AddHeat(thief, Balance.Intercept.HeatGain)

	PlayerState.Notify(
		thief,
		"good",
		string.format("%d abgefangen. +%d Heat -- jetzt bring es heim.", taken, Balance.Intercept.HeatGain)
	)
	PlayerState.Notify(victim, "bad", string.format("Abgefangen. -%d. Der Rest laeuft weiter.", taken))
end

-- -------------------------------------------------------------- Einzahlen --

local function refreshBeam()
	local any = false
	for _, _ in pairs(deposits) do
		any = true
		break
	end
	MapBuilder.SetDepositBeam(any)
end

local function finish(player: Player)
	unmark(player)
	deposits[player] = nil
	refreshBeam()
end

local function runDeposit(player: Player, bank)
	local token = PlayerState.BeginActivity(player, "deposit", "Einzahlung", Balance.Bank.DepositSeconds)
	if not token then
		return
	end

	local deposit = { token = token, intercepted = false }
	deposits[player] = deposit
	mark(player, deposit)
	refreshBeam()

	local deadline = os.clock() + Balance.Bank.DepositSeconds
	local aborted = false

	while os.clock() < deadline do
		task.wait(Balance.Orders.CheckInterval)

		if not player.Parent or not PlayerState.Get(player) then
			finish(player)
			return
		end
		if PlayerState.IsActivityCancelled(player, token) then
			aborted = true
			break
		end
		if not PlayerState.IsNear(player, bank.Position, Balance.Bank.Radius) then
			aborted = true
			break
		end
	end

	PlayerState.EndActivity(player, token)
	finish(player)

	if aborted or not RoundManager.IsRunning() then
		PlayerState.Notify(player, "bad", "Einzahlung abgebrochen.")
		return
	end

	local amount = PlayerState.BankAllCash(player)
	PlayerState.AddHeat(player, -Balance.Bank.HeatRelief)
	PlayerState.Notify(player, "banked", string.format("+%d eingezahlt. Sicher.", amount))
end

local function onBankTriggered(bank, player: Player)
	if not RoundManager.IsRunning() then
		return
	end

	local state = PlayerState.Get(player)
	if not state or PlayerState.IsSpectating(player) then
		return
	end
	if not PlayerState.ConsumeAction(player, "Deposit") then
		return
	end

	if PlayerState.IsBusy(player) then
		PlayerState.Notify(player, "warn", "Du bist gerade beschaeftigt.")
		return
	end
	if state.cash <= 0 then
		PlayerState.Notify(player, "warn", "Nichts dabei zum Einzahlen.")
		return
	end
	if not PlayerState.IsNear(player, bank.Position, Balance.Bank.Radius) then
		return
	end

	task.spawn(runDeposit, player, bank)
end

-- ---------------------------------------------------------------- Aufraeumen --

local function releasePlayer(player: Player)
	unmark(player)
	deposits[player] = nil
	refreshBeam()
end

local function resetAll()
	for player, _ in pairs(table.clone(deposits)) do
		releasePlayer(player)
	end
	table.clear(deposits)
	table.clear(promptOwner)
	MapBuilder.SetDepositBeam(false)
end

function BankService.Start()
	if running then
		return
	end
	running = true

	local bank = MapBuilder.GetBank()
	if not bank then
		warn("[CASHOUT] BankService: keine Bank in der Map. MapBuilder.Start() zuerst aufrufen.")
		return
	end

	bank.Prompt.Triggered:Connect(function(player)
		onBankTriggered(bank, player)
	end)

	game:GetService("Players").PlayerRemoving:Connect(releasePlayer)
	RoundManager.OnRoundStart(resetAll)
	RoundManager.OnRoundEnd(resetAll)
end

function BankService.Stop()
	running = false
end

--[[
	Zahlt dieser Spieler gerade ein? Fuer den Einzahl-Beam in Phase 4.
]]
function BankService.IsDepositing(player: Player): boolean
	return deposits[player] ~= nil
end

return BankService
