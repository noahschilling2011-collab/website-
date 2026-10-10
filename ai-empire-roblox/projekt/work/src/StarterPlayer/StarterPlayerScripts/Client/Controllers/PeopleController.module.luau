--!strict
-- People on the client: job interviews (Notify INTERVIEW_OPEN → UI/Screens/Conversation), the founder's
-- Executive Assistant (Notify ASSISTANT_OPEN → briefing panel) and their notices (PEOPLE_NOTICE,
-- ASSISTANT_NOTICE → toasts). The briefing is built by the server from the founder's own session data;
-- this panel only lays it out. Own ScreenGui with a viewport-fitted UIScale like the lift panel.
local Players=game:GetService("Players")
local GuiService=game:GetService("GuiService")
local UserInputService=game:GetService("UserInputService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Format=require(ReplicatedStorage.Shared.Format)
local State=require(script.Parent.StateController)
local Action=require(script.Parent.ActionController)
local UI=script.Parent.Parent.UI
local Kit=require(UI.Kit)
local Theme=require(UI.Theme)
local Toast=require(UI.Toast)
local Conversation=require(UI.Screens.Conversation)
local C,F=Theme.colors,Theme.font
local Controller={}
local player=Players.LocalPlayer
local panel: ScreenGui?=nil
local openComputer: (string,string?)->()=function(_app: string,_section: string?) end
local MESSAGES: {[string]:string}={
 APPLICANT_GONE="This application is no longer open.",
 ALREADY_INVITED="This candidate is already on the way to the visitor lounge.",
 NO_OFFICE="Your headquarters is still being prepared. Try again in a moment.",
 NOT_HERE="Talk to the candidate in the visitor lounge first.",
 ASKED="You already asked that.",
 QUESTION_LIMIT="That's enough questions. Time to decide.",
 OFFER_DECLINED="They already turned down the lower offer.",
 NO_ASK="There is no question to answer right now.",
 NO_ASSISTANT="Your assistant isn't at her desk yet.",
 ASSISTANT_BUSY="She is already on a coffee run.",
 COFFEE_COOLDOWN="A fresh coffee in a little while. She just brought one.",
 STAFF_FULL="All desks are filled. Upgrade your office or dismiss an employee first.",
}
function Controller.message(err: string?): string
 return if err and MESSAGES[err] then MESSAGES[err] else Action.message(err)
end
-- Remote call with readable error toasts for the people codes.
function Controller.call(name: string,payload: {[string]:any}): (boolean,any)
 local ok,res=Action.call(name,payload,true)
 if not ok and res.err~="BUSY" then Toast.show("error",Controller.message(res.err)) end
 return ok,res
end
local function recruit(payload: {[string]:any}): (boolean,any) return Controller.call("RecruitAction",payload) end

-- Assistant briefing panel ------------------------------------------------------------------------
local function closePanel()
 if panel then panel:Destroy();panel=nil end
end
local W,H=660,600
local function showBriefing(data: any)
 closePanel()
 local screen=Instance.new("ScreenGui");screen.Name="PeopleAssistant";screen.ResetOnSpawn=false;screen.DisplayOrder=41;screen.Parent=player:WaitForChild("PlayerGui");panel=screen
 local box=Kit.frame(screen,UDim2.fromOffset(W,H),UDim2.fromScale(.5,.5));box.AnchorPoint=Vector2.new(.5,.5)
 box.BackgroundColor3=C.panel;box.BackgroundTransparency=0;Kit.corner(box,14);Kit.stroke(box,.85)
 local scale=Instance.new("UIScale");scale.Parent=box
 local function fit()
  local camera=workspace.CurrentCamera;local vp=if camera then camera.ViewportSize else Vector2.new(1280,720)
  scale.Scale=math.clamp(math.min((vp.Y-24)/H,(vp.X-24)/W),.3,1)
 end
 fit()
 local camera=workspace.CurrentCamera
 if camera then
  local resize=camera:GetPropertyChangedSignal("ViewportSize"):Connect(function() if scale.Parent then fit() end end)
  screen.Destroying:Connect(function() resize:Disconnect() end)
 end
 local inner=Kit.frame(box,UDim2.new(1,-32,1,-32),UDim2.fromOffset(16,16))
 local initials="";for word in string.gmatch(tostring(data.name),"%S+") do initials..=string.sub(word,1,1) end
 Conversation.avatar(inner,string.upper(string.sub(initials,1,2)),tonumber(data.seed) or 0,56).Position=UDim2.fromOffset(0,0)
 local title=Kit.text(inner,tostring(data.name),21,F.bold,C.text);title.Position=UDim2.fromOffset(70,2)
 Kit.text(inner,tostring(data.role)..(if typeof(data.company)=="string" then "  ·  "..data.company else ""),14,F.medium,C.muted).Position=UDim2.fromOffset(70,30)
 local closeTop=Kit.button(inner,"Close","ghost",UDim2.fromOffset(92,32));closeTop.AnchorPoint=Vector2.new(1,0);closeTop.Position=UDim2.new(1,0,0,0)
 Kit.onClick(closeTop,closePanel)
 local scroll=Kit.scroll(inner,UDim2.new(1,0,1,-126),UDim2.fromOffset(0,68))
 local stack=Kit.stack(scroll,10);Kit.padding(stack,0,8,8,0)
 -- recommendations first: what to do next
 local recs=Kit.card(stack,1,8)
 local stroke=recs:FindFirstChildOfClass("UIStroke");if stroke then stroke.Transparency=.35;Theme.bindAccent(stroke,"Color") end
 local head=Kit.text(recs,"My recommendations",16,F.bold,C.text);head.LayoutOrder=0
 for i,rec in data.recommendations or {} do
  local rowFrame=Kit.frame(recs,UDim2.fromScale(1,0));rowFrame.AutomaticSize=Enum.AutomaticSize.Y;rowFrame.LayoutOrder=i
  local hasApp=typeof(rec.app)=="string"
  local label=Kit.para(rowFrame,tostring(i)..".  "..tostring(rec.text),15,C.text)
  label.Size=UDim2.new(1,if hasApp then -96 else 0,0,0)
  if hasApp then
   local go=Kit.button(rowFrame,"Open","secondary",UDim2.fromOffset(86,30));go.AnchorPoint=Vector2.new(1,0);go.Position=UDim2.fromScale(1,0);go.TextSize=14
   Kit.onClick(go,function() closePanel();openComputer(rec.app,if typeof(rec.section)=="string" then rec.section else nil) end)
  end
 end
 for i,section in data.sections or {} do
  local card=Kit.card(stack,i+1,4)
  local t=Kit.text(card,tostring(section.title),15,F.bold,C.text);t.LayoutOrder=0
  for j,row in section.rows or {} do
   local line=Kit.frame(card,UDim2.fromScale(1,0));line.AutomaticSize=Enum.AutomaticSize.Y;line.LayoutOrder=j
   local key=Kit.text(line,tostring(row[1]),14,F.medium,C.muted);key.AutomaticSize=Enum.AutomaticSize.None;key.Size=UDim2.fromOffset(170,20)
   local value=Kit.para(line,tostring(row[2]),14,C.text);value.Position=UDim2.fromOffset(178,1);value.Size=UDim2.new(1,-178,0,0)
  end
 end
 local footer=Kit.frame(inner,UDim2.new(1,0,0,46),UDim2.new(0,0,1,-46));Kit.list(footer,10,true)
 local coffee=data.coffee or {}
 local cooldown=tonumber(coffee.cooldown) or 0
 local canOrder=false
 local coffeeText
 if coffee.carrying then coffeeText="She has your coffee"
 elseif coffee.state~="post" and coffee.state~="toPost" and coffee.state~="retryHome" then coffeeText=if coffee.state=="absent" then "Not at her desk" else "On a coffee run"
 elseif cooldown>0 then coffeeText="Coffee in "..Format.duration(cooldown)
 else coffeeText="Bring me a coffee · "..Format.money(tonumber(coffee.price) or 0);canOrder=true end
 local cup=Kit.button(footer,coffeeText,"primary",UDim2.new(.36,-8,1,0));cup.LayoutOrder=1;cup.TextSize=15
 Kit.setDisabled(cup,not canOrder)
 local refresh=Kit.button(footer,"Refresh analysis","secondary",UDim2.new(.25,-8,1,0));refresh.LayoutOrder=2;refresh.TextSize=15
 local apps=Kit.button(footer,"Open applications","secondary",UDim2.new(.25,-8,1,0));apps.LayoutOrder=3;apps.TextSize=15
 local close=Kit.button(footer,"Close","ghost",UDim2.new(.14,0,1,0));close.LayoutOrder=4;close.TextSize=15
 Kit.onClick(cup,function()
  task.spawn(function()
   local ok,res=Controller.call("AssistantAction",{action="coffee"})
   if ok then Toast.show("success",tostring(data.name).." is getting your coffee from the tea kitchen.",4) end
   if typeof(res)=="table" and typeof(res.assistant)=="table" and panel==screen then showBriefing(res.assistant) end
  end)
 end)
 Kit.onClick(refresh,function()
  task.spawn(function()
   local ok,res=Controller.call("AssistantAction",{action="brief"})
   if ok and typeof(res.assistant)=="table" and panel==screen then showBriefing(res.assistant) end
  end)
 end)
 Kit.onClick(apps,function() closePanel();openComputer("empire","team") end)
 Kit.onClick(close,closePanel)
 if UserInputService.GamepadEnabled then GuiService.SelectedObject=cup end
 -- walking away closes the panel
 local character=player.Character;local root=if character then character:FindFirstChild("HumanoidRootPart") else nil
 local start=if root and root:IsA("BasePart") then root.Position else nil
 task.spawn(function()
  while panel==screen do
   task.wait(.5)
   local c=player.Character;local r=if c then c:FindFirstChild("HumanoidRootPart") else nil
   if start and r and r:IsA("BasePart") and (r.Position-start).Magnitude>30 then closePanel();break end
  end
 end)
end

function Controller.init(open: (string,string?)->())
 openComputer=open
 State.onNotify(function(kind,payload)
  if kind=="INTERVIEW_OPEN" and typeof(payload.id)=="string" then
   closePanel();Conversation.open(payload,recruit)
  elseif kind=="ASSISTANT_OPEN" and typeof(payload.name)=="string" then
   if not Conversation.isOpen() then showBriefing(payload) end
  elseif (kind=="PEOPLE_NOTICE" or kind=="ASSISTANT_NOTICE") and typeof(payload.text)=="string" then
   Toast.show("info",payload.text,if kind=="ASSISTANT_NOTICE" then 7 else 5)
  end
 end)
 player.CharacterAdded:Connect(function() closePanel();Conversation.close() end)
end
return Controller
