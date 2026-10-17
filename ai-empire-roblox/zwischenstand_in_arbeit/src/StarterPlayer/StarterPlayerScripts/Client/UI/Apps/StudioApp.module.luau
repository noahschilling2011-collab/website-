--!strict
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Shared=ReplicatedStorage.Shared
local Config=require(Shared.Config.StudioConfig)
local Math=require(Shared.StudioMath)
local Format=require(Shared.Format)
local UI=script.Parent.Parent
local State=require(UI.Parent.Controllers.StateController)
local Action=require(UI.Parent.Controllers.ActionController)
local Theme=require(UI.Theme)
local Kit=require(UI.Kit)
local Toast=require(UI.Toast)
local C,F=Theme.colors,Theme.font
local App={}
local refresh=function(_s: any)end
function App.mount(parent: Frame,nav: any)
	local scroll=Kit.scroll(parent);Kit.padding(scroll,2,14,22,2);Kit.list(scroll,16)
	Kit.heading(scroll,"Project studio","Give your AI a useful job. Build a website, a shop, a game companion or an office workflow.",1)
	local left,right=Kit.columns(scroll,.42,18,2)
	local builder=Kit.card(left,1,12)
	Kit.caption(builder,"01 / Project brief",1)
	local name=Kit.input(builder,"Your brand or project name");name.Text="";name.LayoutOrder=2 -- B7: no placeholder brand
	local kindId,styleId,sourceId="website","paper","own"
	local briefId: string?=nil
	local selected: string?=nil
	local providerModelId: string?=nil
	local options={};for _,def in Config.KINDS do table.insert(options,{id=def.id,label=({website="Website",shop="Shop",gamebot="Game bot",workflow="Workflow"})[def.id]}) end
	local kinds=Kit.segmented(builder,options,kindId,function(id) kindId=id;briefId=nil;if State.snapshot then refresh(State.snapshot) end end)
	kinds.frame.LayoutOrder=3
	Kit.caption(builder,"02 / Visual direction",4)
	local styles=Kit.segmented(builder,{{id="paper",label="Paper"},{id="slate",label="Slate"},{id="brick",label="Clay"}},styleId,function(id) styleId=id end)
	styles.frame.LayoutOrder=5
	Kit.caption(builder,"03 / AI provider",6)
	local sources=Kit.segmented(builder,{{id="own",label="My trained AI"},{id="licensed",label="Subscribed AI"}},sourceId,function(id) sourceId=id;if State.snapshot then refresh(State.snapshot) end end)
	sources.frame.LayoutOrder=7
	local provider=Kit.para(builder,"",14,C.text,8)
	local quote=Kit.para(builder,"",13,C.muted,9)
	local generate=Kit.button(builder,"BUILD PROJECT","primary",UDim2.new(1,0,0,44));generate.LayoutOrder=10
	Kit.onClick(generate,function()
		if not providerModelId then return end
		local ok,result=Action.call("BuildProject",{name=name.Text,kind=kindId,style=styleId,modelId=providerModelId,briefId=briefId})
		if ok then selected=result.projectId end
	end)
	local jobText=Kit.para(builder,"",13,C.dim,11)
	local progress=Kit.bar(builder,6,12)
	local cancel=Kit.button(builder,"CANCEL CURRENT BUILD","ghost",UDim2.new(1,0,0,30));cancel.LayoutOrder=13;cancel.Visible=false
	Kit.onClick(cancel,function() Action.call("CancelProject",{}) end)

	local clientCard=Kit.card(left,2,10);Kit.caption(clientCard,"Client briefs",1)
	for index,brief in Config.BRIEFS do
		local b=Kit.button(clientCard,brief.client.." · "..Format.money(brief.reward),"secondary",UDim2.new(1,0,0,34));b.LayoutOrder=index+1;b.TextSize=13
		Kit.onClick(b,function() briefId=brief.id;kindId=brief.kind;name.Text=brief.client;kinds.set(kindId);if State.snapshot then refresh(State.snapshot) end end)
	end
	local work=Kit.card(left,3,10);Kit.caption(work,"Your portfolio",1)
	local projectList=Kit.stack(work,7,2);local rows={} :: {[string]:any};local listKey=""

	local previewCard=Kit.card(right,1,10)
	Kit.caption(previewCard,"Live project preview",1)
	local browser=Kit.frame(previewCard,UDim2.new(1,0,0,416));browser.LayoutOrder=2;browser.BackgroundTransparency=0;Kit.corner(browser,8)
	local chrome=Kit.frame(browser,UDim2.new(1,0,0,30));chrome.BackgroundTransparency=0;chrome.BackgroundColor3=C.raised
	local address=Kit.text(chrome,"studio.local",11,F.medium,C.muted);address.Position=UDim2.fromOffset(12,8)
	local brand=Kit.text(browser,"Your brand",15,F.bold);brand.Position=UDim2.fromOffset(22,49)
	local contact=Kit.button(browser,"Contact","ghost",UDim2.fromOffset(76,28));contact.Position=UDim2.new(1,-98,0,43);contact.TextSize=12
	local hero=Kit.para(browser,"",27,C.text);hero.AutomaticSize=Enum.AutomaticSize.None;hero.Size=UDim2.new(1,-44,0,96);hero.Position=UDim2.fromOffset(22,100)
	local body=Kit.para(browser,"",13,C.muted);body.AutomaticSize=Enum.AutomaticSize.None;body.Size=UDim2.new(1,-44,0,54);body.Position=UDim2.fromOffset(22,205)
	local tiles={}
	for i=1,3 do
		local tile=Kit.frame(browser,UDim2.new(1/3,-20,0,64),UDim2.new((i-1)/3,16,0,279));tile.BackgroundTransparency=0;Kit.corner(tile,4)
		local label=Kit.para(tile,"",12,C.text);label.AutomaticSize=Enum.AutomaticSize.None;label.Size=UDim2.new(1,-12,1,-12);label.Position=UDim2.fromOffset(6,6);label.TextXAlignment=Enum.TextXAlignment.Center
		tiles[i]={frame=tile,label=label}
	end
	local demo=Kit.button(browser,"Explore the project","secondary",UDim2.new(1,-44,0,34));demo.Position=UDim2.fromOffset(22,360);demo.TextSize=13
	local footer=Kit.para(previewCard,"",13,C.dim,3)
	local controls=Kit.row(previewCard,34,8,4)
	local publish=Kit.button(controls,"PUBLISH","primary",UDim2.fromOffset(120,32))
	local deliver=Kit.button(controls,"DELIVER TO CLIENT","secondary",UDim2.fromOffset(175,32));deliver.LayoutOrder=2
	local archive=Kit.button(previewCard,"Archive project","ghost",UDim2.new(1,0,0,28));archive.LayoutOrder=5;archive.TextSize=12
	local preview:any=nil
	local contactOpen=false;local demoCount=0;local previousId=""
	local function paint(item: any)
		preview=item
		if item.id~=previousId then previousId=item.id;contactOpen=false;demoCount=0 end
		local style=Config.find(Config.STYLES,item.style) or Config.STYLES[1]
		local bg,ink,accent=Theme.rgb(style.bg),Theme.rgb(style.ink),Theme.rgb(style.accent)
		contact.TextColor3=ink
		browser.BackgroundColor3=bg;brand.TextColor3=ink;hero.TextColor3=ink;body.TextColor3=ink
		local shown=if item.name~="" then item.name else "Your brand"
		brand.Text=shown;address.Text="preview / "..item.kind.." / "..shown
		hero.Text=if contactOpen then "Let's make something together." else item.content.headline
		body.Text=if contactOpen then "Contact preview opened. Your visitors can reach the company from this page." else item.content.sub
		for i,refs in tiles do refs.frame.BackgroundColor3=accent:Lerp(bg,.88);refs.label.TextColor3=ink;refs.label.Text=item.content.items[i] or "" end
		demo.BackgroundColor3=accent;demo.BackgroundTransparency=0;demo.TextColor3=bg
		demo.Text=if item.kind=="shop" then "Add item to cart · "..tostring(demoCount).." items" elseif item.kind=="workflow" then "Complete next task · "..tostring(demoCount).." done" elseif item.kind=="gamebot" then "Open robot test arena" else "Explore our work"
		footer.Text=string.format("%s · %.1f quality · Built by %s",item.status,item.quality,item.modelName or "AI provider")
		local mine=State.snapshot and State.snapshot.data.empire.projects[item.id]~=nil
		archive.Visible=mine==true and item.status~="building"
		publish.Visible=mine==true;deliver.Visible=mine==true and item.briefId~=nil
		Kit.setDisabled(publish,item.status~="ready");Kit.setDisabled(deliver,item.status=="building" or item.delivered==true)
	end
	Kit.onClick(contact,function() if preview then contactOpen=not contactOpen;paint(preview) end end)
	Kit.onClick(demo,function()
		if not preview then return end
		if preview.kind=="gamebot" then nav.show("arena")
		elseif preview.kind=="shop" or preview.kind=="workflow" then demoCount+=1;paint(preview)
		else Toast.show("info","Project preview: "..preview.content.items[1]) end
	end)
	Kit.onClick(publish,function() if preview then Action.call("PublishProject",{projectId=preview.id}) end end)
	Kit.onClick(archive,function() if preview then local ok=Action.call("ArchiveProject",{projectId=preview.id});if ok then selected=nil end end end)
	Kit.onClick(deliver,function() if preview then Action.call("DeliverProject",{projectId=preview.id}) end end)
	local gallery=Kit.card(right,2,8);Kit.caption(gallery,"Around the district",1)
	local galleryList=Kit.stack(gallery,6,2);local galleryKey="";local galleryButtons: {TextButton}={}
	refresh=function(s: any)
		local e=s.data.empire;local kind=Config.find(Config.KINDS,kindId)
		local stats:any=nil;providerModelId=nil
		if sourceId=="licensed" then
			local sub=e.subscriptions
			if sub.expires and sub.expires>os.time() then stats=sub.stats or {coding=sub.score,creativity=sub.score,reliability=60,reasoning=sub.score};providerModelId="licensed";provider.Text=sub.provider.." / "..sub.name else provider.Text="Buy AI access in Market first." end
		else
			local best:any=nil
			for _,id in s.data.modelOrder do local m=s.data.models[id];if m and (m.status=="trained" or m.status=="live") and (not best or (m.stats[kind.stat] or 0)>(best.stats[kind.stat] or 0)) then best=m end end
			if best then stats=best.stats;providerModelId=best.id;provider.Text=best.name.." · your best "..kind.stat.." checkpoint" else provider.Text="Train your first model in the Lab." end
		end
		quote.Text=Format.money(kind.cost).." build cost · "..(if stats then tostring(Math.quality(stats,kind)).." expected quality" else "No trained AI available")..(if briefId then "\nClient: "..(Config.find(Config.BRIEFS,briefId).client) else "\nYour own company project")
		Kit.setDisabled(generate,e.projectJob~=nil or not stats or s.data.money<kind.cost)
		local job=e.projectJob;cancel.Visible=job~=nil;progress.set(if job then job.done/job.total else 0)
		jobText.Text=if job then "Building · "..Format.percent(job.done/job.total).." · "..(if s.data.training then "Sharing GPUs with training" else "Using your compute") else "Ready for a new project"
		local key=table.concat(e.projectOrder,",")
		if key~=listKey then
			listKey=key;for _,r in rows do r.button:Destroy() end;table.clear(rows)
			for i,id in e.projectOrder do local b=Kit.button(projectList,"","secondary",UDim2.new(1,0,0,36));b.LayoutOrder=i;b.TextSize=13;rows[id]={button=b};Kit.onClick(b,function() selected=id;refresh(State.snapshot) end) end
		end
		for id,r in rows do local item=e.projects[id];r.button.Text=item.name.." / "..item.status end
		local list=s.live.studio and s.live.studio.gallery or {};local keys={}
		for _,item in list do table.insert(keys,item.id) end
		local gkey=table.concat(keys,",")
		if gkey~=galleryKey then
			galleryKey=gkey;for _,b in galleryButtons do b:Destroy() end;table.clear(galleryButtons)
			for i,item in list do local b=Kit.button(galleryList,item.company.." / "..item.kind,"ghost",UDim2.new(1,0,0,30));b.LayoutOrder=i;b.TextSize=12;table.insert(galleryButtons,b);Kit.onClick(b,function() selected=item.id;refresh(State.snapshot) end) end
		end
		local item=if selected then e.projects[selected] else nil
		if not item and selected then for _,other in list do if other.id==selected then item=other;break end end end
		if not item then item=e.projects[e.projectOrder[#e.projectOrder]] or list[1] end
		if item then paint(item) else
			paint({id="empty",name=name.Text,kind=kindId,style=styleId,status="preview",quality=0,modelName="your next model",content=Math.content(if name.Text~="" then name.Text else "Your brand",kindId,briefId)})
		end
	end
	State.onChange(function(s) if parent.Visible and nav.isOpen() then refresh(s) end end)
end
function App.onShow() if State.snapshot then refresh(State.snapshot) end end
return App
