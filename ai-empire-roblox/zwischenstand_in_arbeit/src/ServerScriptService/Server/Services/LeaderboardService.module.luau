--!strict
-- Cached cross-server rankings. All DataStore calls run outside the simulation heartbeat.
local DataStoreService=game:GetService("DataStoreService")
local RunService=game:GetService("RunService")
local Session=require(script.Parent.SessionService)
local Save=require(script.Parent.SaveService)
local Board={boards={} :: {[string]:any},status="Server preview"}
local modes={"overall","coding","math","reasoning","creativity","arena"}
local stores={} :: {[string]:any}
local profiles:any=nil
local busy=false
local elapsed=170
local sent: {[number]:any}={}
local function values(s: any): any
	local result={overall=s.data.stats.bestOverall,arena=s.data.empire.arenaBest,coding=0,math=0,reasoning=0,creativity=0}
	for _, model in s.data.models do
		if model.trainedAt and model.status~="training" then
			for _,mode in {"coding","math","reasoning","creativity"} do result[mode]=math.max(result[mode],model.stats[mode] or 0) end
		end
	end
	return result
end
local function fallback()
	for _,mode in modes do
		local list={}
		for _,s in Session.all() do
			if not s.closed and s.data.company then table.insert(list,{name=s.data.company.name,userId=s.userId,score=values(s)[mode]}) end
		end
		table.sort(list,function(a,b) if a.score==b.score then return a.userId<b.userId end;return a.score>b.score end)
		while #list>10 do table.remove(list) end
		Board.boards[mode]=list
	end
end
function Board.init()
	if RunService:IsStudio() or not Save.enabled then return end
	local ok=pcall(function()
		profiles=DataStoreService:GetDataStore("AIEmpire_BoardProfiles_v1")
		for _,mode in modes do stores[mode]=DataStoreService:GetOrderedDataStore("AIEmpire_Best_"..mode.."_v1") end
	end)
	if ok then Board.status="Global leaderboard" else stores={};Board.status="Server preview · rankings offline" end
end
local function refresh()
	local ok=pcall(function()
		for _,s in Session.all() do
			if not s.closed and s.data.company then
				local scores=values(s);local previous=sent[s.userId] or {};local changed=false
				for _,mode in modes do
					local value=math.min(9007199254740991,math.floor(scores[mode]*10))
					if value>0 and value>(previous[mode] or 0) then
						stores[mode]:UpdateAsync(tostring(s.userId),function(old) return math.max(tonumber(old) or 0,value) end)
						previous[mode]=value;changed=true
					end
				end
				if changed then profiles:SetAsync(tostring(s.userId),{name=s.data.company.name});sent[s.userId]=previous end
			end
		end
		local newBoards={}
		local profileCache={}
		for _,mode in modes do
			local page=stores[mode]:GetSortedAsync(false,10);local list={}
			for _,row in page:GetCurrentPage() do
				local profile=profileCache[row.key]
				if not profile then local readOk,value=pcall(function() return profiles:GetAsync(row.key) end);profile=if readOk and typeof(value)=="table" then value else {name="Company "..row.key};profileCache[row.key]=profile end
				table.insert(list,{userId=tonumber(row.key) or 0,name=profile.name,score=row.value/10})
			end
			newBoards[mode]=list
		end
		Board.boards=newBoards;Board.status="Global leaderboard"
	end)
	if not ok then fallback();Board.status="Global rankings unavailable · server preview" end
	busy=false
end
function Board.tick(dt: number)
	elapsed+=dt
	if next(stores)==nil then fallback()
	elseif elapsed>=180 and not busy then elapsed=0;busy=true;task.spawn(refresh) end
	for _,s in Session.all() do s.live.rankings={status=Board.status,boards=Board.boards} end
end
return Board
