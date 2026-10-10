--!nocheck
-- World tests: fake players (table doubles with attributes, CharacterAdded and a recording
-- RequestStreamAroundAsync), characters (Model + HumanoidRootPart + Humanoid) and sessions.
return function(M, G)
	local Instance, Vector3, CFrame = G.Instance, G.Vector3, G.CFrame
	local Template = M.require(M.game.ServerScriptService.Server.Lib.Template)
	local F = {}
	function F.character(name, cf)
		local c = Instance.new("Model"); c.Name = name
		local r = Instance.new("Part"); r.Name = "HumanoidRootPart"; r.Size = Vector3.new(2, 2, 1); r.Anchored = false; r.CFrame = cf; r.Parent = c
		local h = Instance.new("Humanoid"); h.Parent = c
		c.PrimaryPart = r
		c.Parent = M.game.Workspace
		return c, r, h
	end
	function F.player(id, name, cf)
		local attrs = {}
		local p = { UserId = id, Name = name, DisplayName = name, Parent = M.game.Players, streamed = {}, attrWrites = 0, streamHook = nil }
		p.CharacterAdded = M.newSignal("CharacterAdded")
		function p:SetAttribute(k, v) attrs[k] = v; self.attrWrites += 1 end
		function p:GetAttribute(k) return attrs[k] end
		function p:RequestStreamAroundAsync(pos, timeout)
			table.insert(self.streamed, { pos = pos, timeout = timeout })
			if self.streamHook then self.streamHook(self) end
			G.task.wait(0.5) -- streaming takes a moment (yields like the real API)
		end
		local c, r, h = F.character(name, cf)
		p.Character = c; p.root = r; p.humanoid = h
		return p
	end
	function F.respawn(p, cf)
		if p.Character then p.Character:Destroy() end
		local c, r, h = F.character(p.Name, cf)
		p.Character = c; p.root = r; p.humanoid = h
		M.fire(p.CharacterAdded, c)
		return c
	end
	function F.session(p, money)
		local data = Template.new()
		data.company = { name = "Nimbus Labs", logo = "N", color = "cyan", spec = "general", reputation = 10, foundedAt = 0 }
		data.money = money or 0
		return { userId = p.UserId, player = p, data = data, live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} }, closed = false }
	end
	return F
end
