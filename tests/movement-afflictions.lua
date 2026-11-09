local statuses=require('./lib/movement-afflictions')
for _,id in ipairs({2,19,7,10,11,28})do assert(statuses.active({buffs={id}}))end
assert(not statuses.active(nil) and not statuses.active({buffs={12,13,106}}))
local f=assert(io.open('lib/smart-move.lua'));local source=f:read('*a');f:close()
source=source:gsub("('[^'\r\n]*'):format",'(%1):format')
local block=assert(source:match('(local iteration = function.-)    while%s+continue'))
local buffs={10}
local runs={}
local env=setmetatable({windower={ffxi={get_player=function()return {buffs=buffs}end,
 get_mob_by_target=function()return {x=0,y=0}end,run=function(v)runs[#runs+1]=v end}},
 coordVector=function()error('normal movement resumed')end},{__index=_G})
local setup='local job={}; local jittering,shouldJitter=true,true; local jitterUntil=99; local speeds={0,0};local nextSpeed=3;local iterationTime=1;local now=0;local me\n'
local chunk=assert(loadstring(setup..block..'return iteration,function()return job.immobilized,#speeds,jittering,shouldJitter end'))
setfenv(chunk,env);local iteration,state=chunk()
assert(iteration()==0.15 and runs[1]==false)
local seen,count,jittering,shouldJitter=state()
assert(seen and count==0 and not jittering and not shouldJitter)
buffs={};local ok,err=pcall(iteration);assert(not ok and err:find('normal movement resumed',1,true))

f=assert(io.open('lib/action-context.lua'));source=f:read('*a');f:close()
block=assert(source:match('(context%.move = function.-)\n    %-%-%-%-'))
local context={movementAvailable=function()return true end,distanceTo=function()return 10 end,checkPosition=function()return false end}
local now,current=0,nil
local smart={getJobInfo=function()return current end,cancelJob=function()current=nil end,
 moveTo=function()current={jobId=1};return 1 end}
env=setmetatable({context=context,smartMove=smart,context_makeXYDO=function(p)return p end,
 windower={ffxi={get_mob_by_target=function()return {x=0,y=0}end,get_player=function()return {buffs={}}end}},
 os={clock=function()return now end},coroutine={sleep=function(dt)now=now+dt;current.immobilized=true end}},{__index=_G})
chunk=assert(loadstring(block));setfenv(chunk,env);chunk()
local arrived,reason=context.move({x=10,y=0,duration=1})
assert(not arrived and reason=='immobilized') -- Brief effects remain recorded after wearing off.
print('PASS: live disabling buffs, both Sleep IDs, jitter-history reset, recovery and immobilized timeout classification')
