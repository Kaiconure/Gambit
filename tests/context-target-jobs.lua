local f=assert(io.open('lib/action-context.lua')); local source=f:read('*a'); f:close()
local prefix=assert(source:match('local function initContextTargetSymbol%(context, symbol, debug%)(.-)    %-%- Set the shared properties'))
local chunk=assert(loadstring('return function(context,symbol) '..prefix..' end'))
local record={main_job='WAR',main_job_level=99,sub_job='SAM',sub_job_level=59}
setfenv(chunk,{globals={ipc_job_info={Member=record}},
    isMobPlayer=function(mob) return mob.player end,applyMobOverrides=function() end,
    actionStateManager={getBuffsForMob=function() return {} end,getMemberBuffsFor=function() return {} end},
    SPAWN_TYPE_MOB=16,SPAWN_TYPE_TRUST=14})
local init=chunk()
local context={player={id=1}}
local panel={}; require('./lib/ux/panel-context').attach(panel)
for _,member in ipairs({false,true}) do
    local symbol={mob={id=2,name='Member',player=true},member=member and {name='Member'} or nil}
    init(context,symbol)
    assert(panel.job_string(symbol)=='WAR99/SAM59')
end
local unknown={mob={id=3,name='Unknown',player=true}}
init(context,unknown); assert(panel.job_string(unknown)==nil)
local monster={mob={id=4,name='Member',player=false}}
init(context,monster); assert(panel.job_string(monster)==nil)
print('PASS: cached jobs reach cursor and party symbols; unknown players and monsters remain unchanged')