local Service=require('./lib/equipment/init')
local inventory=require('./lib/inventory')
resources={items={[1]={id=1},[2]={id=2},[3]={id=3}}}
local listeners,sent,errors,restored={},{},{},{}
local player={status=1,buffs={}}
local now=0
local items={equipment={back=0,back_bag=0},wardrobe={}}
for id=1,3 do items.wardrobe[id]={id=id,slot=id,count=1} end
local function item(id)return {id=id,localId=id,bagId=8}end
local manager
local deps={resources={buffs={[99]={en='Encumbrance'},[100]={en='Protect'}}},
 windower={ffxi={get_player=function()return player end,
 get_items=function()return items end,
 set_equip=function(index,slot)sent[#sent+1]={index=index,slot=slot}end},
 register_event=function(name,fn)listeners[name]=fn;return name end,unregister_event=function()end},
 inventory=inventory,clock=function()return now end,
 report=function(message)errors[#errors+1]=message end,
 restoreGear=function()
  restored[#restored+1]=player.status
  manager:submit({{slot=15,item=item(player.status==1 and 2 or 3)}})
 end}
manager=Service.new(deps);inventory.equipment_manager=manager
local stale=manager:session()
assert(stale:submit({{slot=15,item=item(1)}})==1)
-- Pending swaps must not retry or replay after the buff.
manager:submit({{slot=15,item=item(1)}})
local barrier
manager:barrier(function(ok)barrier=ok end)
player.buffs={99};listeners['gain buff'](99)
assert(barrier==false and #manager.queue.batches==0)
assert(not manager:canEquip() and manager:submit({{slot=15,item=item(2)}})==0)
local session=manager:session()
assert(session:submit({{slot=15,item=item(2)}})==0 and next(session.planned)==nil)
assert(session:commit()==0)
assert(inventory.equip_many({back='anything'})==0)
assert(inventory.restore_equipment({back={empty=true}})==0)
assert(manager.queue:view()[15].localId==0) -- Never project rejected swaps as applied.
now=10;listeners.prerender();assert(#sent==1 and #errors==0)
listeners['lose buff'](100);assert(not manager:canEquip())
-- Loss notifications can precede the live buff snapshot update.
listeners['lose buff'](99);listeners.prerender();assert(#restored==0)
player.status=0;player.buffs={};listeners.prerender()
assert(#restored==1 and restored[1]==0 and sent[2].index==3)
assert(stale:commit()==0) -- A pre-buff phase cannot replay its old gear after removal.
listeners.prerender();assert(#restored==1)
-- A second loss uses battle gear if combat started while equipment was locked.
player.buffs={99};listeners['gain buff'](99)
player.status=1;player.buffs={};listeners['lose buff'](99);listeners.prerender()
assert(#restored==2 and restored[2]==1 and sent[3].index==2)
-- Live state also protects startup and recovers if a buff event was missed.
player.buffs={99};assert(not manager:canEquip())
player.buffs={};listeners.prerender();assert(#restored==3)
player.buffs={99};listeners['gain buff'](99)
listeners.logout();player=nil;listeners.prerender();assert(#restored==3)
inventory.equipment_manager=nil
print('PASS: Encumbrance blocks submissions/sessions/retries, rejects projected swaps, drops stale work and restores current idle/battle gear once')
