--!strict
-- The launcher appears only after a server-authorized snapshot, including before company creation.
local State=require(script.Parent.Parent.Controllers.StateController)
local Action=require(script.Parent.Parent.Controllers.ActionController)
local Theme=require(script.Parent.Theme)
local Kit=require(script.Parent.Kit)
local Toast=require(script.Parent.Toast)
local Panel={}
local frame: Frame?=nil
local authorized=false
local actions={
	{cmd="campus",title="Größten Campus freischalten",body="Sieben Etagen, alle Räume und Stores. Dein Spielstand bleibt erhalten."},
	{cmd="setup",title="Kompletten Firmenstart geben",body="Campus, 240 Mitarbeiter, Forschung, GPUs, Autos, Daten und $1 Mio."},
	{cmd="money",title="+$1.000.000 Spielgeld",body="Auf das eigene Firmenkonto einzahlen."},
	{cmd="staff",title="Team auf 240 auffüllen",body="Vier Rollen ausgewogen ergänzen. Die laufenden Gehälter gelten weiter."},
	{cmd="hardware",title="Compute ausbauen",body="Bis zu zwei Compute-Pods ergänzen und Kühlung auf Stufe 8 setzen."},
	{cmd="research",title="Alle Forschung freischalten",body="Acht Forschungsprojekte abschließen und 10.000 Punkte bereitstellen."},
	{cmd="fleet",title="Alle Firmenautos freischalten",body="Hatch, Cargo, Executive und Circuit GT im Fleet-Tab abholen."},
	{cmd="data",title="Trainingsdaten ergänzen",body="10 Milliarden hochwertige Tokens pro Datenart."},
	{cmd="finish",title="Laufendes Training abschließen",body="Den bestehenden Trainingslauf mit seinen normalen Modellwerten beenden."},
}
function Panel.toggle()
	if frame then frame.Visible=authorized and not frame.Visible end
end
function Panel.mount(parent: Frame)
	local launch=Kit.button(parent,"ADMIN","secondary",UDim2.fromOffset(134,38))
	launch.Name="AdminLauncher";launch.Position=UDim2.new(0,16,1,-16);launch.AnchorPoint=Vector2.new(0,1);launch.Visible=false
	Kit.onClick(launch,Panel.toggle)
	local box=Kit.panel(parent,UDim2.fromOffset(610,610),UDim2.fromScale(.5,.5))
	box.Name="AdminPanel";box.AnchorPoint=Vector2.new(.5,.5);box.Visible=false;frame=box
	local scale=Instance.new("UIScale");scale.Parent=box
	local function resize()
		local camera=workspace.CurrentCamera
		if camera then scale.Scale=math.max(.3,math.min(1,(camera.ViewportSize.X-24)/610,(camera.ViewportSize.Y-40)/610)) end
	end
	resize();if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize) end
	Kit.padding(box,22,22,20,22)
	Kit.text(box,"Campus-Kontrolle",25,Theme.font.bold,Theme.colors.text)
	local caption=Kit.text(box,"Nonortrttrt  /  Administrator",13,Theme.font.medium,Theme.colors.muted);caption.Position=UDim2.fromOffset(0,38)
	local close=Kit.button(box,"Schließen","ghost",UDim2.fromOffset(90,30));close.Position=UDim2.new(1,-90,0,2);Kit.onClick(close,Panel.toggle)
	local scroller=Kit.scroll(box,UDim2.new(1,0,1,-80),UDim2.fromOffset(0,78))
	Kit.list(scroller,9);Kit.padding(scroller,0,8,8,0)
	-- Read-only diagnostics of the admin's own headquarters, shown in a scrollable, selectable box.
	local diag=Kit.card(scroller,0)
	local run=Kit.button(diag,"HQ-Diagnose ausführen","secondary",UDim2.new(1,0,0,36));run.LayoutOrder=1
	Kit.para(diag,"Nur lesen: Räume je Etage, Arbeitsplätze, Mitarbeiter mit Wegproblemen oder Lift-Tickets, Aufzug, offene oder gesperrte Türen und Kameras deines eigenen Hauptquartiers.",13,Theme.colors.muted,2)
	local area=Kit.scroll(diag,UDim2.new(1,0,0,230));area.LayoutOrder=3;area.BackgroundTransparency=.4;area.BackgroundColor3=Theme.colors.bg;Kit.corner(area,8)
	Kit.padding(area,8,8,8,8)
	local report=Instance.new("TextBox");report.Name="DiagnosticsReport";report.BackgroundTransparency=1;report.BorderSizePixel=0
	report.Size=UDim2.fromScale(1,0);report.AutomaticSize=Enum.AutomaticSize.Y;report.TextWrapped=true;report.MultiLine=true
	report.TextEditable=false;report.ClearTextOnFocus=false;report.Font=Theme.font.mono;report.TextSize=12;report.TextColor3=Theme.colors.text
	report.TextXAlignment=Enum.TextXAlignment.Left;report.TextYAlignment=Enum.TextYAlignment.Top;report.Text="Noch kein Bericht.";report.Parent=area
	Kit.onClick(run,function()
		if not authorized then return end
		task.spawn(function()
			Kit.setDisabled(run,true)
			local ok,result=Action.call("AdminAction",{cmd="diag"})
			Kit.setDisabled(run,false)
			if ok and typeof(result.report)=="string" then report.Text=result.report;area.CanvasPosition=Vector2.zero end
		end)
	end)
	-- Tier switch for testing upgrades and downgrades. It changes the admin's OWN save.
	local tiers=Kit.card(scroller,1)
	Kit.para(tiers,"Bürostufe testen: setzt die Stufe DEINES Spielstands und baut dein Hauptquartier neu. Mitarbeiter über der Schreibtischzahl werden wie beim Laden gekürzt. Ändert deinen Spielstand.",13,Theme.colors.muted,1)
	local tierRow=Kit.row(tiers,36,8,2)
	for tier=1,4 do
		local b=Kit.button(tierRow,"Stufe "..tier,"secondary",UDim2.new(.25,-6,1,0));b.LayoutOrder=tier
		Kit.onClick(b,function()
			if not authorized then return end
			task.spawn(function()
				Kit.setDisabled(b,true)
				local ok=Action.call("AdminAction",{cmd="tier"..tier})
				Kit.setDisabled(b,false)
				if ok then Toast.show("success","Bürostufe "..tier.." · Hauptquartier neu gebaut",4) end
			end)
		end)
	end
	for i,def in actions do
		local row=Kit.card(scroller,i+1)
		local b=Kit.button(row,def.title,if i==1 then "primary" else "secondary",UDim2.new(1,0,0,36));b.LayoutOrder=1
		Kit.para(row,def.body,13,Theme.colors.muted,2)
		Kit.onClick(b,function()
			if not authorized then return end
			task.spawn(function()
				Kit.setDisabled(b,true)
				local ok=Action.call("AdminAction",{cmd=def.cmd})
				Kit.setDisabled(b,false)
				if ok then Toast.show("success",def.title.." · erledigt",4) end
			end)
		end)
	end
	State.onChange(function(snapshot)
		authorized=snapshot.live.admin==true;launch.Visible=authorized
		if not authorized then box.Visible=false end
	end)
end
return Panel
