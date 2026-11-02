local Verify=require('./lib/events/verification')
local Runtime=require('./lib/events/runtime')
local Config=require('./lib/events/config')
local Queue=require('./lib/equipment/queue')
local function item(id) return {id=id,localId=id,bagId=8} end
local function setup(kind,off,automatic)
    Verify.stop()
    local now=0
    local reports,errors,sends={}, {}, {}
    local queue=Queue.new({clock=function() return now end,read=function() return {[13]=item(1)} end,
        valid=function() return true end,report=function(message) errors[#errors+1]=message end,
        send=function(_,gear) sends[#sends+1]=gear.id end})
    local reads=0
    if not off then Verify.start({clock=function() return now end,
        snapshot=function() reads=reads+1; return queue.confirmed end,
        report=function(message) reports[#reports+1]=message end}) end
    local section=kind=='spell' and 'spells' or 'weapon_skills'
    local config=Config.load({'test'},function() return {[section]={use_equipment_snapshot=automatic,
        pre={{commands={'pre()'}}},mid=kind=='spell' and {{commands={'mid()'}}} or {},
        post={{commands={'post()'}}}}} end)
    local dispatched=false
    local runtime=Runtime.new(config,{clock=function() return now end,
        report=function(message) errors[#errors+1]=message end,
        equipmentSession=function() return {inventory={snapshot_equipment=function() return {saved=item(1)} end,
            restore_equipment=function() queue:submit({{slot=13,item=item(1)}}); return 1 end},
            commit=function() end,discard=function() end} end,
        barrier=function(fn) queue:barrier(fn) end,
        context=function() return {
            pre=function() queue:submit({{slot=13,item=item(2)}}) end,
            mid=function() queue:submit({{slot=13,item=item(3)}}) end,
            post=function() queue:submit({{slot=13,item=item(automatic and 4 or 1)}}) end} end})
    runtime:submit({kind=kind,id=42,name=kind,target={id=100}},function() dispatched=true end)
    return {queue=queue,runtime=runtime,reports=reports,errors=errors,sends=sends,
        request=runtime.pending[1],reads=function() return reads end,
        dispatched=function() return dispatched end,
        advance=function(value) now=now+value; queue:tick(); Verify.tick() end}
end
local t=setup('weapon_skill')
assert(not t.dispatched() and #t.reports==0)
t.queue:ack(13,item(2)); assert(t.dispatched())
t.runtime:complete('weapon_skill',42,nil,'completed')
Verify.tick(); assert(#t.reports==0) -- Post has not been acknowledged.
t.queue:ack(13,item(1)); Verify.tick()
assert(#t.reports==1 and t.reports[1]:find('PASS',1,true))
Verify.tick(); assert(#t.reports==1)
t=setup('weapon_skill')
t.queue:ack(13,item(2)); t.runtime:complete('weapon_skill',42,nil,'completed')
t.queue:ack(13,item(1)); t.queue:ack(13,item(9)) -- A later action must not invalidate an already-settled post.
assert(#t.reports==1 and t.reports[1]:find('PASS',1,true))
t=setup('weapon_skill',false,true)
t.queue:ack(13,item(2)); t.runtime:complete('weapon_skill',42,nil,'completed')
Verify.tick(); assert(#t.reports==0)
t.queue:ack(13,item(4)); Verify.tick(); assert(#t.reports==0)
t.queue:ack(13,item(1)); Verify.tick()
assert(#t.reports==1 and t.reports[1]:find('PASS',1,true)) -- Automatic baseline restoration is included.
t=setup('spell')
t.queue:ack(13,item(2)); t.queue:ack(13,item(3))
t.runtime:complete('spell',42,nil,'completed'); t.queue:ack(13,item(1)); Verify.tick()
assert(#t.reports==1 and t.reports[1]:find('PASS',1,true) and t.reports[1]:find('mid=confirmed',1,true))
t=setup('spell') -- A fast spell finishes before mid equipment acknowledgment.
t.queue:ack(13,item(2)); t.runtime:complete('spell',42,nil,'completed')
Verify.tick(); assert(#t.reports==0)
t.queue:ack(13,item(3)); t.queue:ack(13,item(1)); Verify.tick()
assert(#t.reports==1 and t.reports[1]:find('WARNING',1,true) and t.reports[1]:find('at result',1,true))
t=setup('weapon_skill') -- An unrelated change briefly displaces WS gear.
t.queue:ack(13,item(2)); t.queue:ack(13,item(9)); t.queue:ack(13,item(2))
t.runtime:complete('weapon_skill',42,nil,'completed'); t.queue:ack(13,item(1)); Verify.tick()
assert(#t.reports==1 and t.reports[1]:find('equipment changed during action',1,true))
t=setup('spell')
t.queue:ack(13,item(2)); t.runtime:complete('spell',42,nil,'interrupted')
t.queue:ack(13,item(3)); t.queue:ack(13,item(1)); Verify.tick()
assert(#t.reports==1 and t.reports[1]:find('PASS',1,true) and t.reports[1]:find('handled interrupted',1,true))
t=setup('weapon_skill')
t.runtime:finish(t.request,'cancelled')
t.queue:ack(13,item(2)); t.queue:ack(13,item(1)); Verify.tick()
assert(#t.reports==1 and t.reports[1]:find('PASS',1,true) and t.reports[1]:find('handled cancelled',1,true))
t=setup('spell')
t.queue:ack(13,item(2)); t.runtime:complete('spell',42,nil,'failed')
t.queue:ack(13,item(3)); t.queue:ack(13,item(1)); Verify.tick()
assert(#t.reports==1 and t.reports[1]:find('PASS',1,true) and t.reports[1]:find('handled rejected',1,true))
t=setup('weapon_skill')
for i=1,3 do t.advance(1) end
assert(#t.reports==1 and t.reports[1]:find('WARNING',1,true) and t.reports[1]:find('pre equipment failed',1,true))
t=setup('spell')
t.queue:ack(13,item(2)); t.queue:ack(13,item(9))
t.runtime:complete('spell',42,nil,'interrupted'); t.queue:ack(13,item(3)); t.queue:ack(13,item(1)); Verify.tick()
assert(#t.reports==1 and t.reports[1]:find('WARNING',1,true)) -- Handled outcomes cannot erase real interference.
t=setup('weapon_skill')
t.queue:ack(13,item(2)); t.advance(4); t.runtime:tick()
t.queue:ack(13,item(1)); Verify.tick()
assert(#t.reports==1 and t.reports[1]:find('INCOMPLETE',1,true) and t.reports[1]:find('timeout',1,true))
t=setup('weapon_skill')
t.queue:ack(13,item(2)); t.queue.confirmed[13]={localId=2,bagId=8}
t.runtime:complete('weapon_skill',42,nil,'completed'); t.queue:ack(13,item(1)); Verify.tick()
assert(#t.reports==1 and t.reports[1]:find('INCOMPLETE',1,true))
t=setup('weapon_skill')
t.queue:ack(13,item(2)); t.runtime:complete('weapon_skill',42,nil,'completed')
for i=1,3 do t.advance(1) end
assert(#t.reports==1 and t.reports[1]:find('WARNING',1,true) and t.reports[1]:find('post equipment failed',1,true))
t=setup('weapon_skill')
t.queue:ack(13,item(2)); t.runtime:complete('weapon_skill',42,nil,'completed')
-- Missing queue progress is bounded independently of normal queue retry failure.
t.queue.deps.ready=function() return false end
t.advance(11)
assert(#t.reports==1 and t.reports[1]:find('INCOMPLETE',1,true))
t=setup('weapon_skill')
Verify.stop(); assert(#t.reports==1 and t.reports[1]:find('INCOMPLETE',1,true))
t=setup('weapon_skill',true)
t.queue:ack(13,item(2)); t.runtime:complete('weapon_skill',42,nil,'completed'); t.queue:ack(13,item(1)); Verify.tick()
assert(#t.reports==0 and t.reads()==0 and not Verify.active())
print('PASS: WS/spell verification, post settlement, fast mid, interference, interrupted/unknown/failing states, deadline, stop and disabled overhead')
