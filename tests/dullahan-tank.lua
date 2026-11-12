local json=require('./lib/jsonlua')
local factory=require('./lib/execution-factory')
local root='settings/_namespaces/ambuscade/dullahan/actions/lib/dullahan/'
local function read(name) local f=assert(io.open(root..name));local d=json.parse(f:read('*a'));f:close();return d end
local rules=read('tank.json').actions
local horse={name='Bozzetto Charger',target_index=2,distance=5}
local boss={name='Bozzetto Retributionist',target_index=1,distance=5}
local target
local env={vars=read('setup.json').vars,me={name='Carbonite',index=1},
    canUseSpell=function() return true end,canUseAbility=function() return true end}
require('./tests/helpers/dullahan-party').attach(env)
env.findMobWhere=function(names,predicate,range)
    local candidates=type(names)=='table' and {horse,boss} or (names==horse.name and {horse} or {boss})
    for _,mob in ipairs(candidates) do
        local fn=factory.get(predicate); setfenv(fn,setmetatable({mob=mob},{__index=env}))
        if mob.alive~=false and mob.distance<=range and fn() then env.mob=mob;return mob end
    end
end
env.useSpell=function(mob) target=mob end
env.useAbility=env.useSpell
local function run(rule)
    for _,condition in ipairs(rule.when) do
        local fn=factory.get(condition);setfenv(fn,env);if not fn() then return false end
    end
    for _,command in ipairs(rule.commands) do local fn=factory.get(command);setfenv(fn,env);fn() end
    return true
end
assert(run(rules[1]) and target==horse)
horse.target_index=1;boss.target_index=2
assert(not run(rules[1])) -- Flash stays reserved even when only the boss loses hate.
assert(run(rules[2]) and target==boss)
assert(run(rules[5]) and target==horse)
assert(run(rules[6]) and target==boss)
horse.distance=30
assert(not run(rules[5])) -- Living but out of Flash range is not a fallback.
horse.alive=false
assert(run(rules[1]) and target==boss)
assert(run(rules[5]) and target==boss)
assert(run(rules[6]) and target==boss)
boss.target_index=nil;assert(not run(rules[2]))
env.me.name='Ladrian';assert(not run(rules[1]))
print('PASS: Flash reserved for living Charger, Provoke assigned to boss, range safety and post-Charger fallback')