--!nocheck
-- guidump: GUI tree dumper for the headless Roblox mock (harness/mock.luau).
--
-- Walks LayerCollectors (ScreenGui / BillboardGui / SurfaceGui) and GuiObjects and prints one JSON line
-- per node ("@@GUI {...}"), which tools/guiprev/guiprev.py lays out and draws. Layout modifiers
-- (UICorner, UIStroke, UIPadding, UIListLayout, UIGridLayout, UIScale, UIAspectRatioConstraint,
-- UISizeConstraint, UITextSizeConstraint, UIGradient, UIFlexItem) are folded into their parent's "mods".
--
-- Property values are read from the mock. Where the mock's typed default (zero / first enum item) differs
-- from the Roblox engine default and the property was never assigned, the Roblox default from
-- ROBLOX_DEFAULTS below is used instead (e.g. TextXAlignment Center, UIScale.Scale 1, UIStroke.Thickness 1,
-- UIListLayout.FillDirection Vertical, UICorner.CornerRadius 0,8).
--
-- Also: setViewport (gives ScreenGuis a real AbsoluteSize so viewport-dependent code such as UIRoot's
-- scale runs) and applyFeedback (writes AbsoluteSize/AbsolutePosition computed by guiprev.py back into
-- the mock and fires the change signals, so code that positions things from AbsoluteSize runs too).
--
-- Usage inside a scene script (see scenes/shop.luau):
--   local GuiDump = require("../guidump")
--   GuiDump.init(M)                                   -- M = harness mock module
--   GuiDump.setViewport(playerGui, 1280, 720, { top = 58, right = 0, bottom = 0, left = 0 })
--   GuiDump.applyFeedback(playerGui, feedbackTable)   -- optional (guiprev passes it)
--   GuiDump.dump({ playerGui, someBillboardGui })     -- prints the @@GUI lines

local GuiDump = {}
local M = nil
local KEY = nil

function GuiDump.init(mock)
	M = mock
	KEY = mock.KEY
end

---------------------------------------------------------------------------------------- defaults
local INF = math.huge
local function c3(r, g, b) return { __c3 = true, r, g, b } end -- 0-255, converted lazily

-- class -> { prop -> Roblox engine default } (only where the mock's typed default is wrong)
local ROBLOX_DEFAULTS = {
	GuiObject = { BorderColor3 = c3(27, 42, 53), BorderMode = "Outline", SizeConstraint = "RelativeXY" },
	TextLabel = { TextXAlignment = "Center", TextYAlignment = "Center", TextColor3 = c3(27, 42, 53), TextStrokeColor3 = c3(0, 0, 0),
		TextStrokeTransparency = 1, LineHeight = 1, MaxVisibleGraphemes = -1, Font = "SourceSans" },
	TextButton = { TextXAlignment = "Center", TextYAlignment = "Center", TextColor3 = c3(27, 42, 53), TextStrokeColor3 = c3(0, 0, 0),
		TextStrokeTransparency = 1, LineHeight = 1, MaxVisibleGraphemes = -1, Font = "SourceSans", Text = "Button" },
	TextBox = { TextXAlignment = "Center", TextYAlignment = "Center", TextColor3 = c3(27, 42, 53), TextStrokeColor3 = c3(0, 0, 0),
		TextStrokeTransparency = 1, LineHeight = 1, MaxVisibleGraphemes = -1, Font = "SourceSans", PlaceholderColor3 = c3(178, 178, 178) },
	ScrollingFrame = { CanvasSize = { __udim2 = true, 0, 0, 2, 0 }, ScrollBarThickness = 12, ScrollingDirection = "XY", ScrollingEnabled = true,
		ScrollBarImageColor3 = c3(0, 0, 0), VerticalScrollBarInset = "None", HorizontalScrollBarInset = "None", ElasticBehavior = "WhenScrollable" },
	UIListLayout = { FillDirection = "Vertical", HorizontalAlignment = "Left", VerticalAlignment = "Top", SortOrder = "LayoutOrder",
		HorizontalFlex = "None", VerticalFlex = "None", ItemLineAlignment = "Automatic" },
	UIGridLayout = { FillDirection = "Horizontal", HorizontalAlignment = "Left", VerticalAlignment = "Top", SortOrder = "LayoutOrder",
		CellSize = { __udim2 = true, 0, 100, 0, 100 }, CellPadding = { __udim2 = true, 0, 5, 0, 5 }, StartCorner = "TopLeft" },
	UICorner = { CornerRadius = { __udim = true, 0, 8 } },
	UIStroke = { Color = c3(0, 0, 0), Thickness = 1, ApplyStrokeMode = "Contextual", LineJoinMode = "Round" },
	UIScale = { Scale = 1 },
	UIAspectRatioConstraint = { AspectRatio = 1, AspectType = "FitWithinMaxSize", DominantAxis = "Width" },
	UISizeConstraint = { MaxSize = { __v2 = true, INF, INF } },
	UITextSizeConstraint = { MaxTextSize = 100, MinTextSize = 1 },
	UIGradient = { Rotation = 0 },
	ScreenGui = { ScreenInsets = "CoreUISafeInsets", ZIndexBehavior = "Sibling", DisplayOrder = 0, IgnoreGuiInset = false },
	BillboardGui = { ZIndexBehavior = "Sibling" },
	SurfaceGui = { ZIndexBehavior = "Sibling", SizingMode = "FixedSize", PixelsPerStud = 50, Face = "Front" },
	ImageLabel = { ScaleType = "Stretch" },
	ImageButton = { ScaleType = "Stretch" },
}
-- inheritance used for the lookup above
local DEFAULT_CHAIN = {
	TextLabel = { "TextLabel", "GuiObject" }, TextButton = { "TextButton", "GuiObject" }, TextBox = { "TextBox", "GuiObject" },
	ScrollingFrame = { "ScrollingFrame", "GuiObject" }, ImageLabel = { "ImageLabel", "GuiObject" }, ImageButton = { "ImageButton", "GuiObject" },
}

------------------------------------------------------------------------------------- encoding
local function r3(x) return math.floor(x * 1000 + 0.5) / 1000 end

local function enc(v)
	if v == nil then return nil end
	local t = M.typeof(v)
	if t == "number" then
		if v == INF then return 1e30 end
		if v == -INF then return -1e30 end
		if v ~= v then return 0 end
		return v
	elseif t == "boolean" or t == "string" then
		return v
	elseif t == "UDim2" then
		return { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset }
	elseif t == "UDim" then
		return { v.Scale, v.Offset }
	elseif t == "Vector2" then
		return { enc(v.X), enc(v.Y) }
	elseif t == "Vector3" then
		return { v.X, v.Y, v.Z }
	elseif t == "Color3" then
		return { math.floor(v.R * 255 + 0.5), math.floor(v.G * 255 + 0.5), math.floor(v.B * 255 + 0.5) }
	elseif t == "EnumItem" then
		return v.Name
	elseif t == "ColorSequence" then
		local out = {}
		for _, kp in v.Keypoints do
			table.insert(out, { r3(kp.Time), math.floor(kp.Value.R * 255 + 0.5), math.floor(kp.Value.G * 255 + 0.5), math.floor(kp.Value.B * 255 + 0.5) })
		end
		return out
	elseif t == "NumberSequence" then
		local out = {}
		for _, kp in v.Keypoints do
			table.insert(out, { r3(kp.Time), r3(kp.Value) })
		end
		return out
	elseif t == "Font" then
		return { family = tostring(v.Family), weight = if v.Weight then v.Weight.Name else "Regular", style = if v.Style then v.Style.Name else "Normal" }
	elseif t == "Rect" then
		return { v.Min.X, v.Min.Y, v.Max.X, v.Max.Y }
	elseif t == "BrickColor" then
		return v.Name
	elseif t == "table" then
		if v.__c3 then return { v[1], v[2], v[3] } end
		if v.__udim2 then return { v[1], v[2], v[3], v[4] } end
		if v.__udim then return { v[1], v[2] } end
		if v.__v2 then return { enc(v[1]), enc(v[2]) } end
		return nil
	elseif t == "Instance" then
		return M.fullName(v)
	end
	return tostring(v)
end

local function cls(inst) return inst[KEY].cls end
local function isA(inst, c) return inst[KEY].info.isa[c] == true end

-- property value: assigned value, else Roblox default (table above), else the mock's typed default
local function get(inst, k)
	local st = inst[KEY]
	local v = st.props[k]
	if v ~= nil then return v end
	local chain = DEFAULT_CHAIN[st.cls] or { st.cls }
	for _, c in chain do
		local d = ROBLOX_DEFAULTS[c]
		if d and d[k] ~= nil then return d[k] end
	end
	if st.info.isa.GuiObject and ROBLOX_DEFAULTS.GuiObject[k] ~= nil then return ROBLOX_DEFAULTS.GuiObject[k] end
	if not st.info.props[k] and not st.info.get[k] then return nil end -- not a member of this class
	local ok, val = pcall(function() return inst[k] end)
	if ok then return val end
	return nil
end

local function put(out, inst, keys)
	for _, k in keys do
		local v = enc(get(inst, k))
		if v ~= nil then out[k] = v end
	end
end

local GUIOBJECT_PROPS = { "Visible", "Size", "Position", "AnchorPoint", "Rotation", "ZIndex", "LayoutOrder", "BackgroundColor3",
	"BackgroundTransparency", "BorderSizePixel", "BorderColor3", "BorderMode", "ClipsDescendants", "AutomaticSize", "SizeConstraint" }
local TEXT_PROPS = { "Text", "TextColor3", "TextSize", "TextScaled", "TextWrapped", "TextXAlignment", "TextYAlignment", "Font", "RichText",
	"TextTransparency", "TextStrokeTransparency", "TextStrokeColor3", "TextTruncate", "LineHeight", "MaxVisibleGraphemes" }
local IMAGE_PROPS = { "Image", "ImageColor3", "ImageTransparency", "ScaleType", "SliceCenter", "ImageRectSize", "ImageRectOffset" }
local SCROLL_PROPS = { "CanvasSize", "CanvasPosition", "AutomaticCanvasSize", "ScrollBarThickness", "ScrollBarImageColor3",
	"ScrollBarImageTransparency", "ScrollingDirection", "VerticalScrollBarInset", "HorizontalScrollBarInset", "ScrollingEnabled" }

local MOD_PROPS = {
	UICorner = { "CornerRadius" },
	UIStroke = { "Color", "Thickness", "Transparency", "ApplyStrokeMode", "LineJoinMode", "Enabled" },
	UIPadding = { "PaddingTop", "PaddingRight", "PaddingBottom", "PaddingLeft" },
	UIListLayout = { "FillDirection", "Padding", "SortOrder", "HorizontalAlignment", "VerticalAlignment", "Wraps", "HorizontalFlex", "VerticalFlex", "ItemLineAlignment" },
	UIGridLayout = { "CellSize", "CellPadding", "FillDirection", "FillDirectionMaxCells", "SortOrder", "StartCorner", "HorizontalAlignment", "VerticalAlignment" },
	UIScale = { "Scale" },
	UIAspectRatioConstraint = { "AspectRatio", "AspectType", "DominantAxis" },
	UISizeConstraint = { "MinSize", "MaxSize" },
	UITextSizeConstraint = { "MinTextSize", "MaxTextSize" },
	UIGradient = { "Color", "Transparency", "Rotation", "Offset", "Enabled" },
	UIFlexItem = { "FlexMode", "GrowRatio", "ShrinkRatio", "ItemLineAlignment" },
	UIPageLayout = { "FillDirection", "Padding", "SortOrder" },
	UITableLayout = { "FillDirection", "Padding", "SortOrder" },
}
GuiDump.MOD_CLASSES = MOD_PROPS

local function attrsOf(inst)
	local out, any = {}, false
	for k, v in inst[KEY].attrs do
		local t = M.typeof(v)
		if t == "number" or t == "boolean" or t == "string" then
			out[k] = v
			any = true
		end
	end
	return if any then out else nil
end

local function modsOf(inst)
	local mods = {}
	for _, ch in inst[KEY].children do
		local c = cls(ch)
		local keys = MOD_PROPS[c]
		if keys then
			local m = { class = c, name = ch[KEY].props.Name }
			put(m, ch, keys)
			if c == "UIStroke" then -- litStroke: a UIGradient inside the stroke
				for _, g in ch[KEY].children do
					if cls(g) == "UIGradient" then
						local gm = {}
						put(gm, g, MOD_PROPS.UIGradient)
						m.gradient = gm
					end
				end
			end
			table.insert(mods, m)
		end
	end
	return mods
end

------------------------------------------------------------------------------------------ paths
-- "Name" or "Name[i]" when several siblings share the name (i = 1-based among them, child order)
local function segment(inst)
	local st = inst[KEY]
	local parent = st.props.Parent
	local name = st.props.Name
	if not parent then return name end
	local n, idx = 0, 0
	for _, ch in parent[KEY].children do
		if ch[KEY].props.Name == name then
			n += 1
			if ch == inst then idx = n end
		end
	end
	return if n > 1 then name .. "[" .. idx .. "]" else name
end

local function pathOf(inst, root)
	local segs = {}
	local p = inst
	while p do
		table.insert(segs, 1, segment(p))
		if p == root then break end
		p = p[KEY].props.Parent
	end
	return table.concat(segs, "/")
end
GuiDump.pathOf = pathOf

------------------------------------------------------------------------------------------- dump
local function emit(node)
	print("@@GUI " .. M.JSON.encode(node))
end

local function partInfo(part)
	if not part or not isA(part, "BasePart") then return nil end
	local out = { name = part[KEY].props.Name, class = cls(part) }
	put(out, part, { "Size", "Color", "Transparency", "Material" })
	return out
end

local nextId = 0
local function walk(inst, parentId, rootInst, depth, siblingIndex)
	local st = inst[KEY]
	local isRoot = st.info.isa.LayerCollector == true
	local isGui = st.info.isa.GuiObject == true
	local myId = parentId
	if isRoot or isGui then
		nextId += 1
		myId = nextId
		local node = { id = myId, parent = parentId, class = st.cls, name = st.props.Name, path = pathOf(inst, rootInst),
			depth = depth, index = siblingIndex, root = isRoot or nil }
		local p = {}
		if isGui then
			put(p, inst, GUIOBJECT_PROPS)
			if isA(inst, "TextLabel") or isA(inst, "TextButton") or isA(inst, "TextBox") then
				node.text = true
				put(p, inst, TEXT_PROPS)
				local ff = st.props.FontFace
				if ff then p.FontFace = enc(ff) end
				if isA(inst, "TextBox") then put(p, inst, { "PlaceholderText", "PlaceholderColor3" }) end
			end
			if isA(inst, "ImageLabel") or isA(inst, "ImageButton") then
				node.image = true
				put(p, inst, IMAGE_PROPS)
			end
			if st.cls == "ScrollingFrame" then put(p, inst, SCROLL_PROPS) end
			if st.cls == "CanvasGroup" then put(p, inst, { "GroupTransparency", "GroupColor3" }) end
		end
		if isRoot then
			put(p, inst, { "Enabled" })
			if st.cls == "ScreenGui" then
				put(p, inst, { "DisplayOrder", "IgnoreGuiInset", "ScreenInsets", "ZIndexBehavior" })
			elseif st.cls == "BillboardGui" then
				put(p, inst, { "Size", "SizeOffset", "StudsOffset", "AlwaysOnTop", "MaxDistance", "LightInfluence", "ClipsDescendants", "ZIndexBehavior" })
				node.part = partInfo(st.props.Adornee or st.props.Parent)
			elseif st.cls == "SurfaceGui" then
				put(p, inst, { "Face", "SizingMode", "PixelsPerStud", "CanvasSize", "LightInfluence", "ZIndexBehavior", "ClipsDescendants" })
				node.part = partInfo(st.props.Adornee or st.props.Parent)
			end
		end
		local abs = st.props.AbsoluteSize
		if abs then node.mockAbsSize = enc(abs) end
		node.props = p
		node.mods = modsOf(inst)
		node.attrs = attrsOf(inst)
		emit(node)
	end
	local i = 0
	for _, ch in st.children do
		local c = ch[KEY]
		-- descend into GuiObjects / LayerCollectors and through Folders (Roblox renders GUI inside Folders)
		if c.info.isa.GuiObject or c.info.isa.LayerCollector or c.cls == "Folder" then
			i += 1
			if (c.info.isa.LayerCollector) and not (isRoot or isGui) then
				walk(ch, nil, ch, 0, i) -- a nested LayerCollector (e.g. under a Part / PlayerGui) is its own root
			else
				walk(ch, myId, rootInst, depth + 1, i)
			end
		end
	end
end

-- roots: list of instances (PlayerGui, Folder, a LayerCollector, or a part holding a Billboard/SurfaceGui)
function GuiDump.dump(roots, meta)
	nextId = 0
	if meta then print("@@META " .. M.JSON.encode(meta)) end
	for _, r in roots do
		local st = r[KEY]
		if st.info.isa.LayerCollector then
			walk(r, nil, r, 0, 1)
		else
			for _, d in r:GetDescendants() do
				if d[KEY].info.isa.LayerCollector then
					-- only top-level collectors (not nested inside another collector)
					local p, nested = d[KEY].props.Parent, false
					while p and p ~= r do
						if p[KEY].info.isa.LayerCollector then nested = true break end
						p = p[KEY].props.Parent
					end
					if not nested then walk(d, nil, d, 0, 1) end
				end
			end
		end
	end
	print("@@END")
end

---------------------------------------------------------------------------- viewport + feedback
local function setRaw(inst, k, v)
	local st = inst[KEY]
	local old = st.props[k]
	if old ~= nil and old.X == v.X and old.Y == v.Y then return false end
	st.props[k] = v
	M.firePropChanged(inst, st, k)
	return true
end

-- insets = { top, right, bottom, left } in screen px for CoreUISafeInsets/TopbarSafeInsets ScreenGuis;
-- device = same for DeviceSafeInsets (notches). ScreenInsets None (and IgnoreGuiInset) = full viewport.
function GuiDump.screenRect(gui, w, h, insets, device)
	local mode = enc(get(gui, "ScreenInsets"))
	local ins = { top = 0, right = 0, bottom = 0, left = 0 }
	if mode == "CoreUISafeInsets" or mode == "TopbarSafeInsets" then
		ins = insets or ins
	elseif mode == "DeviceSafeInsets" then
		ins = device or ins
	end
	return ins.left, ins.top, w - ins.left - ins.right, h - ins.top - ins.bottom
end

function GuiDump.setViewport(container, w, h, insets, device)
	local V2 = M.G.Vector2.new
	local list = {}
	if container[KEY].cls == "ScreenGui" then table.insert(list, container) end
	for _, d in container:GetDescendants() do
		if d[KEY].cls == "ScreenGui" then table.insert(list, d) end
	end
	for _, gui in list do
		local x, y, gw, gh = GuiDump.screenRect(gui, w, h, insets, device)
		setRaw(gui, "AbsolutePosition", V2(x, y))
		setRaw(gui, "AbsoluteSize", V2(gw, gh))
	end
end

-- feedback = { [path] = { x, y, w, h } } (screen px) as written by guiprev.py; paths as in the dump.
-- Returns the number of instances whose AbsoluteSize/AbsolutePosition changed.
function GuiDump.applyFeedback(roots, feedback)
	if not feedback then return 0 end
	local V2 = M.G.Vector2.new
	local changed = 0
	local function visit(inst, rootInst)
		local st = inst[KEY]
		if st.info.isa.GuiObject then
			local f = feedback[pathOf(inst, rootInst)]
			if f then
				local a = setRaw(inst, "AbsolutePosition", V2(f[1], f[2]))
				local b = setRaw(inst, "AbsoluteSize", V2(f[3], f[4]))
				if a or b then changed += 1 end
			end
		end
		for _, ch in st.children do
			local c = ch[KEY]
			if c.info.isa.GuiObject or c.cls == "Folder" then visit(ch, rootInst) end
		end
	end
	for _, r in roots do
		local list = {}
		if r[KEY].info.isa.LayerCollector then table.insert(list, r) end
		for _, d in r:GetDescendants() do
			if d[KEY].info.isa.LayerCollector then table.insert(list, d) end
		end
		for _, lc in list do
			for _, ch in lc[KEY].children do visit(ch, lc) end
		end
	end
	return changed
end

return GuiDump
