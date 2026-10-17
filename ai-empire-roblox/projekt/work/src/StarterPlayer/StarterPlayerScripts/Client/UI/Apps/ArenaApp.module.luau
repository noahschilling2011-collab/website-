--!strict
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Shared=ReplicatedStorage.Shared
local Math=require(Shared.ArenaMath)
local Format=require(Shared.Format)
local UI=script.Parent.Parent
local State=require(UI.Parent.Controllers.StateController)
local Action=require(UI.Parent.Controllers.ActionController)
local Theme=require(UI.Theme)
local Kit=require(UI.Kit)
local C,F=Theme.colors,Theme.font
local App={}
local refresh=function(_s: any)end
function App.mount(parent: Frame,nav: any)
	local scroll=Kit.scroll(parent);Kit.padding(scroll,2,14,24,2);Kit.list(scroll,16)
	Kit.heading(scroll,"Courier lab","Watch your model plan a route around obstacles. Better reasoning means fewer detours; reliable code improves its decisions.",1)
	local left,right=Kit.columns(scroll,.43,18,2)
	local config=Kit.card(left,1,12);Kit.caption(config,"Checkpoint under test",1)
	local name=Kit.text(config,"No trained model",21,F.bold,C.text);name.LayoutOrder=2
	local detail=Kit.para(config,"",13,C.muted,3)
	-- fix round 1 (review B3): touch targets >= 56 px on touch (44.8 pt in the Menu's legacy x 0.80)
	local controls=Kit.row(config,Kit.tap(32,58),8,4)
	local previous=Kit.button(controls,"Previous","secondary",UDim2.fromOffset(100,Kit.tap(30,56)))
	local nextButton=Kit.button(controls,"Next model","secondary",UDim2.fromOffset(110,Kit.tap(30,56)));nextButton.LayoutOrder=2
	local index=1;local ids={}
	local start=Kit.button(config,"RUN COURIER TEST","primary",UDim2.new(1,0,0,Kit.tap(42,56)));start.LayoutOrder=5
	Kit.onClick(previous,function() index=math.max(1,index-1);if State.snapshot then refresh(State.snapshot) end end)
	Kit.onClick(nextButton,function() index=math.min(#ids,index+1);if State.snapshot then refresh(State.snapshot) end end)
	Kit.onClick(start,function() if ids[index] then Action.call("RunArena",{modelId=ids[index]}) end end)
	local progress=Kit.bar(config,6,6)
	local running=Kit.para(config,"",13,C.dim,7)
	Kit.para(config,"The physical course is at Courier Lab, west of the founder district. Run a test here, then walk over to watch your robot. Tests award a record, never farmable cash.",13,C.dim,8)
	local historyCard=Kit.card(left,2,8);Kit.caption(historyCard,"Recent tests",1)
	local histories={};for i=1,6 do histories[i]=Kit.para(historyCard,"",13,C.muted,i+1) end
	local mapCard=Kit.card(right,1,12);Kit.caption(mapCard,"Route planner / nine by seven",1)
	local map=Kit.frame(mapCard,UDim2.new(1,0,0,230));map.LayoutOrder=2
	local cells={}
	for x=1,Math.WIDTH do for z=1,Math.HEIGHT do
		local cell=Kit.frame(map,UDim2.new(1/9,-4,1/7,-4),UDim2.new((x-1)/9,2,(z-1)/7,2));cell.BackgroundTransparency=0;Kit.corner(cell,3)
		local label=Kit.text(cell,"",11,F.medium,C.text);label.AnchorPoint=Vector2.new(.5,.5);label.Position=UDim2.fromScale(.5,.5)
		cells[tostring(x)..":"..tostring(z)]={frame=cell,label=label,x=x,z=z}
	end end
	local routeInfo=Kit.para(mapCard,"",13,C.dim,3)
	local rivalsCard=Kit.card(right,2,10);Kit.caption(rivalsCard,"Rival companies / live activity",1)
	local activities={};for i=1,5 do activities[i]=Kit.para(rivalsCard,"",13,C.muted,i+1) end
	refresh=function(s: any)
		ids={};for _,id in s.data.modelOrder do local m=s.data.models[id];if m and (m.status=="trained" or m.status=="live") then table.insert(ids,id) end end
		index=math.clamp(index,1,math.max(1,#ids));local m=s.data.models[ids[index]]
		local info=s.live.arena or {};local active=info.active
		name.Text=if m then m.name.." v"..tostring(m.version) else "Train a model first"
		detail.Text=if m then string.format("Reasoning %.1f · Coding %.1f · Reliability %.1f",m.stats.reasoning or 0,m.stats.coding or 0,m.stats.reliability or 0) else "Your own checkpoint is required for a ranked test."
		Kit.setDisabled(start,not m or active~=nil)
		progress.set(if active then active.progress else 0)
		running.Text=if active then "Lane "..tostring(active.lane).." · "..Format.percent(active.progress).." · competing with "..active.opponent else "Best arena record: "..tostring(s.data.empire.arenaBest).." points"
		local plan=if m then Math.route(m.stats,#s.data.empire.arenaHistory+1) else nil
		local route={};if plan then for i,p in plan.path do route[tostring(p.x)..":"..tostring(p.z)]=i end end
		for key,c in cells do
			c.frame.BackgroundColor3=if Math.blocked(c.x,c.z) then C.raised elseif route[key] then Theme.accent:Lerp(C.bg,.4) else C.panel
			c.label.Text=if c.x==1 and c.z==4 then "IN" elseif c.x==9 and c.z==4 then "OUT" elseif route[key] then tostring(route[key]) else ""
		end
		routeInfo.Text=if plan then string.format("%d moves · %.1fs estimate · %d detours · %d expected points",plan.moves,plan.seconds,plan.detours,plan.score) else "Select a trained model to inspect its route."
		for i,l in histories do local h=s.data.empire.arenaHistory[i];l.Visible=h~=nil;if h then l.Text=h.name.." · "..tostring(h.score).." pts · "..tostring(h.moves).." moves · "..(if h.winner then "Beat " else "Behind ")..h.opponent end end
		for i,l in activities do local a=info.rivals and info.rivals[i];l.Visible=a~=nil;if a then l.Text=a.company.." / "..a.text end end
	end
	State.onChange(function(s) if parent.Visible and nav.isOpen() then refresh(s) end end)
end
function App.onShow() if State.snapshot then refresh(State.snapshot) end end
return App
