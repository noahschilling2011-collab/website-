--!strict
-- One architectural plan for the whole headquarters. Geometry generators, room access, employee
-- navigation, the lift, wayfinding and camera channels all read these definitions, so a wall, a
-- door and the rule that protects the room behind it can never disagree.
--
-- Coordinates are building-local studs: origin = plot CFrame at street level, -Z faces the street.
-- Level L has its finished floor at levelY(L). B1 = level -1, roof = level floors(tier).
local Plan = {}

Plan.FLOOR_HEIGHT = 16
Plan.B1_Y = -16
Plan.SLAB = 1 -- slab top = level Y, slab bottom = level Y - 1
Plan.CEILING = 13 -- suspended ceiling height in rooms and corridors
Plan.TIER_FLOORS = { 3, 4, 5, 7 } -- above-ground storeys incl. ground floor and founder floor

-- Envelope
Plan.MAIN = { x1 = -82, x2 = 82, z1 = -48, z2 = 80 }
Plan.PAVILION = { x1 = -82, x2 = 82, z1 = 80, z2 = 160, levels = 2 } -- G and 1, roof at y=32
Plan.GARAGE = { x1 = -94, x2 = 112, z1 = -64, z2 = 88 }
Plan.SITE = { x1 = -142, x2 = 145, z1 = -217, z2 = 228 }
Plan.FOUNDER_FRONT_Z = -32 -- the founder storey steps back for a terrace

-- Circulation core and atrium
Plan.ATRIUM = { x1 = -14, x2 = 14, z1 = -16, z2 = 36 } -- open void from level 1 to the roof skylight
Plan.LIFT_LOBBY = { x1 = -22, x2 = 22, z1 = 36, z2 = 54 }
Plan.SHAFT = { x1 = -7, x2 = 7, z1 = 54, z2 = 68 } -- outer shaft; front wall z 53.5..54.5
Plan.CABIN = { x1 = -6, x2 = 6, z1 = 54.8, z2 = 66.8, height = 10.4, capacity = 6 }
Plan.LIFT_DOOR = { x1 = -3, x2 = 3, z = 54, height = 10 } -- centre-opening doors; leaves park inside the 12-stud cabin/shaft width
Plan.RISER = { x1 = -7, x2 = 7, z1 = 68, z2 = 80 }
Plan.STAIR = { x1 = -22, x2 = -7, z1 = 54, z2 = 80 }
-- Switchback stair inside STAIR: front landing at level Y, flight A rises +Z, mid landing at Y+8,
-- flight B rises -Z back to the front landing of the next level. Flights are smooth ramps under
-- non-colliding visual treads so Humanoids and PathfindingService walk them reliably.
Plan.STAIR_LAYOUT = {
	inner = { x1 = -21.5, x2 = -7.5, z1 = 54.5, z2 = 79.5 },
	frontLanding = { z1 = 54.5, z2 = 60 },
	flightA = { x1 = -21.5, x2 = -14.8, z1 = 60, z2 = 75 },
	divider = { x1 = -14.8, x2 = -14.2 },
	flightB = { x1 = -14.2, x2 = -7.5, z1 = 60, z2 = 75 },
	midLanding = { z1 = 75, z2 = 79.5 },
	door = { x = -14.5, z = 54, w = 6 },
}
Plan.WC = { x1 = 7, x2 = 22, z1 = 54, z2 = 80 }

-- Arrival points (building-local, standing height)
Plan.ARRIVAL = Vector3.new(0, 3, -104) -- front plaza, in front of the entrance canopy
Plan.GARAGE_ARRIVAL = Vector3.new(40, Plan.B1_Y + 3, 10)
Plan.GARAGE_SPAWN = CFrame.new(100, Plan.B1_Y + 4, 2) -- company car, nose towards the ramp (-Z)
Plan.ENTRANCE = { x1 = -4, x2 = 4, z = -44 } -- automatic double sliding door in the glazed portal
Plan.PORTAL = { x1 = -14, x2 = 14, z1 = -48, z2 = -44 } -- covered recess in front of the entrance (outside)
-- The public reception hall (z -48..-20) is double height: level 1 leaves this void open, crossed by a
-- gallery bridge (z -24..-16) between the hall and the atrium.
Plan.LOBBY_VOID = { x1 = -22, x2 = 22, z1 = -48, z2 = -24 }
-- Badge speed gates separate the public hall from the staff atrium like in a real headquarters.
Plan.GATE_LINE = { z = -20, x1 = -22, x2 = 22 }

-- Access classes. Players: the founder may enter everything; a guest card opens public + staff.
Plan.CLASSES = { "public", "staff", "technical", "compute", "research", "founder" }
local ROLE_CLEARANCE: { [string]: { [string]: boolean } } = {
	researcher = { public = true, staff = true, research = true },
	engineer = { public = true, staff = true, research = true, compute = true, technical = true },
	curator = { public = true, staff = true },
	marketer = { public = true, staff = true },
	support = { public = true, staff = true, technical = true },
	-- The founder's personal assistant works in the founder suite (brings coffee, briefings).
	assistant = { public = true, staff = true, founder = true },
	-- Job applicants are visitors: front-of-house only.
	visitor = { public = true },
}
Plan.CLASS_LABEL = {
	public = "Visitors welcome",
	staff = "Company card",
	technical = "Technical staff",
	compute = "Compute engineers",
	research = "Research clearance",
	founder = "Founder only",
}

function Plan.floors(tier: number): number
	return Plan.TIER_FLOORS[math.clamp(math.floor(tier), 1, #Plan.TIER_FLOORS)]
end
function Plan.founderLevel(tier: number): number
	return Plan.floors(tier) - 1
end
function Plan.roofLevel(tier: number): number
	return Plan.floors(tier)
end
function Plan.levelY(level: number): number
	return if level < 0 then Plan.B1_Y else level * Plan.FLOOR_HEIGHT
end
function Plan.levels(tier: number): { number }
	local out = {}
	for level = -1, Plan.floors(tier) do
		table.insert(out, level)
	end
	return out
end
-- Level whose occupiable band [Y-2, Y+14) contains y; nil outside.
function Plan.levelAt(tier: number, y: number): number?
	if y >= Plan.B1_Y - 2 and y < -2 then
		return -1
	end
	local top = Plan.floors(tier)
	for level = 0, top do
		local base = Plan.levelY(level)
		if y >= base - 2 and y < base + 14 then
			return level
		end
	end
	return nil
end

-- Work-floor programmes. Every tier keeps the complete data → release journey reachable.
local THEMES_BY_TIER: { { string } } = {
	{ "combined" },
	{ "foundation", "engineering_plus" },
	{ "foundation", "engineering", "research_product" },
	{ "foundation", "engineering", "research", "product", "advanced" },
}
Plan.THEME_NAMES = {
	combined = "Data, models & launch",
	foundation = "Data & model foundations",
	engineering = "AI engineering & training",
	engineering_plus = "Engineering, training & growth",
	research = "AI research & evaluation",
	research_product = "Research, evaluation & product",
	product = "Product, launch & customers",
	advanced = "Advanced labs & platform",
}
function Plan.theme(tier: number, level: number): string?
	local list = THEMES_BY_TIER[math.clamp(math.floor(tier), 1, 4)]
	return list[level]
end
function Plan.levelLabel(tier: number, level: number): string
	if level < 0 then
		return "B1"
	elseif level == 0 then
		return "G"
	elseif level == Plan.roofLevel(tier) then
		return "R"
	end
	return tostring(level)
end
function Plan.levelName(tier: number, level: number): string
	if level < 0 then
		return "Garage, data hall & building services"
	elseif level == 0 then
		return "Reception, atrium, café & compute ops"
	elseif level == Plan.roofLevel(tier) then
		return "Roof terrace"
	elseif level == Plan.founderLevel(tier) then
		return "Founder suite & boardroom"
	end
	local theme = Plan.theme(tier, level)
	return if theme then Plan.THEME_NAMES[theme] else "Offices"
end
-- "2 · AI engineering & training"
function Plan.floorTitle(tier: number, level: number): string
	return Plan.levelLabel(tier, level) .. "  ·  " .. Plan.levelName(tier, level)
end

export type Door = {
	face: string, -- "N" (z2), "S" (z1), "E" (x2), "W" (x1) of the room
	at: number, -- centre along the face (z for E/W faces, x for N/S faces)
	w: number, -- clear opening width
	h: number?, -- clear opening height (default 9)
	kind: string, -- opening | glass | glassdouble | solid | secure | flush | bookcase | vault | autoslide | service
	exterior: boolean?, -- leads outdoors
	access: string?, -- overrides the room class (e.g. an egress door)
	flip: boolean?, -- the protected side is OUTSIDE this room (e.g. public lounge → staff corridor)
	swing: string?, -- "out": the leaf swings away from the room (e.g. stair doors onto the lift lobby)
	hidden: boolean?, -- concealed door (no sign, founder-only prompt)
}
export type Room = {
	id: string,
	level: number,
	name: string,
	kind: string,
	access: string,
	x1: number,
	x2: number,
	z1: number,
	z2: number,
	dept: string?,
	desks: number?,
	seats: number?,
	doors: { Door },
	hidden: boolean?,
	camera: boolean?, -- covered by a security camera channel
	mood: string?, -- warm | neutral | cool | tech | founder | secret | wellness
	style: number,
	walls: string?, -- glass | solid | mixed (corridor-side wall finish)
	open: { string }?, -- faces without a wall (open-plan connection)
	pavilion: boolean?,
	outdoor: boolean?,
	meeting: string?, -- MeetingRoom id used by StaffService meetings
	nowalls: boolean?, -- open area: neighbouring rooms and the envelope define its edges
	fence: boolean?, -- outdoor zone enclosed by a screen fence
}

-- Wing zones (west). East zones mirror x.
local ZONES = {
	S1 = { -82, -50, -48, -8 },
	S2 = { -82, -50, -8, 28 },
	S3 = { -82, -50, 28, 56 },
	S4 = { -82, -50, 56, 80 },
	I1 = { -42, -22, -48, -24 },
	I2 = { -42, -22, -16, 8 },
	I2a = { -42, -22, -16, -4 },
	I2b = { -42, -22, -4, 8 },
	I3 = { -42, -22, 8, 36 },
	I4 = { -42, -22, 44, 80 },
}
-- Corridor-side door for each zone, expressed for the WEST wing.
local ZONE_DOOR: { [string]: { face: string, at: number } } = {
	S1 = { face = "E", at = -16 },
	S2 = { face = "E", at = 0 },
	S3 = { face = "E", at = 36 },
	S4 = { face = "E", at = 66 },
	I1 = { face = "N", at = -32 },
	I2 = { face = "E", at = -2 },
	I2a = { face = "E", at = -10 },
	I2b = { face = "E", at = 2 },
	I3 = { face = "E", at = 22 },
	I4 = { face = "S", at = -32 },
}
local MIRROR_FACE = { E = "W", W = "E", N = "N", S = "S" }

local function rect(zone: string, east: boolean): (number, number, number, number)
	local z = ZONES[zone]
	if east then
		return -z[2], -z[1], z[3], z[4]
	end
	return z[1], z[2], z[3], z[4]
end

local function wingRoom(level: number, east: boolean, zone: string, def: any): Room
	local x1, x2, z1, z2 = rect(zone, east)
	local d = ZONE_DOOR[zone]
	local face = if east then MIRROR_FACE[d.face] else d.face
	local at = if (d.face == "N" or d.face == "S") and east then -d.at else d.at
	local kind = def.kind
	local doorKind = def.door
		or (if kind == "pantry" or kind == "lounge" then "opening" elseif kind == "phone" or kind == "focus" then "glass" elseif kind == "print" then "solid" else "glass")
	local width = if doorKind == "opening" then 8 elseif doorKind == "glassdouble" then 8 else 6
	return {
		id = string.format("L%d_%s%s", level, if east then "E" else "W", zone),
		level = level,
		name = def.name,
		kind = kind,
		access = def.access or "staff",
		x1 = x1,
		x2 = x2,
		z1 = z1,
		z2 = z2,
		dept = def.dept,
		desks = def.desks,
		seats = def.seats,
		doors = { { face = face, at = at, w = width, kind = doorKind } },
		camera = def.camera,
		mood = def.mood or (if kind == "lab" or kind == "control" or kind == "platform" or kind == "hwlab" then "cool" elseif kind == "pantry" or kind == "lounge" then "warm" else "neutral"),
		style = (level * 7 + (if east then 3 else 0) + #zone + #def.name) % 4 + 1,
		meeting = if kind == "meeting" then string.format("L%d_%s%s", level, if east then "E" else "W", zone) else nil,
	}
end

-- Theme tables: zone -> definition. West and east lists are separate so floors are not mirrors.
local THEMES: { [string]: { W: { [string]: any }, E: { [string]: any } } } = {
	combined = {
		W = {
			S1 = { kind = "team", name = "Data Operations", dept = "data", desks = 8, camera = true },
			S2 = { kind = "architecture", name = "Model Architecture", dept = "design", desks = 6 },
			S3 = { kind = "meeting", name = "Model Review", seats = 8, door = "glassdouble" },
			S4 = { kind = "pantry", name = "Tea Kitchen" },
			I1 = { kind = "meeting", name = "Huddle Room", seats = 4 },
			I2a = { kind = "focus", name = "Focus Room 1", dept = "research", desks = 1 },
			I2b = { kind = "focus", name = "Focus Room 2", dept = "design", desks = 1 },
			I3 = { kind = "datalab", name = "Data Quality Lab", dept = "data", desks = 3 },
			I4 = { kind = "phone", name = "Phone Booths" },
		},
		E = {
			S1 = { kind = "team", name = "AI Engineering", dept = "engineering", desks = 8, camera = true },
			S2 = { kind = "control", name = "Training Control", dept = "training", desks = 5, camera = true },
			S3 = { kind = "evaluation", name = "Evaluation Lab", dept = "evaluation", desks = 4 },
			S4 = { kind = "launch", name = "Deployment & Growth", dept = "deployment", desks = 4 },
			I1 = { kind = "meeting", name = "Sprint Huddle", seats = 4 },
			I2a = { kind = "focus", name = "Focus Room 3", dept = "engineering", desks = 1 },
			I2b = { kind = "focus", name = "Focus Room 4", dept = "growth", desks = 1 },
			I3 = { kind = "lounge", name = "Team Lounge" },
			I4 = { kind = "support", name = "Customer Desk", dept = "growth", desks = 3 },
		},
	},
	foundation = {
		W = {
			S1 = { kind = "team", name = "Data Operations A", dept = "data", desks = 12, camera = true },
			S2 = { kind = "team", name = "Data Operations B", dept = "data", desks = 10 },
			S3 = { kind = "meeting", name = "Data Review", seats = 8, door = "glassdouble" },
			S4 = { kind = "pantry", name = "Tea Kitchen" },
			I1 = { kind = "meeting", name = "Huddle Room", seats = 4 },
			I2a = { kind = "focus", name = "Focus Room 1", dept = "data", desks = 1 },
			I2b = { kind = "focus", name = "Focus Room 2", dept = "data", desks = 1 },
			I3 = { kind = "datalab", name = "Data Quality Lab", dept = "data", desks = 4 },
			I4 = { kind = "phone", name = "Phone Booths" },
		},
		E = {
			S1 = { kind = "architecture", name = "Model Architecture Studio", dept = "design", desks = 10, camera = true },
			S2 = { kind = "team", name = "Architecture Team", dept = "design", desks = 10 },
			S3 = { kind = "evaluation", name = "First Evaluation", dept = "evaluation", desks = 5 },
			S4 = { kind = "lounge", name = "Team Lounge" },
			I1 = { kind = "meeting", name = "Design Huddle", seats = 4 },
			I2a = { kind = "focus", name = "Focus Room 3", dept = "design", desks = 1 },
			I2b = { kind = "focus", name = "Focus Room 4", dept = "design", desks = 1 },
			I3 = { kind = "datalab", name = "Pipeline Lab", dept = "data", desks = 4 },
			I4 = { kind = "print", name = "Print & Supplies" },
		},
	},
	engineering = {
		W = {
			S1 = { kind = "team", name = "AI Engineering A", dept = "engineering", desks = 12, camera = true },
			S2 = { kind = "team", name = "AI Engineering B", dept = "engineering", desks = 10 },
			S3 = { kind = "meeting", name = "Sprint Room", seats = 8, door = "glassdouble" },
			S4 = { kind = "pantry", name = "Tea Kitchen" },
			I1 = { kind = "meeting", name = "Huddle Room", seats = 4 },
			I2a = { kind = "focus", name = "Focus Room 1", dept = "engineering", desks = 1 },
			I2b = { kind = "focus", name = "Focus Room 2", dept = "engineering", desks = 1 },
			I3 = { kind = "platform", name = "Build & CI Room", dept = "engineering", desks = 4 },
			I4 = { kind = "phone", name = "Phone Booths" },
		},
		E = {
			S1 = { kind = "control", name = "Training Control", dept = "training", desks = 8, camera = true },
			S2 = { kind = "team", name = "Training Operations", dept = "training", desks = 10 },
			S3 = { kind = "meeting", name = "Incident Room", seats = 6, door = "glassdouble" },
			S4 = { kind = "lounge", name = "Team Lounge" },
			I1 = { kind = "meeting", name = "Ops Huddle", seats = 4 },
			I2a = { kind = "focus", name = "Focus Room 3", dept = "training", desks = 1 },
			I2b = { kind = "focus", name = "Focus Room 4", dept = "training", desks = 1 },
			I3 = { kind = "hwlab", name = "GPU Bench Lab", dept = "engineering", desks = 3, access = "compute" },
			I4 = { kind = "print", name = "Print & Supplies" },
		},
	},
	engineering_plus = {
		W = {
			S1 = { kind = "team", name = "AI Engineering", dept = "engineering", desks = 12, camera = true },
			S2 = { kind = "control", name = "Training Control", dept = "training", desks = 8, camera = true },
			S3 = { kind = "meeting", name = "Sprint Room", seats = 8, door = "glassdouble" },
			S4 = { kind = "pantry", name = "Tea Kitchen" },
			I1 = { kind = "meeting", name = "Huddle Room", seats = 4 },
			I2a = { kind = "focus", name = "Focus Room 1", dept = "engineering", desks = 1 },
			I2b = { kind = "focus", name = "Focus Room 2", dept = "training", desks = 1 },
			I3 = { kind = "platform", name = "Build & CI Room", dept = "engineering", desks = 4 },
			I4 = { kind = "phone", name = "Phone Booths" },
		},
		E = {
			S1 = { kind = "launch", name = "Launch & Marketing", dept = "growth", desks = 10, camera = true },
			S2 = { kind = "studio", name = "Product Studio", dept = "deployment", desks = 8 },
			S3 = { kind = "support", name = "Customer & Support", dept = "growth", desks = 6 },
			S4 = { kind = "lounge", name = "Team Lounge" },
			I1 = { kind = "meeting", name = "Launch Huddle", seats = 4 },
			I2a = { kind = "focus", name = "Focus Room 3", dept = "growth", desks = 1 },
			I2b = { kind = "focus", name = "Focus Room 4", dept = "deployment", desks = 1 },
			I3 = { kind = "hr", name = "People & Company Office", dept = "operations", desks = 3 },
			I4 = { kind = "print", name = "Print & Supplies" },
		},
	},
	research = {
		W = {
			S1 = { kind = "team", name = "AI Research A", dept = "research", desks = 12, camera = true },
			S2 = { kind = "lab", name = "Experiment Lab", dept = "research", desks = 8 },
			S3 = { kind = "meeting", name = "Paper Reading Room", seats = 8, door = "glassdouble" },
			S4 = { kind = "pantry", name = "Tea Kitchen" },
			I1 = { kind = "meeting", name = "Huddle Room", seats = 4 },
			I2a = { kind = "focus", name = "Focus Room 1", dept = "research", desks = 1 },
			I2b = { kind = "focus", name = "Focus Room 2", dept = "research", desks = 1 },
			I3 = { kind = "lab", name = "Quality & Safety Lab", dept = "evaluation", desks = 4 },
			I4 = { kind = "phone", name = "Phone Booths" },
		},
		E = {
			S1 = { kind = "evaluation", name = "Evaluation Lab", dept = "evaluation", desks = 10, camera = true },
			S2 = { kind = "team", name = "AI Research B", dept = "research", desks = 10 },
			S3 = { kind = "meeting", name = "Results Room", seats = 6, door = "glassdouble" },
			S4 = { kind = "lounge", name = "Team Lounge" },
			I1 = { kind = "meeting", name = "Research Huddle", seats = 4 },
			I2a = { kind = "focus", name = "Focus Room 3", dept = "evaluation", desks = 1 },
			I2b = { kind = "focus", name = "Focus Room 4", dept = "research", desks = 1 },
			I3 = { kind = "evaluation", name = "Benchmark Lab", dept = "evaluation", desks = 4 },
			I4 = { kind = "print", name = "Print & Supplies" },
		},
	},
	research_product = {
		W = {
			S1 = { kind = "team", name = "AI Research", dept = "research", desks = 12, camera = true },
			S2 = { kind = "lab", name = "Experiment Lab", dept = "research", desks = 8 },
			S3 = { kind = "meeting", name = "Results Room", seats = 8, door = "glassdouble" },
			S4 = { kind = "pantry", name = "Tea Kitchen" },
			I1 = { kind = "meeting", name = "Huddle Room", seats = 4 },
			I2a = { kind = "focus", name = "Focus Room 1", dept = "research", desks = 1 },
			I2b = { kind = "focus", name = "Focus Room 2", dept = "evaluation", desks = 1 },
			I3 = { kind = "evaluation", name = "Evaluation Lab", dept = "evaluation", desks = 4 },
			I4 = { kind = "phone", name = "Phone Booths" },
		},
		E = {
			S1 = { kind = "launch", name = "Launch & Marketing", dept = "growth", desks = 10, camera = true },
			S2 = { kind = "studio", name = "Product Studio", dept = "deployment", desks = 8 },
			S3 = { kind = "support", name = "Customer & Support", dept = "growth", desks = 6 },
			S4 = { kind = "lounge", name = "Team Lounge" },
			I1 = { kind = "meeting", name = "Launch Huddle", seats = 4 },
			I2a = { kind = "focus", name = "Focus Room 3", dept = "growth", desks = 1 },
			I2b = { kind = "focus", name = "Focus Room 4", dept = "deployment", desks = 1 },
			I3 = { kind = "hr", name = "People & Company Office", dept = "operations", desks = 3 },
			I4 = { kind = "print", name = "Print & Supplies" },
		},
	},
	product = {
		W = {
			S1 = { kind = "studio", name = "Product Studio", dept = "deployment", desks = 10, camera = true },
			S2 = { kind = "launch", name = "Launch & Marketing", dept = "growth", desks = 10 },
			S3 = { kind = "meeting", name = "Launch Room", seats = 8, door = "glassdouble" },
			S4 = { kind = "pantry", name = "Tea Kitchen" },
			I1 = { kind = "meeting", name = "Huddle Room", seats = 4 },
			I2a = { kind = "focus", name = "Focus Room 1", dept = "deployment", desks = 1 },
			I2b = { kind = "focus", name = "Focus Room 2", dept = "growth", desks = 1 },
			I3 = { kind = "studio", name = "UX Lab", dept = "deployment", desks = 4 },
			I4 = { kind = "phone", name = "Phone Booths" },
		},
		E = {
			S1 = { kind = "support", name = "Customer & Support", dept = "growth", desks = 10, camera = true },
			S2 = { kind = "team", name = "Growth Team", dept = "growth", desks = 10 },
			S3 = { kind = "hr", name = "People & Company Office", dept = "operations", desks = 5 },
			S4 = { kind = "lounge", name = "Team Lounge" },
			I1 = { kind = "meeting", name = "Customer Huddle", seats = 4 },
			I2a = { kind = "focus", name = "Focus Room 3", dept = "growth", desks = 1 },
			I2b = { kind = "focus", name = "Focus Room 4", dept = "growth", desks = 1 },
			I3 = { kind = "team", name = "Partnerships", dept = "growth", desks = 4 },
			I4 = { kind = "print", name = "Print & Supplies" },
		},
	},
	advanced = {
		W = {
			S1 = { kind = "lab", name = "Advanced Research Lab", dept = "research", desks = 10, access = "research", camera = true, door = "secure" },
			S2 = { kind = "team", name = "Frontier Team", dept = "research", desks = 10, access = "research", door = "secure" },
			S3 = { kind = "meeting", name = "Research Council", seats = 8, door = "glassdouble" },
			S4 = { kind = "pantry", name = "Tea Kitchen" },
			I1 = { kind = "meeting", name = "Huddle Room", seats = 4 },
			I2a = { kind = "focus", name = "Focus Room 1", dept = "research", desks = 1 },
			I2b = { kind = "focus", name = "Focus Room 2", dept = "research", desks = 1 },
			I3 = { kind = "lab", name = "Alignment Lab", dept = "evaluation", desks = 4 },
			I4 = { kind = "phone", name = "Phone Booths" },
		},
		E = {
			S1 = { kind = "platform", name = "Platform Operations", dept = "deployment", desks = 10, camera = true },
			S2 = { kind = "control", name = "Cluster Control", dept = "training", desks = 8 },
			S3 = { kind = "team", name = "Inference Team", dept = "engineering", desks = 8 },
			S4 = { kind = "lounge", name = "Team Lounge" },
			I1 = { kind = "meeting", name = "Platform Huddle", seats = 4 },
			I2a = { kind = "focus", name = "Focus Room 3", dept = "engineering", desks = 1 },
			I2b = { kind = "focus", name = "Focus Room 4", dept = "deployment", desks = 1 },
			I3 = { kind = "hwlab", name = "Hardware Lab", dept = "engineering", desks = 3, access = "compute" },
			I4 = { kind = "print", name = "Print & Supplies" },
		},
	},
}

local function room(def: any): Room
	def.doors = def.doors or {}
	def.access = def.access or "staff"
	def.style = def.style or (#def.id % 4 + 1)
	return def :: Room
end

local function coreRooms(level: number, tier: number, out: { Room })
	local top = Plan.roofLevel(tier)
	table.insert(out, room({ id = string.format("L%d_STAIR", level), level = level, name = "Stairs", kind = "stair", access = "staff", x1 = Plan.STAIR.x1, x2 = Plan.STAIR.x2, z1 = Plan.STAIR.z1, z2 = Plan.STAIR.z2, doors = { { face = "S", at = Plan.STAIR_LAYOUT.door.x, w = 6, kind = "solid", swing = "out" } }, mood = "neutral" }))
	if level == -1 then
		table.insert(out, room({ id = "B1_SERVICE", level = -1, name = "Service Passage", kind = "service_passage", access = "technical", x1 = 7, x2 = 22, z1 = 54, z2 = 80, doors = { { face = "S", at = 14.5, w = 6, kind = "service" }, { face = "N", at = 14.5, w = 6, kind = "service" } }, mood = "tech" }))
		table.insert(out, room({ id = "B1_LIFTPIT", level = -1, name = "Lift Pit & Machine Access", kind = "liftpit", access = "technical", x1 = -7, x2 = 7, z1 = 68, z2 = 80, doors = { { face = "N", at = 0, w = 5, kind = "service" } }, mood = "tech" }))
	elseif level == top then
		table.insert(out, room({ id = "R_MACHINE", level = level, name = "Lift Machine Room", kind = "machine", access = "technical", x1 = 7, x2 = 22, z1 = 54, z2 = 80, doors = { { face = "E", at = 67, w = 5, kind = "service" } }, mood = "tech" }))
	else
		table.insert(out, room({ id = string.format("L%d_WC", level), level = level, name = "Restrooms", kind = "wc", access = "staff", x1 = Plan.WC.x1, x2 = Plan.WC.x2, z1 = Plan.WC.z1, z2 = Plan.WC.z2, doors = { { face = "S", at = 14.5, w = 6, kind = "solid" } }, mood = "neutral" }))
	end
end

local function groundRooms(out: { Room })
	local L = 0
	local list: { any } = {
		{ id = "G_LOBBY", name = "Reception Hall", kind = "lobby", access = "public", x1 = -22, x2 = 22, z1 = -48, z2 = -20, doors = {}, camera = true, mood = "warm", nowalls = true },
		{ id = "G_ATRIUM", name = "Atrium", kind = "atrium", access = "staff", x1 = -22, x2 = 22, z1 = -20, z2 = 36, nowalls = true, camera = true, mood = "warm",
			doors = {
				{ face = "S", at = -18, w = 4.5, kind = "speedgate" }, -- accessible lane, clear of the atrium column at x=-14
				{ face = "S", at = -6.75, w = 3, kind = "speedgate" },
				{ face = "S", at = -2.25, w = 3, kind = "speedgate" },
				{ face = "S", at = 2.25, w = 3, kind = "speedgate" },
				{ face = "S", at = 6.75, w = 3, kind = "speedgate" },
			} },
		{ id = "G_VISITOR", name = "Visitor Lounge", kind = "visitor_lounge", access = "public", x1 = -50, x2 = -22, z1 = -48, z2 = -16, open = { "E" }, mood = "warm",
			doors = { { face = "N", at = -46, w = 6, kind = "glass", access = "staff", flip = true } } },
		{ id = "G_SHOWROOM", name = "Showroom & Demo", kind = "showroom", access = "public", x1 = -82, x2 = -50, z1 = -48, z2 = -8, doors = { { face = "E", at = -30, w = 8, kind = "glassdouble" } }, camera = true, mood = "neutral" },
		{ id = "G_PROJECT", name = "Project Room", kind = "project_meeting", access = "staff", x1 = -82, x2 = -50, z1 = -8, z2 = 28, seats = 10, doors = { { face = "E", at = 4, w = 6, kind = "glass" } }, meeting = "ProjectRoom", mood = "neutral" },
		{ id = "G_COMPUTE", name = "Compute Operations", kind = "compute", access = "compute", x1 = -82, x2 = -50, z1 = 28, z2 = 80, doors = { { face = "E", at = 40, w = 6, kind = "secure" } }, camera = true, mood = "tech" },
		{ id = "G_FIRSTAI", name = "First AI Studio", kind = "first_ai", access = "staff", x1 = -42, x2 = -22, z1 = -16, z2 = 36, desks = 6, doors = { { face = "E", at = 4, w = 8, kind = "glassdouble" } }, mood = "neutral" },
		{ id = "G_ITDESK", name = "IT Service Desk", kind = "itdesk", access = "technical", x1 = -42, x2 = -22, z1 = 44, z2 = 80, doors = { { face = "S", at = -32, w = 6, kind = "service" } }, mood = "tech" },
		{ id = "G_CAFE", name = "House Kitchen Café", kind = "cafe", access = "public", x1 = 22, x2 = 82, z1 = -48, z2 = 28, doors = { { face = "W", at = -35, w = 18, kind = "opening" } }, camera = true, mood = "warm" },
		{ id = "G_KITCHEN", name = "Kitchen", kind = "kitchen_boh", access = "staff", x1 = 50, x2 = 82, z1 = 28, z2 = 52, doors = { { face = "W", at = 40, w = 6, kind = "solid" }, { face = "S", at = 70, w = 5, kind = "solid" } }, mood = "neutral" },
		{ id = "G_DELIVERY", name = "Deliveries & Service", kind = "delivery", access = "technical", x1 = 50, x2 = 82, z1 = 52, z2 = 80, doors = { { face = "W", at = 66, w = 6, kind = "service" }, { face = "E", at = 66, w = 8, kind = "service", exterior = true } }, mood = "tech" },
		{ id = "G_MAILROOM", name = "Mailroom & Lockers", kind = "mailroom", access = "staff", x1 = 22, x2 = 42, z1 = 44, z2 = 80, doors = { { face = "S", at = 32, w = 6, kind = "glass" } }, mood = "neutral" },
	}
	for _, def in list do
		def.level = L
		table.insert(out, room(def))
	end
end

local function foundationOrWork(level: number, theme: string, out: { Room })
	local t = THEMES[theme]
	for _, side in { "W", "E" } do
		for zone, def in t[side] do
			table.insert(out, wingRoom(level, side == "E", zone, def))
		end
	end
end

local function founderRooms(level: number, out: { Room })
	local F = Plan.FOUNDER_FRONT_Z
	local list: { any } = {
		{ id = "F_ASSIST", name = "Founder Reception", kind = "founder_assist", access = "founder", x1 = 22, x2 = 42, z1 = -24, z2 = 14, desks = 1, doors = { { face = "W", at = -4, w = 6, kind = "secure" }, { face = "E", at = -10, w = 6, kind = "solid" } }, mood = "founder" },
		{ id = "F_OFFICE", name = "Founder Office", kind = "founder_office", access = "founder", x1 = 42, x2 = 82, z1 = F, z2 = 14, desks = 1, doors = { { face = "S", at = 62, w = 6, kind = "glass", exterior = true } }, camera = true, mood = "founder" },
		{ id = "F_LIBRARY", name = "Founder Library", kind = "founder_library", access = "founder", x1 = 42, x2 = 66, z1 = 14, z2 = 30, doors = { { face = "S", at = 54, w = 5, kind = "solid" } }, mood = "founder" },
		{ id = "F_BATH", name = "Private Bathroom", kind = "founder_bath", access = "founder", x1 = 66, x2 = 82, z1 = 14, z2 = 30, doors = { { face = "S", at = 74, w = 5, kind = "solid" } }, mood = "warm" },
		{ id = "F_TERRACE_PRIVATE", name = "Founder Terrace", kind = "terrace", access = "founder", x1 = 42, x2 = 82, z1 = -48, z2 = F, outdoor = true, fence = true, mood = "warm" },
		{ id = "F_TERRACE", name = "Executive Terrace", kind = "terrace", access = "staff", x1 = -82, x2 = 42, z1 = -48, z2 = F, outdoor = true, nowalls = true, doors = { { face = "N", at = 0, w = 8, kind = "glassdouble", exterior = true } }, mood = "warm" },
		{ id = "F_BOARDROOM", name = "Boardroom", kind = "boardroom", access = "staff", x1 = -82, x2 = -50, z1 = F, z2 = 8, seats = 12, doors = { { face = "E", at = -12, w = 8, kind = "glassdouble" } }, camera = false, meeting = "Boardroom", mood = "founder" },
		{ id = "F_EXECTEAM", name = "Executive Team", kind = "team", access = "staff", dept = "growth", x1 = -82, x2 = -50, z1 = 8, z2 = 40, desks = 8, doors = { { face = "E", at = 24, w = 6, kind = "glass" } }, mood = "neutral" },
		{ id = "F_STRATEGY", name = "Strategy Room", kind = "meeting", access = "staff", x1 = -82, x2 = -50, z1 = 40, z2 = 80, seats = 8, doors = { { face = "E", at = 60, w = 6, kind = "glass" } }, meeting = "F_STRATEGY", mood = "neutral" },
		{ id = "F_FOCUS1", name = "Focus Room 1", kind = "focus", access = "staff", dept = "research", x1 = -42, x2 = -22, z1 = -16, z2 = -4, desks = 1, doors = { { face = "E", at = -10, w = 6, kind = "glass" } } },
		{ id = "F_FOCUS2", name = "Focus Room 2", kind = "focus", access = "staff", dept = "research", x1 = -42, x2 = -22, z1 = -4, z2 = 8, desks = 1, doors = { { face = "E", at = 2, w = 6, kind = "glass" } } },
		{ id = "F_ASSISTANTS", name = "Executive Assistants", kind = "team", access = "staff", dept = "operations", x1 = -42, x2 = -22, z1 = 8, z2 = 36, desks = 4, doors = { { face = "E", at = 22, w = 6, kind = "glass" } } },
		{ id = "F_PHONE", name = "Phone Booths", kind = "phone", access = "staff", x1 = -42, x2 = -22, z1 = 44, z2 = 80, doors = { { face = "S", at = -32, w = 6, kind = "glass" } } },
		{ id = "F_HR", name = "People & Company Office", kind = "hr", access = "staff", dept = "operations", x1 = 22, x2 = 42, z1 = 14, z2 = 36, desks = 3, doors = { { face = "W", at = 25, w = 6, kind = "glass" } } },
		{ id = "F_INVESTOR", name = "Investor Room", kind = "meeting", access = "staff", x1 = 22, x2 = 42, z1 = 44, z2 = 80, seats = 6, doors = { { face = "S", at = 32, w = 6, kind = "glass" } }, meeting = "F_INVESTOR" },
		{ id = "F_LOUNGE", name = "Executive Lounge", kind = "lounge", access = "staff", x1 = 50, x2 = 82, z1 = 30, z2 = 56, doors = { { face = "W", at = 43, w = 8, kind = "opening" } }, mood = "warm" },
		{ id = "F_PANTRY", name = "Tea Kitchen", kind = "pantry", access = "staff", x1 = 50, x2 = 82, z1 = 56, z2 = 80, doors = { { face = "W", at = 68, w = 8, kind = "opening" } }, mood = "warm" },
	}
	for _, def in list do
		def.level = level
		table.insert(out, room(def))
	end
end

local function basementRooms(out: { Room })
	local L = -1
	local list: { any } = {
		{ id = "B1_DATAHALL", name = "Data Hall", kind = "datahall", access = "compute", x1 = -94, x2 = -22, z1 = -64, z2 = 64, camera = true, mood = "tech",
			doors = { { face = "E", at = 47, w = 6, kind = "secure" }, { face = "E", at = -40, w = 6, kind = "secure" } } },
		{ id = "B1_GARAGE", name = "Underground Garage", kind = "garage", access = "staff", x1 = -22, x2 = 112, z1 = -64, z2 = 64, camera = true, mood = "tech", nowalls = true },
		{ id = "B1_LOBBY", name = "Garage Lift Lobby", kind = "b1_lobby", access = "staff", x1 = -22, x2 = 22, z1 = 40, z2 = 54, doors = { { face = "S", at = 0, w = 8, kind = "glassdouble" } }, mood = "neutral" },
		{ id = "B1_PLANT", name = "Energy & Plant Room", kind = "plant", access = "technical", x1 = -94, x2 = -58, z1 = 64, z2 = 80, doors = { { face = "S", at = -76, w = 6, kind = "service" }, { face = "N", at = -76, w = 6, kind = "service" } }, camera = true, mood = "tech" },
		{ id = "B1_UPS", name = "UPS & Battery Room", kind = "ups", access = "technical", x1 = -58, x2 = -22, z1 = 64, z2 = 80, doors = { { face = "S", at = -40, w = 6, kind = "service" }, { face = "N", at = -40, w = 6, kind = "service" } }, mood = "tech" },
		{ id = "B1_FLEET", name = "Fleet Office", kind = "fleet", access = "staff", x1 = 22, x2 = 46, z1 = 44, z2 = 64, desks = 1, doors = { { face = "S", at = 34, w = 6, kind = "glass" } }, mood = "neutral" },
		{ id = "B1_WORKSHOP", name = "Workshop", kind = "workshop", access = "technical", x1 = 22, x2 = 62, z1 = 64, z2 = 80, doors = { { face = "S", at = 54, w = 10, kind = "service" }, { face = "N", at = 43, w = 6, kind = "service" } }, mood = "tech" },
		{ id = "B1_STORAGE", name = "Goods-in & IT Storage", kind = "storage", access = "technical", x1 = 62, x2 = 112, z1 = 64, z2 = 80, doors = { { face = "S", at = 88, w = 10, kind = "service" }, { face = "N", at = 88, w = 6, kind = "service" } }, mood = "tech" },
		{ id = "B1_SPINE", name = "Technical Service Spine", kind = "spine", access = "technical", x1 = -94, x2 = 112, z1 = 80, z2 = 88, mood = "tech", nowalls = true },
	}
	for _, def in list do
		def.level = L
		table.insert(out, room(def))
	end
end

local function pavilionRooms(out: { Room })
	local g: { any } = {
		{ id = "P0_CORRIDOR", name = "Wellness Corridor", kind = "pavilion_corridor", access = "staff", x1 = -82, x2 = 82, z1 = 80, z2 = 94, camera = true, mood = "wellness", nowalls = true, doors = { { face = "S", at = -46, w = 6, kind = "glass" }, { face = "S", at = 46, w = 6, kind = "glass" } } },
		{ id = "P0_GYM", name = "Movement Studio", kind = "gym", access = "staff", x1 = -82, x2 = -36, z1 = 94, z2 = 160, doors = { { face = "S", at = -60, w = 8, kind = "glassdouble" } }, camera = true, mood = "wellness" },
		{ id = "P0_RECOVERY", name = "Recovery Lounge", kind = "recovery", access = "staff", x1 = -36, x2 = -6, z1 = 94, z2 = 128, doors = { { face = "S", at = -21, w = 6, kind = "glass" } }, mood = "warm" },
		{ id = "P0_SAUNA", name = "Cedar Sauna", kind = "sauna", access = "staff", x1 = -36, x2 = -6, z1 = 128, z2 = 160, doors = { { face = "S", at = -21, w = 5, kind = "solid" } }, mood = "warm" },
		{ id = "P0_RESTROOMS", name = "Restrooms", kind = "restrooms", access = "staff", x1 = -6, x2 = 24, z1 = 94, z2 = 160, doors = { { face = "S", at = 9, w = 6, kind = "solid" } }, mood = "neutral" },
		{ id = "P0_SHOWERS", name = "Showers & Lockers", kind = "showers", access = "staff", x1 = 24, x2 = 58, z1 = 94, z2 = 160, doors = { { face = "S", at = 41, w = 6, kind = "solid" } }, mood = "neutral" },
		{ id = "P0_GARDEN", name = "Garden Lobby", kind = "garden_lobby", access = "staff", x1 = 58, x2 = 82, z1 = 94, z2 = 160, doors = { { face = "S", at = 70, w = 8, kind = "opening" }, { face = "N", at = 70, w = 8, kind = "glassdouble", exterior = true } }, mood = "warm" },
	}
	for _, def in g do
		def.level = 0
		def.pavilion = true
		table.insert(out, room(def))
	end
	local f: { any } = {
		{ id = "P1_CORRIDOR", name = "Founder Services", kind = "pavilion_corridor", access = "founder", x1 = -82, x2 = 82, z1 = 80, z2 = 94, camera = true, mood = "founder", nowalls = true, doors = { { face = "S", at = -46, w = 6, kind = "secure" }, { face = "S", at = 46, w = 6, kind = "secure" } } },
		{ id = "P1_SECURITY", name = "Campus Security", kind = "security", access = "founder", x1 = -82, x2 = -42, z1 = 94, z2 = 160, doors = { { face = "S", at = -62, w = 6, kind = "secure" } }, mood = "cool" },
		{ id = "P1_ARCHIVE", name = "Founder Archive", kind = "archive", access = "founder", x1 = -42, x2 = 6, z1 = 94, z2 = 126, doors = { { face = "S", at = -18, w = 6, kind = "solid" }, { face = "N", at = -18, w = 7, kind = "bookcase", hidden = true, flip = true } }, camera = true, mood = "founder" },
		{ id = "P1_PASSAGE", name = "Shelf Passage", kind = "secret_passage", access = "founder", hidden = true, x1 = -22.5, x2 = -6.5, z1 = 126, z2 = 130, mood = "secret" },
		-- The hidden lab sits behind a 4-stud thick shelving wall (z 126..130) of the archive.
		{ id = "P1_SECRET", name = "Hidden Research Lab", kind = "secret_lab", access = "founder", hidden = true, x1 = -42, x2 = 6, z1 = 130, z2 = 160, desks = 2, doors = { { face = "S", at = -18, w = 7, kind = "opening" } }, camera = true, mood = "secret" },
		-- Entered through a flush door in the timber wall panelling of the corridor; no sign.
		{ id = "P1_PROTOTYPE", name = "Prototype Lab", kind = "prototype", access = "founder", x1 = 6, x2 = 58, z1 = 94, z2 = 160, desks = 2, doors = { { face = "S", at = 32, w = 6, kind = "flush" } }, camera = true, mood = "secret" },
		{ id = "P1_VAULT", name = "Model Vault", kind = "vault", access = "founder", x1 = 58, x2 = 82, z1 = 94, z2 = 160, doors = { { face = "W", at = 127, w = 6, kind = "vault" } }, mood = "secret" },
	}
	for _, def in f do
		def.level = 1
		def.pavilion = true
		table.insert(out, room(def))
	end
end

local function roofRooms(level: number, out: { Room })
	local list: { any } = {
		{ id = "R_LOBBY", name = "Roof Lobby", kind = "roof_lobby", access = "staff", x1 = -22, x2 = 22, z1 = 42, z2 = 54, doors = { { face = "S", at = 0, w = 8, kind = "glassdouble", exterior = true } }, mood = "neutral" },
		{ id = "R_TERRACE", name = "Roof Terrace", kind = "roof_terrace", access = "staff", x1 = -82, x2 = 82, z1 = Plan.FOUNDER_FRONT_Z, z2 = 42, outdoor = true, nowalls = true, camera = true, mood = "warm" },
		{ id = "R_TECH", name = "Roof Plant", kind = "roof_tech", access = "technical", x1 = 22, x2 = 82, z1 = 42, z2 = 80, outdoor = true, fence = true, doors = { { face = "S", at = 52, w = 6, kind = "service", exterior = true } }, mood = "tech" },
		{ id = "R_SOLAR", name = "Solar Array", kind = "roof_solar", access = "technical", x1 = -82, x2 = -22, z1 = 42, z2 = 80, outdoor = true, fence = true, doors = { { face = "S", at = -52, w = 6, kind = "service", exterior = true } }, mood = "tech" },
	}
	for _, def in list do
		def.level = level
		table.insert(out, room(def))
	end
end

local cache: { [number]: { Room } } = {}
function Plan.rooms(tier: number): { Room }
	tier = math.clamp(math.floor(tier), 1, 4)
	local existing = cache[tier]
	if existing then
		return existing
	end
	local out: { Room } = {}
	basementRooms(out)
	groundRooms(out)
	pavilionRooms(out)
	local founder = Plan.founderLevel(tier)
	for level = 1, founder - 1 do
		local theme = Plan.theme(tier, level)
		if theme then
			foundationOrWork(level, theme, out)
		end
	end
	founderRooms(founder, out)
	roofRooms(Plan.roofLevel(tier), out)
	for level = -1, Plan.roofLevel(tier) do
		coreRooms(level, tier, out)
	end
	-- The pavilion roof is a staff garden reached from the level-2 corridor ends.
	table.insert(out, room({ id = "P2_ROOF", level = 2, name = "Pavilion Roof Garden", kind = "pavilion_roof", access = "staff", x1 = -82, x2 = 82, z1 = 80, z2 = 160, outdoor = true, nowalls = true, pavilion = true, mood = "warm", doors = { { face = "S", at = -46, w = 6, kind = "glass", exterior = true }, { face = "S", at = 46, w = 6, kind = "glass", exterior = true } } }))
	table.sort(out, function(a, b)
		if a.level ~= b.level then
			return a.level < b.level
		end
		return a.id < b.id
	end)
	cache[tier] = out
	return out
end

function Plan.room(tier: number, id: string): Room?
	for _, r in Plan.rooms(tier) do
		if r.id == id then
			return r
		end
	end
	return nil
end

function Plan.roomsOnLevel(tier: number, level: number): { Room }
	local out = {}
	for _, r in Plan.rooms(tier) do
		if r.level == level then
			table.insert(out, r)
		end
	end
	return out
end

-- Smallest room that contains the point (rooms may overlap open-plan areas such as the lobby).
function Plan.roomAt(tier: number, p: Vector3): Room?
	local level = Plan.levelAt(tier, p.Y)
	if level == nil then
		return nil
	end
	local best: Room? = nil
	local area = math.huge
	for _, r in Plan.rooms(tier) do
		if r.level == level and p.X >= r.x1 and p.X <= r.x2 and p.Z >= r.z1 and p.Z <= r.z2 then
			local a = (r.x2 - r.x1) * (r.z2 - r.z1)
			if a < area then
				best = r
				area = a
			end
		end
	end
	return best
end

-- True inside the occupied building volume: main block storeys, pavilion, garage and roof deck.
function Plan.inside(tier: number, p: Vector3): boolean
	local floors = Plan.floors(tier)
	local m = Plan.MAIN
	if p.X > m.x1 - 0.5 and p.X < m.x2 + 0.5 and p.Z > m.z1 - 0.5 and p.Z < m.z2 + 0.5 then
		local roofY = Plan.levelY(floors)
		local pt = Plan.PORTAL
		if p.Y < 14 and p.X > pt.x1 and p.X < pt.x2 and p.Z < pt.z2 then
			return false -- the covered entrance recess is outside the card line
		end
		-- every storey incl. the founder terrace in front of the setback
		if p.Y > -2 and p.Y < roofY - 2 then
			return true
		end
		-- roof deck sits on the set-back founder storey only
		if p.Y >= roofY - 2 and p.Y < roofY + 14 and p.Z > Plan.FOUNDER_FRONT_Z - 0.5 then
			return true
		end
	end
	local pv = Plan.PAVILION
	if p.X > pv.x1 - 0.5 and p.X < pv.x2 + 0.5 and p.Z > pv.z1 and p.Z < pv.z2 + 0.5 and p.Y > -2 and p.Y < 46 then
		return true
	end
	return Plan.inGarage(p)
end

function Plan.inGarage(p: Vector3): boolean
	local g = Plan.GARAGE
	return p.X > g.x1 and p.X < g.x2 and p.Z > g.z1 and p.Z < g.z2 and p.Y > Plan.B1_Y - 3 and p.Y < -2
end

-- Access class at a building-local point. Corridors, lifts lobbies and stairs are staff areas.
function Plan.accessAt(tier: number, p: Vector3): (string, Room?)
	local r = Plan.roomAt(tier, p)
	if r then
		return r.access, r
	end
	-- outdoor grounds (plaza, gardens, paths) are public; anything inside the envelope is staff
	return if Plan.inside(tier, p) then "staff" else "public", nil
end

function Plan.roleAllows(role: string, class: string?): boolean
	if class == nil or class == "public" then
		return true
	end
	local c = ROLE_CLEARANCE[role] or ROLE_CLEARANCE.support
	return c[class] == true
end

-- isOwner: the company founder; guest: holds a valid guest card for this company.
function Plan.playerAllows(isOwner: boolean, hasCard: boolean, class: string?): boolean
	if isOwner or class == "public" then
		return true -- the reception hall, visitor lounge, showroom and café are open to visitors
	end
	if not hasCard then
		return false
	end
	return class == nil or class == "public" or class == "staff"
end

function Plan.employeeAllowed(role: string, tier: number, p: Vector3): boolean
	local floors = Plan.floors(tier)
	if p.Y < Plan.B1_Y - 3 or p.Y > floors * Plan.FLOOR_HEIGHT + 14 then
		return false
	end
	local s = Plan.SITE
	if p.X < s.x1 or p.X > s.x2 or p.Z < s.z1 or p.Z > s.z2 then
		return false
	end
	local class = Plan.accessAt(tier, p)
	return Plan.roleAllows(role, class)
end

-- Lift stops from B1 to the roof, with labels for the cabin panel and landing indicators.
export type Stop = { level: number, y: number, label: string, name: string }
function Plan.liftStops(tier: number): { Stop }
	local out = {}
	for level = -1, Plan.roofLevel(tier) do
		table.insert(out, { level = level, y = Plan.levelY(level), label = Plan.levelLabel(tier, level), name = Plan.levelName(tier, level) })
	end
	return out
end

-- Standing points in front of the lift (waiting queue) and inside the cabin (slots).
function Plan.liftWaitPoint(level: number, slot: number): Vector3
	local columns = { -9, -5, 5, 9, -12, 12 }
	local x = columns[(slot - 1) % #columns + 1]
	local row = (slot - 1) // #columns
	return Vector3.new(x, Plan.levelY(level) + 3, 48 - row * 3)
end
function Plan.liftCabinSlot(slot: number): Vector3
	-- relative to the cabin floor centre (cabin-local, Y = standing height)
	local spots = { Vector3.new(-3.2, 3, 3), Vector3.new(3.2, 3, 3), Vector3.new(-3.2, 3, -0.5), Vector3.new(3.2, 3, -0.5), Vector3.new(0, 3, 3.2), Vector3.new(0, 3, -0.5) }
	return spots[(slot - 1) % #spots + 1]
end
function Plan.liftExitPoint(level: number, slot: number): Vector3
	local xs = { -6, 6, -10, 10, -2, 2 }
	return Vector3.new(xs[(slot - 1) % #xs + 1], Plan.levelY(level) + 3, 44)
end
function Plan.stairEntry(level: number): Vector3
	return Vector3.new(Plan.STAIR_LAYOUT.door.x, Plan.levelY(level) + 3, 50)
end

-- Department room types that host Computer workstations, used by StaffService preferences.
Plan.WORK_KINDS = {
	team = true, architecture = true, datalab = true, control = true, evaluation = true, launch = true,
	support = true, studio = true, platform = true, lab = true, hwlab = true, hr = true, focus = true,
	first_ai = true, founder_office = true, founder_assist = true, fleet = true, secret_lab = true, prototype = true,
}

-- Rooms that must never receive a camera.
Plan.NO_CAMERA = { wc = true, restrooms = true, showers = true, founder_bath = true, sauna = true, stair = true }

return Plan
