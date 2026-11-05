local file=assert(io.open('lib/action-context.lua')); local source=file:read('*a'); file:close()
local body=assert(source:match('(context.abyssea = {}.-)    context.usableWeaponSkills ='))
local Weakness=require('./lib/abyssea-weakness')
local Red=require('./lib/abyssea-red')
Weakness.clear()
local target={id=200,index=2,hpp=90,spawn_type=16,status=1,name='NM'}
local plan={enabled=true,all_ws={'Cyclone','Energy Drain'}}
local context={bt=target,vars=setmetatable({},{__index=function() error('helper must not read action variables') end}),
    player={main_job_id=1,main_job_level=99},log=function() end}
local validation,attempt
local zone=218
local main={id=1,bagId=0,localId=1,item={skill=2}}
local available=true
context.usableWeaponSkills=function(names) return available and names or {} end
context.canUseWeaponSkill=function() return true end
context.useWeaponSkill=function(name,validate,requireLanded,targetId)
    assert(requireLanded,'proc attempts must require a confirmed intended-target hit')
    assert(targetId==200,'proc request must explicitly target its battle target, independent of cursor')
    attempt=name; validation=validate; return true
end
local env=setmetatable({writeDebug=function() end,context=context,
    variableValues=require('./lib/variable-values'),
    findWeaponSkill=function() return {skill=2} end,
    inventory={find_equipment_in_slot=function() return main end},
    windower={ffxi={get_info=function() return {zone=zone} end,
        get_mob_by_target=function() return nil end,get_mob_by_id=function() return target end}}},{__index=_G})
local chunk=assert(loadstring(body)); setfenv(chunk,env); chunk()
local expressions=assert(source:match('(context.execute = function%(code, %.%.%.%).-)    %-%- "Static" context properties'))
local expressionChunk=assert(loadstring(expressions))
setfenv(expressionChunk,setmetatable({context=context,executionFactory=dofile('lib/execution-factory.lua')},{__index=_G}))
expressionChunk()
context.abyssea.runRedProc(plan)
assert(attempt=='Cyclone' and validation())
context.search_enabled=true
plan.is_active='search_enabled'
assert(validation())
context.search_enabled=false;assert(not validation(),'expression must be re-evaluated at dispatch')
attempt=nil;context.abyssea.runRedProc(plan);assert(not attempt,'false expression must prevent search')
context.search_enabled=true
context.checked=0
context.check=function() context.checked=context.checked+1;return true end
plan.is_active={'search_enabled','check()'}
assert(validation() and context.checked==1)
context.search_enabled=false
assert(not validation() and context.checked==1,'AND arrays must short-circuit')
plan.is_active={};assert(not validation(),'empty arrays follow evaluateAll semantics')
assert(not pcall(context.abyssea.runRedProc,{is_active={'true',false}}))
assert(not pcall(context.abyssea.runRedProc,{is_active={named='true'}}))
assert(not pcall(context.abyssea.runRedProc,{is_active='invalid +'}))
context.search_enabled=true
local active=true
plan.is_active=function() return active end
active=false;assert(not validation(),'mode change must invalidate an already queued WS')
active=true;assert(validation())
main={id=2,bagId=0,localId=2,item={skill=2}}
assert(not validation(),'same weapon type with a higher damage weapon must cancel the queued low-weapon WS')
main={id=1,bagId=0,localId=3,item={skill=2}}
assert(not validation(),'different copy of the same item must invalidate the queued WS')
main={id=1,bagId=0,localId=1,item={skill=2}}
available=false
assert(not validation(),'live ability availability must be rechecked at dispatch')
available=true
Weakness.update(218,target,'darkness',false)
assert(not validation(),'hint must invalidate an unrelated queued WS')
context.abyssea.runRedProc(plan)
assert(attempt=='Energy Drain' and validation())
Weakness.update(218,target,nil,true,'Ally')
assert(not validation(),'red confirmation must invalidate queued proc WS')
local copy=context.abyssea.getWeaknesses(); copy.red.triggered=false
assert(Weakness.get(218,target).red.triggered,'public observations must be copies')
plan.on_stagger='full_rotation'
assert(validation(),'explicit full rotation policy keeps requests eligible')
target={id=201,index=3,hpp=100}
assert(not validation(),'queued request must retain its original target')
local json=require('./lib/jsonlua')
file=assert(io.open('actions/lib/abyssea/red-proc.json')); local config=json.parse(file:read('*a'));file:close()
assert(#config.actions==3 and config.actions[3].commands[3]:find('abyssea.runRedProc({',1,true))
assert(context.runRedProc==nil and context.abysseaWeakness==nil,'Abyssea methods belong only to their object')
assert(context.abyssea.weaknesses.red.triggered,'namespaced view reads live observations')
context.abyssea.weaknesses.red.triggered=false
assert(context.abyssea.weaknesses.red.triggered,'namespaced view must not expose mutable state')
zone=1; local previousValidation=validation
context.abyssea.runRedProc(plan)
assert(validation==previousValidation and not context.abyssea.getWeaknesses())
target=context.bt.mob or context.bt
attempt=nil
local outside={all_ws={'Cyclone'}}
context.abyssea.runRedProc(outside);assert(not attempt,'red stays restricted by default')
outside.allow_outside_abyssea=true
context.abyssea.runRedProc(outside);assert(attempt=='Cyclone' and validation(),'red can opt into outside cycling')
assert(not pcall(context.abyssea.runRedProc,{allow_outside_abyssea='true'}))
assert(config.vars['^abyssea'].red_proc.on_stagger=='stop')
assert(not pcall(context.abyssea.runRedProc),'configuration is required, even outside Abyssea')
assert(not pcall(context.abyssea.runRedProc,{weapons='invalid'}))
assert(not pcall(context.abyssea.runRedProc,{on_stagger='invalid'}))
-- Resolve the shipped action's legacy settings outside core Lua, preserving
-- preferred per-proc sets and the shared fallback when a set is absent/empty.
local shared={{main={name='Shared weapon'}}}
local preferred={{main={name='Preferred weapon'}}}
local received
local actionVars={abyssea={weapon_set_name='weapons.LOW',['weapons.LOW']=shared,
    ws_allow_list={NM=true},red_proc={_allowed=true,['weapons.LOW']=preferred}}}
local actionEnv={vars=actionVars,abyssea={runRedProc=function(value) received=value end},
    arrayLength=function(value) return type(value)=='table' and #value or 0 end,
    setVar=function(path,value) actionVars.abyssea.red_proc[path:match('%.([^%.]+)$')]=value end}
local function runShipped()
    for _,command in ipairs(config.actions[3].commands) do
        local fn=assert(loadstring(command));setfenv(fn,actionEnv);fn()
    end
end
runShipped()
assert(received.weapons==preferred and received.state==actionVars.abyssea.red_proc)
assert(received.enabled and received.ws_allow_list==actionVars.abyssea.ws_allow_list)
actionVars.abyssea.red_proc['weapons.LOW']={};runShipped()
assert(received.weapons==shared)
actionVars.abyssea.red_proc['weapons.LOW']=nil;runShipped()
assert(received.weapons==shared)
print('PASS: context integration, candidate/target dispatch guards, observation copies and shipped action config')
