-- Exercise the real smart-move submission inside the real event rule coroutine.
local f=assert(io.open('lib/smart-move.lua'));local source=f:read('*a');f:close()
source=source:gsub("('[^'\r\n]*'):format",'(%1):format') -- Windower string syntax.
local now=0
local actor={id=2,index=2,x=0,y=0,heading=0,hpp=100,valid_target=true}
local me={x=1,y=0}
local env=setmetatable({V=function(value)return value end,
 require=function(name)assert(name=='resources');return {zones={[1]={}}}end,
 windower={ffxi={get_info=function()return {zone=1}end,follow=function()end,run=function()end}},
 coroutine={schedule=function()end,sleep=coroutine.yield}}, {__index=_G})
local chunk=assert(loadstring(source));setfenv(chunk,env)
local move=chunk();move:setLogger()
-- An existing job must be preempted without waiting for the worker to stop it.
move.current={jobId=100,description='existing action movement',is_valid=function()return true end,
 pos=function()return {0,0}end}
local reactions=require('./lib/reactions')
local owner={}
local movement={available=function()return true end,mob=function()return actor end,
 me=function()return me end,clock=function()return now end,
 start=function(x,y)return move:moveTo(x,y,true,owner)end,
 cancel=function(id)move:cancelJob(id,true,owner)end,
 job=function(id)return move:getJobInfo(id,true)end}
reactions.attach({movement=movement,enabled=function()return true end,
 acquireMovement=function()return move:acquireMovement(owner)end,
 releaseMovement=function()move:releaseMovement(owner)end,
 clock=function()return now end,zone=function()return 1 end,
 player=function()return {vitals={hp=100}}end,mob=function()return actor end,
 me=function()return me end,cancelMovement=function()move:cancelJob(nil,true,owner)end,
 cancelReactionMovement=movement.cancel,faceAway=function()end,restore=function()end})
local Config=require('./lib/events/config')
local config=Config.load({'handoff'},function()return {enemy_abilities={pre={{
 when={'event.actor'},commands={"reactions.faceAway(event, {distance=20, angle='rear', wait=1})"}
}}}}end)
local reports={}
local Runtime=require('./lib/events/runtime')
local runtime=Runtime.new(config,{clock=function()return now end,
 context=function()return {reactions=reactions}end,
 report=function(message)reports[#reports+1]=message end})
runtime:observe({actor=actor,id=10,name='Thar She Blows',kind='enemy_ability',phase='pre'},'pre')
assert(#reports==0,table.concat(reports,'\n'))
assert(#move.queue==1 and move.queue[1].position[1]<-20)
local jobId=move.queue[1].jobId
assert(not move:canMove() and move:canMove(owner))
assert(not move:moveTo(50,50,true))
assert(not move:cancelJob(nil,true))
assert(not move:reschedule())
now=0.1;reactions.tick(true)
assert(#move.queue==1 and move.queue[1].jobId==jobId) -- Pending job is still owned.
-- Once dequeued, the same job remains owned without a restart.
local job=move.queue[1];move.queue={};move.current=job
now=0.2;reactions.tick(true);assert(move.current.jobId==jobId and #move.queue==0)
me.x=-21;reactions.tick(true)
assert(not move:canMove()) -- Safe position still holds ownership.
reactions.faceAway({actor=actor,id=11,kind='enemy_ability'},{wait=0})
reactions.observe({actor=actor,id=10,kind='enemy_ability',phase='post'})
now=0.8;reactions.tick(true);assert(not move:canMove()) -- Release wait.
now=1.3;reactions.tick(true);assert(not move:canMove()) -- Overlapping turning hold.
reactions.observe({actor=actor,id=11,kind='enemy_ability',phase='post'})
assert(move:canMove() and move.previousJob==nil)
-- A fresh hold acquires again; explicit lifecycle cleanup releases it.
reactions.faceAway({actor=actor,id=12,kind='enemy_ability'},{distance=30})
assert(not move:canMove())
reactions.clear();assert(move.cancel and #move.queue==0)
assert(move:canMove() and move.previousJob==nil)
print('PASS: real event runner submits and owns immediate smart-move jobs without yielding, including queued/current jobs')
