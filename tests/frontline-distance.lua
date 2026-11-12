local json=require('./lib/jsonlua')
local scope=require('./lib/action-variable-scope')
local f=assert(io.open('actions/lib/frontline-engagement.json'))
local document=json.parse(f:read('*a'));f:close()
local action=document.actions[2]
assert(action.scope=='variable')
action.scopes={execution={}};scope.compile(action)
local config={distance=0.5,distance_offset=0.25,radius_multiplier=0.25}
local ctx=setmetatable({vars={frontline_engagement=config},bt={model_size=4},
 max=math.max,runningAsFunction=function()return false end,
 setVar=function(_,value)config._distance=value end},{__index=_G})
local command=assert(loadstring(action.commands[1]));setfenv(command,ctx)
local function tick()
 local snapshot=assert(scope.capture(action,ctx))
 if not scope.ready(action,snapshot)then return false end
 command();action.scopes.execution.variable=snapshot;return true
end
assert(tick() and config._distance==0.75)
ctx.bt.model_size=8;assert(not tick()) -- Target size is resolved by Smart Move.
config.distance_offset=0.5;assert(tick() and config._distance==1)
config.radius_multiplier=0;assert(tick() and config._distance==1)
config.radius_multiplier=nil;assert(tick() and config._distance==1)
config.distance=-5;assert(tick() and config._distance==0.125)
config.distance=nil;config.distance_offset=nil;assert(tick() and config._distance==0.5)

-- Load actual Smart Move geometry with a minimal vector and Windower host.
local methods={}
local function vec(v)return setmetatable(v,{__index=methods})end
function methods:add(v)return vec({self[1]+v[1],self[2]+v[2]})end
function methods:subtract(v)return vec({self[1]-v[1],self[2]-v[2]})end
function methods:scale(n)return vec({self[1]*n,self[2]*n})end
function methods:length()return math.sqrt(self[1]^2+self[2]^2)end
local me={x=10,y=0,model_size=2,valid_target=true}
local mob={id=1,index=1,x=0,y=0,heading=0,model_size=4,valid_target=true,hpp=100}
f=assert(io.open('lib/smart-move.lua'));local source=f:read('*a');f:close()
source=source:gsub("('[^'\r\n]*'):format",'(%1):format')
local env=setmetatable({V=vec,vector={from_radian=function(a)return vec({math.cos(a),-math.sin(a)})end},
 require=function(name)assert(name=='resources');return {zones={[1]={}}}end,
 windower={ffxi={get_mob_by_target=function()return me end,get_mob_by_id=function()return mob end,
 get_mob_by_index=function()return mob end,get_info=function()return {zone=1}end,
 follow=function()end,run=function()end}},
 coroutine={schedule=function()end,sleep=function()end}},{__index=_G})
local chunk=assert(loadstring(source));setfenv(chunk,env);local smart=chunk()
smart.verbose=function()end
smart:applySettings({useRawDistances=false,followOffset=0})
local options={radius_multiplier=0.25}
assert(smart:findMobOffset(mob,0,0.75,options)[1]==1.75)
assert(smart:followDistance(mob,0.75,options)==1.75)
assert(smart:findMobOffset(mob,0,0.75)[1]==3.75)
assert(smart:followDistance(mob,0.75)==5.25)
assert(smart:findMobOffset(mob,0,0.75,{radius_multiplier=0})[1]==0.75)
assert(smart:followDistance(mob,0.75,{radius_multiplier=-1})==0.75)
smart:applySettings({useRawDistances=true,followOffset=0})
assert(smart:findMobOffset(mob,0,0.75)[1]==0.75)
assert(smart:followDistance(mob,0.75)==0.75)
assert(smart:followDistance(mob,0.75,options)==1.75)
smart:applySettings({useRawDistances=false,followOffset=0})
smart:followIndex(1,0.75,options)
local job=smart.queue[1];assert(job.follow_distance==1.75)
job:reschedule();job=smart.queue[1];assert(job.follow_distance==1.75)
mob.model_size=8;job:pos();assert(job.follow_distance==2.75)
smart:followIndex(1,0.75);job=smart.queue[1];local legacy=job.follow_distance
job:reschedule();assert(smart.queue[1].follow_distance==legacy)
mob.model_size=4

-- Exercise alignment checks and actual destinations with the real geometry.
f=assert(io.open('lib/action-context.lua'));source=f:read('*a');f:close()
local block=assert(source:match('(local function alignmentPositionMatches.-)    context%.align2 ='))
local context={action={},movementAvailable=function()return true end}
context.move=function(pos)me.x,me.y=pos.x,pos.y;return true end
local alignEnv=setmetatable({context=context,alignment=dofile('lib/alignment.lua'),smartMove=smart,
 windower=env.windower,directionality={faceTarget=function()end}},{__index=_G})
chunk=assert(loadstring(block));setfenv(chunk,alignEnv);chunk()
assert(context.align(mob,0,0.75,3,false,0.01,options))
assert(me.x==1.75 and context.aligned(mob,0,0.75,0.01,options))
assert(not context.aligned(mob,0,0.75,0.01))
assert(context.align(mob,0,0.75,3,false,0.01))
assert(me.x==3.75)

-- Distance priority requires angular arrival once per battle.
local radial={radius_multiplier=0.25,distance_priority=true}
context.battleScope=1
me.x,me.y=1.75,0;mob.heading=math.pi
assert(not context.aligned(mob,0,0.75,0.01,radial))
assert(not context.aligned(mob,0,0.75,0.01,options))
local oldMove=context.move
context.move=function()return false,'cancelled'end
assert(not context.align(mob,0,0.75,3,false,0.01,radial))
assert(not context.aligned(mob,0,0.75,0.01,radial))
context.move=oldMove
assert(context.align(mob,0,0.75,3,false,0.01,radial))
assert(math.abs(me.x+1.75)<0.00001)
radial.arrived=true
mob.heading=0 -- Turning no longer requires circling.
assert(context.aligned(mob,0,0.75,0.01,radial))
context.battleScope=2;radial.arrived=false
assert(not context.aligned(mob,0,0.75,0.01,radial))
local getJobInfo=smart.getJobInfo
smart.getJobInfo=function()return {position={1.75,0}}end
assert(context.aligning(mob,0,0.75,0.01,radial))
assert(not context.aligned(mob,0,0.75,0.01,radial))
smart.getJobInfo=getJobInfo
assert(context.align(mob,0,0.75,3,false,0.01,radial))
assert(me.x==1.75)
radial.arrived=true
me.x=2
assert(context.aligned(mob,0,0.75,0.5,radial))
me.x=3
assert(not context.aligned(mob,0,0.75,0.5,radial))
assert(context.align(mob,0,0.75,3,false,0.01,radial))
assert(math.abs(me.x-1.75)<0.00001)
radial.arrived=false;mob.id=2;mob.heading=math.pi
assert(not context.aligned(mob,0,0.75,0.01,radial))
mob.id=1
mob.heading=0

config._distance=0.75;config.radius_multiplier=0.25
ctx.bt={distance=0,center_distance=3,model_size=4}
ctx.following=function()return false end
ctx.followDistance=function(t,d,o)return smart:followDistance(t,d,o)end
local condition=assert(loadstring('return '..document.actions[#document.actions-1].when));setfenv(condition,ctx)
assert(condition());ctx.bt.center_distance=1.75;assert(not condition())
config.distance_priority=true;config.tolerance=0.5
ctx.bt.center_distance=2;assert(not condition())
ctx.bt.center_distance=2.3;assert(condition())
config.distance_priority=false;ctx.bt.center_distance=2;assert(condition())
for _,a in ipairs(document.actions)do
 for _,key in ipairs({'when','commands'})do
  local expressions=a[key]
  if type(expressions)=='string'then expressions={expressions}end
  for _,expression in ipairs(expressions or {})do
   if not expression:match('^%-%-')then assert(loadstring('return '..expression))end
  end
 end
end
print('PASS: variable scope, real alignment/follow geometry, legacy/raw defaults, explicit multiplier/zero, resumption, live size and approach checks')
