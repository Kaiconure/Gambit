local approach=require('./lib/approach-range')
local now,me,target,job,starts,stops,available,blocked,onSleep
local function reset()
 now=0;me={x=0,y=0};target={id=2,index=2,x=10,y=0,hpp=100,valid_target=true}
 job=nil;starts={};stops={};available=true;blocked=false;onSleep=nil
 return {clock=function()return now end,me=function()return me end,mob=function()return target end,
 available=function()return available end,immobilized=function()return blocked end,
 start=function(x,y)starts[#starts+1]={x=x,y=y};job={jobId=#starts};return job.jobId end,
 job=function()return job end,cancel=function(id)stops[#stops+1]=id;if job and job.jobId==id then job=nil end end,
 sleep=function(dt)now=now+dt;if onSleep then onSleep()end end}
end
local deps=reset()
onSleep=function()me.x=6 end
assert(approach.run(target,3,{range=4,duration=3},deps))
assert(#starts==1 and starts[1].x==7 and starts[1].y==0 and #stops==1 and now<0.1)
deps=reset();me.x=9
assert(approach.run(target,3,{range=4},deps) and #starts==0)
deps=reset();onSleep=function()me.x=7 end
assert(approach.run(target,3,{range=3},deps) and starts[1].x==7.5)
deps=reset();onSleep=function()if now<0.1 then target.x=12 else me.x=9 end end
assert(approach.run(target,3,{range=4},deps) and #starts==2 and starts[2].x==9)
deps=reset();local ok,reason=approach.run(target,3,{range=4,duration=0.2},deps)
assert(not ok and reason=='timeout' and #stops==1 and #starts==1)
deps=reset();onSleep=function()available=false;job={jobId=99}end
ok,reason=approach.run(target,3,{range=4},deps)
assert(not ok and reason=='reserved' and job.jobId==99)
deps=reset();onSleep=function()blocked=true end
ok,reason=approach.run(target,3,{range=4},deps);assert(not ok and reason=='immobilized')
deps=reset();onSleep=function()target.hpp=0 end
ok,reason=approach.run(target,3,{range=4},deps);assert(not ok and reason=='target unavailable')
deps=reset();onSleep=function()job=nil end
ok,reason=approach.run(target,3,{range=4},deps);assert(not ok and reason=='cancelled')
print('PASS: direct near-side approach, range arrival, live target refresh, timeout, interruption and owned cancellation')
