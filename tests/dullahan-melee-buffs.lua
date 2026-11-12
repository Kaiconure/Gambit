local json=require('./lib/jsonlua')
local factory=require('./lib/execution-factory')
local root='settings/_namespaces/ambuscade/dullahan/actions/lib/dullahan/'
local function read(path)local f=assert(io.open(root..path));local d=json.parse(f:read('*a'));f:close();return d end
local phase,ready,buffed='normal',true,false
local used,ws
local env={vars={dullahan={enabled=true,tank={'PLD'},positioning={zones={'LegionA'},melee_targets={'melee_dps'}}}},
 me={name='Warrior',tp=2000},bt={},zone_search='LegionA',weapon_skill='Upheaval',
 any=function()return true end,partyMatches=function()return true end,partyNames=function()return {'Tank'}end,
 findByName=function()return true end,hasBuff=function()return buffed end,
 canUseAbility=function()return ready end,
 encounters={state=function()return {phase=phase}end,evaluate=function()return phase=='normal' or phase=='miasma'end},
 useAbility=function(_,name)used=name;return true end,
 useWeaponSkill=function(_,validate)ws=validate();return ws end}
local state=env.encounters.state
env.encounters.state=function(...)env.encounter_state=state(...);return env.encounter_state end
local function execute(code)local fn=factory.get(code);setfenv(fn,env);return fn()end
local rule=read('melee-buffs.json').actions[1]
local function matches()for _,code in ipairs(rule.when)do if not execute(code)then return false end end;return true end
assert(matches());execute(rule.commands[1]);assert(used=='Hasso')
buffed=true;assert(not matches());buffed=false;ready=false;assert(not matches());ready=true
for _,value in ipairs({'miasma','boiling','resolving','unknown'})do phase=value;assert(not matches())end
phase='charging';assert(matches())
for _,path in ipairs({'combat.json','miasma-burst.json'})do
 local commands
 for _,action in ipairs(read(path).actions)do
  if action.commands and action.commands[1]:find("canUseAbility('Sekkanoki')",1,true)then commands=action.commands;break end
 end
 assert(commands)
 phase='normal';used=nil;execute(commands[1]);assert(used=='Sekkanoki')
 env.me.tp=1000;used=nil;execute(commands[1]);assert(not used);env.me.tp=2000
 ready=false;execute(commands[1]);assert(not used);ready=true
 buffed=true;execute(commands[1]);assert(not used);buffed=false
 phase='boiling';execute(commands[1]);assert(not used)
 -- If phase changes while Sekkanoki is used, final WS validation still rejects damage.
 phase='miasma';env.useAbility=function()phase='boiling';return true end
 execute(commands[1]);execute(commands[2]);assert(ws==false)
 env.useAbility=function(_,name)used=name;return true end
end
print('PASS: Hasso readiness/buff/phase guards; Sekkanoki checks in both WS paths and final phase revalidation')
