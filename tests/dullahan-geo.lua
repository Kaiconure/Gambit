local json=require('./lib/jsonlua')
local factory=require('./lib/execution-factory')
local root='settings/_namespaces/ambuscade/dullahan/actions/lib/dullahan/'
local function read(name)local f=assert(io.open(root..name));local d=json.parse(f:read('*a'));f:close();return d end
local rules=read('geo.json').actions
local entrust=false
local allowed=true
local target
local spell
local env={vars=read('setup.json').vars,me={main_job='GEO',name='Aidelle'},zone_search='LegionA',bt={is_engaged=true},
    encounters={state=function()return {phase='normal'}end,evaluate=function()return allowed end},
    hasBuff=function(name)return name=='Entrust' and entrust end,
    any=function(name,list)for _,x in ipairs(list)do if x==name then return true end end end,
    canUseAbility=function()return true end,
    canUseSpell=function(name)spell=name;return true end}
env.partyByName=function(name)env.member={name=name=='WAR' and 'Ladrian' or name,distance=15};return env.member end
env.useAbility=function()entrust=true;return true end
env.syncBuffs=function()return true end
env.useSpell=function(who)target=who;return true end
env.setVar=function()env.vars.dullahan.geo.self_applied=true end
local function run(rule)
 for _,code in ipairs(rule.when)do local f=factory.get(code);setfenv(f,env);if not f()then return false end end
 for _,code in ipairs(rule.commands)do local f=factory.get(code);setfenv(f,env);f()end
 return true
end
assert(run(rules[1]) and spell=='Indi-Refresh' and target==env.me)
assert(run(rules[2]) and spell=='Indi-Fury' and target.name=='Ladrian')
assert(not run(rules[1])) -- Never consume pending Entrust on the self bubble.
entrust=false;allowed=false;assert(not run(rules[2]))
print('PASS: GEO maintains self Refresh, Entrusts melee Fury, preserves pending Entrust and respects damage windows')