local Queue=require('./lib/equipment/queue')
local copy=require('./lib/variable-values').copy
local now,sent,reports=0,{},{}
local function item(id) return {localId=id,bagId=id==0 and 0 or 8,id=id} end
local actual={[0]=item(10),[1]=item(20),[13]=item(30)}
local queue=Queue.new({read=function() return actual end,clock=function() return now end,
    send=function(slot,value) sent[#sent+1]={slot=slot,item=copy(value)} end,
    valid=function(value) return value.id~=999 end,
    report=function(value) reports[#reports+1]=value end})
queue:submit({{slot=13,item=item(31)}})
assert(#sent==1 and queue:view()[13].id==31 and queue:view(true)[13].id==30)
local called
queue:barrier(function(ok) called=ok end)
queue:submit({{slot=13,item=item(30)}})
assert(#sent==1 and queue:view()[13].id==30)
queue:ack(13,item(31))
assert(called==true and #sent==2 and sent[2].item.id==30)
assert(queue:view(true)[13].id==31) -- Raw inventory is still stale at 30.
queue:ack(13,item(30)); queue:tick(); assert(#queue.batches==0)
now=10; queue:tick(); assert(#sent==2) -- Old temporary gear never retries after restoration.
queue:submit({{slot=1,item=item(0)},{slot=0,item=item(11),after=1},{slot=1,item=item(21),after=0}})
assert(sent[#sent].slot==1 and sent[#sent].item.id==0)
queue:ack(1,item(0)); assert(sent[#sent].slot==0)
queue:ack(0,item(11)); assert(sent[#sent].slot==1 and sent[#sent].item.id==21)
queue:ack(1,item(21)); queue:tick()
queue:submit({{slot=13,item=item(32)}})
local start=#sent
for i=1,3 do now=now+1; queue:tick() end
assert(#sent==start+2 and #reports==1)
queue:barrier(function(ok) assert(ok==false) end)
queue:submit({{slot=13,item=item(999)}})
assert(#sent==start+2 and #reports==2)
queue:barrier(function(ok) assert(ok==false) end)
queue:submit({{slot=13,item=item(33)}})
local cleared=false
queue:barrier(function(ok) assert(not ok); cleared=true end)
queue:clear(); assert(cleared and #queue.batches==0)
now=100; local count=#sent; queue:tick(); assert(#sent==count)
-- Test the real adapter: dependency ordering, effective/confirmed snapshots,
-- individual acknowledgments, and reconciliation of stale inventory data.
local Service=require('./lib/equipment/init')
local callbacks={}
local metadataReady=true
local items={equipment={main=10,main_bag=8,sub=20,sub_bag=8},bag={}}
local adapter=Service.new({windower={ffxi={get_items=function() return items end,
    set_equip=function(index,slot,bag) sent[#sent+1]={slot=slot,item=item(index)} end},
    register_event=function(name,fn) callbacks[name]=fn; return name end,unregister_event=function() end},
    packets={new=function(direction,id,values) assert(direction=='outgoing' and id==0x050); return values end,
        inject=function(values)
            sent[#sent+1]={slot=values['Equip Slot'],item=item(values['Item Index'])}
        end},
    inventory={get_item_from_bag=function(_,bag,index) if index>0 and metadataReady then return {id=index} end end},
    clock=function() return now end,report=function(e) error(e) end})
adapter:submit({{slot=0,item=item(11)},{slot=1,item=item(21),after=0}})
assert(sent[#sent].item.id==0 and sent[#sent].slot==1)
assert(adapter:snapshot(items).equipment.main==11 and adapter:snapshot(items,true).equipment.main==10)
local function ack(slot,index)
    callbacks['incoming chunk'](0x050,string.char(0,0,0,0,index,slot,8,0),nil,false)
end
ack(1,0); assert(sent[#sent].slot==0)
ack(0,11); assert(sent[#sent].slot==1 and sent[#sent].item.id==21)
ack(1,21); callbacks.prerender()
assert(adapter:snapshot(items,true).equipment.sub==21)
adapter:submit({{slot=13,item=item(44)}})
local bytes={}
for i=1,136 do bytes[i]=0 end
for slot=0,15 do
    local index=slot==0 and 11 or slot==1 and 21 or slot==13 and 44 or 0
    bytes[73+slot*4]=index; bytes[74+slot*4]=slot; bytes[75+slot*4]=8
end
callbacks['incoming chunk'](0x117,string.char(unpack(bytes)),nil,false)
assert(#adapter.queue.batches==0 and adapter:snapshot(items,true).equipment.left_ring==44)
callbacks.logout()
items.equipment.main=50
assert(adapter:snapshot(items,true).equipment.main==nil) -- No cache fallback after reset.
callbacks.login()
assert(adapter:snapshot(items,true).equipment.main==50)
items.equipment.main=60
callbacks.prerender()
assert(adapter:snapshot(items,true).equipment.main==50)
metadataReady=false
ack(0,61)
assert(adapter:snapshot(items,true).equipment.main==61 and adapter.queue:view(true)[0].id==nil)
metadataReady=true
callbacks['job change']()
assert(adapter:snapshot(items,true).equipment.main==60)
callbacks['zone change']()
assert(adapter:snapshot(items,true).equipment.main==60)
adapter:destroy()
-- Bootstrap once, then accept only packet updates, including idle slots that
-- have never participated in a queued swap. Polling cannot change the ledger.
local reads=0
actual={[13]=item(30)}
local push=Queue.new({read=function() reads=reads+1; return actual end,clock=function() return now end,
    valid=function() return true end,send=function() end,report=function(e) error(e) end})
assert(reads==1)
actual[13]=item(31)
actual[5]=item(55)
for i=1,50 do push:view(); push:view(true); push:tick() end
assert(reads==1 and push:view(true)[13].id==30 and push:view(true)[5]==nil)
push:ack(13,item(32))
assert(push:view(true)[13].id==32 and reads==1)
push:resync(); assert(reads==2 and push:view(true)[13].id==31 and push:view(true)[5].id==55)
push:clear(); push:view(); push:tick()
assert(next(push:view(true))==nil and reads==2)
-- A packet can establish a slot even before its inventory metadata arrives.
push:ack(13,{localId=42,bagId=8})
assert(push:view(true)[13].localId==42 and reads==2)
print('PASS: ordered queue, projected queries, barriers, dependencies, acknowledgments, bounded retries and lifecycle cleanup')
