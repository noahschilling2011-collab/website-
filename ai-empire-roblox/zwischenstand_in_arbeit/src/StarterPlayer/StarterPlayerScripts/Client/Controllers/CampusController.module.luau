--!strict
-- Nearby staff follow a daily routine. Vehicle input supports Roblox's keyboard/gamepad/touch controller.
-- The lift cabin panel (Notify LIFT_PANEL) lists every stop; a choice is a car call for riders or a
-- hall call from the landing the player stands at (the server remembers the floor for boarding).
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local GuiService=game:GetService("GuiService")
local UserInputService=game:GetService("UserInputService")
local Net=require(ReplicatedStorage.Shared.Net)
local Math=require(ReplicatedStorage.Shared.CampusMath)
local State=require(script.Parent.StateController)
local Toast=require(script.Parent.Parent.UI.Toast)
local Action=require(script.Parent.ActionController)
local Theme=require(script.Parent.Parent.UI.Theme)
local Kit=require(script.Parent.Parent.UI.Kit)
local Controller={}
local player=Players.LocalPlayer
local liftGui: ScreenGui?=nil
-- Fallback texts for lift codes ActionController does not know (its own messages win).
local LIFT_MESSAGES: {[string]: string}={
	LIFT_NOT_PASSENGER="Step inside the lift to choose a floor.",
	LIFT_NO_LANDING="Walk up to a lift landing first.",
	LIFT_OUT_OF_SERVICE="The lift is out of service. Please use the stairs.",
	LIFT_FLOOR_LOCKED="Your card does not open that floor.",
	LIFT_SEATED="Leave your seat before using the lift.",
	CARD_REQUIRED="You need a valid card for this company.",
}
local function liftMessage(err: string?): string
	local text=Action.message(err)
	if text==Action.message(nil) and err and LIFT_MESSAGES[err] then return LIFT_MESSAGES[err] end
	return text
end
local function closeLift(gui: ScreenGui?)
	local target=gui or liftGui
	if target then target:Destroy() end
	if liftGui==target then liftGui=nil end
end
local function rootPosition(): Vector3?
	local character=player.Character;local root=if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root.Position else nil
end
local function liftPanel(payload: any)
	closeLift()
	local stops: {any}=if typeof(payload.stops)=="table" then payload.stops else {}
	local gui=Instance.new("ScreenGui");gui.Name="CampusLift";gui.ResetOnSpawn=false;gui.DisplayOrder=40;gui.Parent=player:WaitForChild("PlayerGui");liftGui=gui
	local height=140+#stops*43
	local box=Kit.frame(gui,UDim2.fromOffset(400,height),UDim2.fromScale(.5,.5));box.AnchorPoint=Vector2.new(.5,.5);box.BackgroundColor3=Theme.colors.panel;box.BackgroundTransparency=0;Kit.corner(box,12);Kit.stroke(box,.87);Kit.padding(box,16,16,16,16)
	local scale=Instance.new("UIScale");local camera=workspace.CurrentCamera;scale.Scale=if camera then math.max(.3,math.min(1,(camera.ViewportSize.Y-32)/height,(camera.ViewportSize.X-24)/400)) else 1;scale.Parent=box
	Kit.list(box,5)
	local heading=Kit.para(box,"Lift · choose a floor",20,Theme.colors.text,1);heading.Font=Theme.font.bold
	local here="";for _,stop in stops do if typeof(stop)=="table" and stop.level==payload.current then here=tostring(stop.label).." · "..tostring(stop.name) end end
	local note=if payload.outOfService then "Out of service. Please use the stairs beside the lift."
		elseif payload.passenger then "Cabin at "..here
		else "Pick your floor: the lift comes to this landing and takes you there."
	Kit.para(box,note,14,Theme.colors.muted,2)
	local first: TextButton?=nil
	for i=#stops,1,-1 do -- top floor first, like a real panel
		local stop=stops[i]
		if typeof(stop)~="table" or typeof(stop.level)~="number" then continue end
		local label=tostring(stop.label).."  ·  "..tostring(stop.name)
		local current=stop.level==payload.current
		local b=Kit.button(box,label,"secondary",UDim2.new(1,0,0,38));b.LayoutOrder=10+#stops-i
		b.TextXAlignment=Enum.TextXAlignment.Left;b.TextTruncate=Enum.TextTruncate.AtEnd;Kit.padding(b,0,12,0,14)
		local usable=stop.allowed==true and payload.outOfService~=true
		if current then local stroke=Kit.stroke(b,0,Theme.accent,2);Theme.bindAccent(stroke,"Color") end
		if not usable then
			Kit.setDisabled(b,true);b.Selectable=false;b.TextColor3=Theme.colors.dim
		else
			if current then Theme.bindAccent(b,"TextColor3") end
			if not first then first=b end
		end
		Kit.onClick(b,function()
			task.spawn(function()
				local ok,response=Action.call("UseCampusLift",{ownerId=payload.ownerId,floor=stop.level},true)
				if ok then
					closeLift(gui)
					Toast.show("success",if response.kind=="hall" then "Lift called · it will take you to "..tostring(stop.label)
						elseif current then "Doors opening" else "Going to "..label,3)
				elseif response.err~="BUSY" then
					Toast.show("error",liftMessage(response.err))
				end
			end)
		end)
	end
	local close=Kit.button(box,"Close","ghost",UDim2.new(1,0,0,32));close.LayoutOrder=100;Kit.onClick(close,function()closeLift(gui)end)
	if UserInputService.GamepadEnabled then GuiService.SelectedObject=first or close end
	-- The cabin moves vertically, so only walking away (horizontal distance) closes the panel.
	local start=rootPosition()
	task.spawn(function()
		while gui.Parent do
			task.wait(.5)
			local p=rootPosition()
			if not p or not start or Vector3.new(p.X-start.X,0,p.Z-start.Z).Magnitude>16 then closeLift(gui);break end
		end
	end)
end
function Controller.init()
	local input=Net.getEvent("VehicleInput")
	local clock=0
	RunService.Heartbeat:Connect(function(dt)
		clock+=dt
		local character=player.Character;local humanoid=if character then character:FindFirstChildOfClass("Humanoid") else nil
		local seat=if humanoid then humanoid.SeatPart else nil
		if clock>=.06 then
			clock=0
			if seat and seat:IsA("VehicleSeat") and seat.Parent:GetAttribute("OwnerUserId")==player.UserId then
				input:FireServer(seat.Parent:GetAttribute("CarId"),seat.ThrottleFloat,seat.SteerFloat)
			end
		end

	end)
	State.onNotify(function(kind,payload)
		if kind=="LIFT_PANEL" and typeof(payload.ownerId)=="number" and typeof(payload.stops)=="table" then liftPanel(payload) end
		if kind=="LIFT_CALLED" then
			local arrived=payload.state=="open" or payload.state=="opening" or payload.state=="reopen"
			Toast.show("success",if arrived then "The lift is here." else "Lift called"..(if typeof(payload.label)=="string" then " to "..payload.label else "").." · please wait at the doors.",3)
		end
		if kind=="LIFT_ERROR" then Toast.show("error",liftMessage(if typeof(payload.err)=="string" then payload.err else nil)) end
		if kind=="CAMPUS_NOTICE" and typeof(payload.text)=="string" then
			-- error codes routed as notices (e.g. a refused lift call) become readable messages
			if LIFT_MESSAGES[payload.text] or string.match(payload.text,"^%u+_[%u_]+$") then Toast.show("error",liftMessage(payload.text))
			else Toast.show("info",payload.text,5) end
		end
	end)
end
return Controller
