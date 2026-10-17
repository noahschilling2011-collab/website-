--!strict
-- The guide's ring layer (ONBOARDING_SPEC A2.4 / A9, menu package): a gold ring around the one button to press, a
-- short dim with a hole at the first contact, and (world steps only) a chip "Tap to open the lab ›" left of the HUD
-- column. Own ScreenGui "AIEmpire_Guide", DisplayOrder 22 (above HUD 10, Dim 19 and Overlay 20; below Intro 25,
-- Phone 28 and Top 30), CoreUISafeInsets like the HUD and the Computer, no UIScale on the root: it works in the
-- screen units of AbsolutePosition / AbsoluteSize.
-- It never blocks input: every object is a plain Frame / TextLabel with Active = false and InputSink = None; nothing
-- here is a GuiButton. Positions follow the targets every frame (RenderStepped) while something shows.
-- [A] the two ScreenGuis share CoreUISafeInsets, so AbsolutePosition values line up; check at 844x390 and 1280x720.
-- Fix round 1 (review): the ring pulses (stroke 0 <-> 0.55 and pad 6 <-> 12, 0.8 s Sine each way, A9) by a per-frame
-- phase only while it shows (no tween runs for the whole session; static with ReducedMotion); its rect stays inside the
-- guide root (the safe area) and, on a side where another button is closer than 8 px, the pad shrinks to the gap so the
-- ring and its glow never cover a neighbouring button.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local C = Theme.colors
local F = Theme.font

local Guide = {}

Guide.ORDER = 22
Guide.PAD = 6 -- ring padding around the target (screen px)
Guide.PAD_PULSE = 12 -- the pad at the pulse's peak (A9: pad 6 <-> 12)
Guide.PULSE_SECONDS = 0.8 -- one way (TweenInfo 0.8 s, Sine, InOut, reverses)
Guide.NEIGHBOUR_GAP = 8 -- a button closer than this to the target limits the pad on that side
Guide.STROKE = 3 -- the ring stroke (drawn outside the ring frame)
Guide.GLOW = 10 -- the glow reaches this far beyond the ring (4 px offset + 6 px stroke)
Guide.DIM_IN, Guide.DIM_HOLD, Guide.DIM_OUT = 0.2, 2.5, 0.4
Guide.DIM_TRANSPARENCY = 0.52

export type Rect = { x: number, y: number, w: number, h: number }

local gui: ScreenGui? = nil
local rootFrame: Frame? = nil
local ring: Frame? = nil
local ringStroke: UIStroke? = nil
local glow: Frame? = nil
local chip: TextLabel? = nil
local dims: { Frame } = {}

local ringTarget: GuiObject? = nil
local holeTargets: { GuiObject } = {}
local chipText: string? = nil
local chipAnchor: GuiObject? = nil -- the chip sits left of this (the HUD column), centred on the ring
local dimUntil = 0
local dimStarted = 0
local neighbours: { GuiObject } = {} -- buttons around the ring target (refreshed while the ring shows)
local neighboursAt = -math.huge
local staticPulse: boolean? = nil -- tests / previews: force the static ring (nil = follow ReducedMotion)

-- every guide object: never a button, never active, never sinks input
local function passive(obj: GuiObject)
	obj.Active = false
	obj.Selectable = false
	pcall(function()
		obj.InputSink = Enum.InputSink.None
	end)
end

local function reducedMotion(): boolean
	local ok, value = pcall(function(): any
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and value == true
end

-- visible = the object and every GuiObject ancestor is Visible, its ScreenGui is enabled, and it has a size
function Guide.visible(obj: GuiObject?): boolean
	if obj == nil or obj.Parent == nil then
		return false
	end
	local node: Instance? = obj
	while node do
		if node:IsA("GuiObject") and not (node :: GuiObject).Visible then
			return false
		end
		if node:IsA("LayerCollector") then
			if node:IsA("ScreenGui") and not (node :: ScreenGui).Enabled then
				return false
			end
			break
		end
		node = node.Parent
	end
	local size = obj.AbsoluteSize
	return size.X > 0 and size.Y > 0
end

-- the target rect in guide-root coordinates (nil = hidden: invisible, no size, or clipped by its ScrollingFrame)
function Guide.rectOf(obj: GuiObject?): Rect?
	local root = rootFrame
	if not root or not obj or not Guide.visible(obj) then
		return nil
	end
	local p, s = obj.AbsolutePosition, obj.AbsoluteSize
	local node: Instance? = obj.Parent
	while node do
		if node:IsA("ScrollingFrame") then
			local sp, ss = (node :: GuiObject).AbsolutePosition, (node :: GuiObject).AbsoluteSize
			if p.Y < sp.Y - 1 or p.Y + s.Y > sp.Y + ss.Y + 1 or p.X < sp.X - 1 or p.X + s.X > sp.X + ss.X + 1 then
				return nil -- (partly) scrolled out of view
			end
		end
		if node:IsA("LayerCollector") then
			break
		end
		node = node.Parent
	end
	local o = root.AbsolutePosition
	return { x = p.X - o.X, y = p.Y - o.Y, w = s.X, h = s.Y }
end

local function union(rects: { Rect }): Rect?
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, r in rects do
		x0, y0 = math.min(x0, r.x), math.min(y0, r.y)
		x1, y1 = math.max(x1, r.x + r.w), math.max(y1, r.y + r.h)
	end
	if x0 == math.huge then
		return nil
	end
	return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

local function setDims(hole: Rect?, transparency: number)
	local root = rootFrame
	if not root then
		return
	end
	local W, H = root.AbsoluteSize.X, root.AbsoluteSize.Y
	local on = hole ~= nil and transparency < 1
	for _, d in dims do
		d.Visible = on
		d.BackgroundTransparency = transparency
	end
	if not on or not hole then
		return
	end
	-- the dim covers the whole screen including the safe-area strips (frames reach past the root)
	local big = 4000
	local x0, y0 = hole.x - Guide.PAD, hole.y - Guide.PAD
	local x1, y1 = hole.x + hole.w + Guide.PAD, hole.y + hole.h + Guide.PAD
	local top, bottom, left, right = dims[1], dims[2], dims[3], dims[4]
	top.Position = UDim2.fromOffset(-big, -big)
	top.Size = UDim2.fromOffset(W + 2 * big, y0 + big)
	bottom.Position = UDim2.fromOffset(-big, y1)
	bottom.Size = UDim2.fromOffset(W + 2 * big, math.max(0, H - y1) + big)
	left.Position = UDim2.fromOffset(-big, y0)
	left.Size = UDim2.fromOffset(x0 + big, y1 - y0)
	right.Position = UDim2.fromOffset(x1, y0)
	right.Size = UDim2.fromOffset(math.max(0, W - x1) + big, y1 - y0)
end

-- the other buttons of the target's ScreenGui near it (not the target, not a frame around it)
local function findNeighbours(target: GuiObject): { GuiObject }
	local out: { GuiObject } = {}
	local layer = target:FindFirstAncestorWhichIsA("LayerCollector")
	if not layer then
		return out
	end
	local tp, ts = target.AbsolutePosition, target.AbsoluteSize
	local reach = Guide.PAD_PULSE + Guide.GLOW + Guide.NEIGHBOUR_GAP
	for _, d in layer:GetDescendants() do
		if d:IsA("GuiButton") and d ~= target and not d:IsAncestorOf(target) and not target:IsAncestorOf(d) then
			local p, sz = d.AbsolutePosition, d.AbsoluteSize
			local near = p.X < tp.X + ts.X + reach and p.X + sz.X > tp.X - reach and p.Y < tp.Y + ts.Y + reach and p.Y + sz.Y > tp.Y - reach
			if near then
				table.insert(out, d)
			end
		end
	end
	return out
end

-- the pulse phase 0..1 (0 = pad 6, stroke opaque); 0 with ReducedMotion
local function pulse(): number
	local still = if staticPulse ~= nil then staticPulse else reducedMotion()
	if still then
		return 0
	end
	local t = os.clock() / Guide.PULSE_SECONDS
	return (1 - math.cos(math.pi * t)) / 2
end

-- the ring's pads (left, top, right, bottom): the pulse pad, cut on a side where a neighbouring button is closer than
-- the pad + stroke (so a button 8 px away gets a 5 px pad), then kept inside the root (the safe area)
local function ringPads(rect: Rect, base: number, W: number, H: number): (number, number, number, number, boolean)
	local l, t, r, b = base, base, base, base
	local cramped = false
	for _, n in neighbours do
		local nr = Guide.rectOf(n)
		if nr and not (nr.x <= rect.x and nr.y <= rect.y and nr.x + nr.w >= rect.x + rect.w and nr.y + nr.h >= rect.y + rect.h) then
			local overlapY = nr.y < rect.y + rect.h and nr.y + nr.h > rect.y
			local overlapX = nr.x < rect.x + rect.w and nr.x + nr.w > rect.x
			-- the ring (pad + stroke) never reaches the neighbour; the glow needs PAD_PULSE + GLOW of room (no flicker)
			local function cut(gap: number, pad: number): number
				if gap < Guide.PAD_PULSE + Guide.GLOW then
					cramped = true
				end
				return math.max(0, math.min(pad, gap - Guide.STROKE))
			end
			if overlapY then
				if nr.x + nr.w <= rect.x then
					l = cut(rect.x - (nr.x + nr.w), l)
				elseif nr.x >= rect.x + rect.w then
					r = cut(nr.x - (rect.x + rect.w), r)
				end
			end
			if overlapX then
				if nr.y + nr.h <= rect.y then
					t = cut(rect.y - (nr.y + nr.h), t)
				elseif nr.y >= rect.y + rect.h then
					b = cut(nr.y - (rect.y + rect.h), b)
				end
			end
		end
	end
	-- the safe area: the ring and its stroke stay inside the root (never under the notch / home indicator strips)
	local s = Guide.STROKE
	l = math.max(0, math.min(l, rect.x - s))
	t = math.max(0, math.min(t, rect.y - s))
	r = math.max(0, math.min(r, W - s - (rect.x + rect.w)))
	b = math.max(0, math.min(b, H - s - (rect.y + rect.h)))
	if rect.x - l - Guide.GLOW < 0 or rect.y - t - Guide.GLOW < 0 or rect.x + rect.w + r + Guide.GLOW > W or rect.y + rect.h + b + Guide.GLOW > H then
		cramped = true
	end
	return l, t, r, b, cramped
end

-- Places ring, chip and dim from the current targets (every frame while something shows; tests and the preview call
-- it directly after the layout pass).
function Guide.update()
	local r, st, g, c = ring, ringStroke, glow, chip
	if not r or not st or not g or not c then
		return
	end
	local rect = Guide.rectOf(ringTarget)
	r.Visible = rect ~= nil
	g.Visible = rect ~= nil
	local root = rootFrame
	if rect and root then
		local target = ringTarget :: GuiObject
		local now = os.clock()
		if now - neighboursAt > 1 then
			neighboursAt = now
			neighbours = findNeighbours(target)
		end
		local k = pulse()
		st.Transparency = 0.55 * k
		local base = Guide.PAD + (Guide.PAD_PULSE - Guide.PAD) * k
		local W, H = root.AbsoluteSize.X, root.AbsoluteSize.Y
		local l, t, rr, b, cramped = ringPads(rect, base, W, H)
		r.Position = UDim2.fromOffset(rect.x - l, rect.y - t)
		r.Size = UDim2.fromOffset(rect.w + l + rr, rect.h + t + b)
		-- the soft glow only where it has room (it would spill onto a neighbour or past the safe area otherwise)
		g.Visible = not cramped
		g.Position = UDim2.fromOffset(rect.x - l - 4, rect.y - t - 4)
		g.Size = UDim2.fromOffset(rect.w + l + rr + 8, rect.h + t + b + 8)
	end
	-- chip: left of its anchor (the HUD column), vertically centred on the ring; world steps only
	local anchor = Guide.rectOf(chipAnchor)
	c.Visible = chipText ~= nil and rect ~= nil and anchor ~= nil
	if c.Visible and rect and anchor then
		c.Text = (chipText or "") .. "  ›"
		local w = c.AbsoluteSize.X
		c.Position = UDim2.fromOffset(anchor.x - 10 - w, rect.y + rect.h / 2 - c.AbsoluteSize.Y / 2)
	end
	-- dim: in 0.2 s, hold, out 0.4 s; the hole is the ring rect, or the union of the hole targets (HUD card + row)
	local now = os.clock()
	if now < dimUntil then
		local holes: { Rect } = {}
		for _, t in holeTargets do
			local hr = Guide.rectOf(t)
			if hr then
				table.insert(holes, hr)
			end
		end
		local hole = if #holes > 0 then union(holes) else rect
		local into = now - dimStarted
		local left = dimUntil - now
		local k = math.min(1, into / Guide.DIM_IN, left / Guide.DIM_OUT)
		setDims(hole, 1 - (1 - Guide.DIM_TRANSPARENCY) * math.clamp(k, 0, 1))
	else
		setDims(nil, 1)
	end
end

-- ring on `target` (nil = no ring)
function Guide.setRing(target: GuiObject?)
	if target ~= ringTarget then
		neighbours = {}
		neighboursAt = -math.huge
	end
	ringTarget = target
	Guide.update()
end

-- tests / previews: true = the static ring of ReducedMotion (pad 6, opaque stroke), nil = follow the device setting
function Guide.setStaticPulse(on: boolean?)
	staticPulse = on
end

function Guide.ringTarget(): GuiObject?
	return ringTarget
end

-- chip text (nil = no chip), placed left of `anchor`
function Guide.setChip(text: string?, anchor: GuiObject?)
	chipText = text
	chipAnchor = anchor
	Guide.update()
end

-- the first-contact dim: hole = union of `holes` (or the ring rect when empty), for DIM_HOLD seconds
function Guide.dim(holes: { GuiObject }?)
	holeTargets = holes or {}
	dimStarted = os.clock()
	dimUntil = dimStarted + Guide.DIM_IN + Guide.DIM_HOLD + Guide.DIM_OUT
	Guide.update()
end

-- any input ends the dim early (it never blocks a tap anyway)
function Guide.endDim()
	local now = os.clock()
	if now < dimUntil - Guide.DIM_OUT then
		dimUntil = now + Guide.DIM_OUT
		dimStarted = math.min(dimStarted, now - Guide.DIM_IN)
	end
end

function Guide.dimming(): boolean
	return os.clock() < dimUntil
end

function Guide.clear()
	ringTarget = nil
	chipText = nil
	chipAnchor = nil
	holeTargets = {}
	dimUntil = 0
	Guide.update()
end

-- test / preview helpers
function Guide.chipText(): string?
	return chipText
end

function Guide.parts(): { ring: Frame?, glow: Frame?, chip: TextLabel?, dims: { Frame }, root: Frame?, gui: ScreenGui? }
	return { ring = ring, glow = glow, chip = chip, dims = dims, root = rootFrame, gui = gui }
end

function Guide.mount(playerGui: Instance?)
	local parent = playerGui or Players.LocalPlayer:WaitForChild("PlayerGui")
	local old = parent:FindFirstChild("AIEmpire_Guide")
	if old then
		old:Destroy()
	end
	local g = Instance.new("ScreenGui")
	g.Name = "AIEmpire_Guide"
	g.ResetOnSpawn = false
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	g.DisplayOrder = Guide.ORDER
	g.Parent = parent
	gui = g

	local root = Kit.frame(g)
	root.Name = "Root"
	passive(root)
	rootFrame = root

	dims = {}
	for i = 1, 4 do
		local d = Kit.frame(root, UDim2.fromOffset(0, 0))
		d.Name = "Dim" .. i
		d.BackgroundColor3 = C.black
		d.BackgroundTransparency = 1
		d.Visible = false
		d.ZIndex = 1
		passive(d)
		table.insert(dims, d)
	end

	local gl = Kit.frame(root, UDim2.fromOffset(0, 0))
	gl.Name = "GuideGlow"
	gl.Visible = false
	gl.ZIndex = 2
	Kit.corner(gl, 18)
	local glowStroke = Kit.stroke(gl, 0.72, C.warn, 6)
	glowStroke.Name = "Glow"
	passive(gl)
	glow = gl

	local r = Kit.frame(root, UDim2.fromOffset(0, 0))
	r.Name = "GuideRing"
	r.Visible = false
	r.ZIndex = 3
	Kit.corner(r, 14)
	local st = Kit.stroke(r, 0, C.warn, Guide.STROKE)
	passive(r)
	ring = r
	ringStroke = st
	-- the pulse is a per-frame phase in Guide.update (only while the ring shows), not a tween for the whole session

	local c = Kit.text(root, "", 13, F.bold, C.text)
	c.Name = "GuideChip"
	c.Visible = false
	c.ZIndex = 4
	c.BackgroundColor3 = C.bg
	c.BackgroundTransparency = 0.05
	Kit.corner(c, 12)
	Kit.stroke(c, 0, C.warn, 2)
	Kit.padding(c, 8, 14, 8, 14)
	passive(c)
	chip = c

	UserInputService.InputBegan:Connect(function()
		Guide.endDim()
	end)
	RunService.RenderStepped:Connect(function()
		if ringTarget ~= nil or os.clock() < dimUntil or chipText ~= nil then
			Guide.update()
		end
	end)
	return g
end

return Guide
