local inventory=require('./lib/inventory')
local Service=require('./lib/equipment/init')
local Runtime=require('./lib/events/runtime')
local Config=require('./lib/events/config')
local names={'Original','General','Specific','Body','Old Body','Mid Body'}
resources={items={}}
local items={equipment={left_ring=1,left_ring_bag=8,body=5,body_bag=8},wardrobe={}}
for id,name in ipairs(names) do
    resources.items[id]={id=id,name=name,flags={Equippable=true},slots={[id>=4 and 5 or 13]=true}}
    items.wardrobe[id]={id=id,slot=id,count=1,status=(id==1 or id==5) and 5 or 0}
end
extdata={decode=function() return {augments={}} end}
arrayAppend=function(t,v) t[#t+1]=v end
tableAll=function(t,fn) local r={}; for _,v in pairs(t or {}) do if fn(v) then r[#r+1]=v end end; return r end
findItem=function(query)
    if type(query)=='table' then query=query.name end
    for id,r in ipairs(resources.items) do if query==id or query==r.name then return r end end
end
local sent,errors,order,messages={},{},{},{}
windower={ffxi={get_items=function() return items end,
    set_equip=function(index,slot,bag) sent[#sent+1]={index=index,slot=slot,bag=bag} end},
    register_event=function(name) return name end,unregister_event=function() end}
local function manager()
    local result=Service.new({windower=windower,inventory=inventory,report=function(err) errors[#errors+1]=err end,
        verbose=function(message) messages[#messages+1]=message end})
    inventory.equipment_manager=result
    return result
end
local gear=manager()
local file=assert(io.open('lib/action-context.lua')); local source=file:read('*a'); file:close()
local body=assert(source:match('(    context.equip = function.-)%s*%-%- Push a stop request'))
body=body:gsub("('[^'\r\n]*'):format",'(%1):format')
local captured
local function context(_,state)
    local bound=state.equipment and state.equipment.inventory or inventory
    local ctx={vars=state.vars,mark=function(value) order[#order+1]=value end,
        findEquipmentInSlot=function(slot,confirmed) return bound.find_equipment_in_slot(slot,nil,confirmed) end,
        fail=function() error('phase failure') end,assert=assert}
    local chunk=assert(loadstring(body))
    setfenv(chunk,setmetatable({context=ctx,inventory=bound,Colors={},varargs=function(args) return args end,
        writeVerbose=function() end,pluralize=function() return '' end},{__index=_G}))
    chunk(); captured=state
    return ctx
end
local function runtime(pre,mid,post,useSnapshot)
    local config=Config.load({'test'},function() return {vars={
        general={ring1={name='General'},body={name='Body'}},specific={ring1={name='Specific'}},
        mid={body={name='Mid Body'}}},spells={use_equipment_snapshot=useSnapshot,pre=pre,mid=mid or {},post=post or {}}} end)
    return Runtime.new(config,{context=context,report=function(err) errors[#errors+1]=err end,
        clock=function() return 0 end,schedule=function() error('must reserve barrier without delay') end,
        barrier=function(fn) gear:barrier(fn) end,equipmentSession=function() return gear:session() end})
end
local function event() return {kind='spell',id=10,target={id=100}} end
local function ack(slot,index) gear.queue:ack(slot,{localId=index,bagId=8,id=index}) end
local run=runtime({
    {commands={'equipPush(vars.general)'}},
    {when={"findEquipmentInSlot('ring1').name == 'General'"},commands={'equipMany(vars.specific)'}},
    {commands={"assert(findEquipmentInSlot('ring1').name == 'Specific')",
        "assert(findEquipmentInSlot('ring1', true).name == 'Original')"}},
},{{commands={'equipMany(vars.mid)'}}},{{commands={'equipPop()'}}})
run:submit(event(),function() order[#order+1]='dispatch' end)
assert(#sent==2 and #gear.queue.batches==2) -- One equipment batch plus dispatch barrier.
assert(#messages==1 and messages[1]=='Queued equipment changes: 2') -- Layered pre calls report one batch.
for _,entry in ipairs(sent) do assert(entry.index~=2) end -- General ring never submitted.
assert(order[1]==nil and #captured.vars._.eq_stack==2)
ack(5,4); ack(13,3)
assert(order[1]=='dispatch' and #sent==3 and sent[3].index==6)
run:complete('spell',10,nil,'completed')
assert(#sent==3) -- Post restore stays behind mid gear.
ack(5,6)
assert(#sent==5 and sent[4].index==5 and sent[5].index==1)
ack(5,5); ack(13,1); gear.queue:tick()
assert(#gear.queue.batches==0 and #captured.vars._.eq_stack==0)
gear:destroy()

-- Cancellation discards uncommitted gear AND the pushes associated with it.
gear=manager(); sent={}
run=runtime({{commands={'equipPush(vars.general)',"cancelEvent('test')"}}},nil,
    {{commands={'equipPop()',"mark(event.outcome)"}}})
run:submit(event(),function() error('cancelled action dispatched') end)
assert(#sent==0 and order[#order]=='cancelled' and #captured.vars._.eq_stack==0)
gear:destroy()

gear=manager(); sent={}
run=runtime({{commands={'equipPush(vars.general)','fail()'}}},nil,{{commands={'equipPop()'}}})
run:submit(event(),function() error('failed pre dispatched') end)
assert(#sent==0 and #captured.vars._.eq_stack==0)
gear:destroy()

-- Mid errors discard only mid's plan and stack edits; post can restore pre.
gear=manager(); sent={}
run=runtime({{commands={'equipPush(vars.general)'}}},
    {{commands={'equipPush(vars.mid)','fail()'}}},{{commands={'equipPop()'}}})
run:submit(event(),function() end); ack(5,4); ack(13,2)
assert(#sent==2 and #captured.vars._.eq_stack==2)
run:complete('spell',10,nil,'completed')
assert(#sent==4 and #captured.vars._.eq_stack==0 and #errors>0)
gear:destroy()

-- A fast rejection cannot let inventory snapshots complete a pending restore.
gear=manager(); sent={}
local dispatched=false
run=runtime({{commands={'equipPush(vars.specific)'}}},nil,{{commands={'equipPop()'}}})
run:submit(event(),function() dispatched=true end)
items.equipment.left_ring=3
gear.queue:tick()
assert(not dispatched) -- Merely observing pre gear in cache is not an acknowledgment.
ack(13,3); assert(dispatched)
run:complete('spell',10,nil,'failed') -- Same cleanup path as a rejected roll.
assert(#sent==2 and sent[2].index==1)
items.equipment.left_ring=1
gear.queue:tick()
assert(#gear.queue.batches==1) -- Cached original gear cannot complete restoration.
ack(13,1); gear.queue:tick()
items.equipment.left_ring=3 -- Late pre snapshot must not undo the restore acknowledgment.
gear.queue:tick()
assert(inventory.find_equipment_in_slot('ring1',nil,true).name=='Original')
assert(#gear.queue.batches==0)
items.equipment.left_ring=1
gear:destroy()

-- Sessions are isolated from each other and from normal (immediate) callers.
gear=manager(); sent={}
run=runtime({
    {commands={'equipPush()','equipMany(vars.general)'}},
    {commands={'equipPush(vars.specific)',"assert(findEquipmentInSlot('ring1').name=='Specific')"}},
},nil,{
    {commands={'equipPop()',"assert(findEquipmentInSlot('ring1').name=='General')"}},
    {commands={'equipPop()',"assert(findEquipmentInSlot('ring1').name=='Original')",
        "assert(findEquipmentInSlot('body').name=='Old Body')"}},
})
run:submit(event(),function() end)
assert(#captured.vars._.eq_stack==3 and #sent==2)
for _,entry in ipairs(sent) do assert(entry.index~=2) end
ack(5,4); ack(13,3); run:complete('spell',10,nil,'completed')
assert(#sent==4 and #captured.vars._.eq_stack==0)
for _,entry in ipairs(sent) do assert(entry.index~=2) end
ack(5,5); ack(13,1); gear:destroy()

-- No-argument snapshot covers a later equip() of an originally empty slot.
gear=manager(); sent={}
run=runtime({{commands={"assert(equipPush({head={name='Not owned'}})==nil)",
    'equipMany(vars.general)'}}},nil,{{commands={'equipPop()'}}})
run:submit(event(),function() end)
assert(#captured.vars._.eq_stack==2)
ack(5,4); ack(13,2); run:complete('spell',10,nil,'completed')
assert(#sent==4 and sent[3].index==5 and sent[4].index==1)
gear:destroy()

-- No-argument snapshot covers a later equip() of an originally empty slot.
resources.items[7]={id=7,name='Hat',flags={Equippable=true},slots={[4]=true}}
items.wardrobe[7]={id=7,slot=7,count=1,status=0}
items.equipment.head=0; items.equipment.head_bag=0
gear=manager(); sent={}
run=runtime({{commands={'assert(equipPush())',"equip('head','Hat')"}}},nil,{{commands={'equipPop()'}}})
run:submit(event(),function() end)
assert(#sent==1 and sent[1].index==7)
ack(4,7); run:complete('spell',10,nil,'failed')
assert(#sent==2 and sent[2].index==0 and sent[2].slot==4)
gear:destroy()

-- Automatic lifecycle snapshots restore after post, independently of manual stacks.
for _,outcome in ipairs({'completed','interrupted','failed','timeout','reloaded','zoned','logout','unloaded'}) do
    gear=manager(); sent={}
    run=runtime({{commands={'equipMany(vars.specific)'}}},nil,
        {{commands={'equipPush(vars.general)'}}},true)
    run:submit(event(),function() end); ack(13,3)
    local request=run.pending[1]
    assert(#request.variables.vars._.eq_stack==1 and request.variables.vars._.eq_stack[1].event_baseline)
    run:finish(request,outcome)
    assert(#request.variables.vars._.eq_stack==0) -- All entries are discarded after baseline restoration.
    assert(request.finished and #run.pending==0)
    ack(5,4); ack(13,2) -- Post gear is followed by the original snapshot.
    assert(sent[#sent-1].index==5 and sent[#sent].index==1)
    ack(5,5); ack(13,1)
    assert(#gear.queue.batches==0)
    local count=#sent; run:finish(request,outcome); assert(#sent==count)
    gear:destroy()
end

-- Cancellation and rule errors still clean up, even when post itself fails.
for _,command in ipairs({"cancelEvent('test')",'fail()'}) do
    gear=manager(); sent={}
    run=runtime({{commands={'equipMany(vars.specific)',command}}},nil,
        {{commands={'equipMany(vars.general)','fail()'}}},true)
    run:submit(event(),function() error('cancelled action dispatched') end)
    assert(#sent==0 and #run.pending==0)
    gear:destroy()
end

-- A post error after committed pre gear cannot prevent restoration.
gear=manager(); sent={}
run=runtime({{commands={'equipMany(vars.specific)'}}},nil,{{commands={'fail()'}}},true)
run:submit(event(),function() end); ack(13,3)
run:complete('spell',10,nil,'completed')
assert(#sent==2 and sent[2].index==1)
gear:destroy()

-- Explicitly disabled snapshots leave final gear in place.
gear=manager(); sent={}
run=runtime({{commands={'equipMany(vars.specific)'}}},nil,nil,false)
run:submit(event(),function() end); ack(13,3)
run:complete('spell',10,nil,'completed'); assert(#sent==1)
gear:destroy()

-- Baseline pops work with either policy. Once consumed, a later push is not
-- mistaken for the baseline by automatic cleanup.
for _,automatic in ipairs({false,true}) do
    gear=manager(); sent={}
    run=runtime({{commands={'equipMany(vars.specific)'}}},nil,
        {{commands={'equipPop()',"assert(findEquipmentInSlot('ring1').name=='Original')",
            'equipPop()', 'equipPush(vars.general)'}}},automatic)
    run:submit(event(),function() end); ack(13,3)
    local request=run.pending[1]
    assert(#request.variables.vars._.eq_stack==1)
    run:complete('spell',10,nil,'completed')
    assert(#request.variables.vars._.eq_stack==0 and #sent==3)
    ack(5,4); ack(13,2)
    assert(#sent==3 and #gear.queue.batches==0) -- General gear intentionally stays.
    gear:destroy()
end

-- An extra baseline pop restores a later equip without any explicit push.
gear=manager(); sent={}
run=runtime({{commands={'equipMany(vars.specific)'}}},nil,{{commands={'equipPop()'}}},false)
run:submit(event(),function() end); ack(13,3)
run:complete('spell',10,nil,'completed')
assert(#sent==2 and sent[2].index==1)
gear:destroy()

-- Snapshot failure blocks before pre and never dispatches.
gear=manager(); sent={}
run=runtime({{commands={"mark('must not run')"}}})
local count=#order
run.deps.equipmentSession=function() return {inventory={snapshot_equipment=function() error('capture failed') end},
    discard=function() end} end
run:submit(event(),function() error('snapshot failure dispatched') end)
assert(#order==count and #sent==0 and #run.pending==0)
gear:destroy()

-- Sessions are isolated from each other and from normal (immediate) callers.
gear=manager(); sent={}
local first,second=gear:session(),gear:session()
first.inventory.equip_many({ring1={name='General'}})
assert(#sent==0 and first.inventory.find_equipment_in_slot('ring1').name=='General')
inventory.equip_many({ring1={name='Specific'}})
assert(#sent==1 and first.inventory.find_equipment_in_slot('ring1').name=='General')
assert(second.inventory.find_equipment_in_slot('ring1').name=='Specific')
first:discard(); second:discard()
assert(not pcall(first.inventory.equip_many,{ring1={name='General'}}))
gear:destroy(); inventory.equipment_manager=nil
print('PASS: phase merging, local queries, balanced push/pop, cancellation/error rollback, dispatch barrier and context isolation')
