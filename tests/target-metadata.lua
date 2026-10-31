local metadata=require('./lib/target-metadata')
local identity={id=100,name='Original',index=10}
local mob={id=100,name='Live name',index=10,spawn_type=16,status=1,valid_target=true,in_party=false}
local value=metadata.snapshot(identity,mob,200)
assert(value.is_mob and value.is_engaged and value.valid_target and value.is_player==false)
assert(value.name=='Original' and identity.status==nil and mob.is_mob==nil)
mob.status=2
local dead=metadata.snapshot(identity,mob,200)
assert(dead.is_dead and not dead.is_engaged and value.is_engaged)
local missing=metadata.snapshot(identity,nil,200)
assert(missing.id==100 and missing.name=='Original' and missing.index==10)
assert(not missing.valid_target and missing.is_mob==nil and missing.status==nil)
assert(missing.is_npc==nil and missing.is_pet==nil)
mob.index=11; assert(not metadata.snapshot(identity,mob,200).valid_target); mob.index=10
mob.id=101; assert(not metadata.snapshot(identity,mob,200).valid_target); mob.id=100
for _,spawn in ipairs({1,2,13,14,16}) do
    mob.spawn_type=spawn; mob.status=0; mob.in_party=true; mob.in_alliance=true
    local target=metadata.snapshot(identity,mob,100)
    assert(target.is_player==(spawn==1 or spawn==13))
    assert(target.is_trust==(spawn==14) and target.is_mob==(spawn==16))
    assert(target.is_pet==false and target.is_npc==false)
    assert(target.is_me and target.is_idle and target.is_party_member and target.is_alliance_member)
end
local symbol={}
mob.is_npc=true; mob.spawn_type=16; mob.owner_index=1
metadata.apply(symbol,mob,100)
assert(symbol.is_npc==true and symbol.is_pet==true)
mob.is_npc=false; mob.spawn_type=2; mob.owner_index=0
metadata.apply(symbol,mob,100)
assert(symbol.is_npc==false and symbol.is_pet==false)
metadata.apply(symbol,nil,100)
assert(symbol.is_npc==nil and symbol.is_pet==nil)
for _,owner in ipairs({1,500,2047}) do
    mob.owner_index=owner
    assert(metadata.snapshot(identity,mob,100).is_pet==true)
end
for _,owner in ipairs({0,-1,false,'123'}) do
    mob.owner_index=owner
    assert(metadata.snapshot(identity,mob,100).is_pet==false)
end
mob.owner_index=nil
assert(metadata.snapshot(identity,mob,100).is_pet==false)
mob.status=1; metadata.apply(symbol,mob,100)
mob.status=2; metadata.apply(symbol,mob,100)
assert(symbol.is_dead and not symbol.is_engaged) -- Reused context symbols lose stale flags.
local Config=require('./lib/events/config')
local Runtime=require('./lib/events/runtime')
local targets={}
local config=Config.load({'test'},function() return {spells={pre={{commands={'record(event.target)'}}},
    mid={{commands={'record(event.target)'}}},post={{commands={'record(event.target)'}}}}} end)
mob.spawn_type=16; mob.status=1
local ffxi={get_player=function() return {id=200} end,get_mob_by_id=function() return mob end}
local runtime=Runtime.new(config,{clock=function() return 0 end,report=function(err) error(err) end,
    schedule=function(fn) fn() end,targetSnapshot=function(target) return metadata.refresh(target,ffxi) end,
    context=function() return {record=function(target) targets[#targets+1]=target end} end,
    equipmentSession=function() return {inventory={snapshot_equipment=function() return {} end},
        commit=function() end,discard=function() end} end})
runtime:submit({kind='spell',id=1,target=identity},function() mob.status=2 end)
mob=nil
runtime:complete('spell',1,nil,'completed')
assert(#targets==3 and targets[1].is_engaged and targets[2].is_dead)
assert(targets[3].id==100 and targets[3].name=='Original' and not targets[3].valid_target)
targets[1].id=999; assert(identity.id==100 and targets[2].id==100)
print('PASS: shared target flags, stable identity, missing/replaced targets, phase refresh and isolated snapshots')
