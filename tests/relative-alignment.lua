local relative=require('./lib/relative-alignment')
local function near(a,b) assert(math.abs(a-b)<0.00001,tostring(a)..' ~= '..tostring(b)) end
local target={x=10,y=20,z=3,heading=2}
local partner={x=12,y=20,heading=-1}
for _,case in ipairs({{0,15,20},{90,10,15},{180,5,20},{-90,10,25},{540,5,20}}) do
 local point=relative.point({mob=target},partner,case[1])
 near(point.x,case[2]);near(point.y,case[3]);assert(point.z==3)
end
near(relative.point(target,partner,180,10).x,0)
assert(not relative.point(target,target,180))
assert(not relative.point(nil,partner,180))
assert(not relative.point(target,partner,math.huge))
assert(not relative.point(target,partner,180,-1))
assert(not relative.point({x=0/0,y=0},partner,180))
-- Named arcs preserve valid bearings relative to the partner, not mob heading.
local origin={x=0,y=0,heading=2}
local leader={x=4,y=0}
local radians=170*math.pi/180
local observer={x=5*math.cos(radians),y=-5*math.sin(radians)}
for _,angle in ipairs({'aft','backside','180+/-30'}) do
 local point=relative.point(origin,leader,angle,5,observer)
 near(point.x,observer.x);near(point.y,observer.y)
end
local rotated=relative.point(origin,{x=0,y=4},'aft',5,{x=0,y=-5})
near(rotated.x,0);near(rotated.y,-5)
local side=relative.point(origin,leader,'side',5,{x=0,y=5})
near(side.x,0);near(side.y,5)
assert(not pcall(relative.point,origin,leader,'not-an-angle',5))

local mobs={[1]={id=1,index=1,x=0,y=0,valid_target=true,hpp=0},
 [2]={id=2,index=2,x=8,y=0,valid_target=true}}
local me={x=20,y=0}
local job,serial,starts,cancels,follows,lookups,moves=nil,0,0,0,0,0,0
local reserved,immobile=false,false
local expressionResult
local config={align_relative={target='???',activate_distance=5,release_distance=7,angle=180}}
local context={vars={follow_leader=config},party_leader={mob=mobs[2]},game_info={zone=1}}
context.movementAvailable=function()return not reserved end
context.findByName=function(name)lookups=lookups+1;assert(name=='???');return {mob=mobs[1]}end
context.execute=function(code)assert(code=='target()');return expressionResult end
context.following=function()return job and job.follow_index==2 end
context.follow=function(_,distance)
 follows=follows+1;serial=serial+1;job={jobId=serial,follow_index=2};return serial
end
context.move=function(point)moves=moves+1;assert(point.duration==3);me.x=point.x;me.y=point.y;return true end
relative.attach(context,{
 mob=function(id)return mobs[id]end,me=function()return me end,
 immobilized=function()return immobile end,tolerance=0.33,
 start=function(x,y) starts=starts+1;serial=serial+1;job={jobId=serial,position={x,y},queued=true};return serial end,
 job=function(id)if job and (not id or job.jobId==id)then return job end end,
 cancel=function(id)if job and job.jobId==id then cancels=cancels+1;job=nil end end,
})
assert(context.followLeader()) -- Leader too far away: normal following.
assert(follows==1 and starts==0)
mobs[2].x=5
assert(context.followLeader()) -- Alt's own distance does not gate activation.
assert(starts==1 and follows==1);near(job.position[1],-5)
assert(context.followLeader());assert(starts==1) -- Queued route is retained.
mobs[2].x=6
assert(context.followLeader());assert(starts==1) -- Active within release buffer.
me.x=-5
assert(context.followLeader());assert(job==nil and cancels==1)
assert(context.followLeader());assert(follows==1) -- Hold position; don't resume follow.
mobs[2].x=8
assert(context.followLeader());assert(follows==2)
mobs[2].x=6
assert(context.followLeader());assert(starts==1) -- Inactive: activation radius applies.
mobs[2].x=4;me.x=20
context.followLeader();assert(starts==2)
config.align_relative.target_expression='target()';expressionResult=false
local before=lookups
context.followLeader();assert(follows==3 and lookups==before) -- No name fallback.
expressionResult={x=0,y=0}
context.followLeader();assert(starts==3)
reserved=true;expressionResult=false
context.followLeader();assert(starts==3 and follows==3)
reserved=false;immobile=true
context.followLeader();assert(follows==3)
immobile=false;context.followLeader();assert(follows==4)
config.align_relative.target_expression=nil
config.align_relative.disabled=true
context.followLeader();assert(starts==3)
config.align_relative.disabled=false
mobs[1].valid_target=false;context.followLeader();assert(starts==3)
mobs[1].valid_target=true
mobs[2].x=0;context.followLeader();assert(starts==3) -- Coincident points: no guessed direction.
mobs[2].x=4
assert(context.alignRelative({mob=mobs[1]},{mob=mobs[2]},180))
near(me.x,-5);assert(moves==1)
assert(context.alignRelative({mob=mobs[1]},{mob=mobs[2]},180));assert(moves==1)
reserved=true;assert(not context.alignRelative(target,partner,180));reserved=false
assert(not context.alignRelative({id=999,x=0,y=0},partner,180))
assert(not context.alignRelative({id=1,index=999},partner,180))
-- No configuration preserves ordinary follow behavior.
context.followLeader(context.party_leader,{distance=2});assert(job.follow_index==2)
local beforeStarts,beforeFollows,beforeLookups=starts,follows,lookups
me.id=3;me.index=3
for _,selfTarget in ipairs({me,{mob=me},{id=3,index=3},{is_me=true}}) do
 local result,reason=context.followLeader(selfTarget,config)
 assert(result==false and reason=='self')
end
assert(starts==beforeStarts and follows==beforeFollows and lookups==beforeLookups)
-- Opt-in spawn-point retention bridges target disappearance before bt exists.
config.align_relative.hold_on_target_loss=true
mobs[2].x=4;me.x=-5
assert(context.followLeader());assert(job==nil)
local heldFollows=follows
mobs[1].valid_target=false
assert(context.followLeader());assert(job==nil and follows==heldFollows)
mobs[2].x=6
assert(context.followLeader());assert(job==nil and follows==heldFollows)
mobs[2].x=8
assert(context.followLeader());assert(follows==heldFollows+1)
-- Leaving the release radius clears the hold, even if the leader returns.
mobs[2].x=4
context.followLeader();assert(job.follow_index==2)
mobs[1].valid_target=true
context.followLeader();assert(job==nil)
mobs[1].valid_target=false;context.game_info.zone=2
context.followLeader();assert(job.follow_index==2)
print('PASS: relative geometry, confirmed positions, leader-distance hysteresis, route reuse/holding, expression precedence, target loss, reservations and follow fallback')
print('PASS: opt-in target-loss holding, release on leader departure and zone isolation')
-- Arc destinations stay stable in flight, and small leader shifts do not
-- dislodge a follower already within the arc.
context.game_info.zone=1;mobs[1].valid_target=true;mobs[2].x=4;mobs[2].y=0
config.align_relative.angle='aft';me.x=20;me.y=0
context.followLeader()
local route=job.jobId
me.x=0;me.y=5
context.followLeader();assert(job.jobId==route)
me.x=job.position[1];me.y=job.position[2]
context.followLeader();assert(job==nil)
local settledStarts=starts
mobs[2].y=0.1
context.followLeader();assert(job==nil and starts==settledStarts)
print('PASS: semantic angles, relative frame, stable arc routes and settled-position tolerance')
