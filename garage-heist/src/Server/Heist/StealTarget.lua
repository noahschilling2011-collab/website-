--[[
	StealTarget
	Ein Klau-Ziel ist entweder ein Spieler oder eine Leerstand-Garage. Damit
	DismountManager und CarryManager nicht ueberall auf `Player` pruefen
	muessen, laeuft jeder Zugriff auf ein Ziel durch dieses Modul.

		{ kind = "player",   player = <Player> }
		{ kind = "derelict", plotIndex = <number> }
]]

local ProfileOps = require(script.Parent.Parent.Data.ProfileOps)

local StealTarget = {}

function StealTarget.Player(player: Player)
	return { kind = "player", player = player }
end

function StealTarget.Derelict(plotIndex: number)
	return { kind = "derelict", plotIndex = plotIndex }
end

function StealTarget.IsPlayer(target): boolean
	return target ~= nil and target.kind == "player"
end

-- Auf welchem Plot steht das Ziel? nil = Ziel existiert nicht mehr.
function StealTarget.PlotIndex(services, target): number?
	if not target then
		return nil
	end
	if target.kind == "derelict" then
		return target.plotIndex
	end
	if not target.player or not target.player.Parent then
		return nil
	end
	return services.GarageService:GetPlotIndexOf(target.player)
end

function StealTarget.GetPart(services, target, carIndex: number, slotId: string)
	if not target then
		return nil
	end
	if target.kind == "derelict" then
		return services.DerelictService:GetPart(target.plotIndex, carIndex, slotId)
	end
	local data = services.DataService:Get(target.player)
	if not data then
		return nil
	end
	return ProfileOps.GetPart(data, carIndex, slotId)
end

-- Loest das Teil vom Ziel. Beim Spieler bleibt es bis zur Abgabe als
-- "unterwegs" im Profil stehen (siehe GarageService:TakePart).
function StealTarget.TakePart(services, target, thief: Player, carIndex: number, slotId: string)
	if not target then
		return nil
	end
	if target.kind == "derelict" then
		return services.DerelictService:TakePart(target.plotIndex, carIndex, slotId)
	end
	return services.GarageService:TakePart(target.player, thief, carIndex, slotId)
end

-- Meldung ans Opfer. Leerstand liest keine Meldungen.
function StealTarget.NotifyVictim(services, target, text: string, kind: string?)
	if StealTarget.IsPlayer(target) and target.player.Parent then
		services.EconomyService:Notify(target.player, text, kind or "bad")
	end
end

return StealTarget
