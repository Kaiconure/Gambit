local reactions=require('./lib/reactions')
local Service=require('./lib/events/init')
local now=0
local actor={id=2,index=2,x=0,y=0,heading=0,hpp=100,valid_target=true}
local me={id=1,index=1,x=3,y=0,valid_target=true}
local enabled=true
reactions.attach({enabled=function()return enabled end,clock=function()return now end,
    player=function()return {vitals={hp=100}}end,zone=function()return 1 end,
    mob=function()return actor end,me=function()return me end,
    cancelMovement=function()end,faceAway=function()end,unlock=function()end,restore=function()end})
local event={actor=actor,id=10,kind='enemy_ability',phase='pre'}
local function start(extra)
    reactions.clear()
    local options={angle='sider',wait=3,allow_weapon_skills=true,allow_offensive_magic=true}
    for key,value in pairs(extra or {})do options[key]=value end
    assert(reactions.faceAway(event,options))
end
start({movement_priority=false});assert(not reactions.blocksAction('job_ability',{}))
start() -- Movement takes priority by default, without an explicit option.
for _,kind in ipairs({'spell','job_ability','weapon_skill','item','ranged_attack','pet_ability'})do
    assert(reactions.blocksAction(kind,{targets={Self=true}}))
end
-- No movement job is required: the gap before/between slices stays protected.
local packet={Category=9,Param=1,Target=1}
local injected=0
local service=setmetatable({runtime={},injections={},deps={clock=function()return now end,
    resources={job_abilities={[1]={id=1}},spells={},weapon_skills={}},
    packets={parse=function()return packet end,build=function()return 'headpayload'end,
        inject=function()injected=injected+1 end}}},Service)
for _,category in ipairs({2,3,5,7,9})do
    packet.Category=category
    assert(service:outgoing(0x01A,'raw','raw',false,false)==true)
    assert(service:inject(packet)==false and injected==0)
end
-- Already-permitted injections are rechecked if a reaction begins before echo.
packet.Category=9;service.injections={{payload='payload',expires=10}}
assert(service:outgoing(0x01A,'headpayload',nil,true,false)==true)
assert(#service.injections==0)
-- Targeted automation also rejects before registering or injecting an action.
windower={ffxi={get_mob_by_id=function()return me end}}
packets={new=function()error('Blocked request reached packet construction')end}
assert(not require('./lib/targeted-action').send(9,{id=1},1))
me.x=0;me.y=3
assert(not reactions.blocksActionsWhileMoving() and reactions.active())
packet.Category=9;assert(service:inject(packet) and injected==1)
-- A request selected at safety but held behind gear is cancelled if the enemy
-- turns before the dispatch callback, rather than waiting for a phantom result.
local queued
service.deps.barrier=function(fn)queued=fn end
service.deps.windower={ffxi={}}
service.runtime.config={rules={job_abilities={pre={},mid={},post={}}}}
service.deps.equipmentPending=function()return true end
service.deps.resources.job_abilities[1]={id=1}
packet.Category=9
local observation={}
assert(service:send(packet,observation) and queued)
actor.heading=math.pi/2
assert(reactions.blocksAction('spell',{targets={Self=true}})) -- enemy turned
queued(true)
assert(injected==1 and observation.outcome=='cancelled' and not observation.sent_at)
enabled=false;assert(not reactions.blocksActionsWhileMoving());enabled=true
now=1;reactions.observe({actor=actor,id=10,kind='enemy_ability',phase='post'})
assert(reactions.blocksActionsWhileMoving()) -- still unsafe during release wait
now=4;assert(not reactions.blocksActionsWhileMoving())
reactions.tick(true);assert(not reactions.active())
reactions.faceAway(event,{movement_priority=true,allow_weapon_skills=true,allow_offensive_magic=true})
assert(not reactions.blocksActionsWhileMoving()) -- Turning alone never blocks actions.
reactions.clear()
me.x=1;me.y=0;actor.heading=0;now=0
assert(reactions.faceAway(event,{distance=10,no_turn=true}))
assert(reactions.blocksActionsWhileMoving()) -- Distance-only retreat also defaults on.
assert(not pcall(reactions.faceAway,event,{movement_priority='true'}))
reactions.clear()
print('PASS: default movement priority, explicit opt-out, turn-only/distance-only rules, slice gaps, live safety/turns, release wait, expiry and dispatch guards')
