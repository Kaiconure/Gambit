local inventory=require('./lib/inventory')
resources={items={
 [1]={id=1,name='Main',category='Weapon',type=4,flags={Equippable=true},slots={[0]=true,[1]=true}},
 [2]={id=2,name='Offhand',category='Weapon',type=4,flags={Equippable=true},slots={[0]=true,[1]=true}},
 [3]={id=3,name='Shield',category='Armor',type=5,flags={Equippable=true},slots={[1]=true}},
 [4]={id=4,name='Mantle',category='Armor',type=5,flags={Equippable=true},slots={[15]=true}},
}}
local items={equipment={main=0,main_bag=0,sub=0,sub_bag=0,back=0,back_bag=0},wardrobe={}}
for id=1,4 do items.wardrobe[id]={id=id,slot=id,count=1,status=0} end
findItem=function(query)
 if type(query)=='table'then query=query.id or query.name end
 for _,item in pairs(resources.items)do if item.id==query or item.name==query then return item end end
end
extdata={decode=function()return {augments={}}end}
arrayAppend=function(t,v)t[#t+1]=v end
tableAll=function(t,predicate)local r={};for _,v in pairs(t or {})do if predicate(v)then r[#r+1]=v end end;return r end
local traits,sent,reads={}, {},0
windower={ffxi={get_items=function()return items end,
 get_player=function()return {main_job_id=17,main_job_level=99}end,
 get_abilities=function()reads=reads+1;return traits and {job_traits=traits}end,
 set_equip=function(index,slot,bag)sent[#sent+1]={index=index,slot=slot,bag=bag}end}}
local set={main='Main',sub='Offhand',back='Mantle'}
assert(inventory.equip_many(set)==2 and #sent==2)
for _,swap in ipairs(sent)do assert(swap.slot~=1)end
assert(reads==1)
traits={18};sent={};reads=0
assert(inventory.equip_many(set)==3 and #sent==3 and reads==1)
traits={};sent={}
assert(inventory.equip_many({sub={{name='Offhand'},{name='Shield'}},back='Mantle'})==2)
assert(sent[2].slot==1 and sent[2].index==3)
sent={};assert(inventory.equip_many(set,nil,true)==2 and #sent==0)
local saved={sub={id=2,localId=2,bagId=8},back={id=4,localId=4,bagId=8}}
assert(inventory.restore_equipment(saved)==1 and #sent==1 and sent[1].slot==15)
traits={18};sent={}
assert(inventory.restore_equipment(saved)==2 and #sent==2)
traits=nil;sent={}
assert(inventory.equip_many(set)==2 and #sent==2)
sent={};assert(inventory.equip_many({sub='Shield'})==1 and sent[1].index==3)
-- Empty-slot restoration is legal without Dual Wield.
sent={};assert(inventory.restore_equipment({sub={empty=true}})==1 and sent[1].index==0)
print('PASS: live Dual Wield eligibility, mixed-slot progress, weapon/shield fallback, simulation, snapshot restoration and missing trait data')
