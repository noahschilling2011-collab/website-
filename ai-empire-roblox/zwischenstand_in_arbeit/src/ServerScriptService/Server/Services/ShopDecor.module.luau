--!strict
-- Visible effects of cosmetic Robux items (ShopService decides WHEN, this module builds WHAT):
--   * party        team-party kit in front of the headquarters (balloon towers, banner, sparkles)
--   * founderSuite brass and leather lounge with a fire bowl on the private founder terrace
--   * vipTag       BillboardGui name tag above a VIP player's head
--   * fireworks    Rooftop Fireworks (shop package, SHOP_SPEC 3.4): bursts in the company colour above the HQ
-- Built once (no per-frame work), all decorative parts non-colliding unless they are furniture.
-- Positions are building-local (cf = plot CFrame, like every generator; world = cf * at).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Plan = require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Kit = require(script.Parent.ArchKit)

local C = Kit.C
local M = Kit.M
local V3 = Vector3.new
local CF = CFrame.new
local DETAIL: Kit.Opts = { detail = true }

local ShopDecor = {}

ShopDecor.PARTY_NAME = "TeamParty"
ShopDecor.SUITE_NAME = "FounderSuiteDecor"
ShopDecor.TAG_NAME = "ShopVipTag"
ShopDecor.FIREWORKS_NAME = "RooftopFireworks"

-- Party colours: bright on purpose (a party, not architecture)
local BALLOONS = {
	Color3.fromRGB(232, 84, 84),
	Color3.fromRGB(246, 196, 72),
	Color3.fromRGB(86, 156, 232),
	Color3.fromRGB(112, 200, 128),
	Color3.fromRGB(236, 132, 196),
}
local GOLD = Color3.fromRGB(236, 196, 92)

-- Front plaza between the arrival point and the entrance canopy (Plan.ARRIVAL is where players
-- arrive, 3 studs above the paving; the canopy reaches to z = -66).
local function partyOrigin(): CFrame
	local a = Plan.ARRIVAL
	return CF(a.X, a.Y - 3 + 0.15, a.Z + 30)
end

-- Team party kit: two balloon towers 28 studs apart with a banner between them, facing the arrival
-- point. 25 parts + 2 Sparkles, removed by ShopService after ShopConfig.PARTY_SECONDS.
function ShopDecor.party(parent: Instance, cf: CFrame, title: string): Model
	local model = Kit.model(parent, ShopDecor.PARTY_NAME)
	local o = partyOrigin()
	model.WorldPivot = cf * o
	for side, x in { -14, 14 } do
		local base = o * CF(x, 0, 0)
		Kit.cylinder(model, cf, "PartyBase", "y", 0.4, 2.2, base * CF(0, 0.2, 0), C.metal, M.metal, DETAIL)
		Kit.part(model, cf, "PartyPole", V3(0.35, 10, 0.35), base * CF(0, 5.2, 0), C.brass, M.metal, DETAIL)
		-- two rings of four balloons around the pole top, one on top
		for i = 1, 8 do
			local upper = i > 4
			local angle = (i / 4) * math.pi * 2 + (if upper then math.pi / 4 else 0) + side
			local ring = if upper then 1.0 else 1.5
			local at = base * CF(math.cos(angle) * ring, if upper then 13.0 else 11.4, math.sin(angle) * ring)
			local balloon = Kit.ball(model, cf, "Balloon", 2.3, at, BALLOONS[(i + side) % #BALLOONS + 1], M.smooth, DETAIL)
			if i == 1 then
				local sparkles = Instance.new("Sparkles")
				sparkles.SparkleColor = GOLD
				sparkles.Parent = balloon
			end
		end
		Kit.ball(model, cf, "Balloon", 2.6, base * CF(0, 14.6, 0), BALLOONS[side * 2], M.smooth, DETAIL)
	end
	local banner = Kit.part(model, cf, "PartyBanner", V3(26, 3.6, 0.25), o * CF(0, 8.6, 0), C.white, M.fabric, DETAIL)
	Kit.part(model, cf, "PartyBannerTrim", V3(26.2, 0.3, 0.3), o * CF(0, 6.7, 0), GOLD, M.smooth, DETAIL)
	Kit.part(model, cf, "PartyBannerTrim", V3(26.2, 0.3, 0.3), o * CF(0, 10.5, 0), GOLD, M.smooth, DETAIL)
	-- text on both faces: arriving players see the front (-Z), people leaving see the back
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		Kit.text(banner, "TEAM PARTY · " .. string.upper(title), {
			face = face,
			color = Color3.fromRGB(196, 64, 96),
			font = Enum.Font.BuilderSansExtraBold,
			maxDistance = 220,
			light = 0.2,
			pps = 24,
			pad = 0.1,
			wrap = false,
		})
	end
	return model
end

-- Founder Suite lounge on the private founder terrace. Free zone (measured on the built terrace):
-- x 66..82.4 (door from the founder office at x 59..65, existing seating/parasol in the west half),
-- z -43.5 (front planters) .. -32.45 (facade sill); the deck top is level Y + Kit.FINISH. nil when the
-- current building has no founder terrace (ShopService tries again after every rebuild).
function ShopDecor.founderSuite(parent: Instance, cf: CFrame, tier: number): Model?
	local room = Plan.room(tier, "F_TERRACE_PRIVATE")
	if not room then
		return nil
	end
	local y = Plan.levelY(room.level) + Kit.FINISH
	local x2, z2 = room.x2, room.z2 -- east end, against the founder office facade
	local function at(x: number, z: number, yaw: number?): CFrame
		return CF(x2 + x, y, z2 + z) * CFrame.Angles(0, math.rad(yaw or 0), 0)
	end
	local model = Kit.model(parent, ShopDecor.SUITE_NAME)
	model.WorldPivot = cf * at(-7.5, -5.5)
	-- brass-edged rug
	Kit.part(model, cf, "SuiteRugEdge", V3(11.4, 0.04, 7.8), at(-7.5, -5.5) * CF(0, 0.02, 0), C.brass, M.fabric, DETAIL)
	Kit.part(model, cf, "SuiteRug", V3(10.8, 0.05, 7.2), at(-7.5, -5.5) * CF(0, 0.025, 0), C.fabricCharcoal, M.fabric, DETAIL)
	-- two leather lounge chairs looking out over the terrace (sitter faces -Z)
	Kit.loungeChair(model, cf, at(-10.5, -4.5), 3, { color = C.leather, name = "Seat" })
	Kit.loungeChair(model, cf, at(-4.5, -4.5), 7, { color = C.leather, name = "Seat" })
	-- marble plinth with a brass fire bowl in front, between the chairs
	Kit.part(model, cf, "SuitePlinth", V3(2.2, 1.2, 2.2), at(-7.5, -7.4) * CF(0, 0.6, 0), C.white, M.marble)
	local bowl = Kit.cylinder(model, cf, "SuiteFireBowl", "y", 0.5, 2.0, at(-7.5, -7.4) * CF(0, 1.45, 0), C.brass, M.metal)
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 2
	fire.Color = Color3.fromRGB(255, 150, 60)
	fire.SecondaryColor = Color3.fromRGB(255, 90, 40)
	fire.Parent = bowl
	Kit.light(bowl, "point", Color3.fromRGB(255, 196, 140), 14, 1.1)
	-- tall plants at the front corners (crowns stay clear of the rail at x 82.4)
	Kit.plant(model, cf, at(-14.0, -9.6), "l", 11)
	Kit.plant(model, cf, at(-2.0, -9.6), "l", 23)
	-- brass plaque on a short stand beside the facade, facing the lounge (front = -X)
	local stand = at(-0.8, -2.0, 90)
	Kit.part(model, cf, "SuitePlaqueStand", V3(0.3, 3.2, 0.3), stand * CF(0, 1.6, 0.25), C.metal, M.metal, DETAIL)
	local plaque = Kit.part(model, cf, "SuitePlaque", V3(2.6, 1.2, 0.12), stand * CF(0, 3.4, 0.1), C.brass, M.metal, DETAIL)
	Kit.text(plaque, "FOUNDER SUITE", { color = C.metal, font = Enum.Font.BuilderSansExtraBold, maxDistance = 40, light = 0.3, pps = 60, pad = 0.12 })
	return model
end

-- Rooftop Fireworks (SHOP_SPEC 3.4): 4 invisible, anchored launch points just above the top of the headquarters
-- model (its bounding box: the same code works for every stage, garage included) and ParticleEmitter bursts via
-- :Emit in the company colour, one burst every 1.1 s for `seconds`; ShopService destroys the model afterwards.
-- Nothing collides, touches or blocks a raycast; everyone nearby sees it (it is world content).
function ShopDecor.fireworks(parent: Instance, cf: CFrame, color: Color3, seconds: number): Model
	local model = Kit.model(parent, ShopDecor.FIREWORKS_NAME)
	local center, top = cf, 30
	if parent:IsA("Model") then
		local ok, boxCf, size = pcall(function(): (CFrame, Vector3)
			return parent:GetBoundingBox()
		end)
		if ok and typeof(boxCf) == "CFrame" and typeof(size) == "Vector3" then
			local localBox = cf:ToObjectSpace(boxCf)
			center = cf * CF(localBox.Position.X, 0, localBox.Position.Z)
			top = math.clamp(localBox.Position.Y + size.Y / 2, 12, 400)
		end
	end
	model.WorldPivot = center * CF(0, top, 0)
	local emitters: { ParticleEmitter } = {}
	for i, offset in { V3(-14, 0, -8), V3(14, 0, -8), V3(-8, 0, 10), V3(8, 0, 10) } do
		local p = Instance.new("Part")
		p.Name = "FireworksLauncher" .. i
		p.Size = V3(1, 1, 1)
		p.Transparency = 1
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.CFrame = center * CF(offset.X, top + 2, offset.Z)
		p.Parent = model
		local e = Instance.new("ParticleEmitter")
		e.Name = "Burst"
		e.Rate = 0 -- bursts only (:Emit)
		e.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.25, color),
			ColorSequenceKeypoint.new(1, color),
		})
		e.LightEmission = 1
		e.Lifetime = NumberRange.new(1.4, 2.2)
		e.Speed = NumberRange.new(26, 40)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = V3(0, -14, 0)
		e.Drag = 1.6
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0.2) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1) })
		e.Parent = p
		table.insert(emitters, e)
	end
	task.spawn(function()
		local t, i = 0, 0
		while model.Parent and t < seconds do
			i += 1
			local e = emitters[(i - 1) % #emitters + 1]
			if e.Parent then
				e:Emit(42)
			end
			t += task.wait(1.1)
		end
	end)
	return model
end

-- VIP name tag above the head (cosmetic, replicated with the character).
function ShopDecor.vipTag(head: BasePart, company: string?): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = ShopDecor.TAG_NAME
	gui.Adornee = head
	gui.Size = UDim2.new(5, 0, 1.3, 0) -- studs: scales with distance like a world label
	gui.StudsOffset = V3(0, 2.7, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.BackgroundColor3 = Color3.fromRGB(28, 26, 22)
	badge.BackgroundTransparency = 0.2
	badge.Position = UDim2.fromScale(0.15, 0)
	badge.Size = UDim2.fromScale(0.7, if company then 0.6 else 1)
	badge.Text = "VIP FOUNDER"
	badge.TextColor3 = GOLD
	badge.TextScaled = true
	badge.Font = Enum.Font.BuilderSansExtraBold
	badge.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = badge
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 1.5
	stroke.Transparency = 0.2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = badge
	if company then
		local line = Instance.new("TextLabel")
		line.Name = "Company"
		line.BackgroundTransparency = 1
		line.Position = UDim2.fromScale(0, 0.62)
		line.Size = UDim2.fromScale(1, 0.38)
		line.Text = company
		line.TextColor3 = Color3.fromRGB(246, 244, 239)
		line.TextStrokeTransparency = 0.4
		line.TextScaled = true
		line.Font = Enum.Font.BuilderSansBold
		line.Parent = gui
	end
	gui.Parent = head
	return gui
end

return ShopDecor
