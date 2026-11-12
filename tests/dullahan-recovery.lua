local json=require('./lib/jsonlua')
local factory=require('./lib/execution-factory')
local root='settings/_namespaces/ambuscade/dullahan/actions/lib/dullahan/'
local function read(name) local f=assert(io.open(root..name));local d=json.parse(f:read('*a'));f:close();return d end
local rule=read('recovery.json').actions[1]
local phase='normal'
local target=99
local hold=false
local chargerAlive=false
local env={vars=read('setup.json').vars,zone_search='LegionA',
    me={name='Steris',index=1,hpp=95,mpp=10,hp=1500,mp=150},
    hasBuff=function() return false end,
    any=function(name,list) for _,v in ipairs(list) do if v==name then return true end end end,
    canUseSpell=function() return true end,hasSpell=function() return true end,canUseAbility=function() return true end,
    partyByMinField=function() return false end,
    encounters={state=function() return {phase=phase} end,evaluate=function() return not hold end}}
require('./tests/helpers/dullahan-party').attach(env)
env.findByName=function(name) if name=='Bozzetto Charger' and not chargerAlive then return end env.find_result={mob={target_index=target}};return env.find_result end
local function matches()
    for _,s in ipairs(rule.when) do local fn=factory.get(s);setfenv(fn,env);if not fn() then return false end end
    return true
end
assert(matches())
env.zone_search='LegionB'; assert(matches()); env.zone_search='LegionA'
env.me.name='Aidelle';assert(matches())
env.zone_search='LegionB'; assert(matches()); env.zone_search='LegionA'
phase='boiling';assert(not matches());phase='normal'
target=1;assert(not matches());target=99
chargerAlive=true;assert(not matches());chargerAlive=false
env.me.mp=10;assert(not matches());env.me.mp=150
env.me.hpp=40;assert(not matches());env.me.hpp=95
env.me.name='Miyajima';assert(not matches())
local cured=false
env.useAbility=function() return false end
env.useSpell=function() cured=true end
local fn=factory.get(rule.commands[1]);setfenv(fn,env);fn();assert(not cured)
env.useAbility=function() return true end;fn();assert(cured)
print('PASS: Convert roles, phase/target/HP/MP guards and self-cure only after successful ability')
-- Low current MP must not veto a Cure that becomes affordable after Convert.
env.me.name='Steris';env.me.mp=25;env.canUseSpell=function()return false end
assert(matches())
env.partyByMinField=function()return {} end;assert(not matches())
print('PASS: post-swap cure affordability and critical-party triage gate')