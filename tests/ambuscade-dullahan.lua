local Tracker=require('./lib/encounter-state')
local json=require('./lib/jsonlua')
local f=assert(io.open('settings/_namespaces/ambuscade/dullahan/actions/lib/dullahan/setup.json'))
local definition=json.parse(f:read('*a')).vars.dullahan.tracker; f:close()
local now=0
Tracker.attach({deps={clock=function() return now end,windower={ffxi={}}}})
-- Keep this fixture readable while exercising only the public generic tracker API.
local M={clear=Tracker.clear,text=Tracker.text,observe=Tracker.enemy,action=Tracker.action}
M.configure=function(config) Tracker.configure('test',definition,config) end
M.get=function(mob) return Tracker.get('test',mob) end
M.canWS=function(mob,config,actor,future)
    local before=now
    if future then now=now+4 end
    local result=Tracker.evaluate('test','can_ws',mob,require('./tests/helpers/dullahan-party').attach({me={name=actor}}))
    now=before
    return result
end
local boss={id=10,index=1,name='Bozzetto Retributionist'}
local horse={id=20,index=2,name='Bozzetto Charger'}
local dd={id=30,name='Ladrian',in_party=true}
local mobs={[10]=boss,[20]=horse,[30]=dd}
local ffxi={get_mob_by_id=function(id) return mobs[id] end}
local config={miasma_order={'Ladrian','Gavilar'},miasma_spacing=3}
-- Use the actual battlefield wording through the incoming-text adapter.
boss.hpp=100;boss.valid_target=true
local service={deps={clock=function()return now end,windower={ffxi={get_mob_array=function()return {boss} end}}}}
Tracker.attach(service)
M.configure(config)
service.encounterText("The boss's rage is beginning to boil over.")
assert(M.get(boss).phase=='boiling')
for _,name in ipairs({'Carbonite','Ladrian','Gavilar'}) do
    assert(not M.canWS(boss,config,name))
end
service.encounterText('The boss begins to emit a noxious miasma.')
assert(M.get(boss).phase=='miasma')
service.encounterText('The boss begins charging up.')
assert(M.get(boss).phase=='charging')
local duplicate={id=11,index=4,name=boss.name,hpp=100,valid_target=true}
service.deps.windower.ffxi.get_mob_array=function()return {boss,duplicate} end
service.encounterText("The boss's rage is beginning to boil over.")
assert(M.get(boss).phase=='charging') -- Ambiguous aliases must not update both actors.
print('PASS: actual boss messages route through aliases and block every melee WS in Boiling')
M.clear(); M.configure(config)
assert(M.canWS(boss,nil,'Ladrian'))
M.observe({actor=boss,kind='enemy_ability',phase='pre',resource={en='Charging Up'}})
assert(M.get(boss).phase=='unknown' and not M.canWS(boss,config,'Ladrian'))
M.text('Bozzetto Retributionist begins charging up.',boss)
assert(M.get(boss).phase=='charging' and not M.canWS(boss,config,'Ladrian'))
M.text('Bozzetto Retributionist begins to emit a noxious miasma.',boss)
assert(M.canWS(boss,config,'Ladrian') and not M.canWS(boss,config,'Gavilar'))
M.action({category=3,actor_id=30,targets={{id=10}}},ffxi)
assert(not M.canWS(boss,config,'Ladrian'))
assert(not M.canWS(boss,config,'Gavilar')) -- Quiet time before the next WS.
assert(M.canWS(boss,config,'Gavilar',function() return os.clock()+4 end))
M.text('Bozzetto Retributionist begins to emit a noxious miasma.',boss)
assert(M.get(boss).bursts==1) -- Duplicate text must not reopen the first turn.
M.text("Bozzetto Retributionist's miasma dissipates but its rage is beginning to boil over.",boss)
assert(M.get(boss).phase=='boiling' and not M.canWS(boss,config,'Gavilar'))
M.observe({actor=boss,kind='enemy_ability',phase='post',outcome='completed',resource={en='Charging Up'}})
assert(M.get(boss).phase=='boiling') -- A late completion is not a reset.
M.observe({actor=boss,kind='enemy_ability',phase='post',outcome='interrupted',resource={en='Nether Castigation'}})
assert(M.get(boss).phase=='boiling')
M.observe({actor=boss,kind='enemy_ability',phase='post',outcome='completed',resource={en='Nether Castigation'}})
assert(M.canWS(boss,config,'Ladrian'))
M.observe({actor=horse,kind='enemy_ability',phase='pre',resource={en='Grace of Hera'}})
assert(not M.canWS(horse,config,'Ladrian'))
M.observe({actor=horse,kind='enemy_ability',phase='post',outcome='completed',resource={en='Grace of Hera'}})
assert(not M.canWS(horse,config,'Ladrian'))
M.action({category=1,actor_id=10},ffxi)
assert(not M.canWS(horse,config,'Ladrian'))
M.action({category=1,actor_id=20},ffxi)
assert(not M.canWS(horse,config,'Ladrian')) -- An immediate post-move auto cannot release absorption.
now=5
M.action({category=1,actor_id=20},ffxi)
assert(M.canWS(horse,config,'Ladrian'))
M.action({category=1,actor_id=30,targets={{id=20,actions={{message=373}}}}},ffxi)
assert(not M.canWS(horse,config,'Ladrian')) -- Absorbed melee damage re-closes the window.
now=7; M.action({category=1,actor_id=20},ffxi)
assert(not M.canWS(horse,config,'Ladrian'))
now=10; M.action({category=1,actor_id=20},ffxi)
assert(M.canWS(horse,config,'Ladrian'))
M.observe({actor=horse,kind='enemy_ability',phase='pre',resource={en='Scintillant Lance'}})
now=20; M.action({category=1,actor_id=20},ffxi)
assert(not M.canWS(horse,config,'Ladrian')) -- Even a delayed auto cannot bypass unfinished readying.
local snapshot=M.get(boss); snapshot.phase='boiling'
assert(M.get(boss).phase=='normal')
M.text('Other monster begins to emit a noxious miasma.',boss)
assert(M.get(boss).phase=='normal')
M.clear(); assert(M.get(boss).phase=='normal')
print('PASS: Dullahan phase holds, duplicate messages, late/interrupted results, ordered Miasma WS, Charger next-auto window and cleanup')

-- Reproduce a finisher readied while the tracker still says normal: readying
-- must close the gate even when its preceding chat phase was missed.
for _,name in ipairs({'Nether Castigation','Atramentous Libations','Atramentous Oblation','Eisenschneider'}) do
 M.clear(); M.configure(config)
 assert(M.canWS(boss,nil,'Carbonite'))
 M.observe({actor=boss,kind='enemy_ability',phase='pre',resource={en=name}})
 assert(M.get(boss).phase=='resolving')
 for _,actor in ipairs({'Carbonite','Ladrian','Gavilar'}) do assert(not M.canWS(boss,nil,actor)) end
 M.observe({actor=boss,kind='enemy_ability',phase='post',outcome='completed',resource={en=name}})
 assert(M.canWS(boss,nil,'Ladrian'))
end
print('PASS: finisher readying blocks all melee even after missing phase text; completion reopens normal policy')
-- Exercise actual category-11 decoding, not only hand-built observations.
local Observation=require('./lib/action-observation')
boss.spawn_type=16
ffxi.get_player=function()return {id=30} end
local resources={monster_abilities={[1]={id=1,en='Nether Castigation'},[2]={id=2,en='Atra. Libations'}}}
for id=1,2 do
 M.clear();M.configure(config)
 M.text("The boss's rage is beginning to boil over.",boss)
 assert(not M.canWS(boss,config,'Ladrian'))
 local observation=assert(Observation.enemy({actor_id=10,category=11,param=id,
     targets={{id=30,actions={{message=185}}}}},ffxi,resources,{}))
 M.observe(observation)
 assert(M.get(boss).phase=='normal' and M.canWS(boss,config,'Ladrian'))
end
print('PASS: decoded finisher completions release Boiling, including existing resource-name aliases')
-- Production burst mode removes ordered turns, spacing and retreat suppression.
local burstConfig={miasma_burst=true,retreat=true,tank={'PLD'},miasma_order={'melee_dps','ranged'},miasma_spacing=3}
M.clear();M.configure(burstConfig)
M.text('The boss begins charging up.',boss)
for _,actor in ipairs({'Carbonite','Ladrian','Gavilar'})do assert(not M.canWS(boss,burstConfig,actor))end
M.observe({actor=boss,kind='enemy_ability',phase='post',outcome='completed',resource={en='Atramentous Libations'}})
for _,actor in ipairs({'Carbonite','Ladrian','Gavilar'})do assert(M.canWS(boss,burstConfig,actor))end
M.text('The boss begins to emit a noxious miasma.',boss)
for _,actor in ipairs({'Carbonite','Ladrian','Gavilar'})do assert(M.canWS(boss,burstConfig,actor))end
M.action({category=3,actor_id=30,targets={{id=10}}},ffxi)
for _,actor in ipairs({'Carbonite','Ladrian','Gavilar'})do assert(M.canWS(boss,burstConfig,actor))end
M.text("The boss's rage is beginning to boil over.",boss)
for _,actor in ipairs({'Carbonite','Ladrian','Gavilar'})do assert(not M.canWS(boss,burstConfig,actor))end
M.text('The boss begins to emit a noxious miasma.',boss)
M.observe({actor=boss,kind='enemy_ability',phase='pre',resource={en='Eisenschneider'}})
for _,actor in ipairs({'Carbonite','Ladrian','Gavilar'})do assert(not M.canWS(boss,burstConfig,actor))end
print('PASS: Miasma burst allows every melee immediately and after another WS, but Boiling and Eisenschneider close all WS gates')
