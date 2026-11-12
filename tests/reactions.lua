local M=require('./lib/reactions')
local now,zone,enabled=0,1,true
local player={vitals={hp=100},target_locked=true}
local actors={[2]={id=2,index=2,x=1,y=0,hpp=100,valid_target=true},
 [3]={id=3,index=3,x=2,y=0,hpp=100,valid_target=true}}
local turns,restores,cancels,unlocks={},{},0,0
M.attach({clock=function()return now end,zone=function()return zone end,
 enabled=function()return enabled end,player=function()return player end,
 mob=function(id)return actors[id]end,cancelMovement=function()cancels=cancels+1 end,
 unlock=function()unlocks=unlocks+1 end,faceAway=function(mob)turns[#turns+1]=mob.id end,
 restore=function(id)restores[#restores+1]=id end})
local function event(actor,id,kind,phase)
 return {actor={id=actor,index=actor,name='Enemy'},id=id,kind=kind or 'enemy_ability',phase=phase or 'pre'}
end
local a=event(2,10)
assert(M.faceAway(a,{wait=1}))
assert(turns[1]==2 and cancels==1 and unlocks==1)
assert(M.active() and M.blocksMovement() and M.suppresses('weapon_skills') and M.suppresses('offensive_magic'))
local snapshot=M.state();for _,h in pairs(snapshot)do h.options.no_turn=true end
assert(M.blocksMovement()) -- Query snapshots cannot mutate active requests.
now=0.1;M.faceAway(a,{wait=1});assert(#turns==1) -- Duplicate pre doesn't extend/restart.
local b=event(3,11)
M.faceAway(b,{wait=0,allow_offensive_magic=true})
assert(turns[#turns]==3 and M.suppresses('offensive_magic'))
M.observe(event(2,999,nil,'post'));assert(M.active())
M.observe(event(3,11,nil,'post'));assert(turns[#turns]==2 and #restores==0)
M.observe(event(2,10,nil,'post'));assert(M.active())
now=1.2;M.tick();assert(not M.active() and #restores==1)
M.faceAway(a,{wait=0});local interrupt=event(2,nil,nil,'post');interrupt.interrupted=true
M.observe(interrupt);assert(not M.active())
M.faceAway(a,{wait=0,no_turn=true,allow_weapon_skills=true})
assert(not M.blocksMovement() and not M.suppresses('weapon_skills') and M.suppresses('offensive_magic'))
assert(M.blocksAction('spell',{targets={Enemy=true}}))
assert(not M.blocksAction('spell',{targets={Enemy=true,Party=true}}))
assert(not M.blocksAction('spell',{targets={Self=true}}))
M.observe(event(2,10,nil,'post'));assert(not M.active())
M.faceAway(a,{key='shield',bracket=true,wait=0,timeout=20})
M.observe(event(2,10,nil,'post'));assert(M.active())
assert(not M.release(event(3,99),{key='shield'}))
assert(M.release(event(2,99),{key='shield'}) and not M.active())
M.faceAway(a,{timeout=2});now=4;M.tick();assert(not M.active())
M.faceAway(a);zone=2;M.tick(true);assert(not M.active())
M.faceAway(a);actors[2].hpp=0;M.tick(true);assert(not M.active());actors[2].hpp=100
M.faceAway(a);enabled=false;M.tick(true);assert(not M.active());enabled=true
M.faceAway(a);player.vitals.hp=0;M.tick(true);assert(not M.active());player.vitals.hp=100
assert(not pcall(M.faceAway,a,{timeout=-1}))
print('PASS: immediate non-yielding holds, overlaps, suppression, duplicate pre, matching completion/interruption, brackets, waits, timeout/death/zone/disable cleanup')

-- Exercise stock rules through the real event runner, including alias matching.
local Config=require('./lib/events/config')
local Runtime=require('./lib/events/runtime')
local json=require('./lib/jsonlua')
local f=assert(io.open('events/lib/reactions/face-away.json'));local doc=json.parse(f:read('*a'));f:close()
local config=Config.load({'test'},function()return doc end)
config.vars.reactions.face_away={{kind='enemy_ability',names={'Baleful Gaze'},options={wait=0}}}
local selectedTarget,leaderTarget=actors[2],nil
local context=function(_,state)return {vars=state.vars,bt=selectedTarget,party_leader_bt=leaderTarget,reactions=M}end
local runtime=Runtime.new(config,{context=context,clock=function()return now end,report=function(err)error(err)end})
local e=event(3,12);e.name='Baleful Gaze'
runtime:observe(e,'pre');assert(not M.active()) -- Common lists restrict to bt.
e=event(2,12);e.name='baleful gaze'
runtime:observe(e,'pre');assert(M.active())
M.observe(event(2,12,nil,'post'));assert(not M.active())
selectedTarget=nil;leaderTarget=actors[2]
runtime:observe(e,'pre');assert(M.active())
M.observe(event(2,12,nil,'post'));assert(not M.active())
selectedTarget=actors[3]
runtime:observe(e,'pre');assert(not M.active()) -- Own target takes precedence.
selectedTarget=actors[2];leaderTarget=nil
print('PASS: stock event configuration, real runner, case-insensitive ability matching and target filtering')

local ordinaryRules=config.vars.reactions.face_away
config.vars.reactions.face_away={{key='shield',actor='Enemy',
 start={abilities={'Raise Shield'}},release={spells={'Drop Shield'}},options={wait=1,timeout=20}}}
runtime:compileReactions()
local start=event(2,50);start.name='Raise Shield'
runtime:observe(start,'pre');assert(not M.active()) -- Defaults to successful post.
start.completed=false;runtime:observe(start,'post');assert(not M.active())
start.completed=true;runtime:observe(start,'post');assert(M.active())
M.observe(event(2,50,nil,'post'));assert(M.active())
selectedTarget=actors[3] -- Releases still work after switching away.
local release=event(3,51,'enemy_spell','post');release.name='Drop Shield';release.completed=true
runtime:observe(release,'post');assert(M.active())
release.actor.id=2;release.actor.index=2;release.completed=false
runtime:observe(release,'post');now=now+2;M.tick(true);assert(M.active())
release.completed=true;runtime:observe(release,'post');assert(M.active())
now=now+1;M.tick(true);assert(not M.active())
selectedTarget=actors[2]
config.vars.reactions.face_away[1].start={spells={'Raise Shield'},phase='pre'}
config.vars.reactions.face_away[1].release={abilities={'Drop Shield'},phase='pre'}
runtime:compileReactions()
start.kind='enemy_spell';runtime:observe(start,'pre');assert(M.active())
release.kind='enemy_ability';runtime:observe(release,'pre')
now=now+1;M.tick(true);assert(not M.active())
config.vars.reactions.face_away=ordinaryRules
runtime:compileReactions()
print('PASS: configured brackets, post-success defaults, pre overrides, cross-kind triggers, switched-target releases and wrong-actor rejection')

-- Actor arrays share configuration without sharing individual enemy holds.
local bracket={key='shared',actor={'First Enemy','Second Enemy'},
 start={abilities={'Start'}},release={abilities={'End'}},options={wait=0}}
local start=event(2,60,nil,'post');start.name='Start';start.completed=true
start.actor.name='Other Enemy'
require('./lib/events/matches').attach(start)
assert(not M.handle(start,{bracket}) and not M.active())
for _,name in ipairs(bracket.actor)do
 start.actor.name=name
 assert(M.handle(start,{bracket}) and M.active())
 local release=event(3,61,nil,'post');release.name='End';release.completed=true;release.actor.name=name
 require('./lib/events/matches').attach(release)
 assert(not M.handle(release,{bracket}) and M.active())
 release.actor.id=2;release.actor.index=2
 assert(M.handle(release,{bracket}) and not M.active())
end
local simple={actor={'First Enemy','Second Enemy'},names={'Start'},options={wait=0}}
start.phase='pre'
for _,name in ipairs(simple.actor)do
 start.actor.name=name
 assert(M.handle(start,{simple}) and M.active())
 M.observe(event(2,60,nil,'post'));assert(not M.active())
end
simple.actor={};assert(not M.handle(start,{simple}))
simple.actor='Other Enemy';assert(not M.handle(start,{simple}))
simple.actor='Second Enemy';assert(M.handle(start,{simple}))
M.clear()
print('PASS: actor strings/arrays, either-name matching, empty/nonmatching filters and per-enemy bracket isolation')

-- Real enemy packet adapter -> stock event -> shared hold -> automatic release.
local Service=require('./lib/events/init')
local listeners={}
player.id=100
for _,actor in pairs(actors)do actor.spawn_type=16;actor.name='Enemy'end
local packet={Category=7,Param=55,Target=2}
local service=Service.new({windower={ffxi={get_player=function()return player end,
 get_mob_by_id=function(id)return actors[id]end},register_event=function(name,fn)listeners[name]=fn;return name end,
 unregister_event=function()end},resources={spells={},job_abilities={},weapon_skills={},
 monster_abilities={[12]={id=12,en='Baleful Gaze'}}},
 packets={parse=function()return packet end},
 clock=function()return now end,report=function(err)error(err)end})
service.runtime=runtime
local function emit(category,param,id)
 listeners.action({actor_id=2,category=category,param=param,
  targets={{id=100,actions={{param=id,message=0}}}}})
end
emit(7,24931,12);assert(M.active())
-- The real action-context bridge blocks normal movement during the hold.
local f=assert(io.open('lib/action-context.lua'));local source=f:read('*a');f:close()
local bridge=assert(source:match('(    movementReservations%.attach.-)    engagementHelpers%.attach'))
local ctx={}
local fn=assert(loadstring(bridge));setfenv(fn,setmetatable({context=ctx,resources={spells={}},
 movementReservations={attach=function(c)c.movementAvailable=function()return true end end},
 smartMove={cancelJob=function()end}},{__index=_G}));fn()
assert(not ctx.movementAvailable() and ctx.reactions.active())
assert(service:outgoing(0x01A,'packet','packet',false,false)==true)
assert(service:inject(packet)==false) -- Also protect delayed dispatch after gear.
emit(11,12,nil);assert(not M.active())
assert(ctx.movementAvailable())
emit(7,24931,12);assert(M.active())
emit(7,28787,0);assert(not M.active())
service.deps.resources.spells[10]={id=10,en='Fire',targets={Enemy=true}}
config.vars.reactions.face_away[#config.vars.reactions.face_away+1]={kind='enemy_spell',names={'Fire'},options={wait=0}}
runtime:compileReactions()
emit(8,24931,10);assert(M.active())
emit(8,28787,10);assert(not M.active())
service:destroy();M.clear()
print('PASS: real readying/completion/interruption packets and outgoing/delayed-injection weapon-skill guard')
