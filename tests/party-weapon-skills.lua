local Config=require('./lib/events/config')
local Runtime=require('./lib/events/runtime')
local Service=require('./lib/events/init')
local Result=require('./lib/weapon-skill-result')
local copy=require('./lib/variable-values').copy
local mobs={
 [100]={id=100,index=1,name='Self',spawn_type=1,valid_target=true},
 [101]={id=101,index=2,name='Party',spawn_type=1,valid_target=true},
 [102]={id=102,index=3,name='Alliance',spawn_type=1,valid_target=true},
 [103]={id=103,index=4,name='Other',spawn_type=1,valid_target=true},
 [104]={id=104,index=5,name='Trust',spawn_type=14,in_party=true,valid_target=true},
 [300]={id=300,index=6,name='Enemy',spawn_type=16,valid_target=true},
 [301]={id=301,index=7,name='Other Enemy',spawn_type=16,valid_target=true},
}
local seen,errors,listeners={},{},{}
local resources={weapon_skills={[10]={id=10,en='Upheaval',skillchain_a='Fusion',skillchain_b='Compression',skillchain_c='Fusion'}},
 job_abilities={},buffs={},action_messages={[999]={en='${actor} uses ${ability}.'}}}
local deps={clock=function()return 10 end,resources=resources,
 windower={ffxi={get_player=function()return mobs[100]end,get_mob_by_id=function(id)return mobs[id]end,
  get_mob_by_target=function(name)if name=='me'then return mobs[100]end end,
  get_party=function()return {p0={mob=mobs[100]},p1={mob=mobs[101]},a10={mob=mobs[102]}}end},
  register_event=function(name,fn)listeners[name]=fn;return name end,unregister_event=function()end},
 report=function(s)errors[#errors+1]=s end,
 context=function(_,state)return {vars=state.vars,record=function(event)
  assert(event.matches('upheaval') and event.matches(10));seen[#seen+1]=copy(event)
 end}end,
 schedule=function(fn)fn()end,
 equipmentSession=function()return {inventory={snapshot_equipment=function()return {}end},commit=function()end,discard=function()end}end}
local config=Config.load({'test'},function()return {
 vars={party_weapon_skills={include_alliance=false}},
 weapon_skills={post={{commands={'record(event)'}}}},
 party_weapon_skills={post={{commands={'record(event)'}}}}}end)
local service=Service.new(deps);service.runtime=Runtime.new(config,deps)
local function emit(actor,message,amount,scMessage,scAmount)
 listeners.action({actor_id=actor,category=3,param=10,targets={{id=300,actions={{message=message,param=amount,
  add_effect_message=scMessage,add_effect_param=scAmount,add_effect_animation=1}}}}})
end
emit(101,185,900,288,700)
assert(#seen==1)
local e=seen[1]
assert(e.kind=='party_weapon_skill' and e.phase=='post' and e.actor.name=='Party' and e.actor.is_party_member)
assert(e.actor_id==101 and e.target.id==300 and e.amount==900 and e.damage==900 and e.dealt_damage)
assert(e.triggered_skillchain and e.skillchain.name=='Light' and e.skillchain.damage==700)
assert(e.has_skillchain_properties and table.concat(e.skillchain_properties,',')=='Fusion,Compression')
emit(102,185,100);assert(#seen==1)
config.vars.party_weapon_skills.include_alliance=true
emit(102,185,100);assert(#seen==2 and not seen[2].actor.is_party_member and seen[2].actor.is_alliance_member)
emit(103,185,100);emit(104,185,100);emit(300,185,100);assert(#seen==2)
emit(101,999,100);assert(#seen==2) -- JA in category 3, with overlapping resource ID.
emit(100,185,500);assert(#seen==4) -- Self post-only fallback plus party post.
assert(seen[3].kind=='party_weapon_skill' and seen[4].kind=='weapon_skill')
assert(seen[3].actor.is_me and seen[4].amount==seen[3].amount)
-- A normal self lifecycle still produces exactly one event of each kind.
assert(service.runtime:submit({kind='weapon_skill',id=10,name='Upheaval',actor_id=100,
 actor=copy(mobs[100]),target=copy(mobs[301])},function()return true end))
listeners.action({actor_id=100,category=3,param=10,targets={
 {id=300,actions={{message=185,param=9000}}},
 {id=301,actions={{message=187,param=100,add_effect_message=385,add_effect_param=77}}}}})
assert(#seen==6 and #service.runtime.pending==0)
assert(seen[5].target.id==301 and seen[5].amount==100)
assert(seen[6].kind=='weapon_skill' and seen[6].target.id==301 and seen[6].amount==100)
assert(seen[6].damage==nil and not seen[6].dealt_damage and seen[6].effect_type=='hp_drain')
assert(seen[6].triggered_skillchain and seen[6].skillchain.absorbed and seen[6].skillchain.damage==nil)
assert(seen[6].results[1].damage==9000 and seen[6].has_skillchain_properties)
-- External self-result adapters can finish the lifecycle before the action
-- listener emits the party notification; retain its requested target briefly.
deps.externalSelfResults=true
assert(service.runtime:submit({kind='weapon_skill',id=10,name='Upheaval',actor_id=100,
 actor=copy(mobs[100]),target=copy(mobs[301])},function()return true end))
local packet={actor_id=100,category=3,param=10,targets={
 {id=300,actions={{message=185,param=9000}}},{id=301,actions={{message=185,param=111}}}}}
service:selfResultAction(packet);listeners.action(packet)
assert(#seen==8 and seen[7].kind=='weapon_skill' and seen[8].kind=='party_weapon_skill')
assert(seen[7].amount==111 and seen[8].amount==111 and seen[8].target.id==301)
local amounts=Result.targets({{id=300,actions={{message=225,param=20}}},{id=301,actions={{message=185,param=0}}}})
assert(amounts[1].effect_type=='mp_drain' and amounts[1].damage==nil and amounts[2].damage==0 and not amounts[2].dealt_damage)
assert(not pcall(Config.load,{'bad'},function()return {party_weapon_skills={pre={}}}end))
assert(not pcall(Config.load,{'bad'},function()return {party_weapon_skills={use_equipment_snapshot=true}}end))
assert(#errors==0,table.concat(errors,'; '))
service:destroy()
print('PASS: party/alliance membership, self overlap/fallback, consistent WS metadata/damage/SC results, AoE target selection and post-only schema')
