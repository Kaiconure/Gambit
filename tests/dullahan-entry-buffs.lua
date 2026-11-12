local json=require('./lib/jsonlua')
local factory=require('./lib/execution-factory')
local selectors=require('./lib/target-selectors')
local root='settings/_namespaces/ambuscade/dullahan/actions/'
local function read(path)local f=assert(io.open(root..path));local d=json.parse(f:read('*a'));f:close();return d end
local vars=read('lib/dullahan/setup.json').vars
local env={vars=vars,me={main_job='WHM'}}
local grouped=true
local protect=false
local shell=false
local ready=true
env.evaluateAllConditions=function()return ready end
env.partyCount=function(expression)
 if not expression then return 6 end
 if expression:find('distance',1,true)then return grouped and 6 or 5 end
 if expression:find('Protect',1,true)then return protect and 0 or 6 end
 if expression:find('Shell',1,true)then return shell and 0 or 6 end
 return 6
end
env.canUseSpell=function()return true end
local function matches(rule)
 for _,s in ipairs(rule.when)do local f=factory.get(s);setfenv(f,env);if not f()then return false end end
 return true
end
local rules=read('lib/dullahan/entry-buffs.json').actions
assert(matches(rules[1]) and matches(rules[2]))
grouped=false;assert(not matches(rules[1]) and not matches(rules[2]));grouped=true
protect=true;assert(not matches(rules[1]) and matches(rules[2]))
shell=true;assert(not matches(rules[2]))
ready=false;assert(not matches(rules[1]))
local context={}
for i,job in ipairs({'PLD','WAR','COR','WHM','BRD','GEO'})do context['p'..(i-1)]={name=job,main_job=job,id=i}end
context.me=context.p3
assert(table.concat(selectors.orderedNames(context,vars.haste_cycle.targets),',')=='PLD,COR,WAR')
assert(table.concat(selectors.orderedNames(context,vars.dullahan.buff_targets),',')=='PLD')
context.me=context.p5
assert(table.concat(selectors.orderedNames(context,vars.dullahan.refresh_targets),',')=='GEO,PLD')
assert(#selectors.orderedNames(context,{'PLD','*'})==6)
assert(#selectors.orderedNames(context,{'^mages'})==2) -- Other mages, not non-mages.
assert(read('(all).json').idle[2].import=='dullahan/entry-buffs')
print('PASS: grouped entry AoEs, readiness/completion gates, tank-only upkeep and semantic Haste/Refresh/wildcard selectors')