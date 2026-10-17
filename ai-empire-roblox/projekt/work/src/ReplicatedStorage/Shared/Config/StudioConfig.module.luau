--!strict
local Config = {}
Config.KINDS = {
	{id="website",name="Business website",cost=650,work=18,stat="coding",desc="A complete company homepage with navigation and contact section."},
	{id="shop",name="Online shop",cost=1200,work=28,stat="coding",desc="A product catalogue with a working preview cart."},
	{id="gamebot",name="Game companion",cost=1600,work=32,stat="reasoning",desc="An assistant for an in-game studio, tested in the robot arena."},
	{id="workflow",name="Office automation",cost=900,work=22,stat="reliability",desc="A support workflow with interactive task completion."},
}
Config.STYLES = {
	{id="paper",name="Paper & forest",bg={242,240,232},ink={36,53,46},accent={61,103,79}},
	{id="slate",name="Studio slate",bg={31,39,43},ink={240,237,225},accent={197,156,98}},
	{id="brick",name="Clay & cream",bg={248,241,229},ink={62,43,36},accent={165,85,59}},
}
Config.BRIEFS = {
	{id="cedar",client="Cedar Coffee",kind="website",minimum=30,reward=3500,headline="Good coffee. A quieter moment.",sub="Small-batch coffee, fresh pastries and a place to slow down.",items={"House blend","Oat flat white","Warm pastries"}},
	{id="northside",client="Northside Studio",kind="website",minimum=48,reward=6500,headline="Make something worth keeping.",sub="Independent design, thoughtful spaces and ideas made tangible.",items={"Brand identities","Digital products","Creative direction"}},
	{id="field",client="Field Supply",kind="shop",minimum=50,reward=8000,headline="Everyday objects. Made well.",sub="Useful things, honest materials and fewer distractions.",items={"Canvas carryall","Desk organiser","Stoneware cup"}},
	{id="orbitgame",client="Orbit Games",kind="gamebot",minimum=62,reward=11000,headline="A better companion for every player.",sub="Guide new players, plan a route and answer the next question.",items={"Navigation","Player support","Quest planning"}},
	{id="ledgerflow",client="Ledger Office",kind="workflow",minimum=55,reward=9000,headline="A calmer working day.",sub="Organise the queue, summarise requests and keep the team moving.",items={"Sort requests","Draft replies","Review results"}},
}
function Config.find(list: any,id: any): any
	if typeof(id)~="string" then return nil end
	for _, def in list do if def.id==id then return def end end
	return nil
end
return Config
