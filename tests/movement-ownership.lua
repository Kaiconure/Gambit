local f=assert(io.open('lib/smart-move.lua'));local source=f:read('*a');f:close()
source=source:gsub("('[^'\r\n]*'):format",'(%1):format')
local mob={id=2,index=2,x=5,y=0,valid_target=true,hpp=100}
local env=setmetatable({V=function(value)return value end,
 require=function()return {zones={[1]={}}}end,
 windower={ffxi={get_info=function()return {zone=1}end,
 get_mob_by_index=function()return mob end,get_mob_by_target=function()return mob end,
 follow=function()end,run=function()end}},
 coroutine={schedule=function()end,sleep=coroutine.yield}}, {__index=_G})
local function new()
 local chunk=assert(loadstring(source));setfenv(chunk,env)
 local move=chunk();move:setLogger();return move
end
local move=new();local token,other={},{}
assert(move:moveTo(1,2,true))
assert(move:acquireMovement(token) and #move.queue==0)
assert(move:acquireMovement(token) and not move:acquireMovement(other))
local id=assert(move:moveTo(3,4,true,token))
assert(not move:moveTo(5,6,true) and not move:moveTo(5,6,true,other))
assert(not move:followIndex(2,1) and not move:moveBehindIndex(2))
assert(not move:cancelJob(id,true) and not move:cancelJob(nil,true,other))
assert(#move.queue==1 and move.queue[1].jobId==id)
assert(not move:reschedule(nil) and not move:releaseMovement(other))
assert(move:cancelJob(id,true,token)==nil and #move.queue==0)
assert(not move:canMove()) -- Ownership survives idle gaps.
assert(move:releaseMovement(token) and move:canMove() and move.previousJob==nil)
assert(move:moveTo(1,2,true))
-- A normal call suspended in cancellation cannot enqueue after ownership changes.
move=new();move.current={jobId=10,description='normal',is_valid=function()return true end}
local thread=coroutine.create(function()return move:moveTo(1,2)end)
assert(coroutine.resume(thread) and coroutine.status(thread)=='suspended')
assert(move:acquireMovement(token))
local owned=assert(move:moveTo(3,4,true,token))
move.cancel=false;move.current=nil
assert(coroutine.resume(thread)) -- Finishes cancellation's settling sleep.
assert(coroutine.resume(thread) and coroutine.status(thread)=='dead')
assert(#move.queue==1 and move.queue[1].jobId==owned)
move:stop();assert(move:canMove() and #move.queue==0 and move.previousJob==nil)
assert(move:acquireMovement(token));move:shutdown()
assert(move.movementOwner==nil and not move:acquireMovement(token))
print('PASS: exclusive tokens, starts/follows/resumes/cancellations, idle gaps, suspended-call race and lifecycle override')
