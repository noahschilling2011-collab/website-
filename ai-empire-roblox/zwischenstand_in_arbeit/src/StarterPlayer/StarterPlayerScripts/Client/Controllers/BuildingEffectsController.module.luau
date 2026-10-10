--!strict
-- Calm building feedback on the client:
--   - A pending training decision turns nearby screen headers a steady amber (a status, not an
--     alarm); the header returns to its accent colour as soon as the decision is made.
--   - One quiet local ambience loop chosen from the BuildingPlan room at the camera position.
-- Fans, blades and every other moving prop are animated by PropFxController (PropFx contract).
local Collection=game:GetService("CollectionService")
local RunService=game:GetService("RunService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Config=require(ReplicatedStorage.Shared.Config.CampusAudioConfig)
local Plan=require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Controller={}
local AMBER=Color3.fromRGB(219,171,88)
local SCREEN_RANGE=120;local VOLUME=.08
local screens: {[BasePart]:boolean}={}
local accents: {[TextLabel]:Color3}=setmetatable({},{__mode="k"}) :: any
local clock=0
local ambience: Sound?=nil;local current=""
local KITCHEN={cafe=true,kitchen_boh=true,pantry=true}
local function add(p: Instance) if p:IsA("BasePart") then screens[p]=true end end
local function header(p: BasePart): TextLabel?
	local gui=p:FindFirstChild("Desktop");local label=if gui then gui:FindFirstChild("Header") else nil
	return if label and label:IsA("TextLabel") then label else nil
end
-- Steady status colour; the accent the server built the header with is remembered and restored.
local function paintHeaders(position: Vector3)
	for p in screens do
		if not p.Parent then screens[p]=nil;continue end
		if (position-p.Position).Magnitude>SCREEN_RANGE then continue end
		local label=header(p);if not label then continue end
		if p:GetAttribute("TrainingAlert")==true then
			if not accents[label] then accents[label]=label.TextColor3 end
			if label.TextColor3~=AMBER then label.TextColor3=AMBER end
		else
			local accent=accents[label]
			if accent then label.TextColor3=accent;accents[label]=nil end
		end
	end
end
-- Ambience key of the room around a world position, or "" outside every headquarters.
local function ambienceAt(position: Vector3): string
	local plots=workspace:FindFirstChild("Plots");if not plots then return "" end
	for _,plot in plots:GetChildren() do
		local office=plot:FindFirstChild("Office")
		local cf=if office then office:GetAttribute("CampusCFrame") else nil
		local tier=if office then office:GetAttribute("OfficeTier") else nil
		if typeof(cf)~="CFrame" or typeof(tier)~="number" then continue end
		local v=cf:PointToObjectSpace(position)
		if not Plan.inside(tier,v) then continue end
		local room=Plan.roomAt(tier,v)
		if not room then return "" end
		if room.kind=="compute" or room.kind=="datahall" then return "compute" end
		if KITCHEN[room.kind] then return "kitchen" end
		if room.kind=="garage" or room.level<0 then return "garage" end
		if Plan.WORK_KINDS[room.kind] then return "office" end
		return ""
	end
	return ""
end
local function setAmbience(kind: string,camera: Camera)
	if current==kind then return end
	if ambience then ambience:Destroy();ambience=nil end;current=kind
	local id=Config.AMBIENCE[kind]
	if id and id~="" then
		local s=Instance.new("Sound");s.Name="CampusAmbience";s.SoundId=id;s.Volume=VOLUME;s.Looped=true;s.Parent=camera;s:Play();ambience=s
	end
end
function Controller.init()
	for _,p in Collection:GetTagged("CompanyScreen") do add(p) end
	Collection:GetInstanceAddedSignal("CompanyScreen"):Connect(add)
	Collection:GetInstanceRemovedSignal("CompanyScreen"):Connect(function(p)screens[p]=nil end)
	RunService.Heartbeat:Connect(function(dt)
		clock+=dt;if clock<.5 then return end;clock=0
		local camera=workspace.CurrentCamera;if not camera then return end
		local position=camera.CFrame.Position
		paintHeaders(position)
		setAmbience(ambienceAt(position),camera)
	end)
end
return Controller
