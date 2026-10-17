--!strict
-- Job interview in the visitor lounge. Chat transcript: the founder's questions on the right, the
-- candidate's answers on the left after a short "typing…" pause. Answers come from the server's
-- authored dialogue templates (RecruitingService) chosen by the candidate's hidden skill and temperament;
-- there is no language model behind it.
-- Header: candidate card (initials avatar, applied role, experience, previous employer, specialty, salary
-- ask) and the impression bar = estimated skill range so far (the true skill is revealed after hiring).
-- Footer: Hire (signing cost + wage), a 15% lower offer, Reject, Close (the candidate keeps waiting).
-- Own ScreenGui with a UIScale fitted to the viewport like the lift panel; Kit buttons work with mouse,
-- touch and gamepad (GuiService selection on open and after every answer).
local Players=game:GetService("Players")
local GuiService=game:GetService("GuiService")
local UserInputService=game:GetService("UserInputService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Format=require(ReplicatedStorage.Shared.Format)
local UI=script.Parent.Parent
local Kit=require(UI.Kit)
local Theme=require(UI.Theme)
local Toast=require(UI.Toast)
local C,F=Theme.colors,Theme.font
local Conversation={}
export type Call=(payload: {[string]:any})->(boolean,any)
local W,H=820,600
local player=Players.LocalPlayer
local gui: ScreenGui?=nil
local token=0
local function money(n: number): string return Format.money(n) end
local function wage(n: number): string return string.format("$%.2f/s",n) end
function Conversation.avatarColor(seed: number): Color3
 return Color3.fromHSV((math.floor(math.abs(seed))%360)/360,.32,.72)
end
-- Initials avatar circle (no images, no asset ids).
function Conversation.avatar(parent: Instance,initials: string,seed: number,size: number): Frame
 local circle=Kit.frame(parent,UDim2.fromOffset(size,size))
 circle.BackgroundTransparency=0;circle.BackgroundColor3=Conversation.avatarColor(seed)
 Kit.corner(circle,size//2+1)
 local label=Kit.text(circle,initials,math.floor(size*.38),F.bold,C.bg)
 label.AutomaticSize=Enum.AutomaticSize.None;label.Size=UDim2.fromScale(1,1);label.TextXAlignment=Enum.TextXAlignment.Center
 return circle
end
function Conversation.isOpen(): boolean return gui~=nil end
function Conversation.close()
 token+=1
 if gui then gui:Destroy();gui=nil end
end
local function fitScale(scale: UIScale)
 local camera=workspace.CurrentCamera
 local vp=if camera then camera.ViewportSize else Vector2.new(1280,720)
 scale.Scale=math.clamp(math.min((vp.Y-24)/H,(vp.X-24)/W),.3,1)
end
function Conversation.open(payload: any,call: Call)
 Conversation.close()
 local mine=token
 local data=payload
 local busy=false
 local screen=Instance.new("ScreenGui");screen.Name="PeopleInterview";screen.ResetOnSpawn=false;screen.DisplayOrder=42;screen.IgnoreGuiInset=false
 screen.Parent=player:WaitForChild("PlayerGui");gui=screen
 local box=Kit.frame(screen,UDim2.fromOffset(W,H),UDim2.fromScale(.5,.5));box.AnchorPoint=Vector2.new(.5,.5)
 box.BackgroundColor3=C.panel;box.BackgroundTransparency=0;Kit.corner(box,14);Kit.stroke(box,.85)
 local scale=Instance.new("UIScale");scale.Parent=box;fitScale(scale)
 local camera=workspace.CurrentCamera
 if camera then
  local resize=camera:GetPropertyChangedSignal("ViewportSize"):Connect(function() if scale.Parent then fitScale(scale) end end)
  screen.Destroying:Connect(function() resize:Disconnect() end)
 end
 local inner=Kit.frame(box,UDim2.new(1,-32,1,-32),UDim2.fromOffset(16,16))
 -- Header: candidate card
 Conversation.avatar(inner,data.initials or "?",data.seed or 0,64).Position=UDim2.fromOffset(0,4)
 local name=Kit.text(inner,data.name or "",22,F.bold,C.text);name.Position=UDim2.fromOffset(78,2)
 local roleLine=Kit.text(inner,"",14,F.medium,C.muted);roleLine.Position=UDim2.fromOffset(78,31)
 local facts=Kit.text(inner,"",14,F.regular,C.muted);facts.Position=UDim2.fromOffset(78,51)
 local askLine=Kit.text(inner,"",14,F.medium,C.text);askLine.AnchorPoint=Vector2.new(1,0);askLine.Position=UDim2.new(1,0,0,44);askLine.TextXAlignment=Enum.TextXAlignment.Right
 local closeTop=Kit.button(inner,"Close","ghost",UDim2.fromOffset(92,32));closeTop.AnchorPoint=Vector2.new(1,0);closeTop.Position=UDim2.new(1,0,0,2)
 -- Impression bar
 local impCaption=Kit.text(inner,"Estimated skill",13,F.medium,C.muted);impCaption.Position=UDim2.fromOffset(0,90)
 local track=Kit.frame(inner,UDim2.fromOffset(300,12),UDim2.fromOffset(112,93));track.BackgroundTransparency=0;track.BackgroundColor3=C.raised;Kit.corner(track,6)
 local fill=Kit.frame(track,UDim2.fromScale(1,1));fill.BackgroundTransparency=0;Theme.bindAccent(fill,"BackgroundColor3");Kit.corner(fill,6)
 for i=1,5 do
  local tick=Kit.text(inner,tostring(i),11,F.medium,C.dim);tick.AnchorPoint=Vector2.new(.5,0);tick.Position=UDim2.fromOffset(112+(i-1)/4*300,107)
 end
 local range=Kit.text(inner,"",15,F.bold,C.text);range.Position=UDim2.fromOffset(426,88)
 local note=Kit.text(inner,"",13,F.regular,C.muted);note.Position=UDim2.fromOffset(426,108);note.AutomaticSize=Enum.AutomaticSize.None;note.Size=UDim2.new(1,-426,0,18);note.TextTruncate=Enum.TextTruncate.AtEnd
 -- Transcript
 local scroll=Kit.scroll(inner,UDim2.new(1,0,0,224),UDim2.fromOffset(0,134))
 scroll.BackgroundTransparency=0;scroll.BackgroundColor3=C.bg;Kit.corner(scroll,10)
 local list=Kit.frame(scroll,UDim2.fromScale(1,0));list.AutomaticSize=Enum.AutomaticSize.Y;Kit.list(list,8);Kit.padding(list,10,12,10,10)
 local order=0
 local firstName=string.match(data.name or "","^(%S+)") or "Candidate"
 local function toBottom()
  task.defer(function() if scroll.Parent then scroll.CanvasPosition=Vector2.new(0,math.max(0,scroll.AbsoluteCanvasSize.Y-scroll.AbsoluteWindowSize.Y)) end end)
 end
 local function bubble(fromFounder: boolean,text: string): (Frame,TextLabel)
  order+=1
  local holder=Kit.frame(list,UDim2.fromScale(1,0));holder.AutomaticSize=Enum.AutomaticSize.Y;holder.LayoutOrder=order
  local b=Kit.frame(holder,UDim2.new(.8,0,0,0));b.AutomaticSize=Enum.AutomaticSize.Y;b.BackgroundTransparency=0
  if fromFounder then b.AnchorPoint=Vector2.new(1,0);b.Position=UDim2.fromScale(1,0);Theme.bindAccent(b,"BackgroundColor3",Theme.tint(.62)) else b.BackgroundColor3=C.raised end
  Kit.corner(b,10);Kit.padding(b,7,12,9,12);Kit.list(b,2)
  local who=Kit.text(b,if fromFounder then "You" else firstName,12,F.bold,if fromFounder then C.text else C.muted);who.LayoutOrder=1
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
 for _,line in data.transcript or {} do bubble(line.from=="founder",line.text) end
 -- Questions / replies
 local qCaption=Kit.text(inner,"",13,F.medium,C.muted);qCaption.Position=UDim2.fromOffset(0,366);qCaption.AutomaticSize=Enum.AutomaticSize.None;qCaption.Size=UDim2.new(1,0,0,18);qCaption.TextTruncate=Enum.TextTruncate.AtEnd
 local qArea=Kit.scroll(inner,UDim2.new(1,0,0,124),UDim2.fromOffset(0,388))
 local footer=Kit.frame(inner,UDim2.new(1,0,0,46),UDim2.new(0,0,1,-46));Kit.list(footer,10,true)
 local hire=Kit.button(footer,"Hire","primary",UDim2.new(.38,-8,1,0));hire.LayoutOrder=1
 local low=Kit.button(footer,"Offer less","secondary",UDim2.new(.26,-8,1,0));low.LayoutOrder=2
 local reject=Kit.button(footer,"Reject","danger",UDim2.new(.18,-8,1,0));reject.LayoutOrder=3
 local close=Kit.button(footer,"Close","ghost",UDim2.new(.18,0,1,0));close.LayoutOrder=4
 for _,b in {hire,low,reject,close} do b.TextSize=15 end
 local actionButtons: {TextButton}={}
 local function setBusy(value: boolean)
  busy=value
  for _,b in actionButtons do if b.Parent then Kit.setDisabled(b,value or b:GetAttribute("Locked")==true) end end
 end
 local function lock(b: TextButton,locked: boolean)
  b:SetAttribute("Locked",locked);Kit.setDisabled(b,locked or busy)
 end
 local renderQuestions: ()->()
 local function refresh()
  local imp=data.impression or {estimateLow=1,estimateHigh=5,note=""}
  local lo,hi=tonumber(imp.estimateLow) or 1,tonumber(imp.estimateHigh) or 5
  roleLine.Text="Applying as "..tostring(data.roleName).."  ·  "..tostring(data.years).." of experience"
  facts.Text="Previously at "..tostring(data.prev).."  ·  Specialty: "..tostring(data.spec)
  askLine.Text="Asks "..money(data.cost).." + "..wage(data.wage).."\n≈ "..money(data.wage*(data.monthSeconds or 3600)).." per game month"
  fill.Position=UDim2.fromScale((lo-1)/4,0);fill.Size=UDim2.fromScale(math.max(.03,(hi-lo)/4),1)
  range.Text=string.format("%s – %s ★",tostring(lo),tostring(hi))
  note.Text=imp.note or ""
  hire.Text=if data.staffFull then "All desks filled" else "Hire · "..money(data.cost).." · "..wage(data.wage)
  low.Text=if data.lowDeclined then "Lower offer declined" else "Offer −15% · "..money(data.lowCost)
  lock(hire,data.staffFull==true);lock(low,data.staffFull==true or data.lowDeclined==true)
  renderQuestions()
 end
 local first: GuiObject?=nil
 local function select()
  if UserInputService.GamepadEnabled and screen.Parent then GuiService.SelectedObject=first or hire end
 end
 local function ask(q: any)
  if busy then return end
  setBusy(true)
  bubble(true,q.text)
  local pendingBubble=typing();local started=os.clock()
  local ok,res=call({action="question",id=data.id,questionId=q.id})
  if ok and typeof(res.answer)=="string" then
   local delay=math.clamp(#res.answer/110,.9,2.2)-(os.clock()-started)
   if delay>0 then task.wait(delay) end
   if mine~=token then return end
   pendingBubble:Destroy();bubble(false,res.answer)
   if typeof(res.interview)=="table" then data=res.interview end
  else pendingBubble:Destroy() end
  if mine~=token then return end
  setBusy(false);refresh();select()
 end
 local function reply(index: number,text: string)
  if busy then return end
  setBusy(true)
  bubble(true,text)
  local pendingBubble=typing()
  local ok,res=call({action="reply",id=data.id,option=index})
  task.wait(.9)
  if mine~=token then return end
  pendingBubble:Destroy()
  if ok and typeof(res.text)=="string" then bubble(false,res.text) end
  if ok and typeof(res.interview)=="table" then data=res.interview end
  setBusy(false);refresh();select()
 end
 renderQuestions=function()
  for _,child in qArea:GetChildren() do if child:IsA("GuiObject") or child:IsA("UIGridLayout") or child:IsA("UIListLayout") then child:Destroy() end end
  table.clear(actionButtons);table.insert(actionButtons,hire);table.insert(actionButtons,low);table.insert(actionButtons,reject)
  first=nil
  local pending=data.pendingAsk
  if typeof(pending)=="table" then
   qCaption.Text=firstName.." asked you a question. Your answer:"
   Kit.list(qArea,6)
   for i,text in pending.options do
    local b=Kit.button(qArea,text,"secondary",UDim2.new(1,-8,0,36));b.LayoutOrder=i;b.TextSize=14;b.TextWrapped=true
    Kit.onClick(b,function() task.spawn(reply,i,text) end)
    table.insert(actionButtons,b);if not first then first=b end
   end
  else
   local left=(data.max or 7)-(data.asked or 0)
   local questions=data.questions or {}
   qCaption.Text=if left<=0 or #questions==0 then "You've asked enough. Decide: hire, offer less or reject." else string.format("Ask a question  ·  %d of %d left  ·  technical questions show real skill",left,data.max or 7)
   local grid=Instance.new("UIGridLayout");grid.CellSize=UDim2.new(.5,-6,0,40);grid.CellPadding=UDim2.fromOffset(8,6);grid.SortOrder=Enum.SortOrder.LayoutOrder;grid.Parent=qArea
   for i,q in questions do
    local technical=q.kind=="technical"
    local b=Kit.button(qArea,(if technical then "Technical: " else "")..q.text,if technical then "ghost" else "secondary")
    b.LayoutOrder=if technical then i else 100+i;b.TextSize=13;b.TextWrapped=true;b.TextXAlignment=Enum.TextXAlignment.Left
    if technical then b.TextColor3=C.text;local stroke=Kit.stroke(b,.35,Theme.accent);Theme.bindAccent(stroke,"Color") end
    Kit.padding(b,2,10,2,10)
    Kit.onClick(b,function() task.spawn(ask,q) end)
    table.insert(actionButtons,b);if technical and not first then first=b end
   end
   if not first then for _,child in qArea:GetChildren() do if child:IsA("TextButton") then first=child;break end end end
  end
  for _,b in actionButtons do Kit.setDisabled(b,busy or b:GetAttribute("Locked")==true) end
 end
 local function offer(lower: boolean)
  if busy then return end
  setBusy(true)
  bubble(true,if lower then "We'd like to offer you "..money(data.lowCost).." to sign and "..wage(data.lowWage).."." else "We'd like to offer you the job: "..money(data.cost).." to sign and "..wage(data.wage)..".")
  local pendingBubble=typing()
  local ok,res=call({action="hire",id=data.id,offer=if lower then "low" else "full"})
  task.wait(1)
  if mine~=token then return end
  pendingBubble:Destroy()
  if ok and res.accepted then
   bubble(false,tostring(res.text))
   Toast.show("success",tostring(data.name).." joined your team.",4)
   task.delay(2,function() if mine==token then Conversation.close() end end)
   return
  end
  if ok and typeof(res.text)=="string" then bubble(false,res.text) end
  if ok and typeof(res.interview)=="table" then data=res.interview end
  setBusy(false);refresh();select()
 end
 Kit.onClick(hire,function() task.spawn(offer,false) end)
 Kit.onClick(low,function() task.spawn(offer,true) end)
 Kit.onClick(reject,function()
  if busy then return end
  setBusy(true)
  task.spawn(function()
   local ok=call({action="reject",id=data.id})
   if mine~=token then return end
   if ok then Toast.show("info","Application declined. "..firstName.." is leaving the building.",4);Conversation.close() else setBusy(false) end
  end)
 end)
 local function leave()
  task.spawn(function() call({action="close",id=data.id}) end)
  Conversation.close()
 end
 Kit.onClick(close,leave);Kit.onClick(closeTop,leave)
 refresh();select()
 -- respawning ends the conversation (the candidate keeps waiting in the lounge)
 local character=player.Character;local h=if character then character:FindFirstChildOfClass("Humanoid") else nil
 if h then h.Died:Connect(function() if mine==token then leave() end end) end
end
return Conversation
