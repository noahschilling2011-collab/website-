-- Layout test: unique rooms, every interior door in a wall segment (0 orphan doors) for plan tiers 0..4.
-- "tier N:" lines are the HQ only (guest house rooms/walls/doors left out) and must equal the numbers the
-- buildings had before the garage stage and the guest house existed; "tier N (+guest house)" adds it.
local pass,fail=0,0
local function check(cond,label) if cond then pass+=1 else fail+=1;print("FAIL  "..label) end end
local BASE={[1]={86,75,220,92,99,22},[2]={106,144,272,112,119,32},[3]={126,195,324,132,139,42},[4]={166,306,428,172,179,62}}
local function annexRoom(tier,id) local r=id and Plan.room(tier,id);return r~=nil and r.annex~=nil end
for tier=0,4 do
  local rooms=Plan.rooms(tier)
  local ids={}
  for _,r in rooms do assert(not ids[r.id],"dup room "..r.id);ids[r.id]=true end
  local stats={hq={0,0,0,0,0,0},all={0,0,0,0,0,0}}
  for _,r in rooms do
    stats.all[1]+=1;stats.all[2]+=(r.desks or 0)
    if not r.annex then stats.hq[1]+=1;stats.hq[2]+=(r.desks or 0) end
  end
  for _,level in Plan.levels(tier) do
    for _,w in Layout.walls(tier,level) do
      local hotelWall=annexRoom(tier,w.plus) or annexRoom(tier,w.minus)
      stats.all[3]+=1;stats.all[4]+=#w.openings
      if not hotelWall then stats.hq[3]+=1;stats.hq[4]+=#w.openings end
    end
    local c=#Layout.circulation(tier,level);stats.all[6]+=c;stats.hq[6]+=c
  end
  local doors=Layout.doors(tier)
  local orphan={}
  for _,d in doors do
    stats.all[5]+=1;if not d.annex then stats.hq[5]+=1 end
    if d.builder=="interior" then
      local found=false
      for _,w in Layout.walls(tier,d.level) do for _,o in w.openings do if o.door==d then found=true end end end
      if not found then table.insert(orphan,d.id..(if d.kind=="opening" then "(opening)" else "")) end
    end
  end
  check(#orphan==0,"tier "..tier.." orphan doors: "..table.concat(orphan,","))
  local h,a=stats.hq,stats.all
  if tier>=1 then
    print(string.format("tier %d: rooms %d desks %d walls %d openings %d doors %d circRects %d orphanDoors %s",tier,h[1],h[2],h[3],h[4],h[5],h[6],table.concat(orphan,",")))
    local b=BASE[tier]
    check(h[1]==b[1] and h[2]==b[2] and h[3]==b[3] and h[4]==b[4] and h[5]==b[5] and h[6]==b[6],"tier "..tier.." HQ layout unchanged")
  end
  if tier<1 or Plan.hasHotel(tier) then
    print(string.format("tier %d (%s): rooms %d desks %d walls %d openings %d doors %d circRects %d",tier,if tier<1 then "garage stage" else "+guest house",a[1],a[2],a[3],a[4],a[5],a[6]))
  end
end
-- garage stage (plan tier 0)
check(Plan.floors(0)==1 and #Plan.levels(0)==1 and Plan.levels(0)[1]==0,"tier 0: one storey")
check(#Plan.liftStops(0)==0,"tier 0: no lift stops")
check(Plan.levelAt(0,-14)==nil and Plan.levelAt(0,1)==0,"tier 0: no B1 level")
check(Plan.theme(0,1)==nil,"tier 0: no work-floor theme")
local desks0=0;for _,r in Plan.rooms(0) do desks0+=(r.desks or 0) end
check(desks0==Plan.GARAGE_STAGE.desks,"tier 0: desks = GARAGE_STAGE.desks ("..desks0..")")
local hasEntrance=false;for _,d in Layout.doors(0) do if d.id=="G_ENTRANCE" then hasEntrance=true end end
check(not hasEntrance,"tier 0: no HQ entrance door")
local ext0=0;for _,d in Layout.doors(0) do if d.builder=="exterior" then ext0+=1 end end
check(ext0==1,"tier 0: one exterior door (side door) built by the exterior")
check(#Layout.circulation(0,0)==0,"tier 0: no HQ circulation")
local sr,sh=Layout.slabs(0,0);check(#sr==1 and #sh==0,"tier 0: one ground slab, no holes")
check(Plan.inside(0,Vector3.new(80,3,-100)) and not Plan.inside(0,Vector3.new(0,3,0)) and not Plan.inside(0,Vector3.new(80,-12,-100)),"tier 0: inside = the garage only")
check(Plan.accessAt(0,Vector3.new(105,3,-86))=="founder","tier 0: founder corner is founder-only")
check(Plan.accessAt(0,Vector3.new(80,3,-100))=="staff" and Plan.accessAt(0,Vector3.new(78,3,-122))=="public","tier 0: lab staff, porch public")
check(Plan.postRoom(0,"assistant")=="G0_ASSIST" and Plan.room(0,"G0_ASSIST")~=nil,"tier 0: assistant post room exists")
check(Plan.postRoom(0,"visitors")=="G0_PORCH" and Plan.room(0,"G0_PORCH")~=nil and Plan.room(0,"G0_PORCH").access=="public","tier 0: public waiting porch")
check(Plan.postRoom(2,"assistant")=="F_ASSIST" and Plan.postRoom(2,"visitors")=="G_VISITOR","HQ posts unchanged")
local vr=Plan.visitorRoute(0);check(Plan.accessAt(0,vr.portal)=="public" and Plan.accessAt(0,vr.exits[1])=="public","tier 0: applicant route stays public")
for _,p in vr.standing do check(Plan.accessAt(0,p)=="public","tier 0: standing spot public") end
local hq=Plan.visitorRoute(1);check(hq.room=="G_VISITOR" and #hq.standing==5 and #hq.exits==4,"HQ applicant route as before")
check(Plan.staffFallback(0).X>Plan.GARAGE_LAB.x1 and Plan.inside(0,Plan.staffFallback(0)),"tier 0: staff fallback inside the garage")
check(Plan.tierForOffice(1)==0 and Plan.tierForOffice(5)==4 and Plan.officeForTier(3)==4,"office index -> plan tier (DATA_VERSION 6: office 1 = garage = plan tier 0)")
-- guest house
check(not Plan.hasHotel(0) and not Plan.hasHotel(1) and Plan.hasHotel(2) and Plan.hasHotel(3) and Plan.hasHotel(4),"guest house from plan tier 2")
for tier=2,4 do
  local n,guest,inside=0,0,true
  local h=Plan.HOTEL
  for _,r in Plan.rooms(tier) do
    if r.annex=="hotel" then
      n+=1;if r.kind=="guestroom" then guest+=1 end
      inside=inside and r.x1>=h.x1 and r.x2<=h.x2 and r.z1>=h.z1 and r.z2<=h.z2
    end
  end
  check(n==22 and guest==Plan.HOTEL_ROOMS and inside,"tier "..tier..": 22 guest house rooms, 12 guest rooms, inside Plan.HOTEL")
  local ext={}
  for _,d in Layout.doors(tier) do if d.annex=="hotel" and d.builder=="exterior" then ext[d.id]=true end end
  check(ext.H0_LOBBY_D1 and ext.H0_CORRIDOR_D1,"tier "..tier..": guest house entrance and terrace doors are exterior doors")
  local _,holes=Layout.slabs(tier,1);local stairHole=false
  for _,ho in holes do if ho.kind=="hotelstair" then stairHole=true end end
  check(stairHole,"tier "..tier..": guest house stair void in the level-1 slab")
end
check(Plan.accessAt(2,Vector3.new(-130,3,123))=="guest","guest room class")
check(Plan.accessAt(2,Vector3.new(-107,3,90))=="public","guest house lobby public")
check(Plan.accessAt(2,Vector3.new(-120,19,120))=="guest","first-floor corridor guest")
check(Plan.inside(2,Vector3.new(-120,19,120)) and not Plan.inside(1,Vector3.new(-120,19,120)),"guest house inside only where it is built")
check(Plan.annexAt(2,Vector3.new(-120,3,100))=="hotel" and Plan.annexAt(2,Vector3.new(0,3,0))==nil,"annexAt")
check(Plan.roleAllows("support","guest") and Plan.roleAllows("guest","guest") and not Plan.roleAllows("researcher","guest") and not Plan.roleAllows("visitor","guest"),"guest clearance")
check(Plan.playerAllows(true,false,"guest") and not Plan.playerAllows(false,true,"guest"),"guest rooms: founder yes, card no")
check(Plan.CLASS_LABEL.guest=="Hotel guests","guest label")
check(Plan.NO_CAMERA.guestroom==true,"no cameras in guest rooms")
-- detail dump for tier 4 level 2 and G
for _,level in {0,2} do
  print("== tier4 level",level)
  for _,w in Layout.walls(4,level) do
    local o={};for _,op in w.openings do table.insert(o,string.format("[%g..%g %s]",op.a1,op.a2,op.door.kind)) end
    print(string.format("%s c=%g %g..%g %s +%s -%s %s",w.axis,w.c,w.a1,w.a2,w.finish,tostring(w.plus),tostring(w.minus),table.concat(o," ")))
  end
end
print("== tier0 walls")
for _,w in Layout.walls(0,0) do
  local o={};for _,op in w.openings do table.insert(o,string.format("[%g..%g %s]",op.a1,op.a2,op.door.kind)) end
  print(string.format("%s c=%g %g..%g %s h=%g +%s -%s %s",w.axis,w.c,w.a1,w.a2,w.finish,w.height,tostring(w.plus),tostring(w.minus),table.concat(o," ")))
end
print(string.format("layout tests: %d passed, %d failed",pass,fail))
