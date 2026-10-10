--!strict
local Config=require(script.Parent.Config.StudioConfig)
local Math={}
function Math.quality(stats: any,kind: any): number
	local ability=(stats[kind.stat] or 0)*0.55+(stats.creativity or 0)*0.2+(stats.reliability or 0)*0.25
	return math.round(100*(1-math.exp(-ability/65))*10)/10
end
function Math.rate(gpus: any,empire: any): number
	local ModelMath=require(script.Parent.ModelMath)
	local Hardware=require(script.Parent.Config.HardwareConfig)
	return ModelMath.fleet(gpus).throughput*Hardware.thermal(empire,ModelMath.fleet(gpus).throughput)*0.35
end
function Math.content(title: string,kind: string,briefId: string?): any
	local brief=Config.find(Config.BRIEFS,briefId)
	if brief then return {headline=brief.headline,sub=brief.sub,items=table.clone(brief.items)} end
	if kind=="shop" then return {headline=title..". Made for everyday.",sub="A small collection of useful objects, chosen with care.",items={"Everyday essentials","The studio collection","New arrivals"}} end
	if kind=="gamebot" then return {headline="Meet your next game companion.",sub="Help players explore, learn and find their next adventure.",items={"Find a route","Explain a quest","Help a teammate"}} end
	if kind=="workflow" then return {headline="Make room for better work.",sub="A clear queue, organised tasks and a calmer team.",items={"Review inbox","Prepare reply","Complete task"}} end
	return {headline=title..". Built with purpose.",sub="A clear idea, carefully made. Discover our work and get in touch.",items={"Our approach","Selected work","Meet the team"}}
end
return Math
