local style=require('./lib/follow-style')
local names={'Carbonite','Ladrian','Miyajima','Steris','Gavilar','Aidelle'}
local profiles={}
for _,name in ipairs(names)do
    local a,b=style.profile(name),style.profile(name:upper())
    assert(a.distance==b.distance and a.resume==b.resume and a.lateral==b.lateral)
    assert(a.distance>=0.15 and a.distance<=0.75 and a.resume>=0.75 and a.resume<=1.35)
    assert(a.lateral>=-1 and a.lateral<=1)
    profiles[a.distance..':'..a.resume..':'..a.lateral]=true
end
local count=0;for _ in pairs(profiles)do count=count+1 end;assert(count==#names)
assert(style.heading(0,0.05,10)==0)
assert(style.heading(0,math.pi/2,10)==math.pi/2) -- sharp turns immediately
assert(style.heading(0,0.05,2)==0.05) -- exact steering near destination
assert(style.heading(nil,0.05,10)==0.05)
assert(style.heading(math.pi-0.01,-math.pi+0.01,10)==math.pi-0.01)

-- Exercise real follow jobs, including spacing, catch-up and combat isolation.
local Vector={};Vector.__index=Vector
local function V(value)return setmetatable({value[1],value[2]},Vector)end
function Vector:add(b)return V{self[1]+b[1],self[2]+b[2]}end
function Vector:subtract(b)return V{self[1]-b[1],self[2]-b[2]}end
function Vector:scale(n)return V{self[1]*n,self[2]*n}end
function Vector:length()return math.sqrt(self[1]^2+self[2]^2)end
local me={name='Carbonite',id=1,index=1,x=0,y=0,status=0,heading=0,valid_target=true}
local target={id=2,index=2,x=5,y=0,heading=0,model_size=0,spawn_type=13,hpp=100,valid_target=true}
local file=assert(io.open('lib/smart-move.lua'));local source=file:read('*a');file:close()
source=source:gsub("('[^'\r\n]*'):format",'(%1):format')
local turns=0
local env=setmetatable({V=V,vector={from_radian=function(angle)return V{math.cos(angle),math.sin(angle)}end},windower={ffxi={get_mob_by_target=function()return me end,
    get_mob_by_index=function()return target end,get_info=function()return {zone=1}end,
    follow=function()end,run=function()end,turn=function()turns=turns+1 end}},
    require=function(name)if name=='resources' then return {zones={[1]={}}} end;return require(name)end,
    coroutine={schedule=function()end,sleep=function()end}}, {__index=_G})
local chunk=assert(loadstring(source));setfenv(chunk,env)
local move=chunk();move:setLogger();move:applySettings({followOffset=1})
assert(move:followIndex(2,2,{radius_multiplier=0}))
local job=move.queue[1]
assert(job.naturalFollow and job.followStyle.distance==style.profile('Carbonite').distance)
local point=job:pos()
assert(point[1]>0 and math.abs(point[2])>0)
target.x=20
point=job:pos();assert(point[1]==20 and point[2]==0) -- direct catch-up
target.x=5;me.status=1;assert(job:cycle() and not job.naturalFollow)
target.spawn_type=16;me.status=0;assert(job:cycle() and not job.naturalFollow)
target.spawn_type=13;assert(job:cycle() and job.naturalFollow)
job:oncomplete();assert(turns==0) -- no final target-facing turn
-- Exercise stop/pause/restart in the actual movement loop, not just completion.
local block=assert(source:match('(local iteration = function.-)    while%s+continue'))
env.self=move;env.job=job;env.followStyle=style
env.MAX_SPEEDS=20;env.MIN_AVERAGING=20;env.JITTER_ENABLED=false
env.coordVector=function(value)return V{value.x,value.y}end
env.vectorAngle=function(value)return math.atan2(-value[2],value[1])end
env.sharesHalfspace=function()return true end
local destination=0.1
job.pos=function()return V{destination,0}end
local runs={}
env.windower.ffxi.run=function(value)runs[#runs+1]=value end
local setup=[[local paused=false;local jittering,shouldJitter=false,false;local jitterUntil=0
local speeds={};local nextSpeed=1;local iterationTime=0;local now=0;local hdg=0
local me=windower.ffxi.get_mob_by_target('me')
local vme=coordVector(me)
]]
local finish='return function() iterationTime=0.15;return iteration() end'
local factory=assert(loadstring(setup..block..finish))
setfenv(factory,env);local iteration=factory()
iteration();assert(#runs==1 and runs[1]==false and turns==0)
destination=job.followStyle.resume*0.8
iteration();assert(#runs==1 and turns==0) -- holds still rather than micro-stepping/turning
destination=job.followStyle.resume+0.5
iteration();assert(#runs==2 and type(runs[2])=='number' and turns==1)
job.naturalFollow=false;destination=0.1
factory=assert(loadstring(setup..block..finish));setfenv(factory,env)
iteration=factory();iteration();assert(turns==2) -- ordinary alignment still turns
print('PASS: stable character spacing/thresholds, heading deadband, sharp/near turns, direct catch-up, combat isolation and stopped facing')
