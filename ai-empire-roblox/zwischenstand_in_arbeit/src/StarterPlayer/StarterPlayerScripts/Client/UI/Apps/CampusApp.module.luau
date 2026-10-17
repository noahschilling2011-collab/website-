--!strict
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Config=require(ReplicatedStorage.Shared.Config.CampusConfig)
local Plan=require(ReplicatedStorage.Shared.Config.BuildingPlan)
local EmpireConfig=require(ReplicatedStorage.Shared.Config.EmpireConfig)
local Math=require(ReplicatedStorage.Shared.EmpireMath)
local Format=require(ReplicatedStorage.Shared.Format)
local Ops=require(ReplicatedStorage.Shared.CompanyOps)
local ShopConfigC=require(ReplicatedStorage.Shared.Config.ShopConfig) -- shop package (ONBOARDING_SPEC C4)
local UI=script.Parent.Parent
local State=require(UI.Parent.Controllers.StateController)
local Action=require(UI.Parent.Controllers.ActionController)
local Theme=require(UI.Theme)
local Kit=require(UI.Kit)
local Toast=require(UI.Toast)
local Security=require(UI.Parent.Controllers.SecurityController)
local C,F=Theme.colors,Theme.font
local App={}
local watchers={}
local scroll: ScrollingFrame?=nil
local navigator: any=nil
local current="building"
-- Menu pages (ONBOARDING_SPEC B9, menu package): App.mountPart renders one builder into a Menu page frame with its own
-- watcher list; `filling` is the list watch() fills right now
local filling: {(any)->()}=watchers
local function watch(fn: (any)->())table.insert(filling,fn);if State.snapshot then fn(State.snapshot) end end
local function title(p: Instance,text: string)local t=Kit.para(p,text,19,C.text,1);t.Font=F.bold;return t end
local function para(p: Instance,text: string,order: number?)return Kit.para(p,text,14,C.muted,order or 2)end
local function call(name: string,p: any,message: string)
	task.spawn(function()local ok=Action.call(name,p);if ok then Toast.show("success",message) end end)
end
local function button(p: Instance,text: string,fn: ()->(),order: number?)
	-- fix round 1 (review): 56 px on touch = 44.8 pt on an iPhone (legacy page x 0.80); 40 px with a mouse
	local b=Kit.button(p,text,"primary",UDim2.new(1,0,0,Kit.tap(40,56)));b.LayoutOrder=order or 5;Kit.onClick(b,fn);return b
end
-- Building texts are generated from the shared BuildingPlan, so they always describe the
-- headquarters this tier actually builds (levels, pavilion, founder services, roof, garage).
local function names(tier: number,keep: (any)->boolean): string
	local list={}
	for _,r in Plan.rooms(tier) do if not r.hidden and keep(r) and not table.find(list,r.name) then table.insert(list,r.name) end end
	return table.concat(list,", ")
end
local function directory(tier: number): string
	if tier<1 then return Plan.floorTitle(tier,0) end -- the Garage Lab: one level, no roof terrace, no B1
	local lines={}
	for level=Plan.roofLevel(tier),-1,-1 do table.insert(lines,Plan.floorTitle(tier,level)) end
	return table.concat(lines,"\n")
end
local GETTING_AROUND="The automatic doors in the front portal open for everyone into the double-height reception hall. Visitors need no card for the hall, the café, the showroom and the visitor lounge. Badge speed gates at the back of the hall lead into the staff atrium; walk straight through it to the lift lobby. The lift stops at every level from B1 to the roof: call it at a landing, step inside and choose your floor on the cabin panel.\nThe stairs are right of the lift (as you face it), the restrooms left of it. Every lift lobby has a floor directory; nameplates beside each door show who may enter.\nTeam areas need a company or guest card, labs and technical rooms are reserved for their staff, and founder rooms open only for you."
local GETTING_AROUND_GARAGE="The Garage Lab has one level and no lift: the shared lab with 5 team desks, the glazed founder corner, your assistant's desk by the door, a WC and the porch where applicants wait. Your car is parked in front of the garage. The fenced site around it is where your first headquarters will stand: sign your first business client and save the price, then move up from Team → Office."
local SHARED_FOUNDER_FLOOR={boardroom=true,meeting=true,hr=true,lounge=true,team=true}
-- office index (stage 1..5) -> the building's plan tier (0 = Garage Lab)
local function tierOf(s: any): number return Plan.tierForOffice(s.data.empire.office) end
local function building(p: Instance)
	local hero=Kit.card(p,1);local heading=title(hero,"Your headquarters");local info=para(hero,"")
	watch(function(s)
		local e=s.data.empire;heading.Text=EmpireConfig.OFFICES[e.office].name
		if tierOf(s)<1 then
			info.Text=string.format("Stage %d of %d · the converted garage: 5 team desks, the founder corner and a %d-blade GPU shelf\n%d / %d specialists · no operations staff yet (the founder orders pizza)\nNext: %s for %s once your first business client has signed",e.office,#EmpireConfig.OFFICES,Plan.GARAGE_STAGE.blades,Math.staff(e),EmpireConfig.OFFICES[e.office].staff,EmpireConfig.OFFICES[e.office+1].name,Format.money(EmpireConfig.OFFICES[e.office+1].price))
		else
			info.Text=string.format("Stage %d of %d · %d storeys + garage level B1 + roof terrace · 164 × 208 studs incl. the rear pavilion\n%d / %d specialists + %d operations staff (reception, security, café, facilities, IT, fleet)\nPublic reception hall, café and showroom · badge speed gates to the staff atrium · lift from B1 to the roof",e.office,#EmpireConfig.OFFICES,Plan.floors(tierOf(s)),Math.staff(e),EmpireConfig.OFFICES[e.office].staff,Ops.opsPosts(e))
		end
	end)
	local map=Kit.card(p,2);title(map,"Building directory");local levels=para(map,"")
	watch(function(s)levels.Text=directory(tierOf(s))end)
	local directions=Kit.card(p,3);title(directions,"Getting around");local directionsText=para(directions,GETTING_AROUND)
	watch(function(s)directionsText.Text=if tierOf(s)<1 then GETTING_AROUND_GARAGE else GETTING_AROUND end)
	local pavilion=Kit.card(p,4);title(pavilion,"Wellness pavilion");local wellnessRooms=para(pavilion,"")
	watch(function(s)wellnessRooms.Text="Behind the main building on G, through the Wellness Corridor at the back of the ground floor: "..names(tierOf(s),function(r)return r.pavilion==true and r.level==0 and r.kind~="pavilion_corridor" end)..". Open to your team and guest card holders."end)
	local services=Kit.card(p,5);title(services,"Founder services");local serviceRooms=para(services,"")
	watch(function(s)serviceRooms.Text="Above the wellness pavilion on level 1, behind two secure doors that open only for your founder card: "..names(tierOf(s),function(r)return r.pavilion==true and r.level==1 and r.kind~="pavilion_corridor" end)..". The Prototype Lab has no sign; look for the flush panel in the corridor. One archive shelf is not what it seems."end)
	local top=Kit.card(p,6);title(top,"Founder floor & roof terrace");local topRooms=para(top,"")
	watch(function(s)
		local tier=tierOf(s);local founder=Plan.founderLevel(tier)
		topRooms.Text=string.format("Level %s · founder only: %s.\nLevel %s · shared with your team: %s and the Executive Terrace in front of the setback.\nRoof (%s): %s with lounge seating, reached by lift and stairs. The pavilion roof garden opens from both corridor ends on level 2.",
			Plan.levelLabel(tier,founder),names(tier,function(r)return r.level==founder and r.access=="founder" end),
			Plan.levelLabel(tier,founder),names(tier,function(r)return r.level==founder and r.access~="founder" and SHARED_FOUNDER_FLOOR[r.kind]==true end),
			Plan.levelLabel(tier,Plan.roofLevel(tier)),names(tier,function(r)return r.level==Plan.roofLevel(tier) and r.kind=="roof_terrace" end))
	end)
	local garage=Kit.card(p,7);title(garage,"B1 · Garage & Data Hall");local garageRooms=para(garage,"")
	watch(function(s)garageRooms.Text="Underground below the main building, reached by lift, stairs or the driveable ramp from the street: "..names(tierOf(s),function(r)return r.level==-1 and r.kind~="stair" and r.kind~="liftpit" and r.kind~="service_passage" and r.kind~="spine" end)..". The Data Hall is the company data centre and open to compute engineers only. Collect your company car at the fleet office or from the Fleet tab."end)
	local staff=Kit.card(p,8);title(staff,"A team that has a day")
	para(staff,"Each specialist has a personal workstation, role and schedule. Employees walk through doors, ride the lift, use seats, meet colleagues and take staggered coffee, lunch and lounge breaks. Data, research, training and growth bonuses use the same working team. Founder rooms remain private.")
	local security=Kit.card(p,9);title(security,"Founder camera control")
	para(security,"Live views of your own headquarters, grouped by level: reception hall, atrium, work floors, café, Compute Operations, Data Hall, garage, wellness pavilion, founder rooms and roof. Restrooms, showers, the sauna and your private bathroom never have cameras. The Campus Security room in the founder services wing opens the same live views.")
	button(security,"Open live campus cameras",Security.open)
	local wellness=Kit.card(p,10);title(wellness,"Use the rooms")
	para(wellness,"Treadmills and bikes: stay nearby for an 18-second session. Sauna: relax near the heater for 12 seconds. Completed sessions give a short walking boost. Toilets have usable seats, occupied cubicles and flush buttons. Taps and showers run water and switch off automatically. Chairs and benches are real seats.")
	-- the Garage Lab (plan tier 0) has no pavilion, founder floor, roof terrace, B1 garage or wellness rooms
	watch(function(s)
		local hq=tierOf(s)>=1
		for _,card in {pavilion,services,top,garage,wellness} do card.Visible=hq end
	end)
end
local function access(p: Instance)
	local card=Kit.card(p,1);title(card,"Your employee card");local status=para(card,"")
	watch(function(s)status.Text=if s.live.campus and s.live.campus.hasCard then "Card active · as founder, every door of your headquarters opens for you" else "Your card is missing. Print a replacement below." end)
	button(card,"Print replacement card",function()call("ReplaceCard",{},"New card added to your backpack.")end)
	local help=Kit.card(p,2);title(help,"Invite someone to visit")
	para(help,"Visitors need no card for the reception hall, café, showroom and visitor lounge. Give another player a guest card for one hour to open the speed gates and team areas too: atrium, work floors, wellness pavilion and roof terrace. Technical rooms, Compute Operations, the Data Hall, research labs and every founder room stay closed. Your admin powers never open someone else's private rooms. Revoking a guest card immediately ends access.")
	for i=1,11 do
		local row=Kit.card(p,i+2);local name=title(row,"");local info=para(row,"");local selected: number?=nil;local active=false
		local b=button(row,"Issue guest card",function()
			if selected then call(if active then "RevokeGuestCard" else "GrantGuestCard",{userId=selected},if active then "Guest access revoked." else "One-hour guest card issued.") end
		end)
		watch(function(s)
			local live=s.live.campus;local peer=if live then live.online[i] else nil;row.Visible=peer~=nil;selected=if peer then peer.id else nil;active=false
			if not peer then return end
			for _,pass in live.passes do if pass.id==peer.id then active=true end end
			name.Text=peer.name;info.Text=if active then "Guest card active" else "No guest access to your company";b.Text=if active then "Revoke guest card" else "Issue one-hour guest card"
		end)
	end
end
local function fleet(p: Instance)
	local help=Kit.card(p,1);title(help,"Your company fleet")
	para(help,"A Founder’s Hatch is included. Purchase other cars with company cash. Collect one active car in your underground parking; choose Drive at its seat. Your fleet ownership is saved. An occupied car must be parked and left before collecting another.")
	for i,def in Config.CARS do
		local pass=(def :: any).pass -- game pass car (Executive Limo): ownership comes from the pass (ShopService)
		local card=Kit.card(p,i+1);title(card,def.name);para(card,string.format("%s · top speed %d studs/s · reverse %d studs/s",if pass then "Game pass car" elseif def.price==0 then "Included with your company" else Format.money(def.price),def.speed,def.reverse))
		local owned,hasPass,sellable=false,false,false
		local b=button(card,"",function()
			if pass and not hasPass then if navigator and sellable then navigator.show("shop") end;return end
			if pass and not owned then call("BuyCar",{carId=def.id},"Added to your fleet. Collect it below.");return end
			call(if owned then "SpawnCar" else "BuyCar",{carId=def.id},if owned then "Car ready to collect." else "Car purchased. Collect it below.")
		end)
		watch(function(s)
			owned=s.data.empire.campus.cars[def.id]==true
			local shop=(s.live :: any).shop
			hasPass=pass~=nil and typeof(shop)=="table" and typeof(shop.passes)=="table" and shop.passes[pass]==true
			-- ONBOARDING_SPEC C4 (shop package): no "Get the pass" while the pass has no id or is not sold
			local passDef=if pass then ShopConfigC.pass(pass) else nil
			sellable=passDef~=nil and passDef.id>0 and typeof(shop)=="table" and typeof(shop.available)=="table" and shop.available[pass]==true
			if pass then
				b.Text=if not hasPass then (if sellable then "Get the pass" else "Not available yet") elseif owned then "Collect" else "Add to fleet"
				Kit.setDisabled(b,not hasPass and not sellable)
			else
				b.Text=if owned then "Collect" else "Buy · "..Format.money(def.price);Kit.setDisabled(b,not owned and s.data.money<def.price)
			end
		end)
	end
end
local function shops(p: Instance)
	local hero=Kit.card(p,1);local heading=title(hero,"Your company stores");local info=para(hero,"")
	watch(function(s)
		local c=s.data.empire.campus;heading.Text=s.data.company.name.." / Company stores"
		info.Text=string.format("Retail level %d / 4 · %d sales · %s net revenue\nNPC retail traffic is simulated every 30 seconds. More staff and store upgrades increase visits. Each simulated ticket earns $12 after stock costs.",c.retailLevel,c.retailSales,Format.money(c.retailRevenue))
	end)
	local upgrade=button(hero,"Upgrade store",function()call("UpgradeRetail",{},"Company stores upgraded.")end)
	watch(function(s)local cost=Config.RETAIL[s.data.empire.campus.retailLevel];upgrade.Text=if cost then "Upgrade stores · "..Format.money(cost) else "Stores fully upgraded";Kit.setDisabled(upgrade,not cost or s.data.money<(cost or 0))end)
	local help=Kit.card(p,2);title(help,"House Kitchen & Snack Club")
	para(help,"Buy at the kitchen or shop counter to pay the menu price. The buttons below deliver a snack to your backpack for an extra $15. Equip it, then click or tap to eat. Snacks temporarily improve walk speed; the latest snack replaces the previous effect.")
	for i,def in Config.SNACKS do
		local card=Kit.card(p,i+2);title(card,def.name);local stock=para(card,"")
		local b=button(card,"Deliver · "..Format.money(def.price+15),function()call("BuySnack",{snackId=def.id},"Snack delivered to your backpack.")end)
		watch(function(s)stock.Text=string.format("In your bag: %d · walk speed %d for %ds",s.data.empire.campus.snacks[def.id] or 0,def.speed,def.seconds);Kit.setDisabled(b,s.data.money<def.price+15)end)
	end
end
local builders={building=building,access=access,fleet=fleet,shops=shops}
local function render()
	if not scroll then return end;watchers={};filling=watchers
	for _,child in scroll:GetChildren() do if child:IsA("GuiObject") then child:Destroy() end end
	local stack=Kit.stack(scroll,12);Kit.padding(stack,0,8,24,0);builders[current](stack);scroll.CanvasPosition=Vector2.zero
end
function App.mount(parent: Frame,nav: any)
	navigator=nav
	local head=Kit.frame(parent,UDim2.new(1,0,0,38));local text=Kit.text(head,"Campus",24,F.display,C.text);text.Position=UDim2.fromOffset(0,2)
	local tabs=Kit.row(parent,40,8);tabs.Position=UDim2.fromOffset(0,44);tabs.Size=UDim2.new(1,0,0,40)
	for _,def in {{"building","Building"},{"access","Cards & guests"},{"fleet","Fleet"},{"shops","Stores & snacks"}} do
		local b=Kit.button(tabs,def[2],"secondary",UDim2.new(.25,-6,1,0));Kit.onClick(b,function()current=def[1];render()end)
	end
	scroll=Kit.scroll(parent,UDim2.new(1,0,1,-98),UDim2.fromOffset(0,98))
	State.onChange(function(s)if not s.data.company then return end;if #watchers==0 then render()end;for _,fn in watchers do fn(s)end end)
end
function App.onShow()if #watchers==0 and State.snapshot and State.snapshot.data.company then render() end end
-- Team → Campus (ONBOARDING_SPEC B9): one page, two stacked sections "Cards & guests" and "Stores & snacks"
local function section(p: Instance,text: string,order: number,name: string): Frame
	local head=Kit.text(p,text,22,F.display,C.text);head.LayoutOrder=order;head.Name=name.."Head"
	local stack=Kit.stack(p,12,order+1);stack.Name=name
	return stack
end
local PARTS: {[string]:(Instance)->()}={building=building,access=access,fleet=fleet,shops=shops,
	campus=function(p: Instance) access(section(p,"Cards & guests",1,"CardsGuests"));shops(section(p,"Stores & snacks",3,"StoresSnacks")) end}
export type Part={frame: Frame,id: string,show: ()->(),rebuild: ()->()}
type PartState={frame: Frame,id: string,watchers: {(any)->()},built: boolean}
local partStates: {PartState}={}
local partsBound=false
local function shown(inst: Instance): boolean
	local node: Instance?=inst
	while node do
		if node:IsA("GuiObject") and not (node :: GuiObject).Visible then return false end
		if node:IsA("LayerCollector") then return true end
		node=node.Parent
	end
	return true
end
local function renderPart(part: PartState)
	local snapshot=State.snapshot
	if not snapshot or not snapshot.data.company then return end
	for _,child in part.frame:GetChildren() do if child:IsA("GuiObject") then child:Destroy() end end
	part.watchers={}
	local before=filling;filling=part.watchers
	local stack=Kit.stack(part.frame,12);stack.Name="Campus_"..part.id
	local builder=PARTS[part.id]
	local ok,err=pcall(function() builder(stack) end)
	filling=before
	if not ok then warn("[CampusApp] part "..part.id..": "..tostring(err)) end
	part.built=true
end
function App.mountPart(frame: Frame,id: string,nav: any): Part
	assert(PARTS[id],"unknown CampusApp part "..id)
	navigator=navigator or nav
	frame.AutomaticSize=Enum.AutomaticSize.Y
	local part: PartState={frame=frame,id=id,watchers={},built=false}
	table.insert(partStates,part)
	if not partsBound then
		partsBound=true
		State.onChange(function(s)
			if not s.data.company then return end
			for _,p in partStates do if p.built and shown(p.frame) then for _,fn in p.watchers do fn(s) end end end
		end)
	end
	return {frame=frame,id=id,show=function()
		if not part.built then renderPart(part) elseif State.snapshot then for _,fn in part.watchers do fn(State.snapshot) end end
	end,rebuild=function() renderPart(part) end}
end
-- Prompts and the HUD can open a tab directly (building, access, fleet, shops).
function App.openSection(section: string)
	if builders[section] then current=section;render() end
end
return App
