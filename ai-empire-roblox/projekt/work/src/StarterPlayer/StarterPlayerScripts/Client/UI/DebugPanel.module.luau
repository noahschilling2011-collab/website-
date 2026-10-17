--!strict
-- Test-Abkürzungen. Sichtbar nur in Studio oder für GameConfig.DEV_USER_IDS.
-- Der Server prüft das unabhängig davon noch einmal (DebugService.allowed).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local UI = script.Parent
local Client = UI.Parent
local ActionController = require(Client.Controllers.ActionController)
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Toast = require(UI.Toast)

local C = Theme.colors

local COMMANDS: { { cmd: string, label: string, done: string, key: string? } } = {
	{ cmd = "money", label = "+ $100K", done = "+$100,000" },
	{ cmd = "data", label = "+ 10B tokens per type", done = "+10B tokens of every data type" },
	{ cmd = "finish", label = "Finish training now", done = "Training finished" },
	{ cmd = "rep", label = "+ 25 reputation", done = "+25 reputation" },
	-- shop items for testing (DebugService: Studio only, session flag / voucher, never sold; shop request 6)
	{ cmd = "pass", key = "vip", label = "Shop: VIP pass", done = "VIP pass active (this session)" },
	{ cmd = "pass", key = "limo", label = "Shop: Limo pass", done = "Executive Limousine pass active (this session)" },
	{ cmd = "voucher", key = "headhunter", label = "Shop: Headhunter voucher", done = "Headhunter voucher added" },
}

local DebugPanel = {}

local panel: Frame? = nil

function DebugPanel.allowed(): boolean
	return RunService:IsStudio() or table.find(GameConfig.DEV_USER_IDS, Players.LocalPlayer.UserId) ~= nil
end

function DebugPanel.mount(parent: Frame)
	local frame = Kit.panel(parent, UDim2.fromOffset(240, 0), UDim2.new(0, 16, 0.55, 0))
	frame.AnchorPoint = Vector2.new(0, 0.5)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Visible = false
	frame.Name = "DebugPanel"
	Kit.padding(frame, 12)
	Kit.list(frame, 8)
	local caption = Kit.caption(frame, "Dev tools (Studio only)", 0)
	caption.TextColor3 = C.warn
	panel = frame

	for index, def in COMMANDS do
		local button = Kit.button(frame, def.label, "secondary", UDim2.new(1, 0, 0, 36))
		button.LayoutOrder = index
		button.TextSize = 14
		Kit.onClick(button, function()
			local ok = ActionController.call("Debug", { cmd = def.cmd, key = def.key })
			if ok then
				Toast.show("info", "[Dev] " .. def.done)
			end
		end)
	end

	local reset = Kit.button(frame, "Reset save", "danger", UDim2.new(1, 0, 0, 36))
	reset.LayoutOrder = #COMMANDS + 1
	reset.TextSize = 14
	local armedAt = 0
	Kit.onClick(reset, function()
		if os.clock() - armedAt > 3 then
			armedAt = os.clock()
			reset.Text = "Click again to reset"
			task.delay(3, function()
				reset.Text = "Reset save"
			end)
			return
		end
		armedAt = 0
		reset.Text = "Reset save"
		local ok = ActionController.call("Debug", { cmd = "reset" })
		if ok then
			Toast.show("warn", "[Dev] Save reset. Starting over.")
		end
	end)

	local close = Kit.button(frame, "Close", "ghost", UDim2.new(1, 0, 0, 30))
	close.LayoutOrder = #COMMANDS + 2
	close.TextSize = 13
	Kit.onClick(close, DebugPanel.toggle)
end

function DebugPanel.toggle()
	local frame = panel
	if frame then
		frame.Visible = not frame.Visible
	end
end

return DebugPanel
