--!nocheck
-- World tests: test doubles injected into the generated source table (paths as in make_manifest).
-- SessionService / Remote record and return what the test sets up; ShopService answers from a table.
return {
	["ServerScriptService/Server/Services/SessionService.module.luau"] = [[
--!strict
-- TEST STUB (world tests)
local Session={}
Session.sessions={} :: {any}
Session.loaded={} :: {any};Session.closing={} :: {any}
function Session.all(): {any} return Session.sessions end
function Session.get(player: any): any for _,s in Session.sessions do if s.player==player then return s end end;return nil end
function Session.onLoaded(fn: any) table.insert(Session.loaded,fn) end
function Session.onClosing(fn: any) table.insert(Session.closing,fn) end
function Session.markDirty(s: any,urgent: boolean?) s.dirty=true;if urgent then s.urgent=true end end
return Session
]],
	["ServerScriptService/Server/Lib/Remote.module.luau"] = [[
--!strict
-- TEST STUB (world tests): records fired events and bound handlers.
local Remote={}
Remote.fired={} :: {any}
Remote.binds={} :: {[string]:any}
Remote.limits={} :: {[string]:any}
function Remote.setup() end
function Remote.setSessionProvider(_fn: any) end
function Remote.fire(player: any,name: string,...: any) table.insert(Remote.fired,{player=player,name=name,args={...}}) end
function Remote.bind(name: string,limits: any,handler: any) Remote.binds[name]=handler;Remote.limits[name]=limits end
return Remote
]],
	["ServerScriptService/Server/Services/ShopService.module.luau"] = [[
--!strict
-- TEST STUB (world tests): owns() answers from Shop.passes[userId][key]; Shop.mode "error" makes it throw,
-- "missing" removes it (like the lead's init-only stub).
local Shop={}
Shop.passes={} :: {[number]:{[string]:boolean}}
Shop.mode="ok"
Shop.calls=0
local function owns(target: any,key: string): boolean
	Shop.calls+=1
	if Shop.mode=="error" then error("shop exploded") end
	local id=if typeof(target)=="table" and target.UserId then target.UserId elseif typeof(target)=="table" and target.userId then target.userId else 0
	local t=Shop.passes[id]
	return t~=nil and t[key]==true
end
Shop.owns=owns
function Shop.setMode(mode: string) Shop.mode=mode;Shop.owns=if mode=="missing" then nil else owns end
function Shop.init() end
return Shop
]],
}
