local Queue=require('./lib/equipment/queue')
local Config=require('./lib/events/config')
local Runtime=require('./lib/events/runtime')
local function gear(id) return {id=id,localId=id,bagId=8} end
local sent,scheduled,order={},{},{}
local queue=Queue.new({read=function() return {[13]=gear(1)} end,clock=function() return 0 end,
    valid=function() return true end,send=function(_,item) sent[#sent+1]=item.id end,
    report=function(err) error(err) end})
local config=Config.load({'test'},function() return {spells={
    pre={{commands={'push()'}}},mid={{commands={'mid()'}}},post={{commands={'pop()'}}}}} end)
local runtime=Runtime.new(config,{clock=function() return 0 end,
    equipmentSession=function() return {inventory={snapshot_equipment=function() return {} end},discard=function() end,commit=function() end} end,
    context=function(_,state) return {
        push=function()
            state.vars.saved=queue:view()[13]
            queue:submit({{slot=13,item=gear(2)}})
        end,
        mid=function() order[#order+1]='mid'; queue:submit({{slot=13,item=gear(3)}}) end,
        pop=function() order[#order+1]='post'; queue:submit({{slot=13,item=state.vars.saved}}) end,
    } end,report=function(err) error(err) end,
    schedule=function(fn) scheduled[#scheduled+1]=fn end,
    barrier=function(fn) queue:barrier(fn) end})
runtime:submit({kind='spell',id=1,target={id=100}},function() order[#order+1]='dispatch' end)
assert(#scheduled==0) -- Barrier reservation has no scheduling gap after pre.
assert(#order==0 and sent[1]==2) -- Pre gear is unacknowledged: do not cast yet.
queue:ack(13,gear(2))
assert(table.concat(order,',')=='dispatch,mid' and sent[2]==3)
runtime:complete('spell',1,nil,'completed')
assert(order[3]=='post' and #sent==2) -- Post cannot overtake mid gear.
queue:ack(13,gear(3)); assert(sent[3]==1)
queue:ack(13,gear(1)); queue:tick()
assert(#queue.batches==0 and queue:view()[13].id==1)
print('PASS: event pre acknowledgment barrier, action dispatch, mid gear and post restoration ordering')
