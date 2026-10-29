local inventory=require('./lib/inventory')
local Service=require('./lib/equipment/init')
local function resource(id,name)
    return {id=id,name=name,flags={Equippable=true},slots={[13]=true},type=4}
end
resources={items={[101]=resource(101,'Original'),[202]=resource(202,'Temporary')}}
local items={equipment={left_ring=1,left_ring_bag=8},wardrobe={
    [1]={id=101,slot=1,count=1,status=5},[2]={id=202,slot=2,count=1,status=0}}}
extdata={decode=function() return {augments={}} end}
arrayAppend=function(t,v) t[#t+1]=v end
tableAll=function(t,predicate)
    local result={}; for _,v in pairs(t or {}) do if predicate(v) then result[#result+1]=v end end; return result
end
findItem=function(query)
    if type(query)=='table' then query=query.name end
    for _,r in pairs(resources.items) do if r.id==query or r.name==query then return r end end
end
local sent={}
windower={ffxi={get_items=function() return items end,
    set_equip=function(index,slot,bag) sent[#sent+1]={index,slot,bag} end},
    register_event=function(name,fn) return name end,unregister_event=function() end}
inventory.equipment_manager=Service.new({windower=windower,inventory=inventory,report=function(e) error(e) end})
local changes={}
assert(inventory.equip_many({ring1={name='Temporary'}},nil,false,changes)==1)
assert(#sent==1 and sent[1][1]==2)
assert(inventory.find_equipment_in_slot('ring1').name=='Temporary')
assert(inventory.find_equipment_in_slot('ring1',nil,true).name=='Original')
assert(inventory.find_item('Original',{equippable=true,equipped=false}))
assert(not inventory.find_item('Temporary',{equippable=true,equipped=false}))
assert(changes.removed.ring1.localId==1)
inventory.restore_equipment(changes.removed)
assert(#sent==1) -- Restore waits for the earlier swap, rather than racing it.
inventory.equipment_manager.queue:ack(13,{id=202,localId=2,bagId=8})
assert(#sent==2 and sent[2][1]==1)
inventory.equipment_manager.queue:ack(13,{id=101,localId=1,bagId=8})
inventory.equipment_manager.queue:tick()
assert(inventory.find_equipment_in_slot('ring1').name=='Original')
inventory.equipment_manager:destroy(); inventory.equipment_manager=nil
print('PASS: real inventory selection, pending equipment queries, confirmed queries, snapshots and queued restoration')
