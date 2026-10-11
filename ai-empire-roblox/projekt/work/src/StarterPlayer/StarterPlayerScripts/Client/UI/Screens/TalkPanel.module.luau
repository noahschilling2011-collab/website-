--!strict
-- Talk panel: a short chat with someone in the company (TalkController opens it from Notify TALK_OPEN
-- or a TalkAction open). Same look as the interview (UI/Screens/Conversation): initials avatar, chat
-- bubbles — the person on the left, "You" on the right — and a "typing…" pause before every answer.
-- The lines are authored on the server from real company data (ReplicatedStorage.Shared.Dialogue);
-- this panel only lays them out. Reply chips (2–4) come from the server; the last one says goodbye.
-- Input: mouse/touch on the chips, keys 1–4 for the chips, gamepad selection (GuiService) on the first
-- chip after every answer and ButtonB to close. Own ScreenGui with a UIScale fitted to the viewport.
-- Walking more than WALK_AWAY studs away closes it (the server also ends it beyond 16 studs).
local Players=game:GetService("Players")
local GuiService=game:GetService("GuiService")
local UserInputService=game:GetService("UserInputService")
local UI=script.Parent.Parent
local Kit=require(UI.Kit)
local Theme=require(UI.Theme)
local Conversation=require(script.Parent.Conversation)
local C,F=Theme.colors,Theme.font
local TalkPanel={}
export type Call=(payload: {[string]:any})->(boolean,any)
TalkPanel.W=640;TalkPanel.H=540
TalkPanel.WALK_AWAY=22
local player=Players.LocalPlayer
local gui: ScreenGui?=nil
local currentId: string?=nil
local token=0
local finishHook: ((string?)->())?=nil
local KEYS: {[Enum.KeyCode]:number}={[Enum.KeyCode.One]=1,[Enum.KeyCode.Two]=2,[Enum.KeyCode.Three]=3,[Enum.KeyCode.Four]=4}
function TalkPanel.isOpen(): boolean return gui~=nil end
function TalkPanel.current(): string? return currentId end
function TalkPanel.close()
 token+=1;currentId=nil;finishHook=nil
 if gui then gui:Destroy();gui=nil end
end
-- Server ended the conversation (idle, NPC gone): show the last line, then close.
function TalkPanel.finish(text: string?)
 local hook=finishHook
 if hook then hook(text) else TalkPanel.close() end
end
-- Fit into the ScreenGui (IgnoreGuiInset = false: the area below the Roblox top bar, so the header never slides
-- under it on phones; staffops request 3b). Before the ScreenGui has a size the camera viewport is the fallback.
local function fitScale(scale: UIScale,screen: ScreenGui?)
 local size: Vector2?=if screen then screen.AbsoluteSize else nil
 if typeof(size)~="Vector2" or size.X<=0 or size.Y<=0 then
  local camera=workspace.CurrentCamera
  local vp=if camera then camera.ViewportSize else Vector2.new(1280,720)
  size=vp-Vector2.new(8,8)
 end
 local s=size :: Vector2
 scale.Scale=math.clamp(math.min((s.Y-16)/TalkPanel.H,(s.X-16)/TalkPanel.W),.3,1)
end
-- Typing pause: longer answers take a little longer (minus the time the server already needed).
function TalkPanel.typingDelay(text: string,elapsed: number): number
 return math.max(0,math.clamp(#text/95,.7,2)-elapsed)
end
function TalkPanel.open(payload: any,call: Call)
 TalkPanel.close()
 local mine=token
 local data=payload
 currentId=if typeof(data.id)=="string" then data.id else nil
 local busy=false
 local W,H=TalkPanel.W,TalkPanel.H
 local screen=Instance.new("ScreenGui");screen.Name="TalkPanel";screen.ResetOnSpawn=false;screen.DisplayOrder=42;screen.IgnoreGuiInset=false
 screen.Parent=player:WaitForChild("PlayerGui");gui=screen
 local box=Kit.frame(screen,UDim2.fromOffset(W,H),UDim2.fromScale(.5,.5));box.AnchorPoint=Vector2.new(.5,.5)
 box.BackgroundColor3=C.panel;box.BackgroundTransparency=0;Kit.corner(box,14);Kit.stroke(box,.85)
 local scale=Instance.new("UIScale");scale.Parent=box;fitScale(scale,screen)
 local connections: {RBXScriptConnection}={}
 local camera=workspace.CurrentCamera
 if camera then table.insert(connections,camera:GetPropertyChangedSignal("ViewportSize"):Connect(function() if scale.Parent then fitScale(scale,screen) end end)) end
 table.insert(connections,screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if scale.Parent then fitScale(scale,screen) end end))
 screen.Destroying:Connect(function() for _,c in connections do c:Disconnect() end;table.clear(connections) end)
 local inner=Kit.frame(box,UDim2.new(1,-32,1,-32),UDim2.fromOffset(16,16))
 -- Header: who you are talking to
 local name=tostring(data.name or "")
 Conversation.avatar(inner,tostring(data.initials or "?"),tonumber(data.seed) or 0,56).Position=UDim2.fromOffset(0,0)
 local title=Kit.text(inner,name,21,F.bold,C.text);title.Position=UDim2.fromOffset(70,2)
 local where=if typeof(data.room)=="string" then "  ·  "..data.room..(if typeof(data.level)=="string" then " ("..data.level..")" else "") else ""
 local roleLine=Kit.text(inner,tostring(data.job or "")..where,14,F.medium,C.muted);roleLine.Position=UDim2.fromOffset(70,30)
 roleLine.AutomaticSize=Enum.AutomaticSize.None;roleLine.Size=UDim2.new(1,-176,0,20);roleLine.TextTruncate=Enum.TextTruncate.AtEnd
 local closeTop=Kit.button(inner,"Close","ghost",UDim2.fromOffset(92,32));closeTop.AnchorPoint=Vector2.new(1,0);closeTop.Position=UDim2.new(1,0,0,0)
 -- Transcript
 local scroll=Kit.scroll(inner,UDim2.new(1,0,0,262),UDim2.fromOffset(0,68))
 scroll.BackgroundTransparency=0;scroll.BackgroundColor3=C.bg;Kit.corner(scroll,10)
 local list=Kit.frame(scroll,UDim2.fromScale(1,0));list.AutomaticSize=Enum.AutomaticSize.Y;Kit.list(list,8);Kit.padding(list,10,12,10,10)
 local order=0
 local firstName=string.match(name,"^(%S+)") or "Them"
 local function toBottom()
  task.defer(function() if scroll.Parent then scroll.CanvasPosition=Vector2.new(0,math.max(0,scroll.AbsoluteCanvasSize.Y-scroll.AbsoluteWindowSize.Y)) end end)
 end
 local function bubble(fromPlayer: boolean,text: string): (Frame,TextLabel)
  order+=1
  local holder=Kit.frame(list,UDim2.fromScale(1,0));holder.AutomaticSize=Enum.AutomaticSize.Y;holder.LayoutOrder=order
  local b=Kit.frame(holder,UDim2.new(.8,0,0,0));b.AutomaticSize=Enum.AutomaticSize.Y;b.BackgroundTransparency=0
  if fromPlayer then b.AnchorPoint=Vector2.new(1,0);b.Position=UDim2.fromScale(1,0);Theme.bindAccent(b,"BackgroundColor3",Theme.tint(.62)) else b.BackgroundColor3=C.raised end
  Kit.corner(b,10);Kit.padding(b,7,12,9,12);Kit.list(b,2)
  local who=Kit.text(b,if fromPlayer then "You" else firstName,12,F.bold,if fromPlayer then C.text else C.muted);who.LayoutOrder=1
  local label=Kit.para(b,text,15,C.text,2)
  toBottom()
  return holder,label
 end
 local function typing(): Frame
  local holder,label=bubble(false,"typing")
  task.spawn(function()
   local dots=0
   while holder.Parent do dots=dots%3+1;label.Text="typing"..string.rep(".",dots);task.wait(.35) end
  end)
  return holder
 end
 -- Reply chips
 local caption=Kit.text(inner,"",13,F.medium,C.muted);caption.Position=UDim2.fromOffset(0,338);caption.AutomaticSize=Enum.AutomaticSize.None;caption.Size=UDim2.new(1,0,0,18)
 local area=Kit.frame(inner,UDim2.new(1,0,0,104),UDim2.fromOffset(0,360))
 local grid=Instance.new("UIGridLayout");grid.CellSize=UDim2.new(.5,-4,0,48);grid.CellPadding=UDim2.fromOffset(8,8);grid.SortOrder=Enum.SortOrder.LayoutOrder;grid.Parent=area
 local hint=Kit.text(inner,if UserInputService.KeyboardEnabled then "Keys 1–4 pick a reply. Everything they tell you is live company data." else "Everything they tell you is live company data.",12,F.regular,C.dim)
 hint.AnchorPoint=Vector2.new(0,1);hint.Position=UDim2.new(0,0,1,0)
 local chips: {TextButton}={}
 local options: {any}={}
 local function setBusy(value: boolean)
  busy=value
  for _,b in chips do if b.Parent then Kit.setDisabled(b,value) end end
 end
 local function select()
  if UserInputService.GamepadEnabled and screen.Parent and chips[1] then GuiService.SelectedObject=chips[1] end
 end
 local leave: ()->()
 local choose: (number)->()
 local function render(list: {any})
  for _,b in chips do b:Destroy() end
  table.clear(chips);options=list
  caption.Text=if #list>0 then "Your reply" else ""
  for i,o in list do
   local bye=o.id=="bye"
   local b=Kit.button(area,(if UserInputService.KeyboardEnabled then tostring(i).."  " else "")..tostring(o.text),if bye then "ghost" else "secondary")
   b.LayoutOrder=i;b.TextSize=14;b.TextWrapped=true;b.Name="Option_"..tostring(o.id)
   Kit.onClick(b,function() choose(i) end)
   table.insert(chips,b)
  end
  setBusy(false);select()
 end
 local function ended(text: string?)
  if mine~=token then return end
  setBusy(true)
  for _,b in chips do b:Destroy() end
  table.clear(chips);caption.Text=""
  if text and text~="" then bubble(false,text) end
  task.delay(1.6,function() if mine==token then TalkPanel.close() end end)
 end
 choose=function(index: number)
  local o=options[index]
  if busy or not o then return end
  setBusy(true)
  bubble(true,tostring(o.text))
  local pending=typing();local started=os.clock()
  task.spawn(function()
   local ok,res=call({action="say",id=data.id,option=o.id})
   local text=if ok and typeof(res.text)=="string" then res.text else ""
   local wait=TalkPanel.typingDelay(text,os.clock()-started)
   if wait>0 then task.wait(wait) end
   if mine~=token then return end
   pending:Destroy()
   if not ok then
    -- conversation over on the server (walked away, NPC gone): the controller already toasted why
    if typeof(res)=="table" and (res.err=="NO_TALK" or res.err=="TOO_FAR" or res.err=="NPC_GONE" or res.err=="UNAVAILABLE") then TalkPanel.close() else setBusy(false) end
    return
   end
   bubble(false,text)
   if res.close then ended(nil) else render(if typeof(res.options)=="table" then res.options else {}) end
  end)
 end
 leave=function()
  if mine~=token then return end
  local id=data.id
  TalkPanel.close()
  task.spawn(function() call({action="close",id=id}) end)
 end
 finishHook=ended
 Kit.onClick(closeTop,leave)
 -- keyboard 1–4 and gamepad B
 table.insert(connections,UserInputService.InputBegan:Connect(function(input: InputObject,processed: boolean)
  if processed or mine~=token then return end
  local index=KEYS[input.KeyCode]
  if index then choose(index) elseif input.KeyCode==Enum.KeyCode.ButtonB then leave() end
 end))
 -- greeting after a short typing pause
 setBusy(true)
 local greetingTyping=typing()
 task.delay(TalkPanel.typingDelay(tostring(data.greeting or ""),.4),function()
  if mine~=token then return end
  greetingTyping:Destroy()
  bubble(false,tostring(data.greeting or ""))
  render(if typeof(data.options)=="table" then data.options else {})
 end)
 -- walking away or respawning ends the conversation
 local character=player.Character
 local root=if character then character:FindFirstChild("HumanoidRootPart") else nil
 local start=if root and root:IsA("BasePart") then root.Position else nil
 local humanoid=if character then character:FindFirstChildOfClass("Humanoid") else nil
 if humanoid then table.insert(connections,humanoid.Died:Connect(function() leave() end)) end
 task.spawn(function()
  while mine==token do
   task.wait(.5)
   local c=player.Character;local r=if c then c:FindFirstChild("HumanoidRootPart") else nil
   if mine==token and start and r and r:IsA("BasePart") and (r.Position-start).Magnitude>TalkPanel.WALK_AWAY then leave();break end
  end
 end)
end
return TalkPanel
