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

-- Exhausted ammunition can remain in its old bag slot with a count of zero.
-- It must not satisfy ranged readiness or hide a replacement stack.
resources.items[303]={id=303,name='Test Gun',category='Weapon',range_type='Gun',flags={Equippable=true},slots={[2]=true}}
resources.items[404]={id=404,name='Bullet',ammo_type='Bullet',flags={Equippable=true},slots={[3]=true}}
items={equipment={range=1,range_bag=0,ammo=2,ammo_bag=0},inventory={enabled=true,
    [1]={id=303,slot=1,count=1,status=5},
    [2]={id=404,slot=2,count=0,status=5},
    [3]={id=404,slot=3,count=12,status=0}}}
local ranged=inventory.get_ranged_equipment()
assert(ranged and ranged.weapon and ranged.ammo==nil and not ranged.valid)
local replacement=inventory.find_item('Bullet',{equippable=true})
assert(replacement and replacement.localId==3 and replacement.count==12)
items.inventory[2].count=1
ranged=inventory.get_ranged_equipment()
assert(ranged and ranged.valid and ranged.ammo and ranged.ammo.name=='Bullet')

-- A cached equipment location can be reused by newly generated pouch ammo even
-- though the live ammo slot is empty. Live readiness must ignore that projection.
items.equipment.ammo=0;items.equipment.ammo_bag=0
inventory.equipment_manager={snapshot=function()
    local projected={}
    for key,value in pairs(items) do projected[key]=value end
    projected.equipment={range=1,range_bag=0,ammo=2,ammo_bag=0}
    return projected
end}
assert(inventory.get_ranged_equipment().valid)
ranged=inventory.get_ranged_equipment(nil,true)
assert(ranged and ranged.weapon and ranged.ammo==nil and not ranged.valid)
assert(not inventory.get_ranged_equipment(true).valid)

-- The same stale projection must not suppress a request to equip the new stack.
local staleSent={}
inventory.equipment_manager.submit=function(_,operations)
    for _,operation in ipairs(operations) do staleSent[#staleSent+1]=operation end
    return #operations
end
assert(inventory.equip_many({ammo='Bullet'})==1)
assert(#staleSent==1 and staleSent[1].slot==3 and staleSent[1].item.localId==2)

-- Pouch output may reuse the exhausted equipped stack's exact bag index. The
-- live item status, rather than coordinates alone, identifies it as unequipped.
staleSent={}
items.equipment.ammo=2;items.equipment.ammo_bag=0
items.inventory[2].status=0
items.inventory[3].count=0
assert(not inventory.get_ranged_equipment(true).valid)
assert(inventory.equip_many({ammo='Bullet'})==1)
assert(#staleSent==1 and staleSent[1].slot==3 and staleSent[1].item.localId==2)
inventory.equipment_manager=nil
print('PASS: exhausted ammo does not satisfy ranged readiness or equipment selection')

-- Zoning snapshots can be absent or omit equipment fields/bags.
items=nil
assert(not inventory.get_ranged_equipment())
assert(not inventory.find_item('Original',{equippable=true}))
assert(not inventory.find_item('Original',{usable=true}))
assert(not inventory.get_item_from_bag(nil,8,1))
items={}
assert(not inventory.get_ranged_equipment())
assert(not inventory.find_item('Original',{equippable=true,local_id=1,bag_id=8}))
items={equipment={}}
assert(not inventory.get_ranged_equipment())
assert(not inventory.get_item_from_bag(items,8,nil))
items={equipment={range=1,range_bag=8},wardrobe={}}
assert(not inventory.get_ranged_equipment())
print('PASS: inventory/ranged lookups tolerate absent zoning snapshots, equipment fields and bags')
