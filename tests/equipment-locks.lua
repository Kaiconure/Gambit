local Locks=require('./lib/equipment/locks')
local Queue=require('./lib/equipment/queue')
local copy=require('./lib/variable-values').copy
local doom=true
local factory=require('./lib/execution-factory')
local originalGet=factory.get
local compilations=0
factory.get=function(code) compilations=compilations+1; return originalGet(code) end
local errors,contexts={},0
local locks=Locks.new({context=function()
    contexts=contexts+1
    return {hasBuff=function(name) assert(name=='Doom'); return doom end}
end,report=function(err) errors[#errors+1]=err end})
local original={localId=1,bagId=8,id=1}
local protected={localId=2,bagId=8,id=2}
local request={slot=13,item=protected,lock_when={"hasBuff('Doom')"}}
assert(#locks:filter({request})==1 and locks.slots[13].pending)
locks:filter({{slot=13,item=protected,lock_when={"hasBuff('Doom')"}}})
assert(compilations==1) -- Equivalent arrays/variable-reference copies reuse compiled functions.
assert(#locks:filter({{slot=13,item=original}})==0)
locks:observe(13,original) -- A pre-lock acknowledgement must not remove pending protection.
assert(locks.slots[13])
locks:observe(13,protected)
assert(not locks.slots[13].pending)
locks:observe(13,{localId=2,bagId=8}) -- Metadata may lag the physical location.
assert(locks.slots[13])
locks:observe(13,original) -- Manual changes are allowed and release ownership.
assert(not locks.slots[13])
locks:filter({request}); locks:failed(13,protected)
assert(not locks.slots[13])
locks:filter({request}); doom=false
assert(#locks:filter({{slot=13,item=original}})==1 and not locks.slots[13])
doom=true
-- A phase-local plan can protect its own earlier request without leaking on discard.
local localLocks=copy(locks.slots)
locks:filter({request},localLocks)
assert(#locks:filter({{slot=13,item=original}},localLocks)==0 and not locks.slots[13])
assert(not pcall(locks.filter,locks,{{slot=13,item=protected,lock_when={42}}}))
locks:filter({{slot=13,item=protected,lock_when={"error('condition failure')"}}})
assert(not locks:allows(13,original) and #errors==1) -- Fail closed and report once.
locks:allows(13,original); assert(#errors==1)
locks:clear()
-- Older queued conflicts are discarded; they never reappear after unlock.
local now,sent=0,{}
local queue=Queue.new({read=function() return {[13]=original} end,clock=function() return now end,
    valid=function() return true end,report=function(err) error(err) end,
    send=function(slot,item) sent[#sent+1]=item.localId end,
    allows=function(slot,item) return locks:allows(slot,item) end,
    observed=function(slot,item) locks:observe(slot,item) end,
    failed=function(slot,item) locks:failed(slot,item) end})
queue:submit({{slot=13,item=protected}})
queue:submit({{slot=13,item=original}})
locks:filter({request})
queue:ack(13,protected); queue:tick()
assert(#sent==1 and locks.slots[13] and #queue.batches==0)
doom=false; queue:tick(); assert(#sent==1)
assert(contexts>1)
doom=true; locks:clear()
queue.deps.report=function(message) errors[#errors+1]=message end
locks:filter({request})
queue:resync()
queue:submit({{slot=13,item=protected}})
for i=1,3 do now=now+0.8; queue:tick() end
assert(not locks.slots[13]) -- Repeated failed submissions cannot leave a pending lock.
factory.get=originalGet
print('PASS: compiled conditional locks, fresh contexts, pending/manual updates, errors, phase isolation and queued conflicts')
