--!nocheck
-- Self-test of the mock: CFrame/Vector3 math against hand-computed values, instance semantics.
-- Run: tools/luau harness/test_mock.luau   (exit code 1 on any failure)
local M = require("./mock")
local G = M.G
local Vector3, CFrame, Instance, Enum, Color3 = G.Vector3, G.CFrame, G.Instance, G.Enum, G.Color3
local typeof = G.typeof
local pi, sin, cos = math.pi, math.sin, math.cos

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else fail += 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end
local function veq(a, b, eps) eps = eps or 1e-9; return (a - b).Magnitude <= eps end
local function cfeq(a, b, eps)
	eps = eps or 1e-9
	local A, B = { a:GetComponents() }, { b:GetComponents() }
	for i = 1, 12 do if math.abs(A[i] - B[i]) > eps then return false end end
	return true
end
local function raises(f, pattern)
	local ok, err = pcall(f)
	return (not ok) and (pattern == nil or tostring(err):find(pattern, 1, true) ~= nil), err
end
-- independent elementary rotations written out by hand (right-handed, column vectors)
local function Rx(a) return CFrame.new(0, 0, 0, 1, 0, 0, 0, cos(a), -sin(a), 0, sin(a), cos(a)) end
local function Ry(a) return CFrame.new(0, 0, 0, cos(a), 0, sin(a), 0, 1, 0, -sin(a), 0, cos(a)) end
local function Rz(a) return CFrame.new(0, 0, 0, cos(a), -sin(a), 0, sin(a), cos(a), 0, 0, 0, 1) end

-- Vector3 -------------------------------------------------------------------
local a, b = Vector3.new(1, 2, 3), Vector3.new(-4, 5, 0.5)
check("v3 add", (a + b) == Vector3.new(-3, 7, 3.5))
check("v3 sub", (a - b) == Vector3.new(5, -3, 2.5))
check("v3 mul num", (a * 2) == Vector3.new(2, 4, 6) and (2 * a) == Vector3.new(2, 4, 6))
check("v3 mul vec", (a * b) == Vector3.new(-4, 10, 1.5))
check("v3 div", (a / 2) == Vector3.new(0.5, 1, 1.5) and (a / Vector3.new(1, 2, 3)) == Vector3.one)
check("v3 unm", (-a) == Vector3.new(-1, -2, -3))
check("v3 dot", a:Dot(b) == -4 + 10 + 1.5)
check("v3 cross", a:Cross(b) == Vector3.new(2 * 0.5 - 3 * 5, 3 * -4 - 1 * 0.5, 1 * 5 - 2 * -4))
check("v3 cross basis", Vector3.xAxis:Cross(Vector3.yAxis) == Vector3.zAxis)
check("v3 magnitude", math.abs(Vector3.new(3, 4, 12).Magnitude - 13) < 1e-12)
check("v3 unit", veq(Vector3.new(3, 4, 12).Unit, Vector3.new(3 / 13, 4 / 13, 12 / 13)))
check("v3 zero unit is NaN", Vector3.zero.Unit.X ~= Vector3.zero.Unit.X)
check("v3 lerp", Vector3.zero:Lerp(Vector3.new(2, 4, 6), 0.5) == Vector3.new(1, 2, 3))
check("v3 min/max", a:Min(b) == Vector3.new(-4, 2, 0.5) and a:Max(b) == Vector3.new(1, 5, 3))
check("v3 abs", b:Abs() == Vector3.new(4, 5, 0.5))
check("v3 fuzzy", a:FuzzyEq(a + Vector3.new(1e-7, 0, 0)) and not a:FuzzyEq(a + Vector3.new(1e-3, 0, 0)))
check("v3 tostring", tostring(Vector3.new(1, 2.5, -3)) == "1, 2.5, -3")
check("v3 add number errors", raises(function() return a + 1 end))
check("v3 immutable", raises(function() a.X = 5 end))
check("v3 typeof", typeof(a) == "Vector3")

-- CFrame basics ------------------------------------------------------------------
check("Angles(0,pi/2,0)*X = -Z", veq(CFrame.Angles(0, pi / 2, 0) * Vector3.new(1, 0, 0), Vector3.new(0, 0, -1), 1e-12))
check("Angles(pi/2,0,0)*Y = Z", veq(CFrame.Angles(pi / 2, 0, 0) * Vector3.new(0, 1, 0), Vector3.new(0, 0, 1), 1e-12))
check("Angles(0,0,pi/2)*X = Y", veq(CFrame.Angles(0, 0, pi / 2) * Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), 1e-12))
check("Ry hand matrix", cfeq(CFrame.Angles(0, 0.7, 0), Ry(0.7)))
check("Rx hand matrix", cfeq(CFrame.Angles(0.7, 0, 0), Rx(0.7)))
check("Rz hand matrix", cfeq(CFrame.Angles(0, 0, 0.7), Rz(0.7)))
for _, t in { { 0.3, 0.5, 0.7 }, { -1.2, 2.9, 0.1 }, { 3, -0.4, -2.2 } } do
	local x, y, z = t[1], t[2], t[3]
	check("Angles = Rx*Ry*Rz " .. x, cfeq(CFrame.Angles(x, y, z), Rx(x) * Ry(y) * Rz(z), 1e-12))
	check("fromEulerAnglesXYZ alias " .. x, cfeq(CFrame.fromEulerAnglesXYZ(x, y, z), CFrame.Angles(x, y, z)))
	check("YXZ = Ry*Rx*Rz " .. x, cfeq(CFrame.fromEulerAnglesYXZ(x, y, z), Ry(y) * Rx(x) * Rz(z), 1e-12))
	check("fromOrientation = YXZ " .. x, cfeq(CFrame.fromOrientation(x, y, z), CFrame.fromEulerAnglesYXZ(x, y, z)))
	local ex, ey, ez = CFrame.Angles(x, y, z):ToEulerAnglesXYZ()
	check("ToEulerAnglesXYZ round trip " .. x, cfeq(CFrame.Angles(ex, ey, ez), CFrame.Angles(x, y, z), 1e-9))
	local ox, oy, oz = CFrame.fromOrientation(x, y, z):ToOrientation()
	check("ToOrientation round trip " .. x, cfeq(CFrame.fromOrientation(ox, oy, oz), CFrame.fromOrientation(x, y, z), 1e-9))
	check("fromEulerAngles(order YXZ) " .. x, cfeq(CFrame.fromEulerAngles(x, y, z, Enum.RotationOrder.YXZ), CFrame.fromEulerAnglesYXZ(x, y, z), 1e-12))
end
check("ToEulerAnglesXYZ simple values", (function()
	local x, y, z = CFrame.Angles(0.1, 0.2, 0.3):ToEulerAnglesXYZ()
	return math.abs(x - 0.1) < 1e-12 and math.abs(y - 0.2) < 1e-12 and math.abs(z - 0.3) < 1e-12
end)())
local cf = CFrame.new(10, -3, 7) * CFrame.Angles(0.4, -1.1, 2.0)
check("identity", cfeq(CFrame.new(), CFrame.identity) and cfeq(CFrame.new(), CFrame.new(0, 0, 0)))
check("new(pos)", cfeq(CFrame.new(Vector3.new(1, 2, 3)), CFrame.new(1, 2, 3)))
check("Position/X/Y/Z", cf.Position == Vector3.new(10, -3, 7) and cf.X == 10 and cf.Y == -3 and cf.Z == 7)
check("cf * cf:Inverse() = I", cfeq(cf * cf:Inverse(), CFrame.identity, 1e-12))
check("cf:Inverse() * cf = I", cfeq(cf:Inverse() * cf, CFrame.identity, 1e-12))
local p = Vector3.new(3, -8, 2.5)
check("PointToObjectSpace(PointToWorldSpace)", veq(cf:PointToObjectSpace(cf:PointToWorldSpace(p)), p, 1e-12))
check("PointToWorldSpace = cf*v", veq(cf:PointToWorldSpace(p), cf * p))
check("PointToObjectSpace = inv*v", veq(cf:PointToObjectSpace(p), cf:Inverse() * p, 1e-12))
check("VectorToWorldSpace ignores translation", veq(cf:VectorToWorldSpace(p), cf.Rotation * p, 1e-12))
check("VectorToObjectSpace round trip", veq(cf:VectorToObjectSpace(cf:VectorToWorldSpace(p)), p, 1e-12))
local cf2 = CFrame.new(-5, 1, 2) * CFrame.Angles(1, 2, 3)
check("ToObjectSpace = inv*cf2", cfeq(cf:ToObjectSpace(cf2), cf:Inverse() * cf2, 1e-12))
check("ToWorldSpace(ToObjectSpace)", cfeq(cf:ToWorldSpace(cf:ToObjectSpace(cf2)), cf2, 1e-12))
check("multi-arg PointToWorldSpace", (function() local x, y = cf:PointToWorldSpace(p, Vector3.zero); return veq(x, cf * p) and veq(y, cf.Position) end)())
check("cf + v", cfeq(cf + Vector3.new(1, 2, 3), CFrame.new(11, -1, 10) * cf.Rotation, 1e-12))
check("cf - v", cfeq(cf - Vector3.new(1, 2, 3), CFrame.new(9, -5, 4) * cf.Rotation, 1e-12))
check("translation composes", (CFrame.new(1, 0, 0) * CFrame.new(0, 2, 0)).Position == Vector3.new(1, 2, 0))
check("rotation then offset", veq((CFrame.Angles(0, pi / 2, 0) * CFrame.new(0, 0, -5)).Position, Vector3.new(-5, 0, 0), 1e-12))
check("LookVector is -Z column", veq(CFrame.Angles(0, pi / 2, 0).LookVector, Vector3.new(-1, 0, 0), 1e-12))
check("RightVector/XVector", veq(cf.RightVector, cf.XVector) and veq(cf.RightVector, cf:VectorToWorldSpace(Vector3.xAxis), 1e-12))
check("UpVector/YVector", veq(cf.UpVector, cf.YVector) and veq(cf.UpVector, cf:VectorToWorldSpace(Vector3.yAxis), 1e-12))
check("ZVector = -LookVector", veq(cf.ZVector, -cf.LookVector))
check("Rotation has no translation", cf.Rotation.Position == Vector3.zero)
check("components count", select("#", cf:GetComponents()) == 12)

-- lookAt family -----------------------------------------------------------------
local la = CFrame.lookAt(Vector3.new(160, 24, 252), Vector3.new(160, 24, 0))
check("lookAt plot = identity rotation", cfeq(la, CFrame.new(160, 24, 252), 1e-12))
local lb = CFrame.lookAt(Vector3.new(160, 24, -252), Vector3.new(160, 24, 0))
check("lookAt facing +Z = Ry(pi)", cfeq(lb, CFrame.new(160, 24, -252) * CFrame.Angles(0, pi, 0), 1e-12))
local lx = CFrame.lookAt(Vector3.zero, Vector3.new(5, 0, 0))
check("lookAt +X look", veq(lx.LookVector, Vector3.xAxis, 1e-12) and veq(lx.RightVector, Vector3.zAxis, 1e-12) and veq(lx.UpVector, Vector3.yAxis, 1e-12))
local tgt = Vector3.new(3, 4, -12)
local l3 = CFrame.lookAt(Vector3.new(1, 1, 1), tgt)
check("lookAt general look", veq(l3.LookVector, (tgt - Vector3.new(1, 1, 1)).Unit, 1e-12))
check("lookAt right is horizontal", math.abs(l3.RightVector.Y) < 1e-12)
check("lookAt orthonormal", math.abs(l3.RightVector:Dot(l3.UpVector)) < 1e-12 and math.abs(l3.RightVector:Cross(l3.UpVector):Dot(l3.ZVector) - 1) < 1e-12)
check("new(pos, lookAt) = lookAt", cfeq(CFrame.new(Vector3.new(1, 1, 1), tgt), l3, 1e-12))
check("lookAt straight down finite", (function() local c = CFrame.lookAt(Vector3.zero, Vector3.new(0, -10, 0)); local x = c.RightVector.X; return x == x and veq(c.LookVector, -Vector3.yAxis, 1e-12) end)())
check("lookAlong", cfeq(CFrame.lookAlong(Vector3.new(1, 1, 1), tgt - Vector3.new(1, 1, 1)), l3, 1e-12))

-- other constructors --------------------------------------------------------------
check("fromAxisAngle Y", cfeq(CFrame.fromAxisAngle(Vector3.yAxis, 0.9), CFrame.Angles(0, 0.9, 0), 1e-12))
check("fromAxisAngle X unnormalized", cfeq(CFrame.fromAxisAngle(Vector3.new(3, 0, 0), -0.4), CFrame.Angles(-0.4, 0, 0), 1e-12))
local ax, ang = CFrame.fromAxisAngle(Vector3.new(1, 2, 2), 1.3):ToAxisAngle()
check("ToAxisAngle", veq(ax, Vector3.new(1, 2, 2).Unit, 1e-9) and math.abs(ang - 1.3) < 1e-9)
check("fromMatrix", cfeq(CFrame.fromMatrix(cf.Position, cf.RightVector, cf.UpVector), cf, 1e-12))
check("fromMatrix with Z", cfeq(CFrame.fromMatrix(cf.Position, cf.RightVector, cf.UpVector, cf.ZVector), cf, 1e-12))
check("quaternion new", cfeq(CFrame.new(0, 0, 0, 0, sin(pi / 4), 0, cos(pi / 4)), CFrame.Angles(0, pi / 2, 0), 1e-12))
check("Lerp half", cfeq(CFrame.new():Lerp(CFrame.new(2, 0, 0) * CFrame.Angles(0, pi / 2, 0), 0.5), CFrame.new(1, 0, 0) * CFrame.Angles(0, pi / 4, 0), 1e-9))
check("Lerp ends", cfeq(cf:Lerp(cf2, 0), cf, 1e-9) and cfeq(cf:Lerp(cf2, 1), cf2, 1e-9))
check("cf == same", CFrame.new(1, 2, 3) == CFrame.new(1, 2, 3) and CFrame.new(1, 2, 3) ~= CFrame.new(1, 2, 4))
check("cf * number errors", raises(function() return cf * 2 end))
check("Orthonormalize", cfeq(CFrame.new(0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 1):Orthonormalize(), CFrame.identity, 1e-12))
check("fromRotationBetweenVectors", veq(CFrame.fromRotationBetweenVectors(Vector3.xAxis, Vector3.yAxis) * Vector3.xAxis, Vector3.yAxis, 1e-12))

-- Color3 / enums / typeof -----------------------------------------------------------
local c = Color3.fromRGB(255, 128, 0)
check("fromRGB", math.abs(c.R - 1) < 1e-12 and math.abs(c.G - 128 / 255) < 1e-12 and c.B == 0)
local h, s2, v = c:ToHSV()
check("HSV round trip", (function() local d = Color3.fromHSV(h, s2, v); return math.abs(d.R - c.R) < 1e-9 and math.abs(d.G - c.G) < 1e-9 and math.abs(d.B - c.B) < 1e-9 end)())
check("Color3 lerp", Color3.new(0, 0, 0):Lerp(Color3.new(1, 1, 1), 0.25) == Color3.new(0.25, 0.25, 0.25))
check("ToHex", c:ToHex() == "FF8000")
check("enum item", tostring(Enum.Material.Wood) == "Enum.Material.Wood" and Enum.Material.Wood.Name == "Wood" and typeof(Enum.Material.Wood) == "EnumItem")
check("enum FromName/Value", Enum.Material:FromName("Wood") == Enum.Material.Wood and Enum.Material:FromValue(Enum.Material.Wood.Value) == Enum.Material.Wood)
check("enum stable identity", Enum.NormalId.Front == Enum.NormalId.Front)
check("bad enum errors", raises(function() return Enum.Material.Woood end, "not a valid member"))
check("typeof datatypes", typeof(cf) == "CFrame" and typeof(c) == "Color3" and typeof(G.UDim2.new()) == "UDim2" and typeof(1) == "number" and typeof(Enum.Material) == "Enum")

-- Instances ----------------------------------------------------------------------------
local part = Instance.new("Part")
check("defaults", part.Name == "Part" and part.Size == Vector3.new(4, 1, 2) and part.Anchored == false and part.CanCollide == true and part.Transparency == 0)
part.CFrame = CFrame.new(1, 2, 3) * CFrame.Angles(0, 0.5, 0)
part.Position = Vector3.new(7, 8, 9)
check("Position keeps rotation", cfeq(part.CFrame, CFrame.new(7, 8, 9) * CFrame.Angles(0, 0.5, 0), 1e-12))
part.Orientation = Vector3.new(10, 20, 30)
check("Orientation set/get", veq(part.Orientation, Vector3.new(10, 20, 30), 1e-9) and part.Position == Vector3.new(7, 8, 9))
check("Orientation is YXZ degrees", cfeq(part.CFrame.Rotation, CFrame.fromOrientation(math.rad(10), math.rad(20), math.rad(30)), 1e-12))
check("unknown property errors", raises(function() part.Colour = c end, "not a valid member"))
check("wrong type errors", raises(function() part.Size = 3 end, "Vector3 expected"))
check("enum by string", (function() part.Material = "Neon"; return part.Material == Enum.Material.Neon end)())
check("wrong enum type errors", raises(function() part.Material = Enum.Font.Arial end, "EnumItem of type Material"))
check("read-only errors", raises(function() part.ClassName = "X" end))
check("Size clamp", (function() part.Size = Vector3.new(0, 1, 5000); return part.Size == Vector3.new(0.001, 1, 2048) end)())
check("bad method call style", raises(function() return part.GetChildren() end, "Expected ':'"))
check("Instance.new bad class", raises(function() Instance.new("Partt") end, "Unable to create"))
check("Instance.new abstract class", raises(function() Instance.new("BasePart") end, "Unable to create"))
check("IsA chain", part:IsA("Part") and part:IsA("BasePart") and part:IsA("PVInstance") and part:IsA("Instance") and not part:IsA("Model"))
local seat = Instance.new("Seat")
check("Seat IsA Part", seat:IsA("Part") and seat:IsA("BasePart") and seat.Disabled == false)

local model = Instance.new("Model")
model.Name = "M"
local p1 = Instance.new("Part"); p1.Name = "A"; p1.Size = Vector3.new(2, 2, 2); p1.CFrame = CFrame.new(0, 1, 0); p1.Parent = model
local p2 = Instance.new("Part"); p2.Name = "B"; p2.Size = Vector3.new(2, 2, 2); p2.CFrame = CFrame.new(10, 1, 0) * CFrame.Angles(0, pi / 4, 0); p2.Parent = model
local folder = Instance.new("Folder"); folder.Parent = model
local p3 = Instance.new("WedgePart"); p3.Name = "C"; p3.CFrame = CFrame.new(5, 5, 5); p3.Parent = folder
check("children/descendants", #model:GetChildren() == 3 and #model:GetDescendants() == 4)
check("FindFirstChild", model:FindFirstChild("A") == p1 and model:FindFirstChild("C") == nil and model:FindFirstChild("C", true) == p3)
check("child by dot", model.A == p1 and folder.C == p3)
check("FindFirstChildWhichIsA", model:FindFirstChildWhichIsA("BasePart") == p1 and folder:FindFirstChildOfClass("WedgePart") == p3)
check("FindFirstAncestor", p3:FindFirstAncestor("M") == model and p3:FindFirstAncestorWhichIsA("Model") == model and p3:FindFirstAncestorOfClass("Folder") == folder)
check("IsDescendantOf", p3:IsDescendantOf(model) and not model:IsDescendantOf(p3))
check("circular parent errors", raises(function() model.Parent = folder end, "circular"))
-- pivot: bounding-box centre until WorldPivot set
local piv0 = model:GetPivot()
check("pivot = bbox centre", veq(piv0.Position, Vector3.new((-1 + 10 + math.sqrt(2)) / 2, 2.75, (6 - math.sqrt(2)) / 2), 1e-9) and cfeq(piv0.Rotation, CFrame.identity), piv0)
model.PrimaryPart = p1
check("pivot = PrimaryPart", cfeq(model:GetPivot(), p1.CFrame))
local before2 = p1.CFrame:ToObjectSpace(p2.CFrame)
local before3 = p1.CFrame:ToObjectSpace(p3.CFrame)
local target = CFrame.new(100, 50, -20) * CFrame.Angles(0.2, 1.3, -0.4)
model:PivotTo(target)
check("PivotTo moves PrimaryPart", cfeq(p1.CFrame, target, 1e-9))
check("PivotTo rigid", cfeq(p1.CFrame:ToObjectSpace(p2.CFrame), before2, 1e-9) and cfeq(p1.CFrame:ToObjectSpace(p3.CFrame), before3, 1e-9))
local bbcf, bbsize = model:GetBoundingBox()
check("GetBoundingBox oriented like pivot", cfeq(bbcf.Rotation, target.Rotation, 1e-9) and bbsize.X > 0)
-- bounding box of a single rotated part in a model without PrimaryPart
local m2 = Instance.new("Model")
local q = Instance.new("Part"); q.Size = Vector3.new(4, 2, 2); q.CFrame = CFrame.new(1, 1, 1) * CFrame.Angles(0, pi / 2, 0); q.Parent = m2
local bcf, bsz = m2:GetBoundingBox()
check("bbox world aligned", veq(bsz, Vector3.new(2, 2, 4), 1e-9) and veq(bcf.Position, Vector3.new(1, 1, 1), 1e-9))
m2.WorldPivot = CFrame.new(0, 0, 0)
m2:PivotTo(CFrame.new(10, 0, 0))
check("WorldPivot PivotTo", veq(q.Position, Vector3.new(11, 1, 1), 1e-9) and m2.WorldPivot == CFrame.new(10, 0, 0))
-- part pivot
local r = Instance.new("Part"); r.CFrame = CFrame.new(3, 3, 3)
r:PivotTo(CFrame.new(0, 10, 0))
check("BasePart PivotTo", r.Position == Vector3.new(0, 10, 0))
-- clone
p1:SetAttribute("Tag", 5)
G.game:GetService("CollectionService"):AddTag(p1, "T")
local mc = model:Clone()
check("Clone deep", #mc:GetDescendants() == 4 and mc.Parent == nil and mc ~= model)
check("Clone remaps PrimaryPart", mc.PrimaryPart == mc.A and mc.PrimaryPart ~= p1)
check("Clone copies attributes/tags", mc.A:GetAttribute("Tag") == 5 and mc.A:HasTag("T"))
-- attributes
check("attribute table errors", raises(function() p1:SetAttribute("X", {}) end, "not a supported attribute type"))
check("attribute bad name errors", raises(function() p1:SetAttribute("bad name", 1) end, "invalid"))
p1:SetAttribute("V", Vector3.new(1, 2, 3)); p1:SetAttribute("CF", target)
check("attribute roundtrip", p1:GetAttribute("V") == Vector3.new(1, 2, 3) and p1:GetAttribute("CF") == target and p1:GetAttributes().Tag == 5)
p1:SetAttribute("Tag", nil)
check("attribute remove", p1:GetAttribute("Tag") == nil)
-- destroy
local d = Instance.new("Part"); d.Parent = model
d:Destroy()
check("Destroy unparents", d.Parent == nil and model:FindFirstChild("Part") == nil)
check("Destroy locks Parent", raises(function() d.Parent = model end, "locked"))
-- tagged
local tagged = G.game:GetService("CollectionService"):GetTagged("T")
check("GetTagged only in DataModel", #tagged == 0)
model.Parent = G.workspace
check("GetTagged after parenting", #G.game:GetService("CollectionService"):GetTagged("T") == 1)
-- services / tree
check("GetService singleton", G.game:GetService("ReplicatedStorage") == G.game.ReplicatedStorage)
check("bad service errors", raises(function() G.game:GetService("NotAService") end, "not a valid Service"))
check("workspace", G.workspace == G.game:GetService("Workspace") and G.workspace.CurrentCamera ~= nil)
-- signals and task
local fired = 0
local conn = p1:GetPropertyChangedSignal("Transparency"):Connect(function() fired += 1 end)
p1.Transparency = 0.5
p1.Transparency = 0.5
conn:Disconnect()
p1.Transparency = 0.2
check("property changed signal", fired == 1)
local order = {}
local ok, res = M.runMain(function()
	G.task.defer(function() table.insert(order, "defer") end)
	G.task.delay(0.5, function() table.insert(order, "delay") end)
	G.task.spawn(function() table.insert(order, "spawn") end)
	local dt = G.task.wait(1)
	table.insert(order, "wait")
	return dt
end)
check("runMain + task order", ok and table.concat(order, ",") == "spawn,defer,delay,wait" and res >= 1, table.concat(order, ","))
-- tween applies goal immediately
local tw = G.game:GetService("TweenService"):Create(p1, G.TweenInfo.new(1), { Transparency = 0.9 })
tw:Play()
check("tween applies goal", p1.Transparency == 0.9)
-- JSON
check("json", M.JSON.encode({ a = 1, b = { true, "x\"y\n" } }) == '{"a":1,"b":[true,"x\\"y\\n"]}')
check("json num", M.JSON.num(0.1) == "0.1" and M.JSON.num(-2.5) == "-2.5" and M.JSON.num(0 / 0) == "NaN")

print(string.format("test_mock: %d passed, %d failed", pass, fail))
if fail > 0 then error("test_mock failed", 0) end
