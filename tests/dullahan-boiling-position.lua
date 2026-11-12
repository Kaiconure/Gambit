local json=require('./lib/jsonlua')
local factory=require('./lib/execution-factory')
local f=assert(io.open('settings/_namespaces/ambuscade/dullahan/actions/lib/dullahan/combat.json'))
local actions=json.parse(f:read('*a')).actions;f:close()
local dia
for _,action in ipairs(actions)do
 if action.comment and action.comment:find('The bard feeds minimal TP',1,true)then dia=action end
 assert(not (action.comment and action.comment:find('During Boiling, put the bard',1,true)))
end
assert(dia)
local phase='boiling'
local env={vars={dullahan={enabled=true,bard={'BRD'}}},me={name='Bard'},mob={distance=1},
 partyNames=function()return {'Bard'}end,canUseSpell=function()return true end,
 encounters={state=function()return {phase=phase}end}}
env.findMobWhere=function(_,_,limit)return env.mob.distance<=limit end
local function matches()
 for _,code in ipairs(dia.when)do local fn=factory.get(code);setfenv(fn,env);if not fn()then return false end end
 return true
end
for _,distance in ipairs({1,5,10,14.99,15,19.5,20})do env.mob.distance=distance;assert(matches())end
env.mob.distance=21;assert(not matches());env.mob.distance=10
for _,value in ipairs({'charging','miasma','resolving','normal','unknown'})do phase=value;assert(not matches())end
print('PASS: Boiling Dia has no minimum range or forced positioning, retains casting-range and phase guards')