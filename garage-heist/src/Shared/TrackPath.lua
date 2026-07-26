--[[
	TrackPath
	Die Rennstrecke als reine Mathematik. Seit v9 dreidimensional: die Kurve
	kann steigen, sich querneigen und einen Looping schlagen.

	Liegt in Shared, weil zwei Seiten dieselbe Kurve brauchen:
	- der Server baut die Geometrie darauf (RaceTrack)
	- jeder Client bewegt seinen eigenen Verkehr darauf (TrafficController)

	WICHTIG: TrackPath.At(s) gibt weiterhin genau ein CFrame zurueck - nur eines,
	das jetzt auch kippen und kopfueber stehen kann. Die Signatur bleibt, sonst
	brechen RaceTrack und TrafficController gleichzeitig. Der Verkehr faehrt die
	neue Strecke ohne eine Zeile Aenderung ab; das ist der kostenlose Test, ob
	die Kurve stimmt.

	Masse sind auf die Garagen abgestimmt. Die Plots stehen in zwei Reihen bei
	z = +/-82 (Tiefe 54, also z von 55 bis 109) und x von -163 bis 163.

	HOEHE 44 ist kein Zufall: von der Mitte des Hofs aus streift die Sichtlinie
	ueber ein 18 Studs hohes Garagendach bei z = 55 auf Augenhoehe 5 bei
	z = 140 die Hoehe 36. Alles darunter waere hinter dem Dach versteckt. Bei
	44 sieht man die Autos von ueberall im Hof - genau darum geht es. Die
	Elemente gehen von dieser Hoehe AUS und kehren zu ihr zurueck.

	Segmentarten:
	  line   Gerade in der XZ-Ebene, optional mit Hoehenaenderung (rise)
	  arc    Viertelkreis, optional mit Querneigung (bank)
	  loop   senkrechter Kreis um die Querachse; verbraucht Bogenlaenge, aber
	         keine XZ-Strecke - er endet dort, wo er anfing
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local TrackPath = {}

TrackPath.HALF_LENGTH = 265 -- halbe Ausdehnung in X
TrackPath.HALF_WIDTH = 140 -- halbe Ausdehnung in Z
TrackPath.RADIUS = 70 -- Eckradius
TrackPath.HEIGHT = 44 -- Grundhoehe der Fahrbahn ueber Grund
TrackPath.ROAD_WIDTH = 30
TrackPath.LANES = { -9.5, 0, 9.5 } -- Spurmitten quer zur Fahrtrichtung

local L = TrackPath.HALF_LENGTH
local W = TrackPath.HALF_WIDTH
local R = TrackPath.RADIUS
local Y = TrackPath.HEIGHT

local STRAIGHT_X = 2 * (L - R)
local STRAIGHT_Z = 2 * (W - R)
local ARC = math.pi * R / 2

local CREST = Config.TRACK_CREST_RISE
local CREST_LEN = Config.TRACK_CREST_LENGTH
local BANK = math.rad(Config.TRACK_BANK_DEGREES)
local LOOP_R = Config.TRACK_LOOP_RADIUS
local LOOP_LEN = 2 * math.pi * LOOP_R
local LOOP_AT = Config.TRACK_LOOP_OFFSET

TrackPath.LOOP_RADIUS = LOOP_R
TrackPath.TOP_HEIGHT = Y + math.max(CREST, 2 * LOOP_R) -- hoechster Punkt, fuer Bauzwecke

-- Vector2.X = Welt-X, Vector2.Y = Welt-Z.
-- Reihenfolge im Uhrzeigersinn von oben, Start auf der vorderen Geraden.
-- Der Winkel phi laeuft durchgehend von +90 auf -270 herunter, damit jede
-- Ecke nahtlos an die vorherige anschliesst.
local SEGMENTS = {}

local function line(len: number, fromX: number, fromZ: number, dirX: number, dirZ: number, rise: number?)
	table.insert(SEGMENTS, {
		kind = "line",
		len = len,
		from = Vector2.new(fromX, fromZ),
		dir = Vector2.new(dirX, dirZ),
		rise = rise or 0,
		bank = 0,
	})
end

local function arc(centerX: number, centerZ: number, fromDeg: number)
	table.insert(SEGMENTS, {
		kind = "arc",
		len = ARC,
		center = Vector2.new(centerX, centerZ),
		from = fromDeg,
		rise = 0,
		bank = BANK,
	})
end

local function loop(atX: number, atZ: number, dirX: number, dirZ: number)
	table.insert(SEGMENTS, {
		kind = "loop",
		len = LOOP_LEN,
		from = Vector2.new(atX, atZ),
		dir = Vector2.new(dirX, dirZ),
		rise = 0,
		bank = 0,
	})
end

-- Nordgerade mit Kuppe in der Mitte: hoch, wieder runter, netto null.
local restNorth = STRAIGHT_X - 2 * CREST_LEN
line(restNorth / 2, -(L - R), W, 1, 0)
line(CREST_LEN, -(L - R) + restNorth / 2, W, 1, 0, CREST)
line(CREST_LEN, -(L - R) + restNorth / 2 + CREST_LEN, W, 1, 0, -CREST)
line(restNorth / 2, (L - R) - restNorth / 2, W, 1, 0)

arc(L - R, W - R, 90)
line(STRAIGHT_Z, L, W - R, 0, -1)
arc(L - R, -(W - R), 0)

-- Suedgerade mit Looping. Der Looping verbraucht Bogenlaenge, aber keine
-- XZ-Strecke - die Gerade bleibt deshalb insgesamt STRAIGHT_X lang.
line(LOOP_AT, L - R, -W, -1, 0)
loop((L - R) - LOOP_AT, -W, -1, 0)
line(STRAIGHT_X - LOOP_AT, (L - R) - LOOP_AT, -W, -1, 0)

arc(-(L - R), -(W - R), -90)
line(STRAIGHT_Z, -L, -(W - R), 0, 1)
arc(-(L - R), W - R, -180)

-- Starthoehe je Segment einmal vorrechnen, statt bei jedem At() die Liste
-- aufzusummieren. Die Kette MUSS sich schliessen, sonst haette die Strecke
-- nach einer Runde eine Stufe.
local cursorY = Y
for _, seg in SEGMENTS do
	seg.y0 = cursorY
	cursorY += seg.rise
end
assert(math.abs(cursorY - Y) < 1e-6, "TrackPath: die Hoehen summieren sich nicht auf null")

TrackPath.Segments = SEGMENTS

local length = 0
for _, seg in SEGMENTS do
	length += seg.len
end
TrackPath.LENGTH = length

-- Glaettung 0 -> 1 mit waagerechter Tangente an beiden Enden. Ohne die haette
-- jede Rampe am Anfang und Ende einen Knick.
local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- Querneigung: 0 an beiden Segmentenden, voll in der Mitte. Ein Bogen geht
-- damit sauber aus der Geraden heraus und wieder hinein.
local function bankProfile(t: number): number
	local ramp = 0.25
	if t < ramp then
		return smooth(t / ramp)
	elseif t > 1 - ramp then
		return smooth((1 - t) / ramp)
	end
	return 1
end

--[[
	Der Looping als senkrechter Kreis in der Ebene aus Fahrtrichtung und Hoehe.

	theta = 0 ist der Einstieg unten, theta = pi der Scheitel. Die Formeln sind
	so gewaehlt, dass Ein- und Ausstieg exakt derselbe Punkt mit derselben
	Ausrichtung sind - sonst haette die Strecke dort eine Kante.

	Vorwaerts und Oben stehen in jedem theta senkrecht aufeinander (das Skalar-
	produkt kuerzt sich zu null), deshalb ist CFrame.lookAt hier immer definiert.
]]
local function loopFrame(seg, t: number): CFrame
	local theta = t * math.pi * 2
	local dir = Vector3.new(seg.dir.X, 0, seg.dir.Y)
	local up = Vector3.new(0, 1, 0)
	local base = Vector3.new(seg.from.X, seg.y0, seg.from.Y)
	local center = base + up * LOOP_R

	local position = center - up * (LOOP_R * math.cos(theta)) + dir * (LOOP_R * math.sin(theta))
	local forward = dir * math.cos(theta) + up * math.sin(theta)
	local carUp = up * math.cos(theta) - dir * math.sin(theta)
	return CFrame.lookAt(position, position + forward, carUp)
end

-- CFrame an der Bogenlaenge s. Die LookVector zeigt in Fahrtrichtung, die
-- RightVector quer nach aussen - Spurversatz also einfach mit
--   TrackPath.At(s) * CFrame.new(spur, 0, 0)
function TrackPath.At(s: number): CFrame
	local remaining = s % TrackPath.LENGTH
	for _, seg in SEGMENTS do
		if remaining < seg.len then
			local t = remaining / seg.len
			if seg.kind == "loop" then
				return loopFrame(seg, t)
			end

			local pos, dir
			if seg.kind == "line" then
				pos = seg.from + seg.dir * remaining
				dir = seg.dir
			else
				local phi = math.rad(seg.from - t * 90)
				pos = seg.center + Vector2.new(math.cos(phi), math.sin(phi)) * R
				dir = Vector2.new(math.sin(phi), -math.cos(phi))
			end

			-- Hoehe geglaettet, Steigung ist deren Ableitung. Der Anstieg ist
			-- flach genug, dass der Unterschied zwischen Grundriss- und
			-- Bahnlaenge unter zwei Prozent bleibt; das wird bewusst ignoriert,
			-- damit s eine einfache Zahl bleibt.
			local y = seg.y0 + seg.rise * smooth(t)
			local slope = seg.rise * 6 * t * (1 - t) / seg.len

			local point = Vector3.new(pos.X, y, pos.Y)
			local forward = Vector3.new(dir.X, slope, dir.Y).Unit
			local frame = CFrame.lookAt(point, point + forward)

			if seg.bank ~= 0 then
				-- Drehung um die lokale Z-Achse kippt die Fahrbahn. Positiv hebt
				-- die rechte Seite - und rechts ist in allen vier Boegen aussen,
				-- weil der Kurs im Uhrzeigersinn laeuft.
				frame *= CFrame.Angles(0, 0, seg.bank * bankProfile(t))
			end
			return frame
		end
		remaining -= seg.len
	end
	-- Rundungsrest am Ende: zurueck auf den Anfang.
	return TrackPath.At(0)
end

-- Grobe Punktliste fuer Bauzwecke: gibt Mittelpunkt und Laenge jedes
-- Bauabschnitts zurueck. Nur eine ebene Gerade bleibt ein einziges Part;
-- alles, was sich kruemmt, kippt oder steigt, wird zerlegt.
function TrackPath.BuildSpans(arcSteps: number?)
	local steps = arcSteps or 14
	local spans = {}
	local cursor = 0
	for _, seg in SEGMENTS do
		local pieces
		if seg.kind == "loop" then
			pieces = Config.TRACK_LOOP_STEPS
		elseif seg.kind == "line" and seg.rise == 0 then
			pieces = 1
		else
			pieces = steps
		end

		local piece = seg.len / pieces
		for i = 0, pieces - 1 do
			table.insert(spans, {
				s = cursor + piece * (i + 0.5),
				-- Ueberlappung, sonst klaffen zwischen den Stuecken Fugen.
				len = if pieces > 1 then piece + 1.2 else piece,
				straight = pieces == 1,
				kind = seg.kind,
			})
		end
		cursor += seg.len
	end
	return spans
end

-- Steht die Fahrbahn an dieser Stelle normal auf dem Boden? Der Streckenbau
-- benutzt das, um unter einem Looping keine Stuetzpfeiler zu setzen.
function TrackPath.IsUpright(s: number): boolean
	local frame = TrackPath.At(s)
	return frame.UpVector.Y > 0.9
end

return TrackPath
