local Wait=require('./lib/action-wait')
local Service=require('./lib/events/init')
local Config=require('./lib/events/config')
local now=0
local player={id=100}
local target={id=200,index=2,valid_target=true}
local resource={id=10,name='Test',en='Test',prefix='/ja'}
local barrier,injected
local service=setmetatable({deps={clock=function() return now end,
    windower={ffxi={get_player=function() return player end,get_mob_by_id=function() return target end}},
    resources={job_abilities={[10]=resource},weapon_skills={[10]=resource},spells={[10]=resource}},
    packets={build=function(packet) return packet end,parse=function(_,packet) return packet end},
    equipmentPending=function() return true end,
    barrier=function(fn) barrier=fn end,
    report=function(message) error(message) end},
    injections={},runtime={config=Config.load({'empty'},function() return {} end),pending={}}},Service)
function service:inject(packet) injected=packet; return true end
function service:consumeInjection() return false end
local record={}
Wait.register(record,'job_ability',10,200,now)
service:send({Category=9,Param=10,Target=200},record)
assert(record.queued and not record.outcome and not record.sent_at)
now=2; barrier(true)
assert(injected and record.sent_at==2)
now=2.5
service.runtime=nil -- Observation still works without configured runtime.
service:selfResultAction({category=6,actor_id=100,param=10,targets={{id=200,actions={{message=1}}}}})
assert(record.outcome=='completed' and record.completed_at==2.5)
Wait.release(record)
record={sent_at=now}
Wait.register(record,'weapon_skill',10,200,now)
service:incoming(0x029,{Actor=100,Message=88},nil,false,false)
assert(record.outcome=='failed','rejection must work without an event runtime')
Wait.release(record)
record={}
Wait.register(record,'job_ability',123,100,now)
record.sent_at=now
Wait.observe({kind='job_ability',id=98,target_id=100,phase='post',resource={type='CorsairRoll'},outcome='completed'},3)
assert(record.outcome=='completed','Double-Up result uses roll resource')
Wait.release(record)
print('PASS: no-rule equipment barrier, shared result/rejection without event runtime, Double-Up identity')
