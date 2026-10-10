--!strict
-- Connection to the 3D world:
--   - Owner prompts (OwnerUserId) are shown only to that owner; Public prompts to everyone.
--     A Public prompt marked OwnerOnly is shown only inside the local player's own office.
--   - An owner prompt with an App attribute opens the company computer (optional Section).
--   (GPU blades breathing while the office trains moved to PropFxController: PropFx kind "breathe".)

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local State = require(script.Parent.StateController)

local WorldController = {}

local player = Players.LocalPlayer

local function isOwn(prompt: ProximityPrompt): boolean
	if prompt:GetAttribute("OwnerUserId") == player.UserId then
		return true
	end
	if prompt:GetAttribute("Public") ~= true then
		return false
	end
	if prompt:GetAttribute("OwnerOnly") == true then
		-- The server enforces ownership; locally we only hide the prompt in other companies' buildings.
		local office = prompt:FindFirstAncestor("Office")
		local owner = if office then office:GetAttribute("OwnerUserId") else nil
		return owner == nil or owner == player.UserId
	end
	return true
end

local function setupPrompt(inst: Instance)
	if inst:IsA("ProximityPrompt") then
		inst.Enabled = isOwn(inst)
	end
end

function WorldController.init(openComputer: (string?, string?) -> ())
	State.onNotify(function(kind, payload)
		if kind == "OWNER_COMPUTER" and typeof(payload.app) == "string" then
			openComputer(payload.app, if typeof(payload.section) == "string" then payload.section else nil)
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if who == player and isOwn(prompt) then
			local app = prompt:GetAttribute("App")
			local section = prompt:GetAttribute("Section")
			if typeof(app) == "string" then
				openComputer(app, if typeof(section) == "string" then section else nil)
			end
		end
	end)

	task.spawn(function()
		for _, inst in workspace:GetDescendants() do
			setupPrompt(inst)
		end
		workspace.DescendantAdded:Connect(setupPrompt)
	end)
end

return WorldController
