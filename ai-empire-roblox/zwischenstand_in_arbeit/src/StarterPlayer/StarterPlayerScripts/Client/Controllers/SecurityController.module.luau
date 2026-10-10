--!strict
-- CCTV uses the actual Roblox world camera, so staff, players, doors and cars are live.
-- Channels are grouped by level; the view stays covered by "Loading area…" until the streamed
-- world around the camera has arrived, so the founder never looks into an empty void.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Context=game:GetService("ContextActionService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Plan=require(ReplicatedStorage.Shared.Config.BuildingPlan)
local State=require(script.Parent.StateController)
local Action=require(script.Parent.ActionController)
local Theme=require(script.Parent.Parent.UI.Theme)
local Kit=require(script.Parent.Parent.UI.Kit)
local Controller={}
local player=Players.LocalPlayer
local LOCK="🔒"
local LOAD_RADIUS=20;local LOAD_TIMEOUT=6
type Channel={id: string,name: string,cframe: CFrame,level: number?,private: boolean}
local gui: ScreenGui?=nil
local old: any=nil
local target: CFrame?=nil
local channels: {Channel}={}
local selected=1
local title: TextLabel?=nil
local loading: Frame?=nil
local currentOwner: number?=nil
local token=0
local deathConn: RBXScriptConnection?=nil
local function tier(): number
	local snapshot=State.snapshot
	-- building tier of the own plot (office index 1 = Garage Lab = plan tier 0, CORE_SPEC 2.4)
	return Plan.tierForOffice(if snapshot then snapshot.data.empire.office else 1)
end
local function levelTitle(level: number?): string
	return if level then Plan.floorTitle(tier(),level) else "Other views"
end
function Controller.close()
	token+=1
	if gui then gui:Destroy();gui=nil end
	if deathConn then deathConn:Disconnect();deathConn=nil end
	title=nil;loading=nil;target=nil;currentOwner=nil;Context:UnbindAction("CampusCameraControls")
	local camera=workspace.CurrentCamera
	if camera and old then
		camera.CameraType=old.kind;camera.CFrame=old.cf;camera.FieldOfView=old.fov
		-- After a respawn the old subject is a dead humanoid; the new one (or the default camera
		-- scripts once it exists) takes over instead.
		local h=if player.Character then player.Character:FindFirstChildOfClass("Humanoid") else nil
		if h then camera.CameraSubject=h end
	end
	old=nil
end
-- True once anything other than the local character exists around the camera position.
local function areaReady(position: Vector3): boolean
	local params=OverlapParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.MaxParts=1
	params.FilterDescendantsInstances=if player.Character then {player.Character} else {}
	return #workspace:GetPartBoundsInRadius(position,LOAD_RADIUS,params)>0
end
local function setLoading(visible: boolean)
	if loading then loading.Visible=visible end
end
local function selectChannel(index: number)
	if #channels==0 then return end
	selected=(index-1)%#channels+1
	local def=channels[selected];target=def.cframe;token+=1;local mine=token
	local label=title
	if label then label.Text=string.format("%02d / %02d   %s%s   ·   %s",selected,#channels,if def.private then LOCK.." " else "",def.name,levelTitle(def.level)) end
	local position=def.cframe.Position
	setLoading(not areaReady(position))
	task.spawn(function()
		pcall(function() player:RequestStreamAroundAsync(position,3) end)
		local deadline=os.clock()+LOAD_TIMEOUT
		while mine==token and not areaReady(position) and os.clock()<deadline do task.wait(.25) end
		if mine==token then setLoading(false) end
	end)
end
local function clean(payload: any): {Channel}
	local out: {Channel}={}
	for i,c in payload.channels do
		if typeof(c)~="table" or typeof(c.cframe)~="CFrame" or typeof(c.name)~="string" then continue end
		local level=c.level;if level==nil then level=c.Level end
		local private=c.private;if private==nil then private=c.Private end
		table.insert(out,{id=if typeof(c.id)=="string" then c.id else tostring(i),name=c.name,cframe=c.cframe,level=if typeof(level)=="number" then level else nil,private=private==true})
	end
	-- Top floor first, like a building directory; unknown levels last. Server order within a level.
	local order: {[Channel]:number}={};for i,c in out do order[c]=i end
	table.sort(out,function(a,b)
		local la=a.level or -math.huge;local lb=b.level or -math.huge
		if la~=lb then return la>lb end
		return order[a]<order[b]
	end)
	return out
end
local function watchDeath()
	local h=if player.Character then player.Character:FindFirstChildOfClass("Humanoid") else nil
	if h then deathConn=h.Died:Connect(Controller.close) end
end
local function show(payload: any)
	if payload.ownerId~=player.UserId or typeof(payload.channels)~="table" then return end
	local found=clean(payload)
	if #found==0 or not workspace.CurrentCamera then return end
	Controller.close();channels=found;currentOwner=payload.ownerId
	local camera=workspace.CurrentCamera;old={kind=camera.CameraType,cf=camera.CFrame,fov=camera.FieldOfView}
	camera.CameraType=Enum.CameraType.Scriptable;camera.FieldOfView=78
	watchDeath()
	Context:BindAction("CampusCameraControls",function()return Enum.ContextActionResult.Sink end,false,Enum.PlayerActions.CharacterForward,Enum.PlayerActions.CharacterBackward,Enum.PlayerActions.CharacterLeft,Enum.PlayerActions.CharacterRight,Enum.PlayerActions.CharacterJump)
	local screen=Instance.new("ScreenGui");screen.Name="CampusSecurity";screen.ResetOnSpawn=false;screen.DisplayOrder=55;screen.Parent=player:WaitForChild("PlayerGui");gui=screen
	-- Opaque cover behind the controls while the camera's surroundings stream in.
	local cover=Kit.frame(screen,UDim2.fromScale(1,1));cover.BackgroundColor3=Theme.colors.bg;cover.BackgroundTransparency=0;cover.ZIndex=0;cover.Visible=false;loading=cover
	local hint=Kit.text(cover,"Loading area…",18,Theme.font.medium,Theme.colors.muted);hint.AnchorPoint=Vector2.new(.5,.5);hint.Position=UDim2.fromScale(.5,.5);hint.ZIndex=0
	local top=Kit.panel(screen,UDim2.new(1,-32,0,74),UDim2.fromOffset(16,16));Kit.padding(top,13,18,13,18)
	Kit.text(top,"CAMPUS SECURITY  /  LIVE",12,Theme.font.bold,Theme.colors.muted)
	local heading=Kit.text(top,"",19,Theme.font.bold,Theme.colors.text);heading.Position=UDim2.fromOffset(0,25);heading.AutomaticSize=Enum.AutomaticSize.None;heading.Size=UDim2.new(1,-112,0,25);heading.TextTruncate=Enum.TextTruncate.AtEnd;title=heading
	local close=Kit.button(top,"Back","secondary",UDim2.fromOffset(100,34));close.Position=UDim2.new(1,-100,0,5);Kit.onClick(close,Controller.close)
	local list=Kit.panel(screen,UDim2.new(0,252,1,-184),UDim2.fromOffset(16,102));Kit.padding(list,10,10,10,10)
	list.Visible=camera.ViewportSize.X>=700
	local choose=Kit.button(screen,"Channels","secondary",UDim2.fromOffset(110,34));choose.Position=UDim2.fromOffset(16,102);choose.Visible=not list.Visible;Kit.onClick(choose,function()list.Visible=not list.Visible;choose.Position=if list.Visible then UDim2.fromOffset(280,102) else UDim2.fromOffset(16,102) end)
	local scroll=Kit.scroll(list,UDim2.fromScale(1,1));Kit.list(scroll,6)
	local order=0;local group: any=false
	for i,c in channels do
		if c.level~=group then
			group=c.level;order+=1
			local caption=Kit.text(scroll,levelTitle(c.level),12,Theme.font.bold,Theme.colors.muted);caption.LayoutOrder=order
			caption.AutomaticSize=Enum.AutomaticSize.None;caption.Size=UDim2.new(1,-6,0,22);caption.TextTruncate=Enum.TextTruncate.AtEnd
		end
		order+=1
		local b=Kit.button(scroll,string.format("%02d  %s%s",i,c.name,if c.private then "  "..LOCK else ""),"secondary",UDim2.new(1,-6,0,37));b.TextSize=12;b.LayoutOrder=order;Kit.onClick(b,function()selectChannel(i)end)
	end
	local bottom=Kit.panel(screen,UDim2.fromOffset(math.min(390,camera.ViewportSize.X-32),54),UDim2.new(.5,0,1,-16));bottom.AnchorPoint=Vector2.new(.5,1);Kit.padding(bottom,8,8,8,8)
	local prev=Kit.button(bottom,"← Previous","secondary",UDim2.new(.5,-6,0,38));Kit.onClick(prev,function()selectChannel(selected-1)end)
	local next=Kit.button(bottom,"Next →","secondary",UDim2.new(.5,-6,0,38));next.Position=UDim2.new(.5,6,0,0);Kit.onClick(next,function()selectChannel(selected+1)end)
	selectChannel(1)
end
function Controller.open()
	task.spawn(function()local ok,result=Action.call("OpenSecurity",{});if ok then show(result) end end)
end
function Controller.init()
	RunService.RenderStepped:Connect(function()
		local camera=workspace.CurrentCamera
		if target and camera then camera.CameraType=Enum.CameraType.Scriptable;camera.CFrame=target end
	end)
	player.CharacterAdded:Connect(function() if gui then Controller.close() end end)
	player.CharacterRemoving:Connect(function() if gui then Controller.close() end end)
	State.onNotify(function(kind,payload)if kind=="SECURITY_OPEN" then show(payload) end end)
	State.onChange(function(snapshot)
		if currentOwner and (snapshot.live.campus and snapshot.live.campus.hasCard==false) then Controller.close() end
	end)
end
return Controller
