local reactions=require('./lib/reactions')
local driver=require('./lib/reaction-movement')
local now,me,actors,current,started,allowed,onSleep,onStart,turns,cancelled,reactionDeps
local function reset()
 now=0;me={x=1,y=0,model_size=100};actors={
 [2]={id=2,index=2,x=0,y=0,heading=0,hpp=100,valid_target=true,model_size=100},
 [3]={id=3,index=3,x=0,y=5,heading=0,hpp=100,valid_target=true}}
 current=nil;started={};allowed=true;onSleep=nil;onStart=nil;turns=0;cancelled={}
 local function cancel(id)
  cancelled[#cancelled+1]=id or 'all'
  if current and (not id or current.jobId==id)then current=nil end
 end
 reactionDeps={clock=function()return now end,player=function()return {vitals={hp=100}}end,
 enabled=function()return true end,zone=function()return 1 end,mob=function(id)return actors[id]end,me=function()return me end,
 cancelMovement=function()cancel(nil)end,cancelReactionMovement=cancel,
 unlock=function()end,faceAway=function()turns=turns+1 end,restore=function()end}
 reactions.attach(reactionDeps)
 return {available=function()return allowed end,me=function()return me end,mob=function(id)return actors[id]end,
 clock=function()return now end,cancel=cancel,job=function()return current end,
 start=function(x,y)
  local id=#started+1;started[id]={x=x,y=y};current={jobId=id}
  if onStart then onStart()end
  return id
 end,
 sleep=function(dt)now=now+dt;if onSleep then onSleep()end end}
end
local function start(distance,extra,actor)
 local options={distance=distance,wait=0,timeout=10}
 for k,v in pairs(extra or {})do options[k]=v end
 reactions.faceAway({actor={id=actor or 2,index=actor or 2},id=10,kind='enemy_ability'},options)
end
local function release(actor)
 reactions.observe({actor={id=actor or 2},id=10,kind='enemy_ability',phase='post'})
end
local deps=reset();start(20,{radius_multiplier=100})
assert(#started==0) -- Detection never starts yielding movement.
local before=turns
onSleep=function()
 assert(current and current.jobId==1) -- Tick must not cancel owned movement.
 me.x=started[1].x;me.y=started[1].y
end
assert(driver.run(deps) and started[1].x==20.5 and started[1].y==0)
assert(me.x>=20 and current==nil and turns>before)
now=now+1;assert(not driver.run(deps) and #started==1) -- Never approach if already safe.
release();assert(not reactions.active())

deps=reset();start(20)
onSleep=function()release()end
assert(driver.run(deps) and not reactions.active() and current==nil)
deps=reset();start(20)
onStart=function()release()end -- Release while Smart Move is starting/yielding.
assert(driver.run(deps) and current==nil and not reactions.active())
deps=reset();start(20)
onSleep=function()actors[2].hpp=0 end
assert(driver.run(deps) and current==nil and not reactions.active())
deps=reset();start(20)
assert(driver.run(deps) and now>=0.5 and current==nil) -- Bounded blocked route.
assert(not driver.run(deps)) -- Brief retry gap allows normal actions.
now=now+0.3;assert(driver.run(deps) and #started==2)

deps=reset();start(20);allowed=false
assert(not driver.run(deps) and #started==0)
deps=reset();start(20,{no_turn=true})
assert(reactions.blocksMovement() and turns==0)
assert(driver.run(deps) and turns==0)
deps=reset();me.x=0;me.y=0;start(20)
assert(driver.run(deps) and started[1].x==20.5) -- Coincident centers have a finite escape direction.
deps=reset();start(20)
onSleep=function()allowed=false end
assert(driver.run(deps) and now<0.5 and current==nil)

deps=reset();start(20)
reactions.faceAway({actor={id=2,index=2},id=11,kind='enemy_ability'},{distance=10})
assert(reactions.distanceRequest().options.distance==20) -- Strongest minimum for one enemy.
start(15,nil,3)
assert(reactions.distanceRequest().actor.id==3) -- Newest distance enemy wins.
release(3);assert(reactions.distanceRequest().actor.id==2)
assert(not pcall(start,-1))
assert(not pcall(start,math.huge))
-- Angle and distance must both be satisfied; heading remains target-relative.
deps=reset();start(20,{angle=180})
onSleep=function()me.x=started[1].x;me.y=started[1].y end
assert(driver.run(deps) and math.abs(started[1].x+20.5)<0.00001)
assert(math.abs(started[1].y)<0.00001)
now=now+1;assert(not driver.run(deps))
actors[2].heading=math.pi;onSleep=nil
assert(driver.run(deps) and started[2].x>20)
deps=reset();me.x=30;start(20,{angle='rear'})
assert(driver.run(deps) and math.abs(started[1].x+30)<0.00001)
deps=reset();me.x=-30;start(20,{angle='backside'})
assert(not driver.run(deps) and #started==0)
for _,angle in ipairs({'side','left','right','180+/-30','150-210'})do
 deps=reset();start(20,{angle=angle})
 assert(driver.run(deps))
 assert(require('./lib/alignment').contains(require('./lib/alignment').parse(angle),
  require('./lib/alignment').bearing(actors[2],started[1])))
end
deps=reset();start(20,{angle='rear'})
onSleep=function()me.x=25 end -- At safe distance, but on the wrong side.
assert(driver.run(deps) and now>=0.5)
assert(not pcall(start,20,{angle='invalid'}))
-- Angle-only holds capture raw horizontal radius at the trigger, before movement is available.
deps=reset();me.x=12;me.y=5;allowed=false
start(nil,{angle='rear',no_turn=true})
assert(reactions.distanceRequest().options.distance==13 and reactions.blocksMovement())
assert(not driver.run(deps))
me.x=20;me.y=0
start(nil,{angle='rear',no_turn=true}) -- Duplicate readying must not recapture.
assert(reactions.distanceRequest().options.distance==13)
allowed=true
assert(driver.run(deps) and math.abs(started[1].x+20)<0.00001)
assert(math.abs(started[1].y)<0.00001)
deps=reset();me.x=-13;start(nil,{angle='rear'})
assert(not driver.run(deps) and #started==0)
deps=reset();me.x=0;me.y=0;start(nil,{angle='rear'})
assert(reactions.distanceRequest().options.distance==0)
assert(not driver.run(deps)) -- At zero radius every bearing is within positional tolerance.
deps=reset();me.x=nil
assert(not reactions.faceAway({actor={id=2,index=2},id=10,kind='enemy_ability'},{angle='rear'}))
assert(not reactions.active())
-- Production event/frame path starts without the action loop or any yielding.
deps=reset();reactionDeps.movement=deps
deps.sleep=function()error('Immediate reactions must not yield')end
start(20,{angle='rear'})
assert(#started==1 and current and reactions.immediateMovement())
now=0.1;reactions.tick(true);assert(#started==1)
me.x=-21;reactions.tick(true);assert(not current)
actors[2].heading=math.pi;now=0.4;reactions.tick(true)
assert(#started==2 and current) -- Repositions from frame ticks while actions are busy.
allowed=false;reactions.tick(true);assert(not current)
allowed=true;now=0.8;reactions.tick(true);assert(current)
release();assert(not current and not reactions.active())
deps=reset();reactionDeps.movement=deps
start(20,{no_turn=true});assert(current)
actors[2].hpp=0;reactions.tick(true);assert(not current and not reactions.active())
reactions.clear()
local f=assert(io.open('lib/action-processing.lua'));local source=f:read('*a');f:close()
local scheduler=assert(source:match('(function processNextAction.-)\nlocal function doNextActionCycle'))
local requested=true
local selected,executed=0,0
local env={globals={enabled=true},getNextBattleAction=function()selected=selected+1;return {}end,
 executeBattleAction=function(_,action)executed=executed+1;return action end}
local fn=assert(loadstring(scheduler));setfenv(fn,env);fn()
local ctx={reactions={respond=function()return requested end}}
assert(env.processNextAction(ctx).name=='reaction-distance' and selected==0 and executed==0)
requested=false;assert(env.processNextAction(ctx) and selected==1 and executed==1)
requested=true;env.globals.actionsEnabled=false
assert(env.processNextAction(ctx) and selected==2 and executed==2)
env.globals.enabled=false;assert(env.processNextAction(ctx)==nil and selected==2)
print('PASS: raw center minimum, outward-only retreat, event/runner separation, owned jobs, release/start/death cancellation, bounded retries, movement restrictions, no_turn and overlap policy')
