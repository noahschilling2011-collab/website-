--!strict
-- Original R6-compatible rigs. No downloaded avatars, clothes or animation asset IDs.
-- Identity: an appearance seed (EmployeeConfig.seed(index, owner), or a persistent staff profile's
-- seed) drives build, face, hair, outfit and role details, so the same person always returns with the
-- same look. Presentation (feminine/masculine) always matches the first name: generated names come
-- from CampusMath.staffName(index, owner), which uses the same EmployeeConfig.isFeminine rule; a
-- profile name from the staff lists decides the presentation itself.
-- At most MAX_PARTS parts per rig; accessories are non-colliding, massless, unqueryable and welded.
-- Head: the standard R6 head (2x1x1 part, Head mesh 1.25) slightly flattened in depth so the
-- SurfaceGui face sits in front of the mesh surface; visible head ~1.25 wide.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Collection=game:GetService("CollectionService")
local Config=require(ReplicatedStorage.Shared.Config.EmployeeConfig)
local CampusMath=require(ReplicatedStorage.Shared.CampusMath)
local Dialogue=require(ReplicatedStorage.Shared.Dialogue)
local Rig={}
Rig.MAX_PARTS=22
export type Profile={n: string?,s: number?,k: number?}
local rgb=Color3.fromRGB
local SKINS={rgb(255,226,201),rgb(241,206,172),rgb(232,190,152),rgb(214,170,133),rgb(198,148,106),rgb(176,124,86),rgb(150,103,72),rgb(122,82,56),rgb(96,64,45),rgb(72,48,36)}
local HAIR={rgb(24,21,20),rgb(44,34,28),rgb(70,52,38),rgb(101,70,45),rgb(128,82,48),rgb(156,96,56),rgb(196,160,104),rgb(224,204,158),rgb(146,58,40),rgb(58,84,122)}
local HAIR_WEIGHTS={7,7,6,5,3,2,3,2,2,1}
local GREY={rgb(124,122,120),rgb(160,158,154),rgb(206,204,198)}
local SHIRTS={rgb(236,236,230),rgb(178,202,224),rgb(232,200,200),rgb(190,220,200),rgb(214,200,172),rgb(198,190,222),rgb(150,154,158),rgb(70,74,80),rgb(44,58,92),rgb(58,88,70),rgb(118,44,56),rgb(204,164,70),rgb(52,118,128),rgb(34,34,36),rgb(226,214,236),rgb(240,226,206)}
local TROUSERS={rgb(40,50,76),rgb(52,56,62),rgb(28,28,30),rgb(170,150,110),rgb(110,114,120),rgb(64,88,128),rgb(96,72,52),rgb(88,92,62)}
local SKIRTS={rgb(40,50,76),rgb(52,56,62),rgb(28,28,30),rgb(176,140,96),rgb(92,98,70),rgb(106,44,52),rgb(64,88,128),rgb(120,124,130),rgb(150,112,130)}
local TIGHTS={rgb(30,30,32),rgb(52,54,60),rgb(40,46,66)}
local SHOES={rgb(226,224,216),rgb(26,26,28),rgb(98,66,44),rgb(150,152,156),rgb(40,50,76),rgb(170,126,84),rgb(120,40,48)}
local BLAZERS={rgb(40,52,84),rgb(58,62,68),rgb(176,140,96),rgb(92,98,70),rgb(106,44,52),rgb(164,166,168),rgb(210,196,184)}
local KNITS={rgb(210,196,170),rgb(64,96,74),rgb(164,90,58),rgb(128,130,134),rgb(52,62,96),rgb(150,112,130)}
local HOODIES={rgb(130,134,140),rgb(36,36,40),rgb(52,82,62),rgb(110,40,50),rgb(74,90,110)}
local VESTS={rgb(120,124,128),rgb(48,58,88),rgb(110,84,60),rgb(40,40,42)}
local FRAMES={rgb(30,30,32),rgb(96,62,40),rgb(190,160,96),rgb(170,172,176)}
local METALS={rgb(212,180,96),rgb(200,202,206),rgb(236,232,222)}
local LANYARD={researcher=rgb(126,96,186),engineer=rgb(40,150,140),curator=rgb(64,120,196),marketer=rgb(226,128,60),support=rgb(88,160,96)}
-- none, blazer, cardigan, hoodie, vest
local OVERLAY_WEIGHTS: {[string]:{number}}={researcher={3,1,3,1,2},engineer={3,1,1,4,1},curator={3,1,3,2,2},marketer={1,5,2,1,2}}
local OVERLAY_WEIGHTS_F: {[string]:{number}}={researcher={3,2,4,1,1},engineer={3,2,2,3,1},curator={3,2,4,2,1},marketer={2,6,3,1,1}}
local OVERLAYS={"none","blazer","cardigan","hoodie","vest"}
local STYLES_F={"long","bob","bun","ponytail","braids","curls"};local STYLE_WEIGHTS_F={4,3,2,3,1,2}
local STYLES_M={"short","buzz","sidepart","curls"};local STYLE_WEIGHTS_M={5,2,4,2}
-- Operations staff wear uniform tones per job (Config.OPERATIONS_JOBS); skirt=true allows a skirt.
local UNIFORMS: {[string]:any}={
 Reception={shirt=rgb(236,236,230),jacket=rgb(38,52,82),trousers=rgb(44,48,56),shoes=rgb(30,28,28),skirt=true},
 Security={shirt=rgb(232,232,228),jacket=rgb(30,34,40),trousers=rgb(28,31,36),shoes=rgb(20,20,22),tie=rgb(26,26,30)},
 Facilities={shirt=rgb(74,96,118),trousers=rgb(56,62,70),shoes=rgb(60,48,38)},
 ["IT Support"]={shirt=rgb(52,118,128),trousers=rgb(160,142,108),shoes=rgb(220,220,214)},
 Barista={shirt=rgb(40,40,42),trousers=rgb(36,38,42),shoes=rgb(30,28,28),apron=rgb(122,86,58)},
 Chef={shirt=rgb(242,242,238),trousers=rgb(70,72,76),shoes=rgb(30,28,28),hat=rgb(246,246,242)},
 ["Kitchen Team"]={shirt=rgb(238,238,232),trousers=rgb(40,42,46),shoes=rgb(30,28,28),apron=rgb(34,36,40)},
 ["Cafe Host"]={shirt=rgb(128,44,54),trousers=rgb(40,40,44),shoes=rgb(60,40,30),vest=rgb(48,40,40),skirt=true},
 Fleet={shirt=rgb(46,56,74),trousers=rgb(40,46,56),shoes=rgb(40,34,30),hivis=rgb(204,222,70)},
 ["Hotel Reception"]={shirt=rgb(236,236,230),jacket=rgb(82,46,58),trousers=rgb(44,48,56),shoes=rgb(30,28,28),skirt=true},
 Housekeeping={shirt=rgb(196,214,220),trousers=rgb(70,74,82),shoes=rgb(60,48,38),apron=rgb(236,236,230)},
 Cleaner={shirt=rgb(52,92,150),trousers=rgb(52,56,62),shoes=rgb(40,34,30),hivis=rgb(204,222,70)},
 Mailroom={shirt=rgb(150,112,70),trousers=rgb(56,62,70),shoes=rgb(60,48,38)},
 -- shuttle pilots (ShuttleService, role "pilot"): white shirt, navy jacket and tie, uniform cap with a gold band
 Pilot={shirt=rgb(244,244,240),jacket=rgb(26,34,58),trousers=rgb(26,34,58),shoes=rgb(18,18,20),tie=rgb(20,26,44),cap=rgb(26,34,58)},
}
-- Counter-based stream over EmployeeConfig.hash: identical on every server, no correlated draws.
local function stream(seed: number): (number)->number
 local state=Config.hash(seed)
 return function(n: number): number
  state=(state+0x9e3779b9)%4294967296
  return Config.hash(state)%n+1
 end
end
local function weighted(pick: (number)->number,weights: {number}): number
 local total=0;for _,w in weights do total+=w end
 local roll=pick(total)
 for i,w in weights do roll-=w;if roll<=0 then return i end end
 return #weights
end
-- profile (optional, persistent identity): n = name, s = appearance seed, k = skill 1..5.
function Rig.build(parent: Instance,owner: number,index: number,role: string,pose: CFrame,profile: Profile?): Model
 local job=if role=="support" then Config.OPERATIONS_JOBS[index-300] elseif role=="pilot" then "Pilot" else Config.ROLES[role]
 local seed=if profile and profile.s then math.floor(math.abs(profile.s))%2147483647 else Config.seed(index,owner)
 local name=if profile and profile.n then profile.n else CampusMath.staffName(index,owner)
 local feminine: boolean
 if profile then
  local byName=CampusMath.nameFeminine(name)
  feminine=if byName~=nil then byName elseif profile.s then Config.feminine(seed) else Config.isFeminine(index,owner)
 else feminine=Config.isFeminine(index,owner) end
 local pick=stream(seed)
 local function fraction(): number return (pick(1001)-1)/1000 end
 -- Build within 0.92..1.06: feminine builds a little shorter and narrower on average.
 local sy=if feminine then .92+fraction()*.1 else .95+fraction()*.11
 local sx=math.clamp(sy+(if feminine then -.02 else 0)+(fraction()-.5)*.07,.92,1.06)
 local skin=SKINS[pick(#SKINS)]
 local older=pick(100)<=16
 local hair=if older then GREY[pick(#GREY)] else HAIR[weighted(pick,HAIR_WEIGHTS)]
 local style=if feminine then STYLES_F[weighted(pick,STYLE_WEIGHTS_F)] else STYLES_M[weighted(pick,STYLE_WEIGHTS_M)]
 local shirt=SHIRTS[pick(#SHIRTS)];local trousers=TROUSERS[pick(#TROUSERS)];local shoes=SHOES[pick(#SHOES)]
 local overlay=OVERLAYS[weighted(pick,(if feminine then OVERLAY_WEIGHTS_F[role] else OVERLAY_WEIGHTS[role]) or {1,0,0,0,0})]
 local jacket=if overlay=="blazer" then BLAZERS[pick(#BLAZERS)] elseif overlay=="cardigan" then KNITS[pick(#KNITS)] elseif overlay=="hoodie" then HOODIES[pick(#HOODIES)] else VESTS[pick(#VESTS)]
 local glasses=pick(100)<=(if role=="researcher" then 40 elseif role=="support" then 15 else 26)+(if older then 25 else 0)
 local frame=FRAMES[pick(#FRAMES)];local tinted=pick(12)==1
 local facial=pick(100);local labCoat=role=="researcher" and pick(100)<=30;local headphones=role=="engineer" and pick(100)<=35
 local skirtRoll=pick(100);local skirtColor=SKIRTS[pick(#SKIRTS)];local bareLegs=pick(100)<=40;local tights=TIGHTS[pick(#TIGHTS)];local dressRoll=pick(100)
 local earrings=feminine and pick(100)<=45;local metal=METALS[pick(#METALS)]
 local brow=pick(3);local mouthStyle=pick(2)
 local uniform=if job then UNIFORMS[job] else nil
 if uniform then
  shirt=uniform.shirt;trousers=uniform.trousers;shoes=uniform.shoes
  overlay=if uniform.jacket then "blazer" elseif uniform.vest then "vest" else "none";jacket=uniform.jacket or uniform.vest or shirt
  if uniform.hat then style="chef" end
 end
 if labCoat then overlay="labcoat";jacket=rgb(240,240,236) end
 -- Skirt or dress (feminine, about 40%; uniforms only where allowed). Kept short so it reads as a
 -- skirt standing and sits on the lap when the seated legs swing forward.
 local skirt=feminine and skirtRoll<=40 and (uniform==nil or uniform.skirt==true)
 local dress=skirt and overlay=="none" and uniform==nil and dressRoll<=50
 if skirt then
  if uniform then skirtColor=uniform.trousers end
  if dress then shirt=skirtColor end
  trousers=if bareLegs then skin else tights
 end
 if overlay~="none" and overlay~="vest" and jacket==shirt then shirt=SHIRTS[(table.find(SHIRTS,shirt) or 1)%#SHIRTS+1] end
 local sleeve=if overlay=="blazer" or overlay=="cardigan" or overlay=="hoodie" or overlay=="labcoat" then jacket elseif dress and dressRoll<=20 then skin else shirt
 local model=Instance.new("Model");model.ModelStreamingMode=Enum.ModelStreamingMode.Atomic;model.Name="Employee_"..index;model:SetAttribute("OwnerUserId",owner);model:SetAttribute("StaffIndex",index);model:SetAttribute("EmployeeName",name);model:SetAttribute("RoleId",role);model:SetAttribute("Role",job or "Campus Operations");model:SetAttribute("AccessClass","employee");model:SetAttribute("Activity","ARRIVING");model:SetAttribute("PersonalitySeed",seed);model:SetAttribute("StaffAnimated",true)
 model:SetAttribute("Presentation",if feminine then "feminine" else "masculine")
 if profile and profile.k then model:SetAttribute("Skill",profile.k) end
 local count=0
 local function at(x: number,y: number,z: number): CFrame return CFrame.new(x*sx,y*sy,z*sx) end
 local function part(partName: string,size: Vector3,where: CFrame,color: Color3,collide: boolean?,ball: boolean?): Part
  count+=1
  local p=Instance.new("Part");p.Name=partName
  if ball then local d=size.X*math.min(sx,sy);p.Shape=Enum.PartType.Ball;p.Size=Vector3.new(d,d,d) else p.Size=Vector3.new(size.X*sx,size.Y*sy,size.Z*sx) end
  p.CFrame=pose*where;p.Color=color;p.Material=Enum.Material.SmoothPlastic;p.CanCollide=collide==true;p.CanTouch=false;p.Massless=partName~="HumanoidRootPart";p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth;p.Parent=model;return p
 end
 local function fits(n: number): boolean return count+n<=Rig.MAX_PARTS end
 local root=part("HumanoidRootPart",Vector3.new(2,2,1),CFrame.new(),shirt,true);root.Transparency=1;root.Anchored=true;model.PrimaryPart=root
 local torso=part("Torso",Vector3.new(2,2,1),CFrame.new(),shirt,true)
 local head=part("Head",Vector3.new(2,1,1),at(0,1.5,0),skin)
 local mesh=Instance.new("SpecialMesh");mesh.MeshType=Enum.MeshType.Head;mesh.Scale=Vector3.new(1.25,1.25,.96);mesh.Parent=head
 local leftArm=part("Left Arm",Vector3.new(1,2,1),at(-1.5,0,0),sleeve)
 local rightArm=part("Right Arm",Vector3.new(1,2,1),at(1.5,0,0),sleeve)
 local leftLeg=part("Left Leg",Vector3.new(1,2,1),at(-.5,-2,0),trousers)
 local rightLeg=part("Right Leg",Vector3.new(1,2,1),at(.5,-2,0),trousers)
 local function joint(jointName: string,p0: BasePart,p1: BasePart,c0: CFrame,c1: CFrame)
  local m=Instance.new("Motor6D");m.Name=jointName;m.Part0=p0;m.Part1=p1;m.C0=c0;m.C1=c1;m.Parent=p0
 end
 joint("RootJoint",root,torso,CFrame.new(),CFrame.new())
 joint("Neck",torso,head,at(0,1,0),at(0,-.5,0))
 joint("Left Shoulder",torso,leftArm,at(-1,.5,0),at(.5,.5,0))
 joint("Right Shoulder",torso,rightArm,at(1,.5,0),at(-.5,.5,0))
 joint("Left Hip",torso,leftLeg,at(-.5,-1,0),at(0,1,0))
 joint("Right Hip",torso,rightLeg,at(.5,-1,0),at(0,1,0))
 local function accessory(partName: string,size: Vector3,where: CFrame,color: Color3,target: BasePart,material: Enum.Material?,ball: boolean?): Part?
  if not fits(1) then return nil end
  local p=part(partName,size,where,color,false,ball);p.CanQuery=false;if material then p.Material=material end
  local weld=Instance.new("WeldConstraint");weld.Part0=target;weld.Part1=p;weld.Parent=p;return p
 end
 local H=1.5 -- head centre above the root
 for _,side in {-1,1} do
  accessory("Hand",Vector3.new(1.04,.52,1.04),at(side*1.5,-.76,0),skin,if side<0 then leftArm else rightArm)
  accessory("Shoe",Vector3.new(1.04,.36,1.12),at(side*.5,-2.82,-.05),shoes,if side<0 then leftLeg else rightLeg)
 end
 -- Lanyard in the role colour; a tie wearer clips the badge to the chest pocket instead.
 if uniform and uniform.tie then accessory("IDBadge",Vector3.new(.42,.5,.05),at(.55,.42,-.6),rgb(227,230,215),torso)
 else
  accessory("Lanyard",Vector3.new(.09,1.2,.04),at(0,.25,-.58),LANYARD[role] or LANYARD.support,torso)
  accessory("IDBadge",Vector3.new(.46,.56,.05),at(0,-.55,-.6),rgb(227,230,215),torso)
 end
 -- Hair (1-4 parts), built from small blocks and balls. The cap sits on the crown; back pieces stay
 -- behind the face plane so the face is never covered.
 if style=="chef" then
  accessory("ChefHat",Vector3.new(1.22,.8,1.02),at(0,H+.95,0),uniform.hat,head,Enum.Material.Fabric)
  accessory("HairBack",Vector3.new(1.3,.5,.2),at(0,H+.15,.46),hair,head)
 elseif style=="buzz" then accessory("Hair",Vector3.new(1.3,.14,1.0),at(0,H+.6,0),hair:Lerp(skin,.3),head)
 else
  accessory("Hair",Vector3.new(1.34,.3,1.06),at(0,H+.5,.02),hair,head)
  if style=="long" then accessory("LongHair",Vector3.new(1.36,1.45,.26),at(0,H-.3,.44),hair,head)
  elseif style=="bob" then accessory("Bob",Vector3.new(1.42,.82,.96),at(0,H+.08,.14),hair,head)
  elseif style=="braids" then
   accessory("HairBack",Vector3.new(1.3,.62,.2),at(0,H+.12,.46),hair,head)
   for _,side in {-1,1} do accessory("Braid",Vector3.new(.22,1.25,.22),at(side*.42,H-.62,.5),hair,head) end
  elseif style=="curls" then
   if feminine then accessory("CurlsBack",Vector3.new(1.42,.95,.3),at(0,H-.05,.44),hair,head) end
   for i,x in {-.45,.45,0} do accessory("Curl",Vector3.new(.52,.52,.52),at(x,H+.56+(if i==3 then .08 else 0),if i==3 then .36 else .12),hair,head,nil,true) end
  else
   accessory("HairBack",Vector3.new(1.3,.62,.2),at(0,H+.12,.46),hair,head)
   if style=="sidepart" then accessory("SidePart",Vector3.new(.75,.16,1.06),at(.22,H+.68,.02)*CFrame.Angles(0,0,-.14),hair,head)
   elseif style=="bun" then accessory("HairBun",Vector3.new(.62,.62,.62),at(0,H+.5,.62),hair,head,nil,true)
   elseif style=="ponytail" then accessory("Ponytail",Vector3.new(.3,.95,.3),at(0,H-.3,.62),hair,head) end
  end
 end
 -- Role uniform details first so they always fit the part budget.
 if uniform and uniform.cap and fits(3) then
  accessory("PilotCap",Vector3.new(1.42,.42,1.16),at(0,H+.66,.02),uniform.cap,head,Enum.Material.Fabric)
  accessory("CapBand",Vector3.new(1.45,.12,1.19),at(0,H+.5,.02),rgb(212,176,84),head,Enum.Material.Metal)
  accessory("CapVisor",Vector3.new(1.2,.08,.46),at(0,H+.47,-.68),rgb(20,22,26),head)
 end
 if uniform and uniform.tie and fits(1) then accessory("Tie",Vector3.new(.2,1.15,.05),at(0,.25,-.55),uniform.tie,torso) end
 if uniform and uniform.apron then accessory("Apron",Vector3.new(1.5,2.2,.06),at(0,-.6,-.535),uniform.apron,torso,Enum.Material.Fabric) end
 if uniform and uniform.hivis then accessory("HiVis",Vector3.new(1.94,1.3,.06),at(0,-.1,-.535),uniform.hivis,torso,Enum.Material.Fabric) end
 if skirt then accessory("Skirt",Vector3.new(2.14,.6,1.14),at(0,-1.29,0),skirtColor,torso,Enum.Material.Fabric) end
 -- Outfit overlay.
 if overlay=="blazer" and fits(2) then for _,side in {-1,1} do accessory("Blazer",Vector3.new(.66,1.96,.08),at(side*.66,-.01,-.53),jacket,torso,Enum.Material.Fabric) end
 elseif overlay=="cardigan" and fits(2) then for _,side in {-1,1} do accessory("Cardigan",Vector3.new(.6,1.9,.08),at(side*.68,-.03,-.53),jacket,torso,Enum.Material.Fabric) end
 elseif overlay=="labcoat" and fits(2) then for _,side in {-1,1} do accessory("LabCoat",Vector3.new(.88,2.6,.08),at(side*.56,-.3,-.54),jacket,torso,Enum.Material.Fabric) end
 elseif overlay=="hoodie" and fits(2) then
  accessory("Hood",Vector3.new(1.3,.5,.55),at(0,.86,.42),jacket,torso,Enum.Material.Fabric)
  accessory("HoodiePocket",Vector3.new(1.1,.42,.06),at(0,-.55,-.53),jacket:Lerp(Color3.new(0,0,0),.12),torso,Enum.Material.Fabric)
 elseif overlay=="vest" then accessory("Vest",Vector3.new(1.86,1.5,.06),at(0,-.18,-.53),jacket,torso,Enum.Material.Fabric) end
 if headphones and fits(2) then
  accessory("Headphones",Vector3.new(1.38,.12,.24),at(0,H+.68,0),rgb(36,38,42),head)
  accessory("HeadphoneCups",Vector3.new(1.44,.48,.42),at(0,H,.02),rgb(36,38,42),head)
 end
 if glasses and style~="chef" and fits(2) then
  accessory("GlassesFrame",Vector3.new(1.04,.06,.05),at(0,H+.2,-.54),frame,head)
  local lens=accessory("Glasses",Vector3.new(1.0,.26,.04),at(0,H+.06,-.53),if tinted then rgb(40,44,48) else rgb(200,214,212),head)
  if lens then lens.Transparency=if tinted then .3 else .72 end
 end
 if earrings and not headphones and style~="bob" and fits(2) then
  for _,side in {-1,1} do accessory("Earring",Vector3.new(.13,.13,.13),at(side*.64,H-.24,-.02),metal,head,Enum.Material.Metal,true) end
 end
 if not feminine and facial<=38 and fits(1) then
  if facial<=18 then accessory("Beard",Vector3.new(1.0,.32,.14),at(0,H-.47,-.46),hair,head)
  elseif facial<=28 then accessory("ShortBeard",Vector3.new(.9,.18,.1),at(0,H-.48,-.48),hair:Lerp(skin,.35),head)
  else accessory("Moustache",Vector3.new(.42,.08,.06),at(0,H-.1,-.52),hair,head) end
 end
 -- Face: SurfaceGui on the head's front box face (in front of the flattened mesh).
 local face=Instance.new("SurfaceGui");face.Name="Face";face.Face=Enum.NormalId.Front;face.CanvasSize=Vector2.new(200,100);face.LightInfluence=1;face.MaxDistance=40;face.Parent=head
 local spread=24+pick(8)
 for _,side in {-1,1} do
  local x=100+side*spread
  local eye=Instance.new("Frame");eye.Name="Eye";eye.Size=UDim2.fromOffset(8,if feminine then 13 else 12);eye.Position=UDim2.fromOffset(x-4,38);eye.BackgroundColor3=rgb(34,31,28);eye.BorderSizePixel=0;eye.Parent=face
  local b=Instance.new("Frame");b.Name="Brow";b.Size=UDim2.fromOffset(16,if feminine or brow==1 then 2 else 4);b.Position=UDim2.fromOffset(x-8,29);b.Rotation=side*(brow-2)*6;b.BackgroundColor3=hair;b.BorderSizePixel=0;b.Parent=face
 end
 local mouth=Instance.new("TextLabel");mouth.Name="Mouth";mouth.Text=if mouthStyle==1 then "⌣" else "‿";mouth.TextSize=26;mouth.BackgroundTransparency=1;mouth.TextColor3=rgb(67,42,32);mouth.Size=UDim2.fromOffset(60,24);mouth.Position=UDim2.fromOffset(70,56);mouth.Parent=face
 local hum=Instance.new("Humanoid");hum.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None;hum.RigType=Enum.HumanoidRigType.R6;hum.WalkSpeed=Config.personalityFromSeed(seed).walkSpeed;hum.JumpPower=0;hum.JumpHeight=0;hum.BreakJointsOnDeath=false;hum.Parent=model
 local animator=Instance.new("Animator");animator.Parent=hum
 local badge=Instance.new("BillboardGui");badge.Name="EmployeeBadge";badge.Size=UDim2.fromOffset(150,44);badge.StudsOffset=Vector3.new(0,1.5,0);badge.MaxDistance=14;badge.AlwaysOnTop=false;badge.LightInfluence=.4;badge.Parent=head
 local label=Instance.new("TextLabel");label.BackgroundTransparency=1;label.Size=UDim2.fromScale(1,1);label.Text=name.."\n"..(job or "Campus Operations");label.TextColor3=rgb(239,237,224);label.TextSize=12;label.Font=Enum.Font.BuilderSansBold;label.Parent=badge
 local prompt=Instance.new("ProximityPrompt");prompt.Name="EmployeeTalk";prompt.ActionText="Talk";prompt.ObjectText=name;prompt.MaxActivationDistance=10;prompt.RequiresLineOfSight=true;prompt:SetAttribute("OwnerUserId",owner);prompt:SetAttribute("EmployeeTalk",index)
 -- Front-of-house operations staff (reception, security, café, hotel desk) also talk to visitors:
 -- Public prompts are shown to every player (WorldController); TalkService enforces the same rule.
 if role=="support" and Dialogue.isPublicJob(job) then prompt:SetAttribute("Public",true);prompt.ObjectText=name.." · "..tostring(job) end
 prompt.Parent=head
 model.Parent=parent;Collection:AddTag(model,"CompanyEmployee")
 return model
end
return Rig
