local M=require('./lib/encounter-state')
local now=10
M.attach({deps={clock=function() return now end,windower={ffxi={}}}})
local definition={actors={['Example Sentinel']={initial={mode='idle',hits=0},rules={
    {kind='text',contains='raises its shield',set={mode='guarded'},reset={hits=0},only_on_change=true},
    {kind='enemy_spell',names={'Stone'},phase='post',outcome='completed',set={mode='open'}},
    {kind='party_weapon_skill',when={mode='open'},increment={hits=1},timestamp='hit'},
    {kind='auto_attack',set={mode='idle'}},
}}},conditions={ready="encounter.mode == 'open' and encounter_config.actor == me.name"}}
M.configure('one',definition,{actor='Player'})
M.configure('two',definition,{actor='Other'})
local mob={id=1,index=2,name='Example Sentinel',hpp=100,valid_target=true}
M.text('Someone else raises its shield.',mob)
assert(M.get('one',mob).mode=='idle')
M.text('Example Sentinel raises its shield.',mob)
assert(M.get('one',mob).mode=='guarded')
M.enemy({actor=mob,kind='enemy_spell',resource={en='Stone'},phase='post',outcome='interrupted'})
assert(M.get('one',mob).mode=='guarded')
M.enemy({actor=mob,kind='enemy_spell',resource={en='Stone'},phase='post',outcome='completed'})
assert(M.evaluate('one','ready',mob,{me={name='Player'}}))
assert(not M.evaluate('two','ready',mob,{me={name='Player'}}))
M.observe({kind='party_weapon_skill'},mob)
now=15
local state=M.get('one',mob)
assert(state.hits==1 and state.ages.hit==5)
state.mode='tampered'; state.ages.hit=99
assert(M.get('one',mob).mode=='open' and M.get('one',mob).ages.hit==5)
definition.actors['Example Sentinel'].initial.mode='changed'
local replacement={id=1,index=3,name='Example Sentinel',hpp=100}
assert(M.get('one',replacement).mode=='idle')
assert(not pcall(M.configure,'bad',{actors={A={rules={{kind='unknown'}}}}}))
assert(not M.get('bad',mob))
assert(not M.evaluate('missing','ready',mob,{}))
mob.hpp=0; assert(not M.get('one',mob))
mob.hpp=100; assert(M.get('one',mob).mode=='idle')
M.remove('one'); assert(not M.get('one',mob))
M.clear(); assert(M.get('two',mob).mode=='idle')
local second={id=2,index=4,name=mob.name,hpp=100,valid_target=true}
local nearby={mob,second}
local service={deps={clock=function() return now end,windower={ffxi={get_mob_array=function() return nearby end}}}}
M.attach(service)
service.encounterText('Example Sentinel raises its shield.')
assert(M.get('two',mob).mode=='idle' and M.get('two',second).mode=='idle')
nearby={mob}
service.encounterText('Example Sentinel raises its shield.')
assert(M.get('two',mob).mode=='guarded')
print('PASS: generic actors, configured text/actions, conditions, counters, clocks, isolation, snapshots, respawns, validation and removal')

M.configure('latch',{actors={['Example Sentinel']={initial={open=true,hold=false}}},
 conditions={ready='encounter.open',safe="encounter_test('ready') and not encounter.hold"},latch_conditions={'ready'}})
assert(M.evaluate('latch','ready',mob,{}))
-- Composition must use the latched ready result while evaluating other policy live.
assert(M.evaluate('latch','safe',mob,{}))
M.configure('cycle',{actors={['Example Sentinel']={}},conditions={a="encounter_test('b')",b="encounter_test('a')"}})
assert(not pcall(M.evaluate,'cycle','a',mob,{}))
print('PASS: named condition composition, latched eligibility and circular-reference rejection')
M.reset()
assert(not M.get('two',mob) and not M.get('latch',mob))
local lookups=0
M.action({category=1,actor_id=1,targets={{id=1,actions={{message=185}}}}},
 {get_mob_by_id=function()lookups=lookups+1;return mob end})
assert(lookups==0)
M.configure('fresh',{actors={['Example Sentinel']={initial={mode='fresh'}}}})
assert(M.get('fresh',mob).mode=='fresh')
local f=assert(io.open('lib/action-processing.lua'));local source=f:read('*a');f:close()
local body=assert(source:match('local function compileAllActions%(%)(.-)compileActions%(\'loading\''))
assert(body:find("require('./lib/encounter-state').reset()",1,true))
print('PASS: action reload clears tracker definitions, inactive action observations skip entity lookup, loading can register fresh trackers')
