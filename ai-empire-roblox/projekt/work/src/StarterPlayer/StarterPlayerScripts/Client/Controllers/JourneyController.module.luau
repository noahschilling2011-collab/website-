--!strict
-- One small physical marker, only on the owner's current destination. No giant simulator arrows.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Collection=game:GetService("CollectionService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Journey=require(ReplicatedStorage.Shared.JourneyMath)
local State=require(script.Parent.StateController)
local Controller={};local marker: BillboardGui?=nil;local clock=0
function Controller.init()
 RunService.Heartbeat:Connect(function(dt)
  clock+=dt;if clock<1 then return end;clock=0
  local snapshot=State.snapshot;local camera=workspace.CurrentCamera
  if not snapshot or not snapshot.data.company or not camera then return end
  local progress=Journey.progress(snapshot.data,State.ui);local best=nil;local min=math.huge
  if not progress.complete then for _,p in Collection:GetTagged("CompanyScreen") do
   if p:IsA("BasePart") and p:GetAttribute("JourneyStep")==progress.index then
    local office=p:FindFirstAncestor("Office")
    if office and office:GetAttribute("OwnerUserId")==Players.LocalPlayer.UserId then
     local d=(p.Position-camera.CFrame.Position).Magnitude;if d<min then best=p;min=d end
    end
   end
  end end
  if marker and (not best or marker.Adornee~=best) then marker:Destroy();marker=nil end
  if best and not marker then
   local gui=Instance.new("BillboardGui");gui.Name="FirstAIWaypoint";gui.Adornee=best;gui.Size=UDim2.fromOffset(160,26);gui.StudsOffset=Vector3.new(0,3,0);gui.MaxDistance=80;gui.AlwaysOnTop=false;gui.Parent=best
   local t=Instance.new("TextLabel");t.Size=UDim2.fromScale(1,1);t.BackgroundColor3=Color3.fromRGB(42,55,47);t.BackgroundTransparency=.15;t.TextColor3=Color3.fromRGB(226,235,216);t.TextSize=12;t.Font=Enum.Font.BuilderSansMedium;t.Text=progress.index.." / 7 · "..progress.step.label;t.Parent=gui;marker=gui
  end
 end)
end
return Controller
