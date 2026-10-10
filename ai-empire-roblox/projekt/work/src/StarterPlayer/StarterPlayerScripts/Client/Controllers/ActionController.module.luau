--!strict
-- Einziger Weg, wie die UI den Server um etwas bittet. Schützt vor Doppelklicks und übersetzt
-- Fehlercodes vom Server in verständliche Meldungen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local HardwareConfig = require(ReplicatedStorage.Shared.Config.HardwareConfig)
local Toast = require(script.Parent.Parent.UI.Toast)

export type Result = { [string]: any }

local ActionController = {}

local MESSAGES: { [string]: string } = {
	ADMIN_ONLY="This admin panel belongs to the Roblox account Nonortrttrt.",
	OWNER_ONLY="Only the owner of this plot has access here.",
	LIFT_BUSY="The lift is on its way. Wait a moment at the landing.",
	LIFT_DISTANCE="Move closer to the lift call button or the cabin panel.",
	LIFT_SEATED="Leave your vehicle before using the lift.",
	LIFT_NOT_PASSENGER="Step inside the lift to choose a floor.",
	LIFT_FLOOR_LOCKED="Your card does not open that floor.",
	LIFT_FULL="The lift is full. Wait for the next cabin.",
	LIFT_NO_LANDING="Walk to a lift landing first.",
	LIFT_OUT_OF_SERVICE="The lift is out of service right now. Use the stairs beside the lift.",
	DOOR_DENIED="Your card does not open this door.",
	DOOR_BUSY="This door is moving. Try again in a moment.",
	OCCUPIED="Someone is already using this.",
	FOUNDER_ONLY="Only the company founder can open this.",
	RESEARCH_ONLY="This room needs research clearance.",
	TECHNICAL_ONLY="This room is for technical staff only.",
	COMPUTE_ONLY="The compute room is for compute engineers only.",
	CARD_REQUIRED="You need a valid card for this company.",
	SNACK_FULL="Your snack bag holds 16 items. Eat a snack first.",
	MAX_RETAIL="Your stores are fully upgraded.",
	CAR_OCCUPIED="Leave your current car before collecting another.",
	PLAYER_OFFLINE="This player is no longer on the server.",
	PROJECT_ACTIVE="A project is already using your compute.",
	PROJECT_LIMIT="Your studio has reached its 30-project limit.",
	PROJECT_NOT_READY="Wait for this project to finish building.",
	PROJECT_QUALITY="This project does not meet the client quality requirement.",
	NO_PROJECT_MODEL="Train a model or buy an active AI subscription first.",
	ARENA_ACTIVE="Your model is already running a test.",
	ARENA_BUSY="All three courier courses are in use. Try again shortly.",
	MAX_COOLING="Your cooling system is fully upgraded.",
	RATE_LIMIT = "Slow down a little.",
	LOADING = "Still loading your company...",
	SERVER_ERROR = "Something went wrong on the server. Try again.",
	NETWORK = "Connection problem. Try again.",
	NO_COMPANY = "Found your company first.",
	ALREADY_FOUNDED = "Your company already exists.",
	NAME_FILTERED = "That name isn't allowed. Try another one.",
	FILTER_DOWN = "Name check is unavailable right now. Try again in a moment.",
	BAD_INPUT = "That didn't work. Check your input.",
	NO_MONEY = "Not enough money.",
	COOLDOWN = "The scraper is cooling down.",
	RACK_FULL = "Your server rack is full. Move to a bigger office or research Distributed Cluster.",
	NEW_DATA = "Add at least 100M new tokens before another refinement run.",
	QUOTE_CHANGED = "The offer changed. Check the new monthly price and try again.",
	SELF_PURCHASE = "This is your own model. Publish it to find customers.",
	ACCESS_ACTIVE = "You already have an active API subscription.",
	SELLER_OFFLINE = "The provider must be on this server to buy or renew access.",
	NOT_OWNED = "You don't own that.",
	TRAINING_ACTIVE = "A training run is already in progress.",
	NO_GPU = "You need a GPU to train.",
	VRAM = "Not enough VRAM for this model size. Open Hardware or choose a smaller model size.",
	NO_DATA = "Not enough training data.",
	NO_EVENT = "There is nothing to decide right now.",
	BAD_MODEL = "That model isn't available.",
	NOT_ALLOWED = "Debug tools only work in Studio.",
	NO_TRAINING = "No training is running.",
	STAFF_FULL = "All desks are filled. Upgrade your office or dismiss an employee.",
	ALREADY_DONE = "This reward has already been collected or this upgrade is complete.",
	RESEARCH_ACTIVE = "One research project is already running.",
	PREREQUISITE = "Finish the required research first.",
	NO_POINTS = "Not enough research points. Hire researchers to generate more.",
	MAX_OFFICE = "You already own the largest office.",
	NOT_READY = "Complete this milestone first.",
	OFFICE_REQUIRED = "This customer requires a larger office.",
	CONTRACT_REQUIREMENTS = "Your live model does not meet this contract's requirements.",
	MODEL_LIMIT = "Your company reached the limit of 80 active models. Retire old models first.",
	-- CORE_SPEC 11.8 (company economy)
	FIRST_CLIENT = "Sign your first business client before you leave the garage.",
	LINE_LIMIT = "All product lines of this office are taken. Release a new version into a live line, or move to a bigger office for another line.",
	REFINE_LIMIT = "This model was already refined 3 times. Train a new version instead.",
	MAX_LEVEL = "The Lab is at its highest level.",
	OWNED = "You already own this.",
	OFFICE = "This needs a bigger office stage. Move up in Company → Office.",
	NO_MEETING = "No meeting with this client is scheduled right now.",
	TOO_FAR = "Go to the client's office to join the meeting.",
	NEEDS_PASS = "This car comes with the Executive Limousine game pass.",
}

local busy: { [string]: boolean } = {}

function ActionController.message(err: string?): string
	if err == "BAD_NAME" then
		return `Company names need {GameConfig.COMPANY_NAME_MIN}-{GameConfig.COMPANY_NAME_MAX} characters, model names {GameConfig.MODEL_NAME_MIN}-{GameConfig.MODEL_NAME_MAX}. No invisible symbols.`
	end
	return if err and MESSAGES[err] then MESSAGES[err] else "Something went wrong."
end

-- Ruft ein Remote auf. Gibt (ok, Antwort) zurück. silent = keine Fehler-Toasts.
function ActionController.call(name: string, payload: { [string]: any }?, silent: boolean?): (boolean, Result)
	if busy[name] then
		return false, { ok = false, err = "BUSY" }
	end
	busy[name] = true
	local remote = Net.getFunction(name)
	local ok, result = pcall(function(): any
		return remote:InvokeServer(payload or {})
	end)
	busy[name] = nil

	if not ok or typeof(result) ~= "table" then
		if not silent then
			Toast.show("error", MESSAGES.NETWORK)
		end
		return false, { ok = false, err = "NETWORK" }
	end
	local response: Result = result
	if response.ok ~= true then
		if not silent then
			Toast.show("error", ActionController.message(response.err))
		end
		return false, response
	end
	return true, response
end

return ActionController
