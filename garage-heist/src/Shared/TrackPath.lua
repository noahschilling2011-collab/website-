--[[
	TrackPath
	Die Rennstrecke als reine Mathematik: ein Oval (Stadionform) mit zwei
	langen Geraden in X, zwei kurzen in Z und vier Viertelkreisen.

	Liegt in Shared, weil zwei Seiten dieselbe Kurve brauchen:
	- der Server baut die Geometrie darauf (RaceTrack)
	- jeder Client bewegt seinen eigenen Verkehr darauf (TrafficController)

	Masse sind auf die Garagen abgestimmt. Die Plots stehen in zwei Reihen bei
	z = +/-82 (Tiefe 54, also z von 55 bis 109) und x von -163 bis 163.

	HOEHE 44 ist kein Zufall: von der Mitte des Hofs aus streift die Sichtlinie
	ueber ein 18 Studs hohes Garagendach bei z = 55 auf Augenhoehe 5 bei
	z = 140 die Hoehe 36. Alles darunter waere hinter dem Dach versteckt. Bei
	44 sieht man die Autos von ueberall im Hof - genau darum geht es.
]]

local TrackPath = {}

TrackPath.HALF_LENGTH = 265 -- halbe Ausdehnung in X
TrackPath.HALF_WIDTH = 140 -- halbe Ausdehnung in Z
TrackPath.RADIUS = 70 -- Eckradius
TrackPath.HEIGHT = 44 -- Fahrbahnhoehe ueber Grund
TrackPath.ROAD_WIDTH = 30
TrackPath.LANES = { -9.5, 0, 9.5 } -- Spurmitten quer zur Fahrtrichtung

local L = TrackPath.HALF_LENGTH
local W = TrackPath.HALF_WIDTH
local R = TrackPath.RADIUS
local Y = TrackPath.HEIGHT

local STRAIGHT_X = 2 * (L - R)
local STRAIGHT_Z = 2 * (W - R)
local ARC = math.pi * R / 2

TrackPath.LENGTH = 2 * STRAIGHT_X + 2 * STRAIGHT_Z + 4 * ARC

-- Vector2.X = Welt-X, Vector2.Y = Welt-Z.
-- Reihenfolge im Uhrzeigersinn von oben, Start auf der vorderen Geraden.
-- Der Winkel phi laeuft durchgehend von +90 auf -270 herunter, damit jede
-- Ecke nahtlos an die vorherige anschliesst.
local SEGMENTS = {
	{ kind = "line", len = STRAIGHT_X, from = Vector2.new(-(L - R), W), dir = Vector2.new(1, 0) },
	{ kind = "arc", len = ARC, center = Vector2.new(L - R, W - R), from = 90 },
	{ kind = "line", len = STRAIGHT_Z, from = Vector2.new(L, W - R), dir = Vector2.new(0, -1) },
	{ kind = "arc", len = ARC, center = Vector2.new(L - R, -(W - R)), from = 0 },
	{ kind = "line", len = STRAIGHT_X, from = Vector2.new(L - R, -W), dir = Vector2.new(-1, 0) },
	{ kind = "arc", len = ARC, center = Vector2.new(-(L - R), -(W - R)), from = -90 },
	{ kind = "line", len = STRAIGHT_Z, from = Vector2.new(-L, -(W - R)), dir = Vector2.new(0, 1) },
	{ kind = "arc", len = ARC, center = Vector2.new(-(L - R), W - R), from = -180 },
}

TrackPath.Segments = SEGMENTS

-- CFrame an der Bogenlaenge s. Die LookVector zeigt in Fahrtrichtung, die
-- RightVector quer nach aussen - Spurversatz also einfach mit
--   TrackPath.At(s) * CFrame.new(spur, 0, 0)
function TrackPath.At(s: number): CFrame
	local remaining = s % TrackPath.LENGTH
	for _, seg in SEGMENTS do
		if remaining < seg.len then
			local pos, dir
			if seg.kind == "line" then
				pos = seg.from + seg.dir * remaining
				dir = seg.dir
			else
				local phi = math.rad(seg.from - (remaining / seg.len) * 90)
				pos = seg.center + Vector2.new(math.cos(phi), math.sin(phi)) * R
				dir = Vector2.new(math.sin(phi), -math.cos(phi))
			end
			local point = Vector3.new(pos.X, Y, pos.Y)
			return CFrame.lookAt(point, point + Vector3.new(dir.X, 0, dir.Y))
		end
		remaining -= seg.len
	end
	-- Rundungsrest am Ende: zurueck auf den Anfang.
	return TrackPath.At(0)
end

-- Grobe Punktliste fuer Bauzwecke: gibt Mittelpunkt und Laenge jedes
-- Bauabschnitts zurueck. Geraden bleiben ein einziges Part, Boegen werden
-- in `arcSteps` Stuecke zerlegt.
function TrackPath.BuildSpans(arcSteps: number?)
	local steps = arcSteps or 14
	local spans = {}
	local cursor = 0
	for _, seg in SEGMENTS do
		if seg.kind == "line" then
			table.insert(spans, { s = cursor + seg.len / 2, len = seg.len, straight = true })
			cursor += seg.len
		else
			local piece = seg.len / steps
			for i = 0, steps - 1 do
				table.insert(spans, {
					s = cursor + piece * (i + 0.5),
					-- Ueberlappung, sonst klaffen zwischen den Bogenstuecken Fugen.
					len = piece + 1.2,
					straight = false,
				})
			end
			cursor += seg.len
		end
	end
	return spans
end

return TrackPath
