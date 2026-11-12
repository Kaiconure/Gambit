local options={distance=17,distance_offset=1,angle='lefter',radius_multiplier=0,
 distance_priority=true,arrived=true,duration=4,tolerance=0.5}
local available,canAngle,reached,reason=true,true,true,nil
local calls,faces=0,0
local context={vars={frontline_engagement=options},bt={id=2,valid_target=true,hpp=100},action={},
 movementAvailable=function()return available end,canAlign=function()return canAngle end,
 faceEnemy=function()faces=faces+1 end,
 setVar=function(name,value)options[name:match('%.(.+)$')]=value end,
 align=function(target,angle,distance,duration,noFace,tolerance,actual)
  calls=calls+1
  assert(target.id==2 and distance==18 and duration==4 and not noFace and tolerance==0.5)
  assert(actual~=options and not actual.arrived and options._distance==18)
  assert(angle==(canAngle and 'lefter' or nil))
  return reached,reason
 end}
require('./lib/engagement-helpers').attach(context)
assert(context.frontlineEngage() and options.arrived and faces==1 and not context.action.incomplete)
available=false
assert(not context.frontlineEngage() and calls==1 and not context.action.incomplete)
available=true;reached=false;reason='immobilized'
local ok,why=context.frontlineEngage()
assert(not ok and why=='immobilized' and not context.action.incomplete and not options.arrived)
reached=true;canAngle=false
assert(context.frontlineEngage() and not context.action.incomplete)
-- Synchronous execution stays on the caller's coroutine, including movement waits.
context.align=function()coroutine.yield('moving');return true end
local thread=coroutine.create(function()assert(context.frontlineEngage());return 'done' end)
local resumed,value=coroutine.resume(thread);assert(resumed and value=='moving')
resumed,value=coroutine.resume(thread);assert(resumed and value=='done')
local secondary={distance=22,angle='backside',radius_multiplier=0,arrived=true}
context.align=function(target,angle,distance,_,_,_,actual)
 assert(target==context.bt and angle=='backside' and distance==22)
 assert(actual~=secondary and actual.arrived==false and actual.radius_multiplier==0)
 return true
end
canAngle=true
local originalDistance=options._distance
assert(context.applyEngagement(secondary))
assert(secondary.arrived==true and secondary._distance==nil and options._distance==originalDistance)
context.bt=nil;assert(not context.frontlineEngage() and not context.action.incomplete)
-- Dynamic member positioning works without a battle target and never forces facing.
context.vars.dynamic_engagement={model='member'}
local memberOptions={targets={'PLD'},distance=3,max_distance=25,tolerance=0.5}
context.vars.member_engagement=memberOptions
local member={id=3,distance=2,valid_target=true,hpp=100}
context.partyAnchorByName=function(targets,maximum,excludeSelf)
 assert(targets==memberOptions.targets and maximum==25 and excludeSelf);return member
end
local beforeFaces=faces
context.align=function()error('Already nearby; must not move farther away')end
assert(context.applyEngagement() and faces==beforeFaces)
member.distance=10
context.align=function(target,angle,distance,duration,noFace,tolerance,actual)
 assert(target==member and angle==nil and distance==3 and duration==3 and noFace and tolerance==0.5)
 assert(actual~=memberOptions);return true
end
assert(context.applyEngagement() and faces==beforeFaces)
assert(context.applyEngagement(memberOptions,'member'))
local success,why=context.applyEngagement({},'invalid')
assert(not success and why:find('unknown engagement model',1,true))
context.partyAnchorByName=function()return nil end
assert(not context.applyEngagement())
print('PASS: configured frontline positioning, ownership rejection, single-attempt failure without automatic retry, facing and synchronous yielding')
print('PASS: dynamic model selection, member targeting without battle target, proximity acceptance and no forced facing')
