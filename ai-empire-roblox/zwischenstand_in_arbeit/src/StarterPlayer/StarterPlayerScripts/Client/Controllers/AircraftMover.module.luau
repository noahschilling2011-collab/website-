--!strict
-- AircraftMover (package "flight", client only): moves a client-built AircraftModel / helicopter rigidly with
-- ONE workspace:BulkMoveTo per frame (part offsets cached once relative to the pivot), spins the engine fans
-- (parts with attribute Spin, about the axis of the nearest "Fan" disc) and helicopter rotors (attribute
-- Rotor = "main" about +Y through the model's RotorHub, "tail" about X through TailHub), and shows/hides the
-- landing gear (attribute Gear) and the whole model (LocalTransparencyModifier). Nothing here replicates.
local Mover={}
type Spin={i: number,hub: CFrame,rel: CFrame,kind: string}
export type Mover={model: Model,parts: {BasePart},offsets: {CFrame},cframes: {CFrame},spins: {Spin},gear: {BasePart},gearShown: boolean,visible: boolean}

function Mover.new(model: Model,pivot: CFrame): Mover
	local parts: {BasePart}={}
	local offsets: {CFrame}={}
	local gear: {BasePart}={}
	local fans: {CFrame}={}
	local spinIdx: {number}={}
	local rotorIdx: {number}={}
	for _,d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts,d)
			local off=pivot:ToObjectSpace(d.CFrame)
			table.insert(offsets,off)
			if d:GetAttribute("Gear")==true then table.insert(gear,d) end
			if d:GetAttribute("Spin")==true then
				table.insert(spinIdx,#parts)
				if d.Name=="Fan" then table.insert(fans,off) -- procedural fan disc: cylinder axis = local X = engine axis
				elseif d:IsA("MeshPart") and string.sub(d.Name,1,3)=="Fan" then
					-- imported mesh fan (Fan_1, Fan_2): spin about the model's Z axis through the part
					table.insert(fans,CFrame.new(off.Position)*CFrame.Angles(0,-math.pi/2,0))
				end
			end
			if typeof(d:GetAttribute("Rotor"))=="string" then table.insert(rotorIdx,#parts) end
		end
	end
	local spins: {Spin}={}
	for _,i in spinIdx do
		local off=offsets[i]
		local best: CFrame?=nil;local bestD=math.huge
		for _,f in fans do
			local dd=(f.Position-off.Position).Magnitude
			if dd<bestD then best=f;bestD=dd end
		end
		if best then table.insert(spins,{i=i,hub=best,rel=best:ToObjectSpace(off),kind="fan"}) end
	end
	local hubAttr=model:GetAttribute("RotorHub");local tailAttr=model:GetAttribute("TailHub")
	for _,i in rotorIdx do
		local kind=parts[i]:GetAttribute("Rotor")
		local hub=if kind=="tail" and typeof(tailAttr)=="Vector3" then CFrame.new(tailAttr)
			elseif typeof(hubAttr)=="Vector3" then CFrame.new(hubAttr)*CFrame.Angles(0,0,math.pi/2) -- local X = +Y (mast axis)
			else CFrame.new()
		table.insert(spins,{i=i,hub=hub,rel=hub:ToObjectSpace(offsets[i]),kind=if kind=="tail" then "tail" else "main"})
	end
	local cframes: {CFrame}=table.create(#parts,pivot)
	return {model=model,parts=parts,offsets=offsets,cframes=cframes,spins=spins,gear=gear,gearShown=true,visible=true}
end
-- Move to `cf`. fan / main / tail = rotation angles (radians) of the engine fans, main rotor and tail rotor.
function Mover.move(mv: Mover,cf: CFrame,fan: number?,main: number?,tail: number?)
	local parts,offsets,cframes=mv.parts,mv.offsets,mv.cframes
	for i=1,#parts do cframes[i]=cf*offsets[i] end
	for _,s in mv.spins do
		local a=if s.kind=="fan" then fan elseif s.kind=="main" then main else tail
		if a then cframes[s.i]=cf*s.hub*CFrame.Angles(a,0,0)*s.rel end
	end
	workspace:BulkMoveTo(parts,cframes,Enum.BulkMoveMode.FireCFrameChanged)
end
function Mover.setGear(mv: Mover,shown: boolean)
	if mv.gearShown==shown then return end
	mv.gearShown=shown
	for _,p in mv.gear do p.Transparency=if shown then 0 else 1 end
end
function Mover.setVisible(mv: Mover,visible: boolean)
	if mv.visible==visible then return end
	mv.visible=visible
	for _,p in mv.parts do p.LocalTransparencyModifier=if visible then 0 else 1 end
end
return Mover
