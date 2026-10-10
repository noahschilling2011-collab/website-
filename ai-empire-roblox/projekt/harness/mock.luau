--!nocheck
-- Headless Roblox API mock for running the building generator modules offline.
-- Faithfulness rules (see README): unknown members / wrong property types / bad enum
-- names raise errors like Roblox does; members that exist in the API dump but are not
-- implemented here return no-op stubs and are logged once ("[mock:stub] ...").
local API = require("./classes")

local rawtype, rawtypeof, rawprint = type, typeof, print
local fmt, floor, ceil, sqrt, abs = string.format, math.floor, math.ceil, math.sqrt, math.abs
local sin, cos, atan2, asin, acos, huge, pi = math.sin, math.cos, math.atan2, math.asin, math.acos, math.huge, math.pi
local mmin, mmax = math.min, math.max
local freeze, tinsert, tremove, tsort, tclone, tconcat = table.freeze, table.insert, table.remove, table.sort, table.clone, table.concat
local unpack, pack = table.unpack, table.pack
local BUILTINS = getfenv(0)

local M = {}
M.stats = { errors = 0, warnings = 0, stubs = {}, logs = 0 }
M.quiet = false

local function log(kind, msg)
	M.stats.logs += 1
	rawprint("[mock:" .. kind .. "] " .. tostring(msg))
end
M.log = log
local onceSeen = {}
local function once(key, msg)
	if onceSeen[key] then return end
	onceSeen[key] = true
	log("once", msg)
end
M.once = once

---------------------------------------------------------------------------
-- Type registry
---------------------------------------------------------------------------
local TYPES = {}
local function newType(name)
	local mt = { __type = name }
	TYPES[name] = mt
	return mt
end
local function tname(v)
	if rawtype(v) == "table" then
		local mt = getmetatable(v)
		if rawtype(mt) == "table" then
			local n = rawget(mt, "__type")
			if n then return n end
		end
	end
	return rawtypeof(v)
end
M.typeof = tname
local function robloxType(v)
	if rawtype(v) == "table" then
		local mt = getmetatable(v)
		if rawtype(mt) == "table" and rawget(mt, "__type") then return "userdata" end
	end
	return rawtype(v)
end
local function argErr(fn, i, expected, got)
	error(fmt("invalid argument #%d to '%s' (%s expected, got %s)", i, fn, expected, tname(got)), 3)
end

---------------------------------------------------------------------------
-- Vector3
---------------------------------------------------------------------------
local V3mt = newType("Vector3")
local function V(x, y, z) return freeze(setmetatable({ X = x, Y = y, Z = z }, V3mt)) end
local function isV3(v) return getmetatable(v) == V3mt end
M.V = V
M.isV3 = isV3
local V3m = {}
function V3m.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function V3m.Cross(a, b) return V(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
function V3m.Lerp(a, b, t) return V(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t) end
V3m.lerp = V3m.Lerp
function V3m.Min(a, ...)
	local x, y, z = a.X, a.Y, a.Z
	for i = 1, select("#", ...) do local b = select(i, ...); x, y, z = mmin(x, b.X), mmin(y, b.Y), mmin(z, b.Z) end
	return V(x, y, z)
end
function V3m.Max(a, ...)
	local x, y, z = a.X, a.Y, a.Z
	for i = 1, select("#", ...) do local b = select(i, ...); x, y, z = mmax(x, b.X), mmax(y, b.Y), mmax(z, b.Z) end
	return V(x, y, z)
end
function V3m.Abs(a) return V(abs(a.X), abs(a.Y), abs(a.Z)) end
function V3m.Floor(a) return V(floor(a.X), floor(a.Y), floor(a.Z)) end
function V3m.Ceil(a) return V(ceil(a.X), ceil(a.Y), ceil(a.Z)) end
function V3m.Sign(a) return V(math.sign(a.X), math.sign(a.Y), math.sign(a.Z)) end
function V3m.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	return abs(a.X - b.X) <= eps and abs(a.Y - b.Y) <= eps and abs(a.Z - b.Z) <= eps
end
function V3m.Angle(a, b, axis)
	local c = V3m.Cross(a, b)
	local ang = atan2(sqrt(c.X * c.X + c.Y * c.Y + c.Z * c.Z), V3m.Dot(a, b))
	if axis and V3m.Dot(c, axis) < 0 then ang = -ang end
	return ang
end
V3mt.__index = function(v, k)
	local m = V3m[k]
	if m then return m end
	if k == "Magnitude" or k == "magnitude" then return sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
	if k == "Unit" or k == "unit" then
		local m2 = sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return V(v.X / m2, v.Y / m2, v.Z / m2) -- zero vector -> NaN like Roblox
	end
	if k == "x" then return v.X elseif k == "y" then return v.Y elseif k == "z" then return v.Z end
	error(fmt("%s is not a valid member of Vector3", tostring(k)), 2)
end
V3mt.__add = function(a, b)
	if isV3(a) and isV3(b) then return V(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
	error(fmt("attempt to perform arithmetic (add) on %s and %s", tname(a), tname(b)), 2)
end
V3mt.__sub = function(a, b)
	if isV3(a) and isV3(b) then return V(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
	error(fmt("attempt to perform arithmetic (sub) on %s and %s", tname(a), tname(b)), 2)
end
V3mt.__mul = function(a, b)
	if rawtype(b) == "number" then return V(a.X * b, a.Y * b, a.Z * b) end
	if rawtype(a) == "number" then return V(a * b.X, a * b.Y, a * b.Z) end
	if isV3(a) and isV3(b) then return V(a.X * b.X, a.Y * b.Y, a.Z * b.Z) end
	error(fmt("attempt to perform arithmetic (mul) on %s and %s", tname(a), tname(b)), 2)
end
V3mt.__div = function(a, b)
	if isV3(a) then
		if rawtype(b) == "number" then return V(a.X / b, a.Y / b, a.Z / b) end
		if isV3(b) then return V(a.X / b.X, a.Y / b.Y, a.Z / b.Z) end
	end
	error(fmt("attempt to perform arithmetic (div) on %s and %s", tname(a), tname(b)), 2)
end
V3mt.__idiv = function(a, b)
	if isV3(a) then
		if rawtype(b) == "number" then return V(floor(a.X / b), floor(a.Y / b), floor(a.Z / b)) end
		if isV3(b) then return V(floor(a.X / b.X), floor(a.Y / b.Y), floor(a.Z / b.Z)) end
	end
	error(fmt("attempt to perform arithmetic (idiv) on %s and %s", tname(a), tname(b)), 2)
end
V3mt.__unm = function(a) return V(-a.X, -a.Y, -a.Z) end
V3mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3mt.__tostring = function(a) return tostring(a.X) .. ", " .. tostring(a.Y) .. ", " .. tostring(a.Z) end
local Vector3 = {}
function Vector3.new(x, y, z) return V(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0) end
Vector3.zero = V(0, 0, 0)
Vector3.one = V(1, 1, 1)
Vector3.xAxis = V(1, 0, 0)
Vector3.yAxis = V(0, 1, 0)
Vector3.zAxis = V(0, 0, 1)
local NORMALS = { Right = V(1, 0, 0), Left = V(-1, 0, 0), Top = V(0, 1, 0), Bottom = V(0, -1, 0), Back = V(0, 0, 1), Front = V(0, 0, -1) }
function Vector3.FromNormalId(n) return NORMALS[n.Name] end
Vector3.fromNormalId = Vector3.FromNormalId
function Vector3.FromAxis(a) return ({ X = V(1, 0, 0), Y = V(0, 1, 0), Z = V(0, 0, 1) })[a.Name] end
Vector3.fromAxis = Vector3.FromAxis
function Vector3.min(a, ...) return V3m.Min(a, ...) end
function Vector3.max(a, ...) return V3m.Max(a, ...) end
freeze(Vector3)

---------------------------------------------------------------------------
local V2, isV2, Vector2, Vector3int16, Vector2int16
do
-- Vector2
---------------------------------------------------------------------------
local V2mt = newType("Vector2")
function V2(x, y) return freeze(setmetatable({ X = x, Y = y }, V2mt)) end
function isV2(v) return getmetatable(v) == V2mt end
local V2m = {}
function V2m.Dot(a, b) return a.X * b.X + a.Y * b.Y end
function V2m.Cross(a, b) return a.X * b.Y - a.Y * b.X end
function V2m.Lerp(a, b, t) return V2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t) end
V2m.lerp = V2m.Lerp
function V2m.Abs(a) return V2(abs(a.X), abs(a.Y)) end
function V2m.Floor(a) return V2(floor(a.X), floor(a.Y)) end
function V2m.Ceil(a) return V2(ceil(a.X), ceil(a.Y)) end
function V2m.Sign(a) return V2(math.sign(a.X), math.sign(a.Y)) end
function V2m.Min(a, ...) local x, y = a.X, a.Y; for i = 1, select("#", ...) do local b = select(i, ...); x, y = mmin(x, b.X), mmin(y, b.Y) end; return V2(x, y) end
function V2m.Max(a, ...) local x, y = a.X, a.Y; for i = 1, select("#", ...) do local b = select(i, ...); x, y = mmax(x, b.X), mmax(y, b.Y) end; return V2(x, y) end
function V2m.FuzzyEq(a, b, eps) eps = eps or 1e-5; return abs(a.X - b.X) <= eps and abs(a.Y - b.Y) <= eps end
function V2m.Angle(a, b, signed) local ang = atan2(V2m.Cross(a, b), V2m.Dot(a, b)); if signed then return ang end; return abs(ang) end
V2mt.__index = function(v, k)
	local m = V2m[k]
	if m then return m end
	if k == "Magnitude" or k == "magnitude" then return sqrt(v.X * v.X + v.Y * v.Y) end
	if k == "Unit" or k == "unit" then local m2 = sqrt(v.X * v.X + v.Y * v.Y); return V2(v.X / m2, v.Y / m2) end
	if k == "x" then return v.X elseif k == "y" then return v.Y end
	error(fmt("%s is not a valid member of Vector2", tostring(k)), 2)
end
V2mt.__add = function(a, b) if isV2(a) and isV2(b) then return V2(a.X + b.X, a.Y + b.Y) end; error("attempt to perform arithmetic (add) on " .. tname(a) .. " and " .. tname(b), 2) end
V2mt.__sub = function(a, b) if isV2(a) and isV2(b) then return V2(a.X - b.X, a.Y - b.Y) end; error("attempt to perform arithmetic (sub) on " .. tname(a) .. " and " .. tname(b), 2) end
V2mt.__mul = function(a, b)
	if rawtype(b) == "number" then return V2(a.X * b, a.Y * b) end
	if rawtype(a) == "number" then return V2(a * b.X, a * b.Y) end
	if isV2(a) and isV2(b) then return V2(a.X * b.X, a.Y * b.Y) end
	error("attempt to perform arithmetic (mul) on " .. tname(a) .. " and " .. tname(b), 2)
end
V2mt.__div = function(a, b)
	if rawtype(b) == "number" then return V2(a.X / b, a.Y / b) end
	if isV2(a) and isV2(b) then return V2(a.X / b.X, a.Y / b.Y) end
	error("attempt to perform arithmetic (div) on " .. tname(a) .. " and " .. tname(b), 2)
end
V2mt.__unm = function(a) return V2(-a.X, -a.Y) end
V2mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
V2mt.__tostring = function(a) return tostring(a.X) .. ", " .. tostring(a.Y) end
Vector2 = {}
function Vector2.new(x, y) return V2(tonumber(x) or 0, tonumber(y) or 0) end
Vector2.zero = V2(0, 0)
Vector2.one = V2(1, 1)
Vector2.xAxis = V2(1, 0)
Vector2.yAxis = V2(0, 1)
function Vector2.min(a, ...) return V2m.Min(a, ...) end
function Vector2.max(a, ...) return V2m.Max(a, ...) end
freeze(Vector2)

-- int16 variants (rarely used): plain integer vectors
local V3i16mt = newType("Vector3int16")
V3i16mt.__index = function(_, k) error(tostring(k) .. " is not a valid member of Vector3int16", 2) end
Vector3int16 = { new = function(x, y, z) return freeze(setmetatable({ X = floor(tonumber(x) or 0), Y = floor(tonumber(y) or 0), Z = floor(tonumber(z) or 0) }, V3i16mt)) end }
local V2i16mt = newType("Vector2int16")
V2i16mt.__index = function(_, k) error(tostring(k) .. " is not a valid member of Vector2int16", 2) end
Vector2int16 = { new = function(x, y) return freeze(setmetatable({ X = floor(tonumber(x) or 0), Y = floor(tonumber(y) or 0) }, V2i16mt)) end }

end
---------------------------------------------------------------------------
-- CFrame: array {x,y,z, R00,R01,R02, R10,R11,R12, R20,R21,R22}
-- Columns of R are RightVector (X), UpVector (Y), and Back (Z = -LookVector).
---------------------------------------------------------------------------
local C, isCF, IDENTITY, cfmul, cfinv, cfpoint, cfvector, cfpointInv, cfvectorInv, rotXYZ, rotYXZ, CFm, CFrame, CFmt, matToQuat
do
CFmt = newType("CFrame")
function C(x, y, z, a, b, c, d, e, f, g, h, i)
	return freeze(setmetatable({ x, y, z, a, b, c, d, e, f, g, h, i }, CFmt))
end
function isCF(v) return getmetatable(v) == CFmt end
M.C = C
M.isCF = isCF
IDENTITY = C(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
M.IDENTITY = IDENTITY
function cfmul(A, B)
	local a4, a5, a6, a7, a8, a9, a10, a11, a12 = A[4], A[5], A[6], A[7], A[8], A[9], A[10], A[11], A[12]
	local b1, b2, b3 = B[1], B[2], B[3]
	local b4, b5, b6, b7, b8, b9, b10, b11, b12 = B[4], B[5], B[6], B[7], B[8], B[9], B[10], B[11], B[12]
	return C(
		A[1] + a4 * b1 + a5 * b2 + a6 * b3,
		A[2] + a7 * b1 + a8 * b2 + a9 * b3,
		A[3] + a10 * b1 + a11 * b2 + a12 * b3,
		a4 * b4 + a5 * b7 + a6 * b10, a4 * b5 + a5 * b8 + a6 * b11, a4 * b6 + a5 * b9 + a6 * b12,
		a7 * b4 + a8 * b7 + a9 * b10, a7 * b5 + a8 * b8 + a9 * b11, a7 * b6 + a8 * b9 + a9 * b12,
		a10 * b4 + a11 * b7 + a12 * b10, a10 * b5 + a11 * b8 + a12 * b11, a10 * b6 + a11 * b9 + a12 * b12)
end
M.cfmul = cfmul
function cfinv(A)
	local x, y, z = A[1], A[2], A[3]
	local r00, r01, r02, r10, r11, r12, r20, r21, r22 = A[4], A[5], A[6], A[7], A[8], A[9], A[10], A[11], A[12]
	return C(-(r00 * x + r10 * y + r20 * z), -(r01 * x + r11 * y + r21 * z), -(r02 * x + r12 * y + r22 * z),
		r00, r10, r20, r01, r11, r21, r02, r12, r22)
end
M.cfinv = cfinv
function cfpoint(A, v)
	return V(A[1] + A[4] * v.X + A[5] * v.Y + A[6] * v.Z, A[2] + A[7] * v.X + A[8] * v.Y + A[9] * v.Z, A[3] + A[10] * v.X + A[11] * v.Y + A[12] * v.Z)
end
function cfvector(A, v)
	return V(A[4] * v.X + A[5] * v.Y + A[6] * v.Z, A[7] * v.X + A[8] * v.Y + A[9] * v.Z, A[10] * v.X + A[11] * v.Y + A[12] * v.Z)
end
function cfpointInv(A, v)
	local dx, dy, dz = v.X - A[1], v.Y - A[2], v.Z - A[3]
	return V(A[4] * dx + A[7] * dy + A[10] * dz, A[5] * dx + A[8] * dy + A[11] * dz, A[6] * dx + A[9] * dy + A[12] * dz)
end
function cfvectorInv(A, v)
	return V(A[4] * v.X + A[7] * v.Y + A[10] * v.Z, A[5] * v.X + A[8] * v.Y + A[11] * v.Z, A[6] * v.X + A[9] * v.Y + A[12] * v.Z)
end
function rotXYZ(a, b, c) -- Rx(a)*Ry(b)*Rz(c)
	local ca, sa, cb, sb, cc, sc = cos(a), sin(a), cos(b), sin(b), cos(c), sin(c)
	return cb * cc, -cb * sc, sb,
		ca * sc + sa * sb * cc, ca * cc - sa * sb * sc, -sa * cb,
		sa * sc - ca * sb * cc, sa * cc + ca * sb * sc, ca * cb
end
function rotYXZ(a, b, c) -- Ry(b)*Rx(a)*Rz(c)
	local ca, sa, cb, sb, cc, sc = cos(a), sin(a), cos(b), sin(b), cos(c), sin(c)
	return cb * cc + sb * sa * sc, -cb * sc + sb * sa * cc, sb * ca,
		ca * sc, ca * cc, -sa,
		-sb * cc + cb * sa * sc, sb * sc + cb * sa * cc, cb * ca
end
local function quatToMat(qx, qy, qz, qw)
	local n = sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
	if n == 0 then return 1, 0, 0, 0, 1, 0, 0, 0, 1 end
	qx, qy, qz, qw = qx / n, qy / n, qz / n, qw / n
	return 1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy - qz * qw), 2 * (qx * qz + qy * qw),
		2 * (qx * qy + qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz - qx * qw),
		2 * (qx * qz - qy * qw), 2 * (qy * qz + qx * qw), 1 - 2 * (qx * qx + qy * qy)
end
function matToQuat(A)
	local m00, m01, m02, m10, m11, m12, m20, m21, m22 = A[4], A[5], A[6], A[7], A[8], A[9], A[10], A[11], A[12]
	local tr = m00 + m11 + m22
	local qw, qx, qy, qz
	if tr > 0 then
		local s = sqrt(tr + 1) * 2
		qw = 0.25 * s; qx = (m21 - m12) / s; qy = (m02 - m20) / s; qz = (m10 - m01) / s
	elseif m00 > m11 and m00 > m22 then
		local s = sqrt(1 + m00 - m11 - m22) * 2
		qw = (m21 - m12) / s; qx = 0.25 * s; qy = (m01 + m10) / s; qz = (m02 + m20) / s
	elseif m11 > m22 then
		local s = sqrt(1 + m11 - m00 - m22) * 2
		qw = (m02 - m20) / s; qx = (m01 + m10) / s; qy = 0.25 * s; qz = (m12 + m21) / s
	else
		local s = sqrt(1 + m22 - m00 - m11) * 2
		qw = (m10 - m01) / s; qx = (m02 + m20) / s; qy = (m12 + m21) / s; qz = 0.25 * s
	end
	return qx, qy, qz, qw
end
local function axisAngle(axis, t)
	local m = sqrt(axis.X * axis.X + axis.Y * axis.Y + axis.Z * axis.Z)
	local x, y, z = axis.X / m, axis.Y / m, axis.Z / m
	local c, s = cos(t), sin(t)
	local k = 1 - c
	return c + x * x * k, x * y * k - z * s, x * z * k + y * s,
		y * x * k + z * s, c + y * y * k, y * z * k - x * s,
		z * x * k - y * s, z * y * k + x * s, c + z * z * k
end
local function lookAlong(at, f, up)
	local fm = sqrt(f.X * f.X + f.Y * f.Y + f.Z * f.Z)
	if fm == 0 then return C(at.X, at.Y, at.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1) end
	local fx, fy, fz = f.X / fm, f.Y / fm, f.Z / fm
	local ux, uy, uz = 0, 1, 0
	if up then ux, uy, uz = up.X, up.Y, up.Z end
	local rx, ry, rz = fy * uz - fz * uy, fz * ux - fx * uz, fx * uy - fy * ux
	local rm = sqrt(rx * rx + ry * ry + rz * rz)
	if rm < 1e-9 then
		-- forward parallel to up: choose a right vector perpendicular to forward
		rx, ry, rz = 1, 0, 0
		local d = rx * fx + ry * fy + rz * fz
		rx, ry, rz = rx - d * fx, ry - d * fy, rz - d * fz
		rm = sqrt(rx * rx + ry * ry + rz * rz)
		if rm < 1e-9 then rx, ry, rz = 0, 0, 1; rm = 1 end
	end
	rx, ry, rz = rx / rm, ry / rm, rz / rm
	local vx, vy, vz = ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx -- up = right x forward
	return C(at.X, at.Y, at.Z, rx, vx, -fx, ry, vy, -fy, rz, vz, -fz)
end

CFm = {}
function CFm.Inverse(a) return cfinv(a) end
CFm.inverse = CFm.Inverse
function CFm.ToWorldSpace(a, ...)
	local n = select("#", ...)
	if n == 1 then return cfmul(a, (...)) end
	local out = {}
	for i = 1, n do out[i] = cfmul(a, (select(i, ...))) end
	return unpack(out, 1, n)
end
CFm.toWorldSpace = CFm.ToWorldSpace
function CFm.ToObjectSpace(a, ...)
	local inv = cfinv(a)
	local n = select("#", ...)
	if n == 1 then return cfmul(inv, (...)) end
	local out = {}
	for i = 1, n do out[i] = cfmul(inv, (select(i, ...))) end
	return unpack(out, 1, n)
end
CFm.toObjectSpace = CFm.ToObjectSpace
local function mapper(f)
	return function(a, ...)
		local n = select("#", ...)
		if n == 1 then return f(a, (...)) end
		local out = {}
		for i = 1, n do out[i] = f(a, (select(i, ...))) end
		return unpack(out, 1, n)
	end
end
CFm.PointToWorldSpace = mapper(cfpoint)
CFm.pointToWorldSpace = CFm.PointToWorldSpace
CFm.PointToObjectSpace = mapper(cfpointInv)
CFm.pointToObjectSpace = CFm.PointToObjectSpace
CFm.VectorToWorldSpace = mapper(cfvector)
CFm.vectorToWorldSpace = CFm.VectorToWorldSpace
CFm.VectorToObjectSpace = mapper(cfvectorInv)
CFm.vectorToObjectSpace = CFm.VectorToObjectSpace
function CFm.GetComponents(a) return unpack(a, 1, 12) end
CFm.components = CFm.GetComponents
function CFm.ToEulerAnglesXYZ(a)
	local r02 = mmax(-1, mmin(1, a[6]))
	local ry = asin(r02)
	if abs(r02) > 0.9999999 then
		return 0, ry, atan2(a[7], a[8]) -- gimbal: rx=0, rz=atan2(R10,R11)
	end
	return atan2(-a[9], a[12]), ry, atan2(-a[5], a[4])
end
CFm.toEulerAnglesXYZ = CFm.ToEulerAnglesXYZ
function CFm.ToEulerAnglesYXZ(a)
	local r12 = mmax(-1, mmin(1, a[9]))
	local rx = asin(-r12)
	if abs(r12) > 0.9999999 then
		return rx, atan2(-a[10], a[4]), 0
	end
	return rx, atan2(a[6], a[12]), atan2(a[7], a[8])
end
CFm.toEulerAnglesYXZ = CFm.ToEulerAnglesYXZ
CFm.ToOrientation = CFm.ToEulerAnglesYXZ
function CFm.ToEulerAngles(a, order)
	local o = order and order.Name or "XYZ"
	if o == "XYZ" then return CFm.ToEulerAnglesXYZ(a) end
	if o == "YXZ" then return CFm.ToEulerAnglesYXZ(a) end
	once("cf-euler-" .. o, "CFrame:ToEulerAngles order " .. o .. " is not implemented in the mock (returning XYZ)")
	return CFm.ToEulerAnglesXYZ(a)
end
function CFm.ToAxisAngle(a)
	local qx, qy, qz, qw = matToQuat(a)
	if qw < 0 then qx, qy, qz, qw = -qx, -qy, -qz, -qw end
	local ang = 2 * acos(mmin(1, qw))
	local s = sqrt(mmax(0, 1 - qw * qw))
	if s < 1e-9 then return V(1, 0, 0), 0 end
	return V(qx / s, qy / s, qz / s), ang
end
CFm.toAxisAngle = CFm.ToAxisAngle
function CFm.Lerp(a, b, t)
	local ax, ay, az, aw = matToQuat(a)
	local bx, by, bz, bw = matToQuat(b)
	local d = ax * bx + ay * by + az * bz + aw * bw
	if d < 0 then bx, by, bz, bw, d = -bx, -by, -bz, -bw, -d end
	local k0, k1
	if d > 0.9995 then
		k0, k1 = 1 - t, t
	else
		local th = acos(d)
		local s = sin(th)
		k0, k1 = sin((1 - t) * th) / s, sin(t * th) / s
	end
	local r00, r01, r02, r10, r11, r12, r20, r21, r22 = quatToMat(ax * k0 + bx * k1, ay * k0 + by * k1, az * k0 + bz * k1, aw * k0 + bw * k1)
	return C(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, r00, r01, r02, r10, r11, r12, r20, r21, r22)
end
CFm.lerp = CFm.Lerp
function CFm.Orthonormalize(a)
	-- Gram-Schmidt on the columns
	local xx, xy, xz = a[4], a[7], a[10]
	local m = sqrt(xx * xx + xy * xy + xz * xz); xx, xy, xz = xx / m, xy / m, xz / m
	local yx, yy, yz = a[5], a[8], a[11]
	local d = xx * yx + xy * yy + xz * yz
	yx, yy, yz = yx - d * xx, yy - d * xy, yz - d * xz
	m = sqrt(yx * yx + yy * yy + yz * yz); yx, yy, yz = yx / m, yy / m, yz / m
	local zx, zy, zz = xy * yz - xz * yy, xz * yx - xx * yz, xx * yy - xy * yx
	return C(a[1], a[2], a[3], xx, yx, zx, xy, yy, zy, xz, yz, zz)
end
function CFm.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	for i = 1, 12 do if abs(a[i] - b[i]) > eps then return false end end
	return true
end
function CFm.AngleBetween(a, b)
	local _, ang = CFm.ToAxisAngle(cfmul(cfinv(a), b))
	return ang
end
CFmt.__index = function(cf, k)
	local m = CFm[k]
	if m then return m end
	if k == "Position" or k == "p" then return V(cf[1], cf[2], cf[3]) end
	if k == "X" or k == "x" then return cf[1] end
	if k == "Y" or k == "y" then return cf[2] end
	if k == "Z" or k == "z" then return cf[3] end
	if k == "LookVector" or k == "lookVector" then return V(-cf[6], -cf[9], -cf[12]) end
	if k == "RightVector" or k == "rightVector" or k == "XVector" then return V(cf[4], cf[7], cf[10]) end
	if k == "UpVector" or k == "upVector" or k == "YVector" then return V(cf[5], cf[8], cf[11]) end
	if k == "ZVector" then return V(cf[6], cf[9], cf[12]) end
	if k == "Rotation" then return C(0, 0, 0, cf[4], cf[5], cf[6], cf[7], cf[8], cf[9], cf[10], cf[11], cf[12]) end
	error(fmt("%s is not a valid member of CFrame", tostring(k)), 2)
end
CFmt.__mul = function(a, b)
	if isCF(a) then
		if isCF(b) then return cfmul(a, b) end
		if isV3(b) then return cfpoint(a, b) end
	end
	error(fmt("attempt to perform arithmetic (mul) on %s and %s", tname(a), tname(b)), 2)
end
CFmt.__add = function(a, b)
	if isCF(a) and isV3(b) then return C(a[1] + b.X, a[2] + b.Y, a[3] + b.Z, a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12]) end
	error(fmt("attempt to perform arithmetic (add) on %s and %s", tname(a), tname(b)), 2)
end
CFmt.__sub = function(a, b)
	if isCF(a) and isV3(b) then return C(a[1] - b.X, a[2] - b.Y, a[3] - b.Z, a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12]) end
	error(fmt("attempt to perform arithmetic (sub) on %s and %s", tname(a), tname(b)), 2)
end
CFmt.__eq = function(a, b)
	for i = 1, 12 do if a[i] ~= b[i] then return false end end
	return true
end
CFmt.__tostring = function(a)
	local t = {}
	for i = 1, 12 do t[i] = tostring(a[i]) end
	return tconcat(t, ", ")
end
CFrame = {}
CFrame.identity = IDENTITY
function CFrame.new(...)
	local n = select("#", ...)
	if n == 0 then return IDENTITY end
	local a, b = ...
	if n == 1 then
		if not isV3(a) then argErr("CFrame.new", 1, "Vector3", a) end
		return C(a.X, a.Y, a.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	if n == 2 then
		if isV3(a) and isV3(b) then return lookAlong(a, b - a, nil) end
		argErr("CFrame.new", 2, "Vector3", b)
	end
	local t = { ... }
	for i = 1, n do
		local v = tonumber(t[i])
		if v == nil then argErr("CFrame.new", i, "number", t[i]) end
		t[i] = v
	end
	if n == 3 then return C(t[1], t[2], t[3], 1, 0, 0, 0, 1, 0, 0, 0, 1) end
	if n == 7 then
		local r00, r01, r02, r10, r11, r12, r20, r21, r22 = quatToMat(t[4], t[5], t[6], t[7])
		return C(t[1], t[2], t[3], r00, r01, r02, r10, r11, r12, r20, r21, r22)
	end
	if n == 12 then return C(unpack(t, 1, 12)) end
	error("Invalid number of arguments: " .. n, 2)
end
function CFrame.lookAt(at, target, up)
	if not isV3(at) then argErr("CFrame.lookAt", 1, "Vector3", at) end
	if not isV3(target) then argErr("CFrame.lookAt", 2, "Vector3", target) end
	return lookAlong(at, target - at, up)
end
function CFrame.lookAlong(at, dir, up) return lookAlong(at, dir, up) end
function CFrame.fromMatrix(pos, vX, vY, vZ)
	if not vZ then vZ = V3m.Cross(vX, vY).Unit end
	return C(pos.X, pos.Y, pos.Z, vX.X, vY.X, vZ.X, vX.Y, vY.Y, vZ.Y, vX.Z, vY.Z, vZ.Z)
end
function CFrame.Angles(rx, ry, rz)
	return C(0, 0, 0, rotXYZ(tonumber(rx) or 0, tonumber(ry) or 0, tonumber(rz) or 0))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.fromEulerAnglesYXZ(rx, ry, rz)
	return C(0, 0, 0, rotYXZ(tonumber(rx) or 0, tonumber(ry) or 0, tonumber(rz) or 0))
end
CFrame.fromOrientation = CFrame.fromEulerAnglesYXZ
function CFrame.fromEulerAngles(rx, ry, rz, order)
	local o = order and order.Name or "XYZ"
	local R = {
		X = C(0, 0, 0, rotXYZ(rx, 0, 0)), Y = C(0, 0, 0, rotXYZ(0, ry, 0)), Z = C(0, 0, 0, rotXYZ(0, 0, rz)),
	}
	local out = IDENTITY
	for i = 1, 3 do out = cfmul(out, R[o:sub(i, i)]) end
	return out
end
function CFrame.fromAxisAngle(axis, t) return C(0, 0, 0, axisAngle(axis, t)) end
function CFrame.fromRotationBetweenVectors(a, b)
	local au, bu = a.Unit, b.Unit
	local c = V3m.Cross(au, bu)
	local d = V3m.Dot(au, bu)
	if c.Magnitude < 1e-9 then
		if d > 0 then return IDENTITY end
		local perp = abs(au.X) < 0.9 and V3m.Cross(au, V(1, 0, 0)) or V3m.Cross(au, V(0, 1, 0))
		return C(0, 0, 0, axisAngle(perp, pi))
	end
	return C(0, 0, 0, axisAngle(c, atan2(c.Magnitude, d)))
end
freeze(CFrame)

end
---------------------------------------------------------------------------
-- Color3
---------------------------------------------------------------------------
local RGB, isC3, Color3, nearestBrick, BrickColor, C3mt
do
C3mt = newType("Color3")
function RGB(r, g, b) return freeze(setmetatable({ R = r, G = g, B = b }, C3mt)) end
function isC3(v) return getmetatable(v) == C3mt end
M.RGB = RGB
local C3m = {}
function C3m.Lerp(a, b, t) return RGB(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end
C3m.lerp = C3m.Lerp
local function toHSV(c)
	local r, g, b = c.R, c.G, c.B
	local mx, mn = mmax(r, g, b), mmin(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == r then h = ((g - b) / d) % 6
		elseif mx == g then h = (b - r) / d + 2
		else h = (r - g) / d + 4 end
		h = h / 6
	end
	local s = mx == 0 and 0 or d / mx
	return h, s, mx
end
C3m.ToHSV = toHSV
function C3m.ToHex(c)
	local function q(x) return mmax(0, mmin(255, floor(x * 255 + 0.5))) end
	return fmt("%02X%02X%02X", q(c.R), q(c.G), q(c.B))
end
C3mt.__index = function(c, k)
	local m = C3m[k]
	if m then return m end
	if k == "r" then return c.R elseif k == "g" then return c.G elseif k == "b" then return c.B end
	error(fmt("%s is not a valid member of Color3", tostring(k)), 2)
end
C3mt.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
C3mt.__tostring = function(c) return tostring(c.R) .. ", " .. tostring(c.G) .. ", " .. tostring(c.B) end
Color3 = {}
function Color3.new(r, g, b) return RGB(tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0) end
function Color3.fromRGB(r, g, b) return RGB((tonumber(r) or 0) / 255, (tonumber(g) or 0) / 255, (tonumber(b) or 0) / 255) end
function Color3.fromHSV(h, s, v)
	h = (h % 1) * 6
	local i = floor(h)
	local f = h - i
	local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	i = i % 6
	if i == 0 then return RGB(v, t, p) elseif i == 1 then return RGB(q, v, p) elseif i == 2 then return RGB(p, v, t)
	elseif i == 3 then return RGB(p, q, v) elseif i == 4 then return RGB(t, p, v) end
	return RGB(v, p, q)
end
function Color3.toHSV(c) return toHSV(c) end
function Color3.fromHex(hex)
	hex = tostring(hex):gsub("^#", "")
	if #hex == 3 then hex = hex:sub(1, 1):rep(2) .. hex:sub(2, 2):rep(2) .. hex:sub(3, 3):rep(2) end
	if #hex ~= 6 or not hex:match("^%x+$") then error("Unable to convert characters to hex value", 2) end
	return RGB(tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255)
end
freeze(Color3)

---------------------------------------------------------------------------
-- BrickColor (minimal palette)
---------------------------------------------------------------------------
local BRICKS = {
	{ 1, "White", 242, 243, 243 }, { 5, "Brick yellow", 215, 197, 154 }, { 21, "Bright red", 196, 40, 28 },
	{ 23, "Bright blue", 13, 105, 172 }, { 24, "Bright yellow", 245, 205, 48 }, { 26, "Black", 27, 42, 53 },
	{ 28, "Dark green", 40, 127, 71 }, { 37, "Bright green", 75, 151, 75 }, { 38, "Dark orange", 160, 95, 53 },
	{ 102, "Medium blue", 110, 153, 202 }, { 106, "Bright orange", 218, 133, 65 }, { 119, "Br. yellowish green", 164, 189, 71 },
	{ 192, "Reddish brown", 105, 64, 40 }, { 194, "Medium stone grey", 163, 162, 165 }, { 199, "Dark stone grey", 99, 95, 98 },
	{ 208, "Light stone grey", 229, 228, 223 }, { 1001, "Institutional white", 248, 248, 248 }, { 1002, "Mid gray", 205, 205, 205 },
	{ 1003, "Really black", 17, 17, 17 }, { 1004, "Really red", 255, 0, 0 }, { 1009, "New Yeller", 255, 255, 0 },
	{ 1010, "Really blue", 0, 0, 255 }, { 1020, "Lime green", 0, 255, 0 }, { 1019, "Toothpaste", 0, 255, 255 },
	{ 1032, "Hot pink", 255, 0, 191 }, { 1, "Pastel Blue", 128, 187, 219 }, { 217, "Brown", 124, 92, 70 },
	{ 1030, "Pastel brown", 255, 204, 153 }, { 316, "Earth green", 39, 70, 45 }, { 1012, "Deep blue", 33, 84, 185 },
}
local BCmt = newType("BrickColor")
local function mkBrick(e) return freeze(setmetatable({ Number = e[1], Name = e[2], Color = RGB(e[3] / 255, e[4] / 255, e[5] / 255), r = e[3] / 255, g = e[4] / 255, b = e[5] / 255 }, BCmt)) end
BCmt.__index = function(_, k) error(fmt("%s is not a valid member of BrickColor", tostring(k)), 2) end
BCmt.__eq = function(a, b) return a.Number == b.Number and a.Name == b.Name end
BCmt.__tostring = function(b) return b.Name end
function nearestBrick(c)
	local best, bd = BRICKS[14], huge
	for _, e in BRICKS do
		local d = (c.R * 255 - e[3]) ^ 2 + (c.G * 255 - e[4]) ^ 2 + (c.B * 255 - e[5]) ^ 2
		if d < bd then best, bd = e, d end
	end
	return mkBrick(best or BRICKS[14])
end
BrickColor = {}
function BrickColor.new(a, g, b)
	if isC3(a) then return nearestBrick(a) end
	if rawtype(a) == "number" and g ~= nil then return nearestBrick(RGB(a, g, b)) end
	if rawtype(a) == "number" then
		for _, e in BRICKS do if e[1] == a then return mkBrick(e) end end
		once("brick" .. a, "BrickColor.new(" .. a .. ") not in mock palette; using Medium stone grey")
		return mkBrick(BRICKS[14])
	end
	if rawtype(a) == "string" then
		for _, e in BRICKS do if e[2] == a then return mkBrick(e) end end
		once("brick" .. a, "BrickColor.new('" .. a .. "') not in mock palette; using Medium stone grey")
		return mkBrick(BRICKS[14])
	end
	return mkBrick(BRICKS[14])
end
for _, nm in { "White", "Black", "Red", "Blue", "Green", "Yellow", "Gray", "DarkGray" } do
	local map = { White = "White", Black = "Black", Red = "Bright red", Blue = "Bright blue", Green = "Dark green", Yellow = "Bright yellow", Gray = "Medium stone grey", DarkGray = "Dark stone grey" }
	BrickColor[nm] = function() return BrickColor.new(map[nm]) end
end
function BrickColor.random() return mkBrick(BRICKS[1]) end
BrickColor.Random = BrickColor.random
function BrickColor.palette(i) return mkBrick(BRICKS[(i % #BRICKS) + 1]) end
freeze(BrickColor)

end
---------------------------------------------------------------------------
-- Small value types
---------------------------------------------------------------------------
local Enum
local UDim, UDim2, NumberRange, NumberSequenceKeypoint, NumberSequence, ColorSequenceKeypoint, ColorSequence, Rect, PhysicalProperties, TweenInfo, Ray, Region3, Font, Axes, Faces, Random, RaycastParams, OverlapParams, UDmt
do
local function simpleType(name, fields)
	local mt = newType(name)
	mt.__index = function(_, k) error(fmt("%s is not a valid member of %s", tostring(k), name), 2) end
	mt.__eq = function(a, b)
		for _, f in fields do if a[f] ~= b[f] then return false end end
		return true
	end
	return mt
end
UDmt = simpleType("UDim", { "Scale", "Offset" })
local function UD(s, o) return freeze(setmetatable({ Scale = s, Offset = o }, UDmt)) end
UDmt.__add = function(a, b) return UD(a.Scale + b.Scale, a.Offset + b.Offset) end
UDmt.__sub = function(a, b) return UD(a.Scale - b.Scale, a.Offset - b.Offset) end
UDmt.__unm = function(a) return UD(-a.Scale, -a.Offset) end
UDmt.__tostring = function(a) return tostring(a.Scale) .. ", " .. tostring(a.Offset) end
UDim = { new = function(s, o) return UD(tonumber(s) or 0, tonumber(o) or 0) end }
local UD2mt = newType("UDim2")
local function UD2(x, y) return freeze(setmetatable({ X = x, Y = y, Width = x, Height = y }, UD2mt)) end
UD2mt.__index = function(u, k)
	if k == "Lerp" or k == "lerp" then
		return function(a, b, t) return UD2(UD(a.X.Scale + (b.X.Scale - a.X.Scale) * t, a.X.Offset + (b.X.Offset - a.X.Offset) * t), UD(a.Y.Scale + (b.Y.Scale - a.Y.Scale) * t, a.Y.Offset + (b.Y.Offset - a.Y.Offset) * t)) end
	end
	error(fmt("%s is not a valid member of UDim2", tostring(k)), 2)
end
UD2mt.__add = function(a, b) return UD2(a.X + b.X, a.Y + b.Y) end
UD2mt.__sub = function(a, b) return UD2(a.X - b.X, a.Y - b.Y) end
UD2mt.__unm = function(a) return UD2(-a.X, -a.Y) end
UD2mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
UD2mt.__tostring = function(a) return "{" .. tostring(a.X) .. "}, {" .. tostring(a.Y) .. "}" end
UDim2 = {}
function UDim2.new(a, b, c, d)
	if getmetatable(a) == UDmt then return UD2(a, b) end
	return UD2(UD(tonumber(a) or 0, tonumber(b) or 0), UD(tonumber(c) or 0, tonumber(d) or 0))
end
function UDim2.fromScale(x, y) return UD2(UD(tonumber(x) or 0, 0), UD(tonumber(y) or 0, 0)) end
function UDim2.fromOffset(x, y) return UD2(UD(0, tonumber(x) or 0), UD(0, tonumber(y) or 0)) end

local NRmt = simpleType("NumberRange", { "Min", "Max" })
NRmt.__tostring = function(a) return tostring(a.Min) .. " " .. tostring(a.Max) end
NumberRange = {
	new = function(a, b)
		a = tonumber(a) or 0
		b = tonumber(b) or a
		if b < a then error("NumberRange: invalid range", 2) end
		return freeze(setmetatable({ Min = a, Max = b }, NRmt))
	end,
}
local NSKmt = simpleType("NumberSequenceKeypoint", { "Time", "Value", "Envelope" })
NumberSequenceKeypoint = { new = function(t, v, e) return freeze(setmetatable({ Time = tonumber(t) or 0, Value = tonumber(v) or 0, Envelope = tonumber(e) or 0 }, NSKmt)) end }
local NSmt = simpleType("NumberSequence", {})
NSmt.__eq = function(a, b) return a == b end
NumberSequence = {
	new = function(a, b)
		local kps
		if rawtype(a) == "table" and getmetatable(a) == nil then kps = a
		elseif b ~= nil then kps = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) }
		else kps = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, a) } end
		return freeze(setmetatable({ Keypoints = freeze(tclone(kps)) }, NSmt))
	end,
}
local CSKmt = simpleType("ColorSequenceKeypoint", { "Time", "Value" })
ColorSequenceKeypoint = { new = function(t, c) return freeze(setmetatable({ Time = tonumber(t) or 0, Value = c }, CSKmt)) end }
local CSmt = simpleType("ColorSequence", {})
CSmt.__eq = function(a, b) return a == b end
ColorSequence = {
	new = function(a, b)
		local kps
		if rawtype(a) == "table" and getmetatable(a) == nil then kps = a
		elseif b ~= nil then kps = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b) }
		else kps = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, a) } end
		return freeze(setmetatable({ Keypoints = freeze(tclone(kps)) }, CSmt))
	end,
}
local Rectmt = simpleType("Rect", { "Min", "Max" })
Rect = {
	new = function(a, b, c, d)
		local mn, mx
		if isV2(a) then mn, mx = a, b
		elseif a == nil then mn, mx = V2(0, 0), V2(0, 0)
		else mn, mx = V2(a, b), V2(c, d) end
		return freeze(setmetatable({ Min = mn, Max = mx, Width = mx.X - mn.X, Height = mx.Y - mn.Y }, Rectmt))
	end,
}
local PPmt = simpleType("PhysicalProperties", { "Density", "Friction", "Elasticity" })
PhysicalProperties = {
	new = function(a, f, e, fw, ew)
		if tname(a) == "EnumItem" then return freeze(setmetatable({ Density = 0.7, Friction = 0.3, Elasticity = 0.5, FrictionWeight = 1, ElasticityWeight = 1, AcousticAbsorption = 1 }, PPmt)) end
		return freeze(setmetatable({ Density = tonumber(a) or 0.7, Friction = tonumber(f) or 0.3, Elasticity = tonumber(e) or 0.5, FrictionWeight = tonumber(fw) or 1, ElasticityWeight = tonumber(ew) or 1, AcousticAbsorption = 1 }, PPmt))
	end,
}
local TImt = simpleType("TweenInfo", { "Time", "EasingStyle", "EasingDirection", "RepeatCount", "Reverses", "DelayTime" })
TweenInfo = {
	new = function(t, style, dir, rep, rev, delay)
		return freeze(setmetatable({ Time = tonumber(t) or 1, EasingStyle = style or Enum.EasingStyle.Quad, EasingDirection = dir or Enum.EasingDirection.Out, RepeatCount = tonumber(rep) or 0, Reverses = rev == true, DelayTime = tonumber(delay) or 0 }, TImt))
	end,
}
local Raymt = newType("Ray")
Ray = {}
Raymt.__index = function(r, k)
	if k == "Unit" then return Ray.new(r.Origin, r.Direction.Unit) end
	if k == "ClosestPoint" then return function(self, p) local d = self.Direction.Unit; local t = mmax(0, V3m.Dot(p - self.Origin, d)); return self.Origin + d * t end end
	if k == "Distance" then return function(self, p) return (self:ClosestPoint(p) - p).Magnitude end end
	error(tostring(k) .. " is not a valid member of Ray", 2)
end
function Ray.new(o, d) return freeze(setmetatable({ Origin = o or V(0, 0, 0), Direction = d or V(0, 0, 0) }, Raymt)) end
local R3mt = simpleType("Region3", { "CFrame", "Size" })
Region3 = { new = function(a, b) return freeze(setmetatable({ CFrame = C((a.X + b.X) / 2, (a.Y + b.Y) / 2, (a.Z + b.Z) / 2, 1, 0, 0, 0, 1, 0, 0, 0, 1), Size = b - a }, R3mt)) end }
local Fontmt = simpleType("Font", { "Family", "Weight", "Style" })
Font = {}
function Font.new(family, weight, style) return freeze(setmetatable({ Family = family, Weight = weight or Enum.FontWeight.Regular, Style = style or Enum.FontStyle.Normal, Bold = false }, Fontmt)) end
function Font.fromEnum(f) return Font.new("rbxasset://fonts/families/" .. f.Name .. ".json") end
function Font.fromName(n, w, s) return Font.new("rbxasset://fonts/families/" .. n .. ".json", w, s) end
function Font.fromId(id, w, s) return Font.new("rbxassetid://" .. tostring(id), w, s) end
local Axesmt = newType("Axes")
Axes = { new = function(...) return freeze(setmetatable({ args = { ... } }, Axesmt)) end }
local Facesmt = newType("Faces")
Faces = { new = function(...) return freeze(setmetatable({ args = { ... } }, Facesmt)) end }

-- Random: deterministic generator (two 31-bit LCG streams combined)
local Randmt = newType("Random")
local Randm = {}
Randmt.__index = function(_, k)
	local m = Randm[k]
	if m then return m end
	error(tostring(k) .. " is not a valid member of Random", 2)
end
local function rnext(r)
	r._a = (r._a * 1103515245 + 12345) % 2147483648
	r._b = (r._b * 22695477 + 1) % 2147483648
	return ((r._a / 2147483648) + (r._b / 2147483648) / 2147483648) % 1
end
function Randm.NextNumber(r, a, b)
	local u = rnext(r)
	if a == nil then return u end
	return a + (b - a) * u
end
function Randm.NextInteger(r, a, b)
	a, b = floor(a), floor(b)
	if b < a then error("invalid argument #2 to 'NextInteger' (interval is empty)", 2) end
	return a + floor(rnext(r) * (b - a + 1))
end
function Randm.NextUnitVector(r)
	local z = rnext(r) * 2 - 1
	local t = rnext(r) * 2 * pi
	local s = sqrt(1 - z * z)
	return V(s * cos(t), s * sin(t), z)
end
function Randm.Shuffle(r, t)
	for i = #t, 2, -1 do local j = Randm.NextInteger(r, 1, i); t[i], t[j] = t[j], t[i] end
end
function Randm.Clone(r) return setmetatable({ _a = r._a, _b = r._b }, Randmt) end
Random = {
	new = function(seed)
		seed = floor(tonumber(seed) or 12345) % 2147483647
		local r = setmetatable({ _a = seed, _b = (seed * 7 + 3) % 2147483647 }, Randmt)
		rnext(r); rnext(r)
		return r
	end,
}

local function paramsType(name, defaults)
	local mt = newType(name)
	mt.__index = function(_, k)
		if k == "AddToFilter" then
			return function(self, x)
				local list = tclone(rawget(self, "FilterDescendantsInstances") or {})
				if rawtype(x) == "table" and getmetatable(x) == nil then for _, i in x do tinsert(list, i) end else tinsert(list, x) end
				rawset(self, "FilterDescendantsInstances", list)
			end
		end
		return nil
	end
	return {
		new = function()
			local o = {}
			for k, v in defaults() do o[k] = v end
			return setmetatable(o, mt)
		end,
	}
end
RaycastParams = paramsType("RaycastParams", function() return { FilterDescendantsInstances = {}, FilterType = Enum.RaycastFilterType.Exclude, IgnoreWater = false, CollisionGroup = "Default", RespectCanCollide = false, BruteForceAllSlow = false } end)
OverlapParams = paramsType("OverlapParams", function() return { FilterDescendantsInstances = {}, FilterType = Enum.RaycastFilterType.Exclude, MaxParts = 0, CollisionGroup = "Default", RespectCanCollide = false, BruteForceAllSlow = false } end)

end
---------------------------------------------------------------------------
-- Enum
---------------------------------------------------------------------------
local EnumItemMT = newType("EnumItem")
local EnumMT = newType("Enum")
local EnumsMT = newType("Enums")
local enumData = {}
local enumObjs = {}
local function getEnum(name)
	local e = enumObjs[name]
	if e then return e end
	local def = API.enums[name]
	if not def then return nil end
	e = setmetatable({}, EnumMT)
	local data = { name = name, items = {}, byValue = {}, list = {} }
	for iname, val in def do
		local item = freeze(setmetatable({ Name = iname, Value = val, EnumType = e }, EnumItemMT))
		data.items[iname] = item
		if data.byValue[val] == nil or iname < data.byValue[val].Name then data.byValue[val] = item end
		tinsert(data.list, item)
	end
	tsort(data.list, function(a, b) if a.Value ~= b.Value then return a.Value < b.Value end return a.Name < b.Name end)
	enumData[e] = data
	enumObjs[name] = e
	return e
end
EnumItemMT.__index = function(item, k)
	if k == "IsA" then return function(self, n) return enumData[self.EnumType].name == n end end
	error(fmt("%s is not a valid member of \"%s\"", tostring(k), tostring(item)), 2)
end
EnumItemMT.__tostring = function(item) return "Enum." .. enumData[item.EnumType].name .. "." .. item.Name end
EnumMT.__index = function(e, k)
	local d = enumData[e]
	local item = d.items[k]
	if item then return item end
	if k == "GetEnumItems" then return function() return tclone(d.list) end end
	if k == "FromName" then return function(_, n) return d.items[n] end end
	if k == "FromValue" then return function(_, v) return d.byValue[v] end end
	error(fmt("%s is not a valid member of \"Enum.%s\"", tostring(k), d.name), 2)
end
EnumMT.__tostring = function(e) return enumData[e].name end
Enum = setmetatable({}, EnumsMT)
EnumsMT.__index = function(_, k)
	if k == "GetEnums" then
		return function()
			local out = {}
			for n in API.enums do tinsert(out, getEnum(n)) end
			return out
		end
	end
	local e = getEnum(k)
	if e then return e end
	error(fmt("%s is not a valid member of \"Enum\"", tostring(k)), 2)
end
EnumsMT.__tostring = function() return "Enum" end
M.Enum = Enum
M.enumName = function(item) return enumData[item.EnumType].name end

---------------------------------------------------------------------------
-- Scheduler, task library, signals
---------------------------------------------------------------------------
local FRAME = 1 / 60
local Sched = { now = 0, queue = {}, seq = 0, steps = 0, cancelled = setmetatable({}, { __mode = "k" }) }
M.Sched = Sched
local function traceHandler(e) return debug.traceback(tostring(e), 2) end
local function schedule(t, co, ...)
	Sched.seq += 1
	tinsert(Sched.queue, { t = t, seq = Sched.seq, co = co, args = pack(...) })
end
local function resumeThread(co, ...)
	if Sched.cancelled[co] then return end
	if coroutine.status(co) ~= "suspended" then return end
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		M.stats.errors += 1
		log("error", tostring(err) .. "\n" .. debug.traceback(co))
	end
end
local function makeThread(f)
	if rawtype(f) ~= "function" then error("invalid argument #1 (function expected, got " .. tname(f) .. ")", 3) end
	return coroutine.create(function(...)
		local ok, err = xpcall(f, traceHandler, ...)
		if not ok then
			M.stats.errors += 1
			log("error", err)
		end
	end)
end
function Sched.step(limit)
	local q = Sched.queue
	if #q == 0 then return false end
	local bi = 1
	for i = 2, #q do
		local a, b = q[i], q[bi]
		if a.t < b.t or (a.t == b.t and a.seq < b.seq) then bi = i end
	end
	local e = q[bi]
	if e.t > limit then return false end
	tremove(q, bi)
	if e.t > Sched.now then Sched.now = e.t end
	Sched.steps += 1
	if e.fn then
		e.fn(unpack(e.args, 1, e.args.n))
	else
		resumeThread(e.co, unpack(e.args, 1, e.args.n))
	end
	return true
end
function Sched.run(limit, maxSteps, stopWhen)
	maxSteps = maxSteps or 200000
	local n = 0
	while n < maxSteps do
		if stopWhen and stopWhen() then return "stopped" end
		if not Sched.step(limit) then return "idle" end
		n += 1
	end
	return "maxsteps"
end
local task = {}
function task.spawn(f, ...)
	local co = rawtype(f) == "thread" and f or makeThread(f)
	resumeThread(co, ...)
	return co
end
function task.defer(f, ...)
	local co = rawtype(f) == "thread" and f or makeThread(f)
	schedule(Sched.now, co, ...)
	return co
end
function task.delay(t, f, ...)
	local co = rawtype(f) == "thread" and f or makeThread(f)
	schedule(Sched.now + mmax(tonumber(t) or 0, 0), co, ...)
	return co
end
function task.wait(t)
	t = mmax(tonumber(t) or 0, FRAME)
	if not coroutine.isyieldable() then
		once("wait-noyield", "task.wait() called where the thread cannot yield; returned immediately")
		return t
	end
	local co = coroutine.running()
	local start = Sched.now
	schedule(Sched.now + t, co)
	coroutine.yield()
	return Sched.now - start
end
function task.cancel(co)
	Sched.cancelled[co] = true
	pcall(coroutine.close, co)
end
function task.synchronize() end
function task.desynchronize() end
freeze(task)
M.task = task

local SigMT = newType("RBXScriptSignal")
local ConnMT = newType("RBXScriptConnection")
ConnMT.__index = {
	Disconnect = function(c) c.Connected = false end,
}
local FRAME_SIGNALS = { Heartbeat = true, Stepped = true, RenderStepped = true, PreSimulation = true, PostSimulation = true, PreRender = true, PreAnimation = true }
local Sigm = {}
function Sigm.Connect(s, fn)
	if rawtype(fn) ~= "function" then error("Attempt to connect failed: Passed value is not a function", 2) end
	local c = setmetatable({ Connected = true, _fn = fn, _sig = s }, ConnMT)
	tinsert(s._conns, c)
	return c
end
Sigm.connect = Sigm.Connect
Sigm.ConnectParallel = Sigm.Connect
function Sigm.Once(s, fn)
	local c = Sigm.Connect(s, fn)
	c._once = true
	return c
end
function Sigm.Wait(s)
	if FRAME_SIGNALS[s._name] then
		local dt = task.wait(FRAME)
		if s._name == "Stepped" then return Sched.now, dt end
		return dt
	end
	if not coroutine.isyieldable() then
		once("sigwait-noyield", "Signal:Wait() on non-yieldable thread; returned nil")
		return nil
	end
	local co = coroutine.running()
	local waiter = { co = co, done = false }
	tinsert(s._waiters, waiter)
	Sched.seq += 1
	tinsert(Sched.queue, { t = Sched.now + 1, seq = Sched.seq, args = pack(), fn = function()
		if not waiter.done then
			waiter.done = true
			log("once", "Signal " .. s._name .. ":Wait() timed out after 1 virtual second (no event in headless mock)")
			resumeThread(co)
		end
	end })
	return coroutine.yield()
end
Sigm.wait = Sigm.Wait
SigMT.__index = function(_, k)
	local m = Sigm[k]
	if m then return m end
	error(tostring(k) .. " is not a valid member of RBXScriptSignal", 2)
end
SigMT.__tostring = function(s) return "Signal " .. s._name end
local function newSignal(name) return setmetatable({ _name = name, _conns = {}, _waiters = {}, _n = 0 }, SigMT) end
M.newSignal = newSignal
local function fire(s, ...)
	if #s._conns > 0 then
		local list = tclone(s._conns)
		for _, c in list do
			if c.Connected then
				if c._once then
					c.Connected = false
				end
				task.spawn(c._fn, ...)
			end
		end
		for i = #s._conns, 1, -1 do if not s._conns[i].Connected then tremove(s._conns, i) end end
	end
	if #s._waiters > 0 then
		local ws = s._waiters
		s._waiters = {}
		for _, w in ws do
			if not w.done then w.done = true; resumeThread(w.co, ...) end
		end
	end
end
M.fire = fire

---------------------------------------------------------------------------
-- Instances
---------------------------------------------------------------------------
local KEY = setmetatable({}, { __tostring = function() return "<state>" end })
M.KEY = KEY
local CLASSES = API.classes
local IMPL = {}
M.IMPL = IMPL
local infoCache = {}
local InstMT = newType("Instance")
local function isInstance(v) return rawtype(v) == "table" and getmetatable(v) == InstMT end
M.isInstance = isInstance

local function fullName(inst)
	local names = {}
	local p = inst
	while p do
		local st = p[KEY]
		if st.cls == "DataModel" then break end
		tinsert(names, 1, st.props.Name)
		p = st.props.Parent
	end
	return tconcat(names, ".")
end
M.fullName = fullName

local function impl(cls)
	local t = IMPL[cls]
	if not t then
		t = { methods = {}, get = {}, set = {}, defaults = {} }
		IMPL[cls] = t
	end
	return t
end

local function classInfo(name)
	local info = infoCache[name]
	if info then return info end
	if rawtype(name) ~= "string" or not CLASSES[name] then return nil end
	local chain = {}
	local c = name
	while c do
		tinsert(chain, 1, c)
		local d = CLASSES[c]
		c = d and d.s
	end
	info = { name = name, def = CLASSES[name], isa = {}, props = {}, ro = {}, events = {}, funcs = {}, cbs = {}, methods = {}, get = {}, set = {}, defaults = {}, inits = {}, stubs = {} }
	for _, cn in chain do
		info.isa[cn] = true
		local d = CLASSES[cn]
		if d.p then for k, v in d.p do info.props[k] = v end end
		if d.r then for k in d.r do info.ro[k] = true end end
		if d.e then for k in d.e do info.events[k] = true end end
		if d.f then for k in d.f do info.funcs[k] = true end end
		if d.c then for k in d.c do info.cbs[k] = true end end
		local im = IMPL[cn]
		if im then
			for k, f in im.methods do info.methods[k] = f end
			for k, f in im.get do info.get[k] = f end
			for k, f in im.set do info.set[k] = f end
			for k, v in im.defaults do info.defaults[k] = v end
			if im.init then tinsert(info.inits, im.init) end
		end
	end
	infoCache[name] = info
	return info
end
M.classInfo = classInfo

-- property type checkers -------------------------------------------------
local checkers = {}
local function checker(spec)
	local f = checkers[spec]
	if f then return f end
	if spec == "b" then
		f = function(v, k) if rawtype(v) == "boolean" then return v end; return nil, fmt("Unable to assign property %s. bool expected, got %s", k, tname(v)) end
	elseif spec == "n" then
		f = function(v, k)
			if rawtype(v) == "number" then return v end
			if rawtype(v) == "string" and tonumber(v) then return tonumber(v) end
			return nil, fmt("Unable to assign property %s. number expected, got %s", k, tname(v))
		end
	elseif spec == "s" then
		f = function(v, k)
			if rawtype(v) == "string" then return v end
			if rawtype(v) == "number" then return tostring(v) end
			return nil, fmt("Unable to assign property %s. string expected, got %s", k, tname(v))
		end
	elseif spec:sub(1, 2) == "E:" then
		local en = spec:sub(3)
		f = function(v, k)
			local e = getEnum(en)
			if not e then return v end
			if tname(v) == "EnumItem" then
				if enumData[v.EnumType].name == en then return v end
				return nil, fmt("Unable to assign property %s. EnumItem of type %s expected, got an EnumItem of type %s", k, en, enumData[v.EnumType].name)
			end
			if rawtype(v) == "number" then
				local it = enumData[e].byValue[v]
				if it then return it end
			elseif rawtype(v) == "string" then
				local it = enumData[e].items[v]
				if it then return it end
			end
			return nil, fmt("Unable to assign property %s. EnumItem of type %s expected, got %s", k, en, tname(v))
		end
	elseif spec:sub(1, 2) == "C:" then
		local cn = spec:sub(3)
		f = function(v, k)
			if v == nil then return nil end
			if isInstance(v) and v[KEY].info.isa[cn] then return v end
			return nil, fmt("Unable to assign property %s. %s expected, got %s", k, cn, isInstance(v) and v[KEY].cls or tname(v))
		end
	elseif TYPES[spec] then
		f = function(v, k)
			if tname(v) == spec then return v end
			return nil, fmt("Unable to assign property %s. %s expected, got %s", k, spec, tname(v))
		end
	else
		f = function(v) return v end
	end
	checkers[spec] = f
	return f
end
M.checker = checker

local TRUE_BY_DEFAULT = { Enabled = true, Visible = true, Archivable = true, CanCollide = true, CanQuery = true, CanTouch = true, CastShadow = true, AutoLocalize = true, Active = false }
local defaultCache = {}
local function typedDefault(spec, k)
	if spec == "b" then return TRUE_BY_DEFAULT[k] == true end
	if spec == "n" then return 0 end
	if spec == "s" then return "" end
	if spec:sub(1, 2) == "E:" then
		local e = getEnum(spec:sub(3))
		if not e then return nil end
		return enumData[e].byValue[0] or enumData[e].list[1]
	end
	if spec:sub(1, 2) == "C:" then return nil end
	if spec == "Vector3" then return Vector3.zero end
	if spec == "Vector2" then return Vector2.zero end
	if spec == "CFrame" then return IDENTITY end
	if spec == "Color3" then return RGB(1, 1, 1) end
	if spec == "UDim2" then return UDim2.new() end
	if spec == "UDim" then return UDim.new() end
	if spec == "NumberRange" then return NumberRange.new(0) end
	if spec == "NumberSequence" then return NumberSequence.new(0) end
	if spec == "ColorSequence" then return ColorSequence.new(RGB(1, 1, 1)) end
	if spec == "Rect" then return Rect.new() end
	if spec == "BrickColor" then return BrickColor.new("Medium stone grey") end
	return nil
end
local function propDefault(info, k)
	local key = info.name .. "." .. k
	local v = defaultCache[key]
	if v == nil then
		v = typedDefault(info.props[k], k)
		if v == nil then return nil end
		defaultCache[key] = v
	end
	return v
end

local function getSignal(st, key)
	local sigs = st.signals
	if not sigs then sigs = {}; st.signals = sigs end
	local s = sigs[key]
	if not s then s = newSignal(key); sigs[key] = s end
	return s
end
M.getSignal = getSignal

local function firePropChanged(self, st, k)
	local sigs = st.signals
	if not sigs then return end
	local s = sigs["@" .. k]
	if s then fire(s) end
	s = sigs.Changed
	if s then fire(s, k) end
end
M.firePropChanged = firePropChanged

local nextId = 0
local function newInstance(className)
	local info = classInfo(className)
	if not info then error(fmt("Unable to create an Instance of type \"%s\"", tostring(className)), 3) end
	nextId += 1
	local st = { cls = className, info = info, props = { Name = className }, children = {}, attrs = {}, id = nextId }
	local self = setmetatable({ [KEY] = st }, InstMT)
	st.self = self
	for k, v in info.defaults do st.props[k] = v end
	for _, f in info.inits do f(self, st) end
	return self
end
M.newInstance = newInstance

local function stubFor(info, k)
	local f = info.stubs[k]
	if f then return f end
	f = function(self)
		local cls = isInstance(self) and self[KEY].cls or info.name
		local key = cls .. ":" .. k
		if not M.stats.stubs[key] then
			M.stats.stubs[key] = 0
			once("stub-" .. key, "unimplemented API method " .. key .. "() called; returned nil")
		end
		M.stats.stubs[key] += 1
		return nil
	end
	info.stubs[k] = f
	return f
end

InstMT.__index = function(self, k)
	local st = self[KEY]
	local info = st.info
	local g = info.get[k]
	if g then return g(self, st) end
	local v = st.props[k]
	if v ~= nil then return v end
	local m = info.methods[k]
	if m then return m end
	if info.props[k] then return propDefault(info, k) end
	if info.events[k] then return getSignal(st, k) end
	if info.funcs[k] then return stubFor(info, k) end
	if info.cbs[k] then return nil end
	for _, c in st.children do
		if c[KEY].props.Name == k then return c end
	end
	error(fmt("%s is not a valid member of %s \"%s\"", tostring(k), st.cls, fullName(self)), 2)
end
InstMT.__newindex = function(self, k, v)
	local st = self[KEY]
	local info = st.info
	local s = info.set[k]
	if s then
		local err = s(self, st, v)
		if err then error(err, 2) end
		return
	end
	local spec = info.props[k]
	if not spec then
		if info.cbs[k] then st.props[k] = v; return end
		error(fmt("%s is not a valid member of %s \"%s\"", tostring(k), st.cls, fullName(self)), 2)
	end
	if info.ro[k] then error(fmt("Unable to assign property %s. Property is read only", k), 2) end
	local nv, err = checker(spec)(v, k)
	if err then error(err, 2) end
	local old = st.props[k]
	st.props[k] = nv
	if st.signals and old ~= nv then firePropChanged(self, st, k) end
end
InstMT.__tostring = function(self) return self[KEY].props.Name end

-- generic property write used by mock internals (validated, fires signals)
local function setProp(self, k, v) self[k] = v end
M.setProp = setProp

-- Tag registry ------------------------------------------------------------
local TAGS = {}
M.TAGS = TAGS
local tagSignals = { added = {}, removed = {} }
local anyTagSignals = false
local game -- forward
local function inGame(inst)
	local p = inst
	while p do
		local st = p[KEY]
		if st.cls == "DataModel" then return true end
		p = st.props.Parent
	end
	return false
end
local function addTag(inst, tag)
	tag = tostring(tag)
	local st = inst[KEY]
	if not st.tags then st.tags = {} end
	if st.tags[tag] then return end
	st.tags[tag] = true
	local set = TAGS[tag]
	if not set then set = setmetatable({}, { __mode = "k" }); TAGS[tag] = set end
	set[inst] = true
	if anyTagSignals and tagSignals.added[tag] and inGame(inst) then fire(tagSignals.added[tag], inst) end
end
local function removeTag(inst, tag)
	local st = inst[KEY]
	if not st.tags or not st.tags[tag] then return end
	st.tags[tag] = nil
	if TAGS[tag] then TAGS[tag][inst] = nil end
	if anyTagSignals and tagSignals.removed[tag] and inGame(inst) then fire(tagSignals.removed[tag], inst) end
end
local function getTags(inst)
	local st = inst[KEY]
	local out = {}
	if st.tags then for t in st.tags do tinsert(out, t) end end
	tsort(out)
	return out
end
M.getTags = getTags

-- Parenting ---------------------------------------------------------------
local function walkDesc(inst, fn)
	for _, c in inst[KEY].children do
		fn(c)
		walkDesc(c, fn)
	end
end
local function fireAncestors(start, sigName, arg)
	local p = start
	while p do
		local ps = p[KEY]
		if ps.signals and ps.signals[sigName] then fire(ps.signals[sigName], arg) end
		p = ps.props.Parent
	end
end
local function setParent(self, st, v)
	if v ~= nil and not isInstance(v) then return "Unable to assign property Parent. Instance expected, got " .. tname(v) end
	if st.parentLocked then
		return fmt("The Parent property of %s is locked, current parent: NULL, new parent %s", st.props.Name, v and v[KEY].props.Name or "NULL")
	end
	local old = st.props.Parent
	if old == v then return nil end
	if v then
		if v == self then return "Attempt to set " .. fullName(self) .. " as its own parent" end
		local p = v
		while p do
			if p == self then return fmt("Attempt to set parent of %s to %s would result in circular reference", fullName(self), fullName(v)) end
			p = p[KEY].props.Parent
		end
		if v[KEY].parentLocked and v[KEY].destroyed then
			-- Roblox allows parenting to a destroyed (locked) instance; keep behaviour
		end
	end
	if old then
		local os = old[KEY]
		local ch = os.children
		for i = #ch, 1, -1 do
			if ch[i] == self then tremove(ch, i); break end
		end
		if os.signals and os.signals.ChildRemoved then fire(os.signals.ChildRemoved, self) end
		fireAncestors(old, "DescendantRemoving", self)
	end
	st.props.Parent = v
	if v then
		local vs = v[KEY]
		tinsert(vs.children, self)
		if vs.signals and vs.signals.ChildAdded then fire(vs.signals.ChildAdded, self) end
		-- DescendantAdded for self and its descendants on all new ancestors
		local p = v
		local any = false
		while p do
			local ps = p[KEY]
			if ps.signals and ps.signals.DescendantAdded then any = true; break end
			p = ps.props.Parent
		end
		if any then
			fireAncestors(v, "DescendantAdded", self)
			walkDesc(self, function(d) fireAncestors(v, "DescendantAdded", d) end)
		end
		if anyTagSignals and inGame(v) then
			local function chk(d)
				local ds = d[KEY]
				if ds.tags then for t in ds.tags do if tagSignals.added[t] then fire(tagSignals.added[t], d) end end end
			end
			chk(self)
			walkDesc(self, chk)
		end
	end
	if st.signals then
		if st.signals.AncestryChanged then fire(st.signals.AncestryChanged, self, v) end
		firePropChanged(self, st, "Parent")
	end
	return nil
end
M.setParent = setParent

local function destroy(self)
	local st = self[KEY]
	if st.destroyed then return end
	if st.signals and st.signals.Destroying then fire(st.signals.Destroying) end
	local ch = st.children
	for i = #ch, 1, -1 do destroy(ch[i]) end
	if st.props.Parent then setParent(self, st, nil) end
	st.destroyed = true
	st.parentLocked = true
	if st.tags then for t in st.tags do if TAGS[t] then TAGS[t][self] = nil end end end
	st.signals = nil
end

local function cloneRec(src, map)
	local s = src[KEY]
	if s.props.Archivable == false then return nil end
	local c = newInstance(s.cls)
	local cs = c[KEY]
	for k, v in s.props do if k ~= "Parent" then cs.props[k] = v end end
	for k, v in s.attrs do cs.attrs[k] = v end
	cs.pivotSet = s.pivotSet
	cs.file = s.file
	if s.tags then for t in s.tags do addTag(c, t) end end
	map[src] = c
	for _, ch in s.children do
		local cc = cloneRec(ch, map)
		if cc then
			cc[KEY].props.Parent = c
			tinsert(cs.children, cc)
		end
	end
	return c
end

-- Attributes --------------------------------------------------------------
local ATTR_TYPES = { string = true, boolean = true, number = true, UDim = true, UDim2 = true, BrickColor = true, Color3 = true, Vector2 = true, Vector3 = true, CFrame = true, NumberSequence = true, ColorSequence = true, NumberRange = true, Rect = true, Font = true, EnumItem = true }

-- Instance methods --------------------------------------------------------
local I = impl("Instance")
I.defaults.Archivable = true
I.get.ClassName = function(_, st) return st.cls end
I.get.className = I.get.ClassName
I.set.Parent = setParent
I.set.Name = function(self, st, v)
	if rawtype(v) == "number" then v = tostring(v) end
	if rawtype(v) ~= "string" then return "Unable to assign property Name. string expected, got " .. tname(v) end
	local old = st.props.Name
	st.props.Name = v
	if st.signals and old ~= v then firePropChanged(self, st, "Name") end
end
local function checkSelf(self, fname)
	if not isInstance(self) then error(fmt("Expected ':' not '.' calling member function %s", fname), 3) end
	return self[KEY]
end
local IM = I.methods
function IM.GetChildren(self) return tclone(checkSelf(self, "GetChildren").children) end
IM.getChildren = IM.GetChildren
IM.children = IM.GetChildren
function IM.GetDescendants(self)
	checkSelf(self, "GetDescendants")
	local out = {}
	local n = 0
	local function rec(i)
		for _, c in i[KEY].children do
			n += 1
			out[n] = c
			rec(c)
		end
	end
	rec(self)
	return out
end
function IM.FindFirstChild(self, name, recursive)
	local st = checkSelf(self, "FindFirstChild")
	for _, c in st.children do if c[KEY].props.Name == name then return c end end
	if recursive then
		for _, c in st.children do
			local r = IM.FindFirstChild(c, name, true)
			if r then return r end
		end
	end
	return nil
end
IM.findFirstChild = IM.FindFirstChild
function IM.FindFirstChildOfClass(self, cls)
	local st = checkSelf(self, "FindFirstChildOfClass")
	for _, c in st.children do if c[KEY].cls == cls then return c end end
	return nil
end
function IM.FindFirstChildWhichIsA(self, cls, recursive)
	local st = checkSelf(self, "FindFirstChildWhichIsA")
	for _, c in st.children do if c[KEY].info.isa[cls] then return c end end
	if recursive then
		for _, c in st.children do
			local r = IM.FindFirstChildWhichIsA(c, cls, true)
			if r then return r end
		end
	end
	return nil
end
function IM.FindFirstDescendant(self, name) return IM.FindFirstChild(self, name, true) end
function IM.FindFirstAncestor(self, name)
	local p = checkSelf(self, "FindFirstAncestor").props.Parent
	while p do
		if p[KEY].props.Name == name then return p end
		p = p[KEY].props.Parent
	end
	return nil
end
function IM.FindFirstAncestorOfClass(self, cls)
	local p = checkSelf(self, "FindFirstAncestorOfClass").props.Parent
	while p do
		if p[KEY].cls == cls then return p end
		p = p[KEY].props.Parent
	end
	return nil
end
function IM.FindFirstAncestorWhichIsA(self, cls)
	local p = checkSelf(self, "FindFirstAncestorWhichIsA").props.Parent
	while p do
		if p[KEY].info.isa[cls] then return p end
		p = p[KEY].props.Parent
	end
	return nil
end
function IM.IsA(self, cls) return checkSelf(self, "IsA").info.isa[cls] == true end
IM.isA = IM.IsA
function IM.IsDescendantOf(self, anc)
	local p = checkSelf(self, "IsDescendantOf").props.Parent
	while p do
		if p == anc then return true end
		p = p[KEY].props.Parent
	end
	return false
end
IM.isDescendantOf = IM.IsDescendantOf
function IM.IsAncestorOf(self, d)
	checkSelf(self, "IsAncestorOf")
	return isInstance(d) and IM.IsDescendantOf(d, self)
end
function IM.GetFullName(self) checkSelf(self, "GetFullName"); return fullName(self) end
function IM.Destroy(self) checkSelf(self, "Destroy"); destroy(self) end
IM.destroy = IM.Destroy
function IM.Remove(self) checkSelf(self, "Remove"); self.Parent = nil end
IM.remove = IM.Remove
function IM.ClearAllChildren(self)
	local st = checkSelf(self, "ClearAllChildren")
	for i = #st.children, 1, -1 do destroy(st.children[i]) end
end
function IM.Clone(self)
	checkSelf(self, "Clone")
	local map = {}
	local c = cloneRec(self, map)
	if not c then return nil end
	for _, new in map do
		local ns = new[KEY]
		for k, v in ns.props do
			if k ~= "Parent" and isInstance(v) and map[v] then ns.props[k] = map[v] end
		end
	end
	return c
end
IM.clone = IM.Clone
function IM.SetAttribute(self, name, value)
	local st = checkSelf(self, "SetAttribute")
	if rawtype(name) ~= "string" then error("Argument 1 missing or nil", 2) end
	if #name > 100 or not name:match("^[%w_]+$") or name:sub(1, 3) == "RBX" then
		error(fmt("Attribute name '%s' is invalid (alphanumeric/underscore, <=100 chars, no RBX prefix)", name), 2)
	end
	if value ~= nil and not ATTR_TYPES[tname(value)] then
		error(fmt("Cannot set attribute '%s': %s is not a supported attribute type", name, tname(value)), 2)
	end
	local old = st.attrs[name]
	st.attrs[name] = value
	if st.signals and old ~= value then
		local s = st.signals.AttributeChanged
		if s then fire(s, name) end
		s = st.signals["attr@" .. name]
		if s then fire(s) end
	end
end
function IM.GetAttribute(self, name) return checkSelf(self, "GetAttribute").attrs[name] end
function IM.GetAttributes(self) return tclone(checkSelf(self, "GetAttributes").attrs) end
function IM.GetAttributeChangedSignal(self, name) return getSignal(checkSelf(self, "GetAttributeChangedSignal"), "attr@" .. tostring(name)) end
function IM.GetPropertyChangedSignal(self, prop)
	local st = checkSelf(self, "GetPropertyChangedSignal")
	if not st.info.props[prop] and prop ~= "Parent" and prop ~= "Name" then error(prop .. " is not a valid property name.", 2) end
	return getSignal(st, "@" .. prop)
end
function IM.WaitForChild(self, name, timeout)
	local st = checkSelf(self, "WaitForChild")
	local c = IM.FindFirstChild(self, name)
	if c then return c end
	if not coroutine.isyieldable() then
		log("warn", "Infinite yield possible on '" .. fullName(self) .. ":WaitForChild(\"" .. tostring(name) .. "\")' (non-yieldable thread; returned nil)")
		return nil
	end
	local limit = Sched.now + (tonumber(timeout) or 5)
	while Sched.now < limit do
		task.wait(FRAME * 6)
		c = IM.FindFirstChild(self, name)
		if c then return c end
	end
	if timeout == nil then log("warn", "Infinite yield possible on '" .. fullName(self) .. ":WaitForChild(\"" .. tostring(name) .. "\")'") end
	return nil
end
function IM.AddTag(self, tag) checkSelf(self, "AddTag"); addTag(self, tag) end
function IM.RemoveTag(self, tag) checkSelf(self, "RemoveTag"); removeTag(self, tag) end
function IM.HasTag(self, tag) local st = checkSelf(self, "HasTag"); return st.tags ~= nil and st.tags[tag] == true end
function IM.GetTags(self) checkSelf(self, "GetTags"); return getTags(self) end
function IM.GetDebugId(self) return "MOCK_" .. checkSelf(self, "GetDebugId").id end
function IM.GetActor() return nil end
function IM.IsPropertyModified() return false end

---------------------------------------------------------------------------
-- PVInstance / BasePart / Model
---------------------------------------------------------------------------
local function eachDescPart(inst, fn)
	for _, c in inst[KEY].children do
		if c[KEY].info.isa.BasePart then fn(c) end
		eachDescPart(c, fn)
	end
end
M.eachDescPart = eachDescPart
local function setPartCF(part, cf)
	local st = part[KEY]
	st.props.CFrame = cf
	if st.signals then firePropChanged(part, st, "CFrame"); firePropChanged(part, st, "Position"); firePropChanged(part, st, "Orientation") end
end

local BP = impl("BasePart")
for k, v in {
	Anchored = false, CanCollide = true, CanQuery = true, CanTouch = true, CastShadow = true, Transparency = 0, Reflectance = 0,
	Massless = false, Locked = false, CollisionGroup = "Default", RootPriority = 0, EnableFluidForces = true, AudioCanCollide = true,
	MaterialVariant = "",
} do BP.defaults[k] = v end
BP.init = function(self, st)
	local p = st.props
	p.Color = RGB(163 / 255, 162 / 255, 165 / 255)
	p.Material = Enum.Material.Plastic
	p.CFrame = IDENTITY
	p.PivotOffset = IDENTITY
	if p.Size == nil then p.Size = V(4, 1, 2) end
	for _, face in { "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface" } do p[face] = Enum.SurfaceType.Smooth end
end
BP.get.Position = function(_, st) local c = st.props.CFrame; return V(c[1], c[2], c[3]) end
BP.get.position = BP.get.Position
BP.get.Orientation = function(_, st)
	local rx, ry, rz = CFm.ToEulerAnglesYXZ(st.props.CFrame)
	return V(math.deg(rx), math.deg(ry), math.deg(rz))
end
BP.get.Rotation = function(_, st)
	local rx, ry, rz = CFm.ToEulerAnglesXYZ(st.props.CFrame)
	return V(math.deg(rx), math.deg(ry), math.deg(rz))
end
BP.get.BrickColor = function(_, st) return nearestBrick(st.props.Color) end
BP.get.brickColor = BP.get.BrickColor
local DENSITY = { Wood = 0.35, Concrete = 2.4, Metal = 7.85, Glass = 2.4, Neon = 0.7, Plastic = 0.7, SmoothPlastic = 0.7, Fabric = 0.7, Grass = 0.9, Marble = 2.56, Slate = 2.69, Asphalt = 2.36, WoodPlanks = 0.35 }
local function mass(st)
	local s = st.props.Size
	return s.X * s.Y * s.Z * (DENSITY[st.props.Material.Name] or 0.7)
end
BP.get.Mass = function(_, st) return mass(st) end
BP.get.AssemblyMass = BP.get.Mass
BP.get.AssemblyRootPart = function(self) return self end
BP.get.ExtentsSize = function(_, st) return st.props.Size end
BP.get.ExtentsCFrame = function(_, st) return st.props.CFrame end
BP.get.AssemblyLinearVelocity = function() return Vector3.zero end
BP.get.AssemblyAngularVelocity = function() return Vector3.zero end
BP.get.Velocity = BP.get.AssemblyLinearVelocity
BP.get.CenterOfMass = function(_, st) return Vector3.zero end
BP.get.AssemblyCenterOfMass = function(_, st) local c = st.props.CFrame; return V(c[1], c[2], c[3]) end
BP.set.CFrame = function(self, st, v)
	if not isCF(v) then return "Unable to assign property CFrame. CFrame expected, got " .. tname(v) end
	setPartCF(self, v)
end
BP.set.Position = function(self, st, v)
	if not isV3(v) then return "Unable to assign property Position. Vector3 expected, got " .. tname(v) end
	local c = st.props.CFrame
	setPartCF(self, C(v.X, v.Y, v.Z, c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12]))
end
BP.set.position = BP.set.Position
BP.set.Orientation = function(self, st, v)
	if not isV3(v) then return "Unable to assign property Orientation. Vector3 expected, got " .. tname(v) end
	local c = st.props.CFrame
	setPartCF(self, C(c[1], c[2], c[3], rotYXZ(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))))
end
BP.set.Rotation = function(self, st, v)
	if not isV3(v) then return "Unable to assign property Rotation. Vector3 expected, got " .. tname(v) end
	local c = st.props.CFrame
	setPartCF(self, C(c[1], c[2], c[3], rotXYZ(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))))
end
BP.set.Size = function(self, st, v)
	if not isV3(v) then return "Unable to assign property Size. Vector3 expected, got " .. tname(v) end
	-- Roblox clamps each axis to [0.001, 2048]; the requested value is kept for the checker.
	-- NaN passes through unchanged so the geometry check can report it.
	local function cl(a) if a ~= a then return a end; return mmin(mmax(a, 0.001), 2048) end
	local x, y, z = cl(v.X), cl(v.Y), cl(v.Z)
	if (x ~= v.X and v.X == v.X) or (y ~= v.Y and v.Y == v.Y) or (z ~= v.Z and v.Z == v.Z) then
		st.requestedSize = v
		v = V(x, y, z)
	else
		st.requestedSize = nil
	end
	local old = st.props.Size
	st.props.Size = v
	if st.signals and old ~= v then firePropChanged(self, st, "Size") end
end
BP.set.BrickColor = function(self, st, v)
	if tname(v) ~= "BrickColor" then return "Unable to assign property BrickColor. BrickColor expected, got " .. tname(v) end
	st.props.Color = v.Color
	if st.signals then firePropChanged(self, st, "Color"); firePropChanged(self, st, "BrickColor") end
end
BP.set.brickColor = BP.set.BrickColor
local BPM = BP.methods
function BPM.GetMass(self) return mass(checkSelf(self, "GetMass")) end
function BPM.GetTouchingParts() return {} end
function BPM.GetConnectedParts(self) return { self } end
function BPM.GetJoints() return {} end
function BPM.GetNoCollisionConstraints() return {} end
function BPM.BreakJoints() end
function BPM.MakeJoints() end
function BPM.SetNetworkOwner() end
function BPM.SetNetworkOwnershipAuto() end
function BPM.GetNetworkOwner() return nil end
function BPM.GetNetworkOwnershipAuto() return true end
function BPM.CanSetNetworkOwner() return true, nil end
function BPM.ApplyImpulse() end
function BPM.ApplyImpulseAtPosition() end
function BPM.ApplyAngularImpulse() end
function BPM.GetVelocityAtPosition() return Vector3.zero end
function BPM.GetRootPart(self) return self end
function BPM.GetClosestPointOnSurface(self, p) return p end

local PV = impl("PVInstance")
local function getPivot(self)
	local st = self[KEY]
	if st.info.isa.BasePart then
		return cfmul(st.props.CFrame, st.props.PivotOffset or IDENTITY)
	end
	if st.info.isa.Model then
		local pp = st.props.PrimaryPart
		if pp and IM.IsDescendantOf(pp, self) then return getPivot(pp) end
		if st.pivotSet then return st.props.WorldPivot end
		-- bounding box centre (world aligned) until WorldPivot is first set
		local mnx, mny, mnz, mxx, mxy, mxz = huge, huge, huge, -huge, -huge, -huge
		local any = false
		eachDescPart(self, function(p)
			any = true
			local ps = p[KEY].props
			local c, s = ps.CFrame, ps.Size
			local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
			local ex = abs(c[4]) * hx + abs(c[5]) * hy + abs(c[6]) * hz
			local ey = abs(c[7]) * hx + abs(c[8]) * hy + abs(c[9]) * hz
			local ez = abs(c[10]) * hx + abs(c[11]) * hy + abs(c[12]) * hz
			mnx, mxx = mmin(mnx, c[1] - ex), mmax(mxx, c[1] + ex)
			mny, mxy = mmin(mny, c[2] - ey), mmax(mxy, c[2] + ey)
			mnz, mxz = mmin(mnz, c[3] - ez), mmax(mxz, c[3] + ez)
		end)
		if not any then return st.props.WorldPivot or IDENTITY end
		return C((mnx + mxx) / 2, (mny + mxy) / 2, (mnz + mxz) / 2, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	return IDENTITY
end
M.getPivot = getPivot
local function transformTree(self, delta, includeSelf)
	local st = self[KEY]
	if includeSelf and st.info.isa.BasePart then setPartCF(self, cfmul(delta, st.props.CFrame)) end
	local function rec(i)
		for _, c in i[KEY].children do
			local cs = c[KEY]
			if cs.info.isa.BasePart then setPartCF(c, cfmul(delta, cs.props.CFrame))
			elseif cs.info.isa.Model and cs.pivotSet then cs.props.WorldPivot = cfmul(delta, cs.props.WorldPivot) end
			rec(c)
		end
	end
	rec(self)
end
M.transformTree = transformTree
function PV.methods.GetPivot(self) checkSelf(self, "GetPivot"); return getPivot(self) end
function PV.methods.PivotTo(self, cf)
	local st = checkSelf(self, "PivotTo")
	if not isCF(cf) then error("invalid argument #1 to 'PivotTo' (CFrame expected, got " .. tname(cf) .. ")", 2) end
	local cur = getPivot(self)
	local delta = cfmul(cf, cfinv(cur))
	if st.info.isa.BasePart then
		transformTree(self, delta, true)
	else
		local pp = st.props.PrimaryPart
		transformTree(self, delta, false)
		if not (pp and IM.IsDescendantOf(pp, self)) then
			st.pivotSet = true
			st.props.WorldPivot = cf
		end
	end
end

local MD = impl("Model")
MD.defaults.LevelOfDetail = nil
MD.get.WorldPivot = function(self, st)
	if st.pivotSet then return st.props.WorldPivot end
	return getPivot(self)
end
MD.set.WorldPivot = function(self, st, v)
	if not isCF(v) then return "Unable to assign property WorldPivot. CFrame expected, got " .. tname(v) end
	st.pivotSet = true
	st.props.WorldPivot = v
end
MD.set.PrimaryPart = function(self, st, v)
	if v ~= nil and not (isInstance(v) and v[KEY].info.isa.BasePart) then
		return "Unable to assign property PrimaryPart. BasePart expected, got " .. (isInstance(v) and v[KEY].cls or tname(v))
	end
	st.props.PrimaryPart = v
	if st.signals then firePropChanged(self, st, "PrimaryPart") end
end
local function boundingBox(self)
	local piv = getPivot(self)
	local rot = C(0, 0, 0, piv[4], piv[5], piv[6], piv[7], piv[8], piv[9], piv[10], piv[11], piv[12])
	local inv = cfinv(rot)
	local mn = { huge, huge, huge }
	local mx = { -huge, -huge, -huge }
	local any = false
	eachDescPart(self, function(p)
		any = true
		local ps = p[KEY].props
		local c, s = cfmul(inv, ps.CFrame), ps.Size
		local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
		local e = { abs(c[4]) * hx + abs(c[5]) * hy + abs(c[6]) * hz, abs(c[7]) * hx + abs(c[8]) * hy + abs(c[9]) * hz, abs(c[10]) * hx + abs(c[11]) * hy + abs(c[12]) * hz }
		for i = 1, 3 do mn[i] = mmin(mn[i], c[i] - e[i]); mx[i] = mmax(mx[i], c[i] + e[i]) end
	end)
	if not any then return piv, Vector3.zero end
	local center = cfpoint(rot, V((mn[1] + mx[1]) / 2, (mn[2] + mx[2]) / 2, (mn[3] + mx[3]) / 2))
	return C(center.X, center.Y, center.Z, piv[4], piv[5], piv[6], piv[7], piv[8], piv[9], piv[10], piv[11], piv[12]), V(mx[1] - mn[1], mx[2] - mn[2], mx[3] - mn[3])
end
M.boundingBox = boundingBox
local MDM = MD.methods
function MDM.GetBoundingBox(self) checkSelf(self, "GetBoundingBox"); return boundingBox(self) end
function MDM.GetExtentsSize(self) checkSelf(self, "GetExtentsSize"); local _, s = boundingBox(self); return s end
function MDM.GetPrimaryPartCFrame(self)
	local st = checkSelf(self, "GetPrimaryPartCFrame")
	if not st.props.PrimaryPart then error("Model:GetPrimaryPartCFrame() failed because no PrimaryPart has been set, or the PrimaryPart no longer exists. Please set Model.PrimaryPart before using this.", 2) end
	return st.props.PrimaryPart.CFrame
end
function MDM.SetPrimaryPartCFrame(self, cf)
	local st = checkSelf(self, "SetPrimaryPartCFrame")
	local pp = st.props.PrimaryPart
	if not pp then error("Model:SetPrimaryPartCFrame() failed because no PrimaryPart has been set, or the PrimaryPart no longer exists. Please set Model.PrimaryPart before using this.", 2) end
	transformTree(self, cfmul(cf, cfinv(pp[KEY].props.CFrame)), false)
end
function MDM.TranslateBy(self, v)
	checkSelf(self, "TranslateBy")
	transformTree(self, C(v.X, v.Y, v.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1), false)
	local st = self[KEY]
	if st.pivotSet then st.props.WorldPivot = st.props.WorldPivot + v end
end
function MDM.MoveTo(self, pos)
	checkSelf(self, "MoveTo")
	once("model-moveto", "Model:MoveTo ignores collisions in the mock (pure translation of the pivot to the target)")
	local piv = getPivot(self)
	MDM.TranslateBy(self, pos - piv.Position)
end
function MDM.GetScale(self) return checkSelf(self, "GetScale").scale or 1 end
function MDM.ScaleTo(self, s)
	local st = checkSelf(self, "ScaleTo")
	local old = st.scale or 1
	local k = s / old
	local piv = getPivot(self)
	eachDescPart(self, function(p)
		local ps = p[KEY].props
		local rel = cfmul(cfinv(piv), ps.CFrame)
		local nc = cfmul(piv, C(rel[1] * k, rel[2] * k, rel[3] * k, rel[4], rel[5], rel[6], rel[7], rel[8], rel[9], rel[10], rel[11], rel[12]))
		p.Size = ps.Size * k
		setPartCF(p, nc)
	end)
	st.scale = s
end
function MDM.BreakJoints() end
function MDM.MakeJoints() end
function MDM.GetPersistentPlayers() return {} end

local AT = impl("Attachment")
AT.init = function(_, st) st.props.CFrame = IDENTITY end
local function attParentCF(st)
	local p = st.props.Parent
	if p and p[KEY].info.isa.BasePart then return p[KEY].props.CFrame end
	return IDENTITY
end
AT.get.Position = function(_, st) local c = st.props.CFrame; return V(c[1], c[2], c[3]) end
AT.set.Position = function(self, st, v)
	if not isV3(v) then return "Unable to assign property Position. Vector3 expected, got " .. tname(v) end
	local c = st.props.CFrame
	st.props.CFrame = C(v.X, v.Y, v.Z, c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
end
AT.get.Orientation = BP.get.Orientation
AT.set.Orientation = function(self, st, v)
	local c = st.props.CFrame
	st.props.CFrame = C(c[1], c[2], c[3], rotYXZ(math.rad(v.X), math.rad(v.Y), math.rad(v.Z)))
end
AT.get.WorldCFrame = function(_, st) return cfmul(attParentCF(st), st.props.CFrame) end
AT.get.WorldPosition = function(_, st) return cfpoint(attParentCF(st), AT.get.Position(nil, st)) end
AT.set.WorldCFrame = function(self, st, v) st.props.CFrame = cfmul(cfinv(attParentCF(st)), v) end
AT.set.WorldPosition = function(self, st, v) AT.set.Position(self, st, cfpointInv(attParentCF(st), v)) end
AT.get.Axis = function(_, st) local c = st.props.CFrame; return V(c[4], c[7], c[10]) end
AT.get.SecondaryAxis = function(_, st) local c = st.props.CFrame; return V(c[5], c[8], c[11]) end
AT.get.WorldAxis = function(_, st) local c = cfmul(attParentCF(st), st.props.CFrame); return V(c[4], c[7], c[10]) end
AT.get.WorldSecondaryAxis = function(_, st) local c = cfmul(attParentCF(st), st.props.CFrame); return V(c[5], c[8], c[11]) end


do
-- Class defaults ------------------------------------------------------------
local function defaults(cls, t) local im = impl(cls); for k, v in t do im.defaults[k] = v end end
local function initSize(cls, x, y, z)
	local im = impl(cls)
	local prev = im.init
	im.init = function(self, st) st.props.Size = V(x, y, z); if prev then prev(self, st) end end
end
initSize("CornerWedgePart", 2, 2, 2)
initSize("TrussPart", 2, 2, 2)
initSize("SpawnLocation", 12, 1, 12)
impl("Part").init = function(_, st) st.props.Shape = Enum.PartType.Block end
defaults("Seat", { Disabled = false })
defaults("VehicleSeat", { Disabled = false, MaxSpeed = 25, Torque = 10, TurnSpeed = 1 })
defaults("Light", { Brightness = 1, Enabled = true, Shadows = false })
impl("Light").init = function(_, st) st.props.Color = RGB(1, 1, 1) end
defaults("PointLight", { Range = 8 })
defaults("SpotLight", { Range = 16, Angle = 90 })
impl("SpotLight").init = function(_, st) st.props.Face = Enum.NormalId.Front end
defaults("SurfaceLight", { Range = 16, Angle = 90 })
impl("SurfaceLight").init = function(_, st) st.props.Face = Enum.NormalId.Front end
defaults("ProximityPrompt", { ActionText = "Interact", ObjectText = "", MaxActivationDistance = 10, HoldDuration = 0, RequiresLineOfSight = true, Enabled = true, ClickablePrompt = true, AutoLocalize = true })
defaults("TextLabel", { Text = "Label", TextScaled = false, TextWrapped = false, TextSize = 14, BackgroundTransparency = 0, TextTransparency = 0 })
defaults("TextButton", { Text = "Button", TextScaled = false, TextSize = 14 })
defaults("TextBox", { Text = "", TextScaled = false, TextSize = 14 })
defaults("GuiObject", { Visible = true, BackgroundTransparency = 0, ZIndex = 1, LayoutOrder = 0, Rotation = 0, BorderSizePixel = 1 })
impl("GuiObject").init = function(_, st) st.props.Size = UDim2.new(0, 100, 0, 100); st.props.Position = UDim2.new(); st.props.BackgroundColor3 = RGB(1, 1, 1) end
defaults("LayerCollector", { Enabled = true, ResetOnSpawn = true })
defaults("SurfaceGuiBase", { Active = true })
defaults("SurfaceGui", { LightInfluence = 1, MaxDistance = 0, AlwaysOnTop = false, PixelsPerStud = 50, Brightness = 1 })
impl("SurfaceGui").init = function(_, st) st.props.Face = Enum.NormalId.Front; st.props.CanvasSize = V2(800, 600) end
defaults("BillboardGui", { LightInfluence = 0, MaxDistance = huge, AlwaysOnTop = false })
impl("BillboardGui").init = function(_, st) st.props.StudsOffset = Vector3.zero end
defaults("Humanoid", { Health = 100, MaxHealth = 100, WalkSpeed = 16, JumpPower = 50, JumpHeight = 7.2, HipHeight = 0, AutoRotate = true, UseJumpPower = true, Sit = false, PlatformStand = false, MaxSlopeAngle = 89, BreakJointsOnDeath = true, AutoJumpEnabled = true, RequiresNeck = true, EvaluateStateMachine = true })
impl("Humanoid").get.RootPart = function(self, st)
	local p = st.props.Parent
	return p and IM.FindFirstChild(p, "HumanoidRootPart") or nil
end
impl("Humanoid").get.MoveDirection = function() return Vector3.zero end
impl("Humanoid").get.SeatPart = function() return nil end
defaults("Sound", { Volume = 0.5, Playing = false, Looped = false, PlaybackSpeed = 1, TimePosition = 0, RollOffMaxDistance = 10000, RollOffMinDistance = 10 })
defaults("ParticleEmitter", { Enabled = true, Rate = 5, LightEmission = 0, LightInfluence = 0, Rotation = 0 })
defaults("Camera", { FieldOfView = 70 })
impl("Camera").init = function(_, st) st.props.CFrame = IDENTITY; st.props.Focus = IDENTITY end
defaults("Lighting", { ClockTime = 14, Brightness = 2, GlobalShadows = true, ExposureCompensation = 0, GeographicLatitude = 0 })
defaults("Workspace", { Gravity = 196.2, FallenPartsDestroyHeight = -500, StreamingEnabled = false })
defaults("Weld", { Enabled = true })
defaults("WeldConstraint", { Enabled = true })
impl("JointInstance").init = function(_, st) st.props.C0 = IDENTITY; st.props.C1 = IDENTITY end
defaults("PathfindingModifier", { PassThrough = false, Label = "" })
defaults("SpecialMesh", {})
impl("FileMesh").init = function(_, st) st.props.Scale = V(1, 1, 1); st.props.Offset = Vector3.zero end
defaults("StringValue", { Value = "" })
defaults("NumberValue", { Value = 0 })
defaults("IntValue", { Value = 0 })
defaults("BoolValue", { Value = false })

-- Methods for misc classes ----------------------------------------------------
local function trackFor(owner, anim)
	local t = newInstance("AnimationTrack")
	t[KEY].props.Animation = anim
	t[KEY].props.Name = anim and anim[KEY].props.Name or "AnimationTrack"
	return t
end
impl("AnimationTrack").methods.Play = function(self) self[KEY].props.IsPlaying = true end
impl("AnimationTrack").methods.Stop = function(self) self[KEY].props.IsPlaying = false end
impl("AnimationTrack").methods.AdjustSpeed = function(self, s) self[KEY].props.Speed = s end
impl("AnimationTrack").methods.AdjustWeight = function() end
impl("AnimationTrack").methods.GetMarkerReachedSignal = function(self, n) return getSignal(self[KEY], "marker@" .. tostring(n)) end
impl("AnimationTrack").methods.GetTimeOfKeyframe = function() return 0 end
impl("Animator").methods.LoadAnimation = function(self, anim) return trackFor(self, anim) end
impl("Animator").methods.GetPlayingAnimationTracks = function() return {} end
impl("AnimationController").methods.LoadAnimation = function(self, anim) return trackFor(self, anim) end
local HM = impl("Humanoid").methods
HM.LoadAnimation = function(self, anim) return trackFor(self, anim) end
HM.MoveTo = function() end
HM.Move = function() end
HM.GetState = function() return Enum.HumanoidStateType.Running end
HM.ChangeState = function() end
HM.SetStateEnabled = function() end
HM.GetStateEnabled = function() return true end
HM.TakeDamage = function(self, d) local st = self[KEY]; st.props.Health = mmax(0, (st.props.Health or 100) - d) end
HM.EquipTool = function() end
HM.UnequipTools = function() end
HM.GetPlayingAnimationTracks = function() return {} end
HM.AddAccessory = function(self, acc) acc.Parent = self[KEY].props.Parent end
HM.BuildRigFromAttachments = function() end
HM.GetAccessories = function() return {} end
HM.ApplyDescription = function() end
HM.GetAppliedDescription = function() return newInstance("HumanoidDescription") end
impl("Seat").methods.Sit = function() end
impl("VehicleSeat").methods.Sit = function() end
impl("Sound").methods.Play = function(self) self[KEY].props.Playing = true end
impl("Sound").methods.Stop = function(self) self[KEY].props.Playing = false end
impl("Sound").methods.Pause = function(self) self[KEY].props.Playing = false end
impl("Sound").methods.Resume = function(self) self[KEY].props.Playing = true end
impl("ParticleEmitter").methods.Emit = function() end
impl("ParticleEmitter").methods.Clear = function() end
impl("ProximityPrompt").methods.InputHoldBegin = function() end
impl("ProximityPrompt").methods.InputHoldEnd = function() end
impl("BindableEvent").methods.Fire = function(self, ...) fire(getSignal(self[KEY], "Event"), ...) end
impl("BindableFunction").methods.Invoke = function(self, ...)
	local f = self[KEY].props.OnInvoke
	if not f then error("BindableFunction has no OnInvoke callback", 2) end
	return f(...)
end
for _, rc in { "RemoteEvent", "UnreliableRemoteEvent" } do
	impl(rc).methods.FireClient = function() end
	impl(rc).methods.FireAllClients = function() end
	impl(rc).methods.FireServer = function() end
end
impl("RemoteFunction").methods.InvokeClient = function() return nil end
impl("RemoteFunction").methods.InvokeServer = function() return nil end

end
-- Tween ------------------------------------------------------------------------
local TW = impl("Tween")
TW.methods.Play = function(self)
	local st = self[KEY]
	local target = st.target
	for k, v in st.goals do target[k] = v end
	st.props.PlaybackState = Enum.PlaybackState.Completed
	local s = getSignal(st, "Completed")
	task.defer(function() fire(s, Enum.PlaybackState.Completed) end)
end
TW.methods.Cancel = function(self) self[KEY].props.PlaybackState = Enum.PlaybackState.Cancelled end
TW.methods.Pause = function(self) self[KEY].props.PlaybackState = Enum.PlaybackState.Paused end

---------------------------------------------------------------------------
-- Services
---------------------------------------------------------------------------
local getService
do
M.collision = { groups = { "Default" }, pairs = {} }
M.terrainOps = {}
local function pairKey(a, b) if a > b then a, b = b, a end; return a .. "|" .. b end

local DM = impl("DataModel")
local services = {}
function getService(name, create)
	local s = services[name]
	if s then return s end
	local d = CLASSES[name]
	if not d or not d.svc then return nil end
	if not create then return nil end
	s = newInstance(name)
	s[KEY].props.Name = name
	services[name] = s
	if game then
		s[KEY].props.Parent = game
		tinsert(game[KEY].children, s)
	end
	return s
end
M.getService = getService
DM.methods.GetService = function(self, name)
	checkSelf(self, "GetService")
	local s = getService(name, true)
	if not s then error(fmt("'%s' is not a valid Service name", tostring(name)), 2) end
	return s
end
DM.methods.getService = DM.methods.GetService
DM.methods.FindService = function(self, name) return getService(name, false) end
DM.methods.IsLoaded = function() return true end
DM.methods.BindToClose = function() end
DM.methods.GetJobsInfo = function() return {} end
DM.get.Workspace = function() return getService("Workspace", true) end
DM.get.workspace = DM.get.Workspace
DM.get.PlaceId = function() return 0 end
DM.get.GameId = function() return 0 end
DM.get.JobId = function() return "MOCK-JOB" end
DM.get.CreatorId = function() return 0 end
DM.get.PlaceVersion = function() return 0 end

local WS = impl("Workspace")
WS.init = function(self, st)
	local cam = newInstance("Camera")
	cam[KEY].props.Name = "Camera"
	setParent(cam, cam[KEY], self)
	st.props.CurrentCamera = cam
	local ter = newInstance("Terrain")
	ter[KEY].props.Name = "Terrain"
	setParent(ter, ter[KEY], self)
	st.props.Terrain = ter
end
local WSM = WS.methods
for _, n in { "Raycast", "Blockcast", "Spherecast", "Shapecast", "FindPartOnRay", "FindPartOnRayWithIgnoreList", "FindPartOnRayWithWhitelist" } do
	WSM[n] = function() once("ws-" .. n, "Workspace:" .. n .. "() always returns nil in the mock (no physics)"); return nil end
end
for _, n in { "GetPartBoundsInBox", "GetPartBoundsInRadius", "GetPartsInPart", "FindPartsInRegion3", "FindPartsInRegion3WithIgnoreList", "FindPartsInRegion3WithWhiteList" } do
	WSM[n] = function() once("ws-" .. n, "Workspace:" .. n .. "() always returns {} in the mock (no physics)"); return {} end
end
WSM.GetServerTimeNow = function() return 1.7e9 + Sched.now end
WSM.ArePartsTouchingOthers = function() return false end
WSM.GetRealPhysicsFPS = function() return 60 end
WSM.GetNumAwakeParts = function() return 0 end
local TR = impl("Terrain").methods
for _, n in { "FillBlock", "FillBall", "FillCylinder", "FillWedge", "FillRegion", "Clear", "ReplaceMaterial", "WriteVoxels", "FillTerrain" } do
	TR[n] = function(self, ...)
		local args = { ... }
		local rec = { op = n }
		for i, a in args do rec[i] = a end
		tinsert(M.terrainOps, rec)
	end
end
TR.ReadVoxels = function() return {}, {} end
TR.WorldToCell = function(_, p) return V(floor(p.X / 4), floor(p.Y / 4), floor(p.Z / 4)) end
TR.CellCenterToWorld = function(_, x, y, z) return V(x * 4 + 2, y * 4 + 2, z * 4 + 2) end

local PL = impl("Players")
PL.get.LocalPlayer = function() return nil end
PL.methods.GetPlayers = function() return {} end
PL.methods.GetPlayerByUserId = function() return nil end
PL.methods.GetPlayerFromCharacter = function() return nil end
PL.methods.GetNameFromUserIdAsync = function(_, id) return "Player" .. tostring(id) end
PL.methods.GetUserIdFromNameAsync = function() return 1 end
PL.methods.GetUserThumbnailAsync = function(_, id) return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(id) .. "&w=150&h=150", true end
PL.methods.GetFriendsAsync = function() return nil end
PL.methods.GetHumanoidDescriptionFromUserId = function() return newInstance("HumanoidDescription") end
for k, v in { MaxPlayers = 12, RespawnTime = 5, CharacterAutoLoads = true } do impl("Players").defaults[k] = v end

local CS = impl("CollectionService").methods
CS.AddTag = function(_, inst, tag) addTag(inst, tag) end
CS.RemoveTag = function(_, inst, tag) removeTag(inst, tag) end
CS.HasTag = function(_, inst, tag) local st = inst[KEY]; return st.tags ~= nil and st.tags[tag] == true end
CS.GetTags = function(_, inst) return getTags(inst) end
CS.GetTagged = function(_, tag)
	local out = {}
	local set = TAGS[tag]
	if set then
		for inst in set do
			local st = inst[KEY]
			if not st.destroyed and inGame(inst) then tinsert(out, inst) end
		end
	end
	tsort(out, function(a, b) return a[KEY].id < b[KEY].id end)
	return out
end
CS.GetAllTags = function()
	local out = {}
	for t in TAGS do tinsert(out, t) end
	tsort(out)
	return out
end
CS.GetInstanceAddedSignal = function(_, tag)
	anyTagSignals = true
	local s = tagSignals.added[tag]
	if not s then s = newSignal("InstanceAdded:" .. tag); tagSignals.added[tag] = s end
	return s
end
CS.GetInstanceRemovedSignal = function(_, tag)
	anyTagSignals = true
	local s = tagSignals.removed[tag]
	if not s then s = newSignal("InstanceRemoved:" .. tag); tagSignals.removed[tag] = s end
	return s
end

local PS = impl("PhysicsService").methods
local function hasGroup(n) for _, g in M.collision.groups do if g == n then return true end end; return false end
PS.RegisterCollisionGroup = function(_, n) if not hasGroup(n) then tinsert(M.collision.groups, n) end end
PS.CreateCollisionGroup = function(_, n) PS.RegisterCollisionGroup(nil, n); for i, g in M.collision.groups do if g == n then return i - 1 end end end
PS.UnregisterCollisionGroup = function(_, n) for i, g in M.collision.groups do if g == n then tremove(M.collision.groups, i); break end end end
PS.RemoveCollisionGroup = PS.UnregisterCollisionGroup
PS.IsCollisionGroupRegistered = function(_, n) return hasGroup(n) end
PS.CollisionGroupSetCollidable = function(_, a, b, v)
	if not hasGroup(a) or not hasGroup(b) then error("Collision group does not exist: " .. tostring(hasGroup(a) and b or a), 2) end
	M.collision.pairs[pairKey(a, b)] = v and true or false
end
PS.CollisionGroupsAreCollidable = function(_, a, b) local v = M.collision.pairs[pairKey(a, b)]; return v ~= false end
PS.GetRegisteredCollisionGroups = function()
	local out = {}
	for i, g in M.collision.groups do tinsert(out, { name = g, id = i - 1, mask = 0 }) end
	return out
end
PS.GetCollisionGroups = PS.GetRegisteredCollisionGroups
PS.GetMaxCollisionGroups = function() return 32 end
PS.SetPartCollisionGroup = function(_, part, n) part.CollisionGroup = n end
PS.GetCollisionGroupId = function(_, n) for i, g in M.collision.groups do if g == n then return i - 1 end end; return -1 end
PS.GetCollisionGroupName = function(_, id) return M.collision.groups[id + 1] end
PS.RenameCollisionGroup = function(_, a, b) for i, g in M.collision.groups do if g == a then M.collision.groups[i] = b end end end

local TS = impl("TweenService").methods
TS.Create = function(_, inst, info, goals)
	if not isInstance(inst) then error("Unable to cast value to Object", 2) end
	if tname(info) ~= "TweenInfo" then error("Unable to cast value to TweenInfo", 2) end
	for k, v in goals do
		local spec = inst[KEY].info.props[k]
		if not spec then error(fmt("No property named '%s' for object '%s'", tostring(k), inst[KEY].props.Name), 2) end
	end
	local t = newInstance("Tween")
	local st = t[KEY]
	st.target = inst
	st.goals = tclone(goals)
	st.props.TweenInfo = info
	st.props.Instance = inst
	st.props.PlaybackState = Enum.PlaybackState.Begin
	return t
end
TS.GetValue = function(_, a) return a end
TS.SmoothDamp = function(_, cur, target) return target, cur and cur * 0 end

local RS = impl("RunService").methods
RS.IsStudio = function() return false end
RS.IsServer = function() return true end
RS.IsClient = function() return false end
RS.IsRunning = function() return true end
RS.IsRunMode = function() return false end
RS.IsEdit = function() return false end
RS.BindToRenderStep = function() end
RS.UnbindFromRenderStep = function() end
RS.BindToSimulation = function() end

local LT = impl("Lighting").methods
LT.GetMinutesAfterMidnight = function(self) return (self[KEY].props.ClockTime or 14) * 60 end
LT.SetMinutesAfterMidnight = function(self, m) self[KEY].props.ClockTime = (m / 60) % 24 end
LT.GetSunDirection = function() return V(0.5, 0.7, 0.5).Unit end
LT.GetMoonDirection = function() return V(-0.5, 0.7, -0.5).Unit end
impl("Lighting").init = function(_, st) st.props.Ambient = RGB(0.27, 0.27, 0.27); st.props.OutdoorAmbient = RGB(0.5, 0.5, 0.5) end

local guidN = 0
local HS = impl("HttpService").methods
HS.GenerateGUID = function(_, wrap)
	guidN += 1
	local s = fmt("%08X-0000-4000-8000-%012X", guidN, guidN * 7919)
	if wrap == false then return s end
	return "{" .. s .. "}"
end
HS.UrlEncode = function(_, s) return (tostring(s):gsub("[^%w%-_%.~]", function(c) return fmt("%%%02X", c:byte()) end)) end
for _, n in { "GetAsync", "PostAsync", "RequestAsync" } do HS[n] = function() error("HttpService is not allowed to access ROBLOX resources (mock: HTTP disabled)", 2) end end

local TXS = impl("TextService").methods
TXS.GetTextSize = function(_, text, size, _font, frame)
	local lines = 1
	for _ in tostring(text):gmatch("\n") do lines += 1 end
	return V2(mmin(#tostring(text) * size * 0.5, frame and frame.X or huge), lines * size)
end
local TFRmt = newType("TextFilterResult")
TFRmt.__index = function(r, k)
	if k == "GetNonChatStringForBroadcastAsync" or k == "GetNonChatStringForUserAsync" or k == "GetChatForUserAsync" then return function(self) return self._text end end
	error(tostring(k) .. " is not a valid member of TextFilterResult", 2)
end
TXS.FilterStringAsync = function(_, text) return setmetatable({ _text = text }, TFRmt) end
TXS.GetTextBoundsAsync = function(_, params) return V2(100, 14) end

local PFS = impl("PathfindingService").methods
PFS.CreatePath = function()
	local p = newInstance("Path")
	p[KEY].props.Status = Enum.PathStatus.NoPath
	return p
end
PFS.FindPathAsync = function() return PFS.CreatePath() end
impl("Path").methods.ComputeAsync = function() once("path-compute", "Path:ComputeAsync is a no-op in the mock (Status=NoPath)") end
impl("Path").methods.GetWaypoints = function() return {} end
impl("Path").methods.CheckOcclusionAsync = function() return -1 end

local DEB = impl("Debris").methods
DEB.AddItem = function(_, inst, t) task.delay(t or 10, function() if isInstance(inst) then destroy(inst) end end) end

local SG = impl("StarterGui").methods
SG.SetCore = function() end
SG.GetCore = function() return nil end
SG.SetCoreGuiEnabled = function() end
SG.GetCoreGuiEnabled = function() return true end

-- in-memory DataStores ------------------------------------------------------------
local DSmt = newType("DataStore")
local DSm = {}
DSmt.__index = DSm
function DSm.GetAsync(s, k) return s._d[k] end
function DSm.SetAsync(s, k, v) s._d[k] = v end
function DSm.UpdateAsync(s, k, f) local nv = f(s._d[k]); if nv ~= nil then s._d[k] = nv end; return nv end
function DSm.IncrementAsync(s, k, d) s._d[k] = (s._d[k] or 0) + (d or 1); return s._d[k] end
function DSm.RemoveAsync(s, k) local v = s._d[k]; s._d[k] = nil; return v end
function DSm.GetSortedAsync(s) return setmetatable({ IsFinished = true, GetCurrentPage = function() return {} end, AdvanceToNextPageAsync = function() end }, newType("DataStorePages")) end
local stores = {}
local DSS = impl("DataStoreService").methods
DSS.GetDataStore = function(_, n, scope) local k = tostring(n) .. "/" .. tostring(scope); stores[k] = stores[k] or setmetatable({ _d = {} }, DSmt); return stores[k] end
DSS.GetOrderedDataStore = DSS.GetDataStore
DSS.GetGlobalDataStore = function() return DSS.GetDataStore(nil, "global") end
DSS.GetRequestBudgetForRequestType = function() return 100 end
local MS = impl("MessagingService").methods
MS.PublishAsync = function() end
MS.SubscribeAsync = function() return setmetatable({ Connected = true }, ConnMT) end

end
---------------------------------------------------------------------------
-- JSON (also used by HttpService)
---------------------------------------------------------------------------
local JSON = {}
M.JSON = JSON
local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["\b"] = "\\b", ["\f"] = "\\f" }
function JSON.str(s)
	return '"' .. (s:gsub('[%c"\\]', function(c) return ESC[c] or fmt("\\u%04x", c:byte()) end)) .. '"'
end
function JSON.num(n)
	if n ~= n then return "NaN" end
	if n == huge then return "Infinity" end
	if n == -huge then return "-Infinity" end
	if n == floor(n) and abs(n) < 1e15 then return fmt("%d", n) end
	if abs(n) >= 1e-4 then
		local s = fmt("%.6f", n):gsub("0+$", "")
		if s:sub(-1) == "." then s = s:sub(1, -2) end
		if s == "-0" then s = "0" end
		return s
	end
	return fmt("%.6g", n)
end
-- higher precision variant used for CFrame components in dumps
function JSON.nump(n)
	if n ~= n or n == huge or n == -huge or (n == floor(n) and abs(n) < 1e15) then return JSON.num(n) end
	local s = fmt("%.9f", n):gsub("0+$", "")
	if s:sub(-1) == "." then s = s:sub(1, -2) end
	if s == "-0" then s = "0" end
	return s
end
function JSON.encode(v, seen)
	local t = rawtype(v)
	if v == nil then return "null" end
	if t == "boolean" then return v and "true" or "false" end
	if t == "number" then return JSON.num(v) end
	if t == "string" then return JSON.str(v) end
	if t == "table" then
		local tn = tname(v)
		if tn ~= "table" then
			if tn == "Vector3" then return "[" .. JSON.num(v.X) .. "," .. JSON.num(v.Y) .. "," .. JSON.num(v.Z) .. "]" end
			return JSON.str(tostring(v))
		end
		seen = seen or {}
		if seen[v] then error("cyclic table in JSON encode", 2) end
		seen[v] = true
		local n = #v
		local out = {}
		if n > 0 or next(v) == nil then
			for i = 1, n do out[i] = JSON.encode(v[i], seen) end
			seen[v] = nil
			return "[" .. tconcat(out, ",") .. "]"
		end
		local keys = {}
		for k in v do tinsert(keys, tostring(k)) end
		tsort(keys)
		for _, k in keys do
			local val = v[k]
			if val == nil then val = v[tonumber(k)] end
			tinsert(out, JSON.str(k) .. ":" .. JSON.encode(val, seen))
		end
		seen[v] = nil
		return "{" .. tconcat(out, ",") .. "}"
	end
	return JSON.str(tostring(v))
end
function JSON.decode(s)
	local pos = 1
	local function ws() pos = s:find("[^ \t\r\n]", pos) or #s + 1 end
	local val
	local function str()
		local out = {}
		pos += 1
		while true do
			local c = s:sub(pos, pos)
			if c == "" then error("unterminated string") end
			if c == '"' then pos += 1; break end
			if c == "\\" then
				local e = s:sub(pos + 1, pos + 1)
				local map = { n = "\n", r = "\r", t = "\t", b = "\b", f = "\f", ["/"] = "/", ["\\"] = "\\", ['"'] = '"' }
				if e == "u" then tinsert(out, utf8.char(tonumber(s:sub(pos + 2, pos + 5), 16))); pos += 6
				else tinsert(out, map[e] or e); pos += 2 end
			else
				tinsert(out, c); pos += 1
			end
		end
		return tconcat(out)
	end
	val = function()
		ws()
		local c = s:sub(pos, pos)
		if c == "{" then
			local o = {}
			pos += 1; ws()
			if s:sub(pos, pos) == "}" then pos += 1; return o end
			while true do
				ws(); local k = str(); ws(); pos += 1
				o[k] = val(); ws()
				local d = s:sub(pos, pos); pos += 1
				if d == "}" then return o end
			end
		elseif c == "[" then
			local a = {}
			pos += 1; ws()
			if s:sub(pos, pos) == "]" then pos += 1; return a end
			while true do
				tinsert(a, val()); ws()
				local d = s:sub(pos, pos); pos += 1
				if d == "]" then return a end
			end
		elseif c == '"' then return str()
		elseif s:sub(pos, pos + 3) == "true" then pos += 4; return true
		elseif s:sub(pos, pos + 4) == "false" then pos += 5; return false
		elseif s:sub(pos, pos + 3) == "null" then pos += 4; return nil
		else
			local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
			if not num or num == "" then error("Can't parse JSON at " .. pos, 0) end
			pos += #num
			return tonumber(num)
		end
	end
	return val()
end
impl("HttpService").methods.JSONEncode = function(_, v) return JSON.encode(v) end
impl("HttpService").methods.JSONDecode = function(_, s) return JSON.decode(s) end

---------------------------------------------------------------------------
-- Instance library, game tree, globals
---------------------------------------------------------------------------
local InstanceLib = {}
function InstanceLib.new(className, parent)
	if rawtype(className) ~= "string" then error("invalid argument #1 to 'new' (string expected, got " .. tname(className) .. ")", 2) end
	local d = CLASSES[className]
	if not d then error(fmt("Unable to create an Instance of type \"%s\"", className), 2) end
	if d.nc or d.svc then error(fmt("Unable to create an Instance of type \"%s\"", className), 2) end
	local i = newInstance(className)
	if parent ~= nil then i.Parent = parent end
	return i
end
function InstanceLib.fromExisting(inst)
	local s = inst[KEY]
	local c = newInstance(s.cls)
	for k, v in s.props do if k ~= "Parent" then c[KEY].props[k] = v end end
	for k, v in s.attrs do c[KEY].attrs[k] = v end
	return c
end
freeze(InstanceLib)

game = newInstance("DataModel")
game[KEY].props.Name = "Game"
M.game = game
for _, n in { "Workspace", "Players", "Lighting", "ReplicatedFirst", "ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterGui", "StarterPack", "StarterPlayer", "Teams", "SoundService", "Chat", "TextChatService", "LocalizationService", "TestService" } do
	getService(n, true)
end
local workspace = getService("Workspace", true)
M.workspace = workspace
do
	local sp = getService("StarterPlayer", true)
	for _, n in { "StarterPlayerScripts", "StarterCharacterScripts" } do
		local c = newInstance(n)
		c[KEY].props.Name = n
		setParent(c, c[KEY], sp)
	end
end

-- require ---------------------------------------------------------------------
local SOURCES = {}
local moduleCache = {}
local loading = {}
M.modulesLoaded = {}
local G -- forward
local function requireModule(mod)
	if not isInstance(mod) then
		error("Attempted to call require with invalid argument(s).", 2)
	end
	local st = mod[KEY]
	if st.cls ~= "ModuleScript" then error("Attempted to call require with invalid argument(s).", 2) end
	local cached = moduleCache[mod]
	if cached then return cached.value end
	if loading[mod] then error("Requested module was required recursively", 2) end
	local src = st.file and SOURCES[st.file]
	if not src then error("ModuleScript " .. fullName(mod) .. " has no source in the mock", 2) end
	local fn, err = loadstring(src, "=" .. fullName(mod))
	if not fn then error("Syntax error in " .. fullName(mod) .. ": " .. tostring(err), 2) end
	setfenv(fn, setmetatable({ script = mod }, { __index = G }))
	loading[mod] = true
	local t0 = os.clock()
	local r = pack(fn())
	loading[mod] = nil
	if r.n ~= 1 then error("Module code did not return exactly one value (" .. fullName(mod) .. ")", 2) end
	moduleCache[mod] = { value = r[1] }
	tinsert(M.modulesLoaded, { name = fullName(mod), file = st.file, seconds = os.clock() - t0 })
	return r[1]
end
M.require = requireModule

function M.loadTree(manifest, sources)
	SOURCES = sources
	for _, e in manifest do
		local segs = e.path
		local parent = getService(segs[1], true)
		if not parent then
			parent = IM.FindFirstChild(game, segs[1])
			if not parent then
				parent = newInstance("Folder")
				parent[KEY].props.Name = segs[1]
				setParent(parent, parent[KEY], game)
			end
		end
		for i = 2, #segs - 1 do
			local nx = IM.FindFirstChild(parent, segs[i])
			if not nx then
				nx = newInstance("Folder")
				nx[KEY].props.Name = segs[i]
				setParent(nx, nx[KEY], parent)
			end
			parent = nx
		end
		local name = segs[#segs]
		if #segs >= 2 then
			local existing = IM.FindFirstChild(parent, name)
			if existing and e.class ~= "Folder" and existing[KEY].cls == "Folder" then
				-- a folder created implicitly earlier is really a script with children: convert
				local inst = newInstance(e.class)
				inst[KEY].props.Name = name
				inst[KEY].file = e.file
				for _, ch in IM.GetChildren(existing) do setParent(ch, ch[KEY], inst) end
				destroy(existing)
				setParent(inst, inst[KEY], parent)
			elseif not existing then
				local inst = newInstance(e.class)
				inst[KEY].props.Name = name
				inst[KEY].file = e.file
				setParent(inst, inst[KEY], parent)
			end
		end
	end
end

-- globals ----------------------------------------------------------------------
local TICK_BASE = 1.7e9
local function joinArgs(...)
	local n = select("#", ...)
	local t = {}
	for i = 1, n do t[i] = tostring((select(i, ...))) end
	return tconcat(t, " ")
end
local robloxDebug = setmetatable({
	profilebegin = function() end, profileend = function() end, setmemorycategory = function() end,
	resetmemorycategory = function() end, dumpcodesize = function() end,
}, { __index = debug })
local DTmt = newType("DateTime")
local DateTime = {}
local function mkDT(ms)
	return setmetatable({ UnixTimestampMillis = ms, UnixTimestamp = floor(ms / 1000),
		ToIsoDate = function(self) return os.date("!%Y-%m-%dT%H:%M:%SZ", self.UnixTimestamp) end,
		FormatUniversalTime = function(self, f) return os.date("!%Y-%m-%d %H:%M:%S", self.UnixTimestamp) end,
		FormatLocalTime = function(self, f) return os.date("!%Y-%m-%d %H:%M:%S", self.UnixTimestamp) end,
		ToUniversalTime = function(self) local d = os.date("!*t", self.UnixTimestamp); return { Year = d.year, Month = d.month, Day = d.day, Hour = d.hour, Minute = d.min, Second = d.sec, Millisecond = self.UnixTimestampMillis % 1000 } end,
	}, DTmt)
end
function DateTime.now() return mkDT(floor((TICK_BASE + Sched.now) * 1000)) end
function DateTime.fromUnixTimestamp(t) return mkDT(floor(t * 1000)) end
function DateTime.fromUnixTimestampMillis(t) return mkDT(floor(t)) end

math.randomseed(20240601)

G = {
	game = game, Game = game, workspace = workspace, Workspace = workspace,
	Instance = InstanceLib, Vector3 = Vector3, Vector2 = Vector2, Vector3int16 = Vector3int16, Vector2int16 = Vector2int16,
	CFrame = CFrame, Color3 = Color3, BrickColor = BrickColor, UDim = UDim, UDim2 = UDim2,
	NumberRange = NumberRange, NumberSequence = NumberSequence, NumberSequenceKeypoint = NumberSequenceKeypoint,
	ColorSequence = ColorSequence, ColorSequenceKeypoint = ColorSequenceKeypoint, Rect = Rect,
	PhysicalProperties = PhysicalProperties, TweenInfo = TweenInfo, Random = Random, RaycastParams = RaycastParams,
	OverlapParams = OverlapParams, Ray = Ray, Region3 = Region3, Font = Font, Axes = Axes, Faces = Faces, DateTime = DateTime,
	Enum = Enum, typeof = tname, type = robloxType, require = requireModule, task = task,
	wait = function(t) local dt = task.wait(t); return dt, Sched.now end,
	delay = function(t, f) task.delay(t, f) end,
	spawn = function(f) task.defer(f) end,
	Wait = function(t) local dt = task.wait(t); return dt, Sched.now end,
	Delay = function(t, f) task.delay(t, f) end,
	Spawn = function(f) task.defer(f) end,
	tick = function() return TICK_BASE + Sched.now end,
	time = function() return Sched.now end,
	elapsedTime = function() return Sched.now end,
	warn = function(...) M.stats.warnings += 1; rawprint("[warn] " .. joinArgs(...)) end,
	print = function(...) if not M.quiet then rawprint("[print] " .. joinArgs(...)) end end,
	printidentity = function() end,
	shared = {}, _G = {},
	ypcall = pcall,
	version = function() return "0.741.0.mock" end,
	settings = function() return setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return nil end }) end }) end,
	UserSettings = function() return setmetatable({}, { __index = function() return function() return nil end end }) end,
	debug = robloxDebug,
	plugin = nil,
}
setmetatable(G, { __index = BUILTINS })
M.G = G

-- Helper to run a function as if it were a Script body in the mock environment.
function M.envFor(scriptInst)
	return setmetatable({ script = scriptInst }, { __index = G })
end

-- Run fn as the main thread under the scheduler; returns ok, result/traceback, status
function M.runMain(fn, opts)
	opts = opts or {}
	local done, ok, res = false, false, nil
	local co = coroutine.create(function()
		ok, res = xpcall(fn, traceHandler)
		done = true
	end)
	local okr, err = coroutine.resume(co)
	if not okr then return false, tostring(err) .. "\n" .. debug.traceback(co), "crash" end
	local limit = opts.timeout or 30
	local status = Sched.run(limit, opts.maxSteps or 500000, function() return done end)
	if not done then
		return false, "main thread did not finish (blocked or yielding beyond " .. limit .. " virtual seconds; scheduler status: " .. status .. ")\n" .. debug.traceback(co), "blocked"
	end
	return ok, res, "done"
end
function M.settle(seconds)
	return Sched.run(Sched.now + (seconds or 1), 200000)
end

return M
