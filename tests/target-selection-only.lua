local f=assert(io.open('lib/target-processing.lua'));local source=f:read('*a');f:close()
local body=assert(source:match('function processTargeting%(player, party%)(.-)    if not shouldAquireNewTarget'))
local calls={}
local mob={id=10,index=2,hpp=100,valid_target=true,spawn_type=16}
local env={actionStateManager={},SPAWN_TYPE_MOB=16,
 windower={ffxi={get_mob_by_id=function()return mob end},send_command=function()calls.attack=true end},
 smartMove={cancelJob=function()calls.cancel=true end},coroutine={sleep=function()calls.sleep=true end},
 resetCurrentMob=function(value)calls.selected=value end,setTargetMob=function(value)calls.legacy=value end}
local make=assert(loadstring('return function(player,party)'..body..' end'));setfenv(make,env);local run=make()
env.actionStateManager.user_target_id=10;env.actionStateManager.user_target_engage=false
run({},{});assert(calls.selected==mob and not calls.attack and not calls.legacy and not calls.sleep and not calls.cancel)
assert(env.actionStateManager.user_target_id==nil and env.actionStateManager.user_target_engage==nil)
calls={};env.actionStateManager.user_target_id=10;run({},{})
assert(calls.attack and calls.legacy==mob and calls.sleep)
local f=assert(io.open('lib/action-context.lua'));source=f:read('*a');f:close()
local setter=assert(source:match('context.setBattleTarget = function%(mob, engage%)(.-)\n    end'))
local make=assert(loadstring('return function(mob,engage)'..setter..' end'));setfenv(make,setmetatable(env,{__index=_G}));local set=make()
assert(set(mob,false) and env.actionStateManager.user_target_engage==false)
assert(set(mob) and env.actionStateManager.user_target_engage==true)
assert(not pcall(set,mob,'bad'))
print('PASS: explicit selection-only targeting emits no engage/cursor path; legacy callers retain behavior')
local json=require('./lib/jsonlua')
local factory=require('./lib/execution-factory')
local f=assert(io.open('settings/_namespaces/ambuscade/dullahan/actions/lib/dullahan/targeting.json'))
local rule=json.parse(f:read('*a')).actions[1];f:close()
local horse={id=20,name='Bozzetto Charger',alive=true,engaged=false}
local boss={id=30,name='Bozzetto Retributionist',alive=true,engaged=false}
local selected,selectionMode,disengaged
local ctx={vars={dullahan={enabled=true,positioning={zones={'LegionA','LegionB'}}}},zone_search='LegionA',me={is_engaged=true}}
ctx.any=function(value,list)for _,v in ipairs(list)do if v==value then return true end end end
ctx.findMobWhere=function(names,_,_,aggro)
 for _,m in ipairs({horse,boss})do
  if m.alive and (not aggro or m.engaged) and (type(names)=='table' or names==m.name)then ctx.mob=m;return m end
 end
end
ctx.disengage=function()disengaged=true end
ctx.getMobByTarget=function()return boss end
ctx.logf=function()return true end
ctx.setBattleTarget=function(m,mode)selected=m;selectionMode=mode end
local function run()
 for _,code in ipairs(rule.when)do local f=factory.get(code);setfenv(f,ctx);if not f()then return false end end
 for _,code in ipairs(rule.commands)do local f=factory.get(code);setfenv(f,ctx);f()end
 return true
end
assert(not run() and not selected)
boss.engaged=true;assert(run() and selected==horse and selectionMode==false and disengaged)
ctx.bt=horse;assert(not run())
horse.alive=false;assert(run() and selected==boss)
-- The action context may name a different enemy from the actual battle target.
-- Updating tracking alone must not disengage somebody already on the right enemy.
horse.alive=true;ctx.bt=boss;disengaged=false
ctx.getMobByTarget=function()return horse end
assert(run() and selected==horse and not disengaged)
ctx.zone_search='Elsewhere';assert(not run())
print('PASS: manual encounter target priority, no opening pull, no repeated reselection and post-Charger transition')
