import os
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
plan=open(os.path.join(ROOT,'work/src/ReplicatedStorage/Shared/Config/BuildingPlan.module.luau')).read()
lay=open(os.path.join(ROOT,'work/src/ReplicatedStorage/Shared/BuildingLayout.module.luau')).read()
def lb(s):
    lvl=0
    while ']'+'='*lvl+']' in s: lvl+=1
    return '['+'='*lvl+'[',']'+'='*lvl+']'
a,b=lb(plan);c,d=lb(lay)
test=open(os.path.join(ROOT,'tests/layout_test_body.luau')).read()
out=f'''
local V={{}};V.__index=V;V.__unm=function(a) return setmetatable({{X=-a.X,Y=-a.Y,Z=-a.Z}},V) end
V.__add=function(a,b) return setmetatable({{X=a.X+b.X,Y=a.Y+b.Y,Z=a.Z+b.Z}},V) end
V.__sub=function(a,b) return setmetatable({{X=a.X-b.X,Y=a.Y-b.Y,Z=a.Z-b.Z}},V) end
V.__mul=function(a,b) if type(a)=="number" then a,b=b,a end return setmetatable({{X=a.X*b,Y=a.Y*b,Z=a.Z*b}},V) end
Vector3={{new=function(x,y,z) return setmetatable({{X=x or 0,Y=y or 0,Z=z or 0}},V) end}}
local CFM={{}};CFM.__index=CFM;CFM.__mul=function(a,b) return a end
CFrame={{new=function(...) return setmetatable({{...}},CFM) end,Angles=function(...) return setmetatable({{...}},CFM) end}}
local planSrc={a}{plan}{b}
local laySrc={c}{lay}{d}
local planMod=loadstring(planSrc,"BuildingPlan")()
local fakeScript={{Parent={{Config={{BuildingPlan="PLAN"}}}}}}
local f=loadstring(laySrc,"BuildingLayout")
setfenv(f,setmetatable({{script=fakeScript,require=function(x) return planMod end}},{{__index=getfenv()}}))
local Layout=f()
local Plan=planMod
{test}
'''
open(os.path.join(ROOT,'tests/layout_test.luau'),'w').write(out)
