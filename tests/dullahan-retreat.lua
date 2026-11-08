local json=require('./lib/jsonlua')
local factory=require('./lib/execution-factory')
local tracker=require('./lib/encounter-state')
local root='settings/_namespaces/ambuscade/dullahan/actions/'
local function read(path)local f=assert(io.open(root..path));local d=json.parse(f:read('*a'));f:close();return d end
local vars=read('lib/dullahan/setup.json').vars
tracker.configure('retreat',vars.dullahan.tracker,{retreat=true,tank=vars.dullahan.tank})
local boss={id=10,index=1,name='Bozzetto Retributionist',hpp=100}
local moved,waited,disengaged
local env={vars=vars,zone_search='LegionA',me={name='Ladrian',is_engaged=true},
 any=function(v,values)for _,x in ipairs(values)do if x==v then return true end end end,
 findByName=function()return boss end,
 encounters={state=function(_,mob)return tracker.get('retreat',mob)end},
 cancelFollow=function()end,isResting=function()return false end,
 disengage=function()disengaged=true end,hasBuff=function()return false end,
 distanceTo=function()return 30 end,move=function(x,y)moved={x=x,y=y}end,
 wait=function()waited=true end}
env.setVar=function(path,value)if path=='vars.dullahan.return_to_camp'then vars.dullahan.return_to_camp=value end;return true end
env.movementAvailable=function()return true end
env.findByName=function()env.find_result=boss;return boss end
require('./tests/helpers/dullahan-party').attach(env)
local rule=read('lib/dullahan/retreat.json').actions[1]
local function execute(code)local fn=factory.get(code);setfenv(fn,env);return fn()end
local function matches()for _,code in ipairs(rule.when)do if not execute(code)then return false end end;return true end
assert(not matches())
tracker.text('The boss begins to emit a noxious miasma.',boss)
for _,name in ipairs({'Miyajima','Steris','Aidelle'})do
 env.me.name=name;assert(matches())
 for _,code in ipairs(rule.commands)do execute(code)end
 assert(moved.x==160 and moved.y==-160 and waited and disengaged)
 assert(not tracker.evaluate('retreat','can_ws',boss,env))
end
env.me.name='Carbonite';assert(not matches()) -- Keep boss away from the retreat camp.
env.me.name='Ladrian';assert(not matches()) -- DDs now burst immediately rather than retreating on Miasma.
env.me.name='Steris';moved=nil;waited=false;env.distanceTo=function()return 0 end
assert(matches());for _,code in ipairs(rule.commands)do execute(code)end
assert(not moved and waited) -- Arrival still blocks routine camp/attack actions.
tracker.enemy({actor=boss,kind='enemy_ability',phase='pre',resource={en='Eisenschneider'}})
env.me.name='Ladrian'
assert(matches())
tracker.enemy({actor=boss,kind='enemy_ability',phase='post',outcome='completed',resource={en='Eisenschneider'}})
assert(not matches())
tracker.text('The boss begins to emit a noxious miasma.',boss)
tracker.text("The boss's miasma dissipates but its rage is beginning to boil over.",boss)
assert(not matches())
tracker.text('The boss begins to emit a noxious miasma.',boss)
env.me.name='Steris'
env.zone_search='Other';assert(not matches());env.zone_search='LegionB';assert(matches())
vars.dullahan.retreat.enabled=false;assert(not matches())
assert(read('lib/dullahan/combat.json').actions[1].import=='dullahan/retreat')
assert(read('(all).json').idle[1].import=='dullahan/retreat')
print('PASS: mages retreat on Miasma, DDs burst then retreat on Eisenschneider; tank, resolution, zone and toggle guards')
local rules=read('lib/dullahan/retreat.json').actions
rule=rules[2];env.me.name='Carbonite'
local resting=false
env.isResting=function()return resting end
env.rest=function()resting=true end
env.cancelRest=function()resting=false end
env.setVar=function(path,value)
 if path=='vars.dullahan.tank_rest_active'then vars.dullahan.tank_rest_active=value end
 return true
end
assert(not matches()) -- Miasma alone does not trigger knee-taking.
tracker.enemy({actor=boss,kind='enemy_ability',phase='pre',resource={en='Eisenschneider'}})
assert(matches());for _,code in ipairs(rule.commands)do execute(code)end
assert(resting and vars.dullahan.tank_rest_active)
assert(matches()) -- Remains the highest-priority tank action while resolving.
env.me.name='Ladrian';assert(not matches());env.me.name='Carbonite'
rule=rules[3];assert(not matches())
tracker.enemy({actor=boss,kind='enemy_ability',phase='post',outcome='completed',resource={en='Eisenschneider'}})
assert(matches());for _,code in ipairs(rule.commands)do execute(code)end
assert(not resting and not vars.dullahan.tank_rest_active)
assert(not matches()) -- Do not undo manually initiated rest afterward.
rule=rules[2]
tracker.enemy({actor=boss,kind='enemy_ability',phase='pre',resource={en='Eisenschneider'}})
vars.dullahan.tank_ko_rest=false;assert(not matches());vars.dullahan.tank_ko_rest=true
assert(matches());for _,code in ipairs(rule.commands)do execute(code)end
tracker.enemy({actor=boss,kind='enemy_ability',phase='post',outcome='interrupted',resource={en='Eisenschneider'}})
rule=rules[3];assert(matches());for _,code in ipairs(rule.commands)do execute(code)end
assert(not resting and not vars.dullahan.tank_rest_active)
print('PASS: tank rests only for Eisenschneider readying, blocks routine actions, stands after completion/interruption, respects toggle and rest ownership')
-- Return must work even though retreat scattered the party outside buff range.
rule=rules[4];env.me.name='Steris';vars.dullahan.return_to_camp=true
env.setVar=function(path,value)
 if path=='vars.dullahan.return_to_camp'then vars.dullahan.return_to_camp=value end
 return true
end
env.evaluateAllConditions=function()return false end
env.distanceTo=function()return 30 end
tracker.enemy({actor=boss,kind='enemy_ability',phase='post',outcome='completed',resource={en='Eisenschneider'}})
assert(matches());for _,code in ipairs(rule.commands)do execute(code)end
assert(moved.x==vars.dullahan.positioning.mages.x and moved.y==vars.dullahan.positioning.mages.y)
assert(vars.dullahan.return_to_camp)
tracker.text('The boss begins to emit a noxious miasma.',boss);assert(not matches())
tracker.text("The boss's rage is beginning to boil over.",boss);assert(matches())
env.distanceTo=function()return 0 end
for _,code in ipairs(rule.commands)do execute(code)end
assert(not vars.dullahan.return_to_camp and not matches())
print('PASS: scattered mages return after resolution or Boiling release, stop on renewed Miasma and clear the return marker on arrival')
