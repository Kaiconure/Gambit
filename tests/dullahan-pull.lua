local json=require('./lib/jsonlua')
local M=require('./lib/encounter-state')
local root='settings/_namespaces/ambuscade/dullahan/actions/'
local f=assert(io.open(root..'lib/dullahan/setup.json'));local d=json.parse(f:read('*a')).vars.dullahan;f:close()
local params={tank=d.tank,miasma_order=d.miasma_order,miasma_spacing=d.miasma_spacing,
    pull={anchor=d.positioning.tank,tank_tolerance=d.pull.tank_tolerance,enemy_radius=d.pull.enemy_radius}}
M.configure('pull',d.tracker,params)
local tank={name='Carbonite',index=1,x=137,y=-137}
local horse={name='Bozzetto Charger',id=20,index=2,x=160,y=-160,is_engaged=true,mob={target_index=1}}
local boss={name='Bozzetto Retributionist',id=30,index=3,x=160,y=-160,is_engaged=true,mob={target_index=1}}
local env={me={name='Ladrian'}}
require('./tests/helpers/dullahan-party').attach(env)
env.partyByName=function(name) if name=='PLD' or name==tank.name then env.member=tank;return tank end end
env.partyAnchorByName=function()env.member=tank;return tank end
env.findByName=function(name) env.find_result=name==horse.name and horse or boss;return env.find_result end
local function ready() return M.evaluate('pull','pull_ready',horse,env) end
assert(not ready())
tank.x=params.pull.anchor.x;tank.y=params.pull.anchor.y
assert(not ready()) -- Tank home alone is insufficient.
horse.x=137;horse.y=-137;boss.x=137;boss.y=-137
horse.mob.target_index=0;boss.mob.target_index=9
-- Enemy target information is not a prerequisite for releasing the initial pull.
assert(ready() and M.evaluate('pull','can_ws',horse,env))
horse.mob.target_index=9;assert(ready() and M.evaluate('pull','can_ws',horse,env)) -- Release stays latched after a hate change.
env.me.name='Carbonite';assert(M.evaluate('pull','can_ws',horse,env)) -- Tank can establish hate.
horse.mob.target_index=1;tank.is_dead=true;assert(ready());tank.is_dead=false
horse.is_engaged=false;assert(ready());horse.is_engaged=true
local entry=assert(io.open(root..'(all).json'));local all=json.parse(entry:read('*a'));entry:close()
for _,rule in ipairs(all.idle) do if rule.import=='follow-leader' then
 assert(rule.precondition[1]=="not any(zone_search, vars.dullahan.positioning.zones)")
end end
assert(table.concat(all.loading[1].commands):find('Pull steps',1,true))
-- Once Charger is defeated, do not keep re-running the initial two-enemy pull
-- geometry against the boss. Its damage-phase policy must still apply.
env.me.name='Ladrian'; tank.x=150; tank.y=-150
horse.is_dead=true; horse.hpp=0; boss.mob.target_index=9
assert(M.evaluate('pull','pull_ready',boss,env))
assert(M.evaluate('pull','can_ws',boss,env))
M.text("Bozzetto Retributionist's rage is beginning to boil over.",boss)
assert(not M.evaluate('pull','can_ws',boss,env))
for _,profile in ipairs(d.song_targets) do
    if profile.id=='mages' then
        assert(profile.songs[1]=="Mage's Ballad III" and profile.songs[2]=="Mage's Ballad II")
    end
end
print('PASS: pull staging requires tank and both enemies in camp without requiring enemy target indices; tank hate tools remain available')

-- Release is one-time; transient geometry must not re-run the staging disengage.
M.clear();M.configure('pull',d.tracker,params)
env.me.name='Ladrian';tank.x=params.pull.anchor.x;tank.y=params.pull.anchor.y
horse.is_dead=false;horse.hpp=100;horse.mob.target_index=1;boss.mob.target_index=1
assert(ready())
tank.x=150;horse.x=145;horse.mob.target_index=9
assert(ready() and M.evaluate('pull','can_ws',horse,env))
M.enemy({actor=horse,kind='enemy_ability',phase='pre',resource={en='Grace of Hera'}})
assert(ready() and not M.evaluate('pull','can_ws',horse,env)) -- Absorption is still live.
M.clear();assert(not ready()) -- A new encounter must satisfy initial placement again.
print('PASS: released melee do not oscillate with hate/position changes; damage holds and encounter reset remain active')
