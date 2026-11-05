local Trace=require('./lib/events/weapon-skill-trace')
local Queue=require('./lib/equipment/queue')
local Runtime=require('./lib/events/runtime')
local Config=require('./lib/events/config')
local Service=require('./lib/events/init')
local now=0
local function item(id) return {id=id,localId=id,bagId=8} end
Trace.record('disabled',{x=1}); assert(not Trace.stop())
Trace.start(function() return now end)
local sent={}
local queue=Queue.new({clock=function() return now end,read=function() return {[13]=item(1)} end,
    valid=function() return true end,send=function(_,gear) sent[#sent+1]=gear.id end,
    report=function(err) error(err) end})
local function snapshot() return {confirmed={ring1=queue:view(true)[13]},planned={ring1=queue:view()[13]}} end
local config=Config.load({'test'},function() return {weapon_skills={
    pre={{commands={'pre()'}}},post={{commands={'post()'}}}}} end)
local runtime=Runtime.new(config,{clock=function() return now end,traceEquipment=snapshot,
    report=function(err) error(err) end,barrier=function(fn) queue:barrier(fn) end,
    equipmentSession=function() return {inventory={snapshot_equipment=function() return {} end},
        commit=function() end,discard=function() end} end,
    context=function() return {pre=function() queue:submit({{slot=13,item=item(2)}}) end,
        post=function() queue:submit({{slot=13,item=item(1)}}) end} end})
local packet={Category=7,Param=42,Target=200}
local service=Service.new({resources={weapon_skills={[42]={id=42}},job_abilities={}},
    clock=function() return now end,traceEquipment=snapshot,
    windower={ffxi={get_player=function() return {id=100,name='Tester'} end},register_event=function() end},
    packets={build=function() return 'HEADpayload' end,inject=function() end}})
service.runtime=runtime
runtime:submit({kind='weapon_skill',id=42,name='Savage Blade',target={id=200}},function() service:inject(packet) end)
assert(#sent==1 and sent[1]==2)
now=0.4; queue:ack(13,item(2))
now=1.2
service:selfResultAction({actor_id=100,category=3,param=42,targets={{id=200,actions={{message=0,param=100}}}}})
assert(sent[2]==1)
now=1.5; queue:ack(13,item(1)); queue:tick()
local result=Trace.stop()
local dispatch,resultIndex,restoreIndex,preAck
for index,row in ipairs(result.entries) do
    assert(row.step==index)
    if row.kind=='equipment_ack' and row.item.id==2 then preAck=index end
    if row.kind=='dispatch' then
        dispatch=index; assert(row.equipment.confirmed.ring1.id==2 and row.time==0.4)
    end
    if row.kind=='result' then
        resultIndex=index; assert(row.equipment.confirmed.ring1.id==2)
    end
    if row.kind=='equipment_send' and row.item.id==1 then restoreIndex=index end
end
assert(preAck<dispatch and dispatch<resultIndex and resultIndex<restoreIndex)
assert(not Trace.active())
-- Data is copied: later snapshot mutation must not change the capture.
queue.confirmed[13].id=99
assert(result.entries[dispatch].equipment.confirmed.ring1.id==2)
Trace.start(function() return now end)
for i=1,2050 do Trace.record('bounded',{value=i}) end
result=Trace.stop(); assert(result.truncated and #result.entries==2048)
local writes={}
service.deps.writeProcessed=function(path,value) writes[#writes+1]={path,value} end
assert(service:weaponSkillTrace('start'):find('started',1,true))
Trace.record('sample',{equipment={confirmed={['0']=item(5),['13']=item(2)}}})
assert(service:weaponSkillTrace('stop'):find('.output/ws-trace-',1,true))
local encoded=require('./lib/jsonlua').stringify(writes[1][2])
local decoded=require('./lib/jsonlua').parse(encoded)
assert(decoded.entries[1].equipment.confirmed['0'].id==5)
assert(service:weaponSkillTrace('stop')=='No weapon skill trace is active.')
print('PASS: opt-in bounded WS trace, acknowledgment-before-dispatch, result-before-restoration, snapshots and JSON export')
