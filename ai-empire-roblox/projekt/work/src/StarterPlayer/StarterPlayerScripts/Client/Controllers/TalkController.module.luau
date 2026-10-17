--!strict
-- Talking to people on the client: Notify TALK_OPEN → UI/Screens/TalkPanel, TALK_CLOSE (the server ended
-- the conversation) → last line + close, TALK_NOTICE (one-liners such as "Maya is off duty") → toast.
-- Replies go through TalkAction {action=say|close} (TalkService validates everything).
-- Talk prompts ("EmployeeTalk" on every staff rig) are shown locally only when they can work: own staff
-- or a Public front-of-house prompt (same rule as WorldController), not while the person is off duty /
-- inactive, and not while they are talking to someone (attribute TalkingTo, set by the server).
-- One AttributeChanged connection per rig; no per-frame work.
local Players=game:GetService("Players")
local Collection=game:GetService("CollectionService")
local State=require(script.Parent.StateController)
local Action=require(script.Parent.ActionController)
local UI=script.Parent.Parent.UI
local Toast=require(UI.Toast)
local TalkPanel=require(UI.Screens.TalkPanel)
local Conversation=require(UI.Screens.Conversation)
local Controller={}
local player=Players.LocalPlayer
local watched: {[Instance]:RBXScriptConnection}={}
local MESSAGES: {[string]:string}={
 NPC_BUSY="They're talking to someone else right now.",
 OFF_DUTY="They're off duty. Try again during working hours.",
 TOO_FAR="You walked away, so the conversation ended.",
 NPC_GONE="They're no longer here.",
 NO_TALK="That conversation has ended.",
 NOT_PUBLIC="Only this company's founder can talk to them.",
 UNAVAILABLE="They can't talk right now.",
}
function Controller.message(err: string?): string
 return if err and MESSAGES[err] then MESSAGES[err] else Action.message(err)
end
function Controller.call(payload: {[string]:any}): (boolean,any)
 local ok,res=Action.call("TalkAction",payload,true)
 if not ok and res.err~="BUSY" and res.err~="RATE_LIMIT" then Toast.show("error",Controller.message(res.err)) end
 return ok,res
end
-- Prompt visibility -----------------------------------------------------------------------------------
local function promptOf(model: Instance): ProximityPrompt?
 local head=model:FindFirstChild("Head")
 local prompt=if head then head:FindFirstChild("EmployeeTalk") else nil
 return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
end
function Controller.promptEnabled(model: Instance,prompt: ProximityPrompt): boolean
 local allowed=prompt:GetAttribute("OwnerUserId")==player.UserId or prompt:GetAttribute("Public")==true
 return allowed and model:GetAttribute("OffDuty")~=true and model:GetAttribute("Activity")~="INACTIVE" and model:GetAttribute("TalkingTo")==nil
end
local function refresh(model: Instance)
 local prompt=promptOf(model)
 if not prompt then return end
 local enabled=Controller.promptEnabled(model,prompt)
 if prompt.Enabled~=enabled then prompt.Enabled=enabled end
end
local function watch(model: Instance)
 if watched[model] or not model:IsA("Model") then return end
 watched[model]=model.AttributeChanged:Connect(function(name: string)
  if name=="OffDuty" or name=="TalkingTo" or name=="Activity" then refresh(model) end
 end)
 task.defer(refresh,model) -- after WorldController's own DescendantAdded pass
end
local function unwatch(model: Instance)
 local c=watched[model];if c then c:Disconnect();watched[model]=nil end
end
function Controller.init()
 State.onNotify(function(kind,payload)
  if kind=="TALK_OPEN" and typeof(payload.id)=="string" then
   if Conversation.isOpen() then
    -- an interview is open: don't stack panels, end the new conversation right away
    task.spawn(function() Controller.call({action="close",id=payload.id}) end)
    return
   end
   TalkPanel.open(payload,Controller.call)
  elseif kind=="TALK_CLOSE" then
   if typeof(payload.id)=="string" and TalkPanel.current()==payload.id then TalkPanel.finish(if typeof(payload.text)=="string" then payload.text else nil) end
  elseif kind=="TALK_NOTICE" and typeof(payload.text)=="string" then
   Toast.show("info",payload.text,5)
  elseif (kind=="INTERVIEW_OPEN" or kind=="ASSISTANT_OPEN") and TalkPanel.isOpen() then
   -- an interview or the assistant briefing takes over the screen: end the chat
   local id=TalkPanel.current()
   TalkPanel.close()
   task.spawn(function() Controller.call({action="close",id=id}) end)
  end
 end)
 player.CharacterAdded:Connect(function() TalkPanel.close() end)
 for _,m in Collection:GetTagged("CompanyEmployee") do watch(m) end
 Collection:GetInstanceAddedSignal("CompanyEmployee"):Connect(watch)
 Collection:GetInstanceRemovedSignal("CompanyEmployee"):Connect(unwatch)
end
return Controller
