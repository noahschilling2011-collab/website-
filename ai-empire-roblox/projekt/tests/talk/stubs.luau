--!nocheck
-- Talk tests: test doubles injected into the generated source table (paths as in make_manifest).
-- SessionService / PlotService / Remote only record and return what the test sets up.
return {
	["ServerScriptService/Server/Services/SessionService.module.luau"] = [[
--!strict
-- TEST STUB (talk tests)
local Session={}
Session.sessions={} :: {any}
Session.loaded={} :: {any};Session.closing={} :: {any}
function Session.all(): {any} return Session.sessions end
function Session.get(player: any): any for _,s in Session.sessions do if s.player==player then return s end end;return nil end
function Session.onLoaded(fn: any) table.insert(Session.loaded,fn) end
function Session.onClosing(fn: any) table.insert(Session.closing,fn) end
function Session.markDirty(s: any,_urgent: boolean?) s.dirty=true end
return Session
]],
	["ServerScriptService/Server/Services/PlotService.module.luau"] = [[
--!strict
-- TEST STUB (talk tests)
local Plot={}
Plot.plots={} :: {any}
function Plot.all(): {any} return Plot.plots end
function Plot.get(player: any): any for _,p in Plot.plots do if p.owner==player then return p end end;return nil end
function Plot.refresh(_s: any) end
function Plot.onChanged(_fn: any) end
return Plot
]],
	["ServerScriptService/Server/Lib/Remote.module.luau"] = [[
--!strict
-- TEST STUB (talk tests): records fired events and bound handlers.
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
}
