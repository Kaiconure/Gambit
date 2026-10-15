local alignment=dofile('lib/alignment.lua')
local function contains(value,angle) return alignment.contains(alignment.parse(value),angle) end
for name, angle in pairs({rear=180,face=0,front=0,facing=0}) do
    local spec=alignment.parse(' ' .. name:upper() .. ' ')
    assert(spec.exact==angle and spec.arcs==nil)
    local candidates=alignment.candidates(spec,45)
    assert(#candidates==1 and candidates[1]==angle)
end
assert(contains('backside',180) and not contains('backside',0))
assert(contains('frontside',350) and contains('330-30',0))
assert(contains('left',90) and contains('right',-90))
assert(contains('side',90) and contains('side',270) and not contains('side',180))
assert(contains('180+/-30',150) and contains('150-210',210))
assert(contains(nil,234) and contains(180,180) and not contains(180,181))
assert(alignment.bearing({x=0,y=0,heading=0},{x=0,y=-10})==90)
assert(not pcall(alignment.parse,'nonsense'))
assert(not pcall(alignment.parse,'180+/-181'))
local c=alignment.candidates(alignment.parse('side'),0,90)
assert(c[1]==90 and #c==5)
for _,a in ipairs(c) do assert(contains('side',a)) end
c=alignment.candidates(alignment.parse(nil),10)
assert(c[1]==10 and c[2]==55 and c[3]==-35)
assert(alignment.candidates(alignment.parse('backside'),165,200)[1]==165)

local f=assert(io.open('lib/action-context.lua'));local source=f:read('*all');f:close()
local block=assert(source:match('(local function alignmentPositionMatches.-)    context%.align2 ='))
local context={action={},battleScope=1,movementAvailable=function() return true end}
local mob={id=1,x=0,y=0,heading=0,valid_target=true,hpp=100}
local me={x=1,y=0}
local clock=0
local attempts={}
local mode='fallback'
local smart={tolerance=0.33,getJobInfo=function() return nil end}
function smart:findMobOffset(t,a,d)
    return {t.x+math.cos(t.heading+a)*d,t.y-math.sin(t.heading+a)*d}
end
context.move=function(pos)
    local x,y,duration=pos.x,pos.y,pos.duration
    attempts[#attempts+1]={x=x,y=y,duration=duration}
    attempts[#attempts].tolerance=pos.tolerance
    clock=clock+duration
    if mode=='cancel' then return nil,'cancelled' end
    if mode=='moving' then mob.x=mob.x+1;return nil,'timeout' end
    if mode=='success' then me.x,me.y=x,y;return true end
    if mode=='fail' or #attempts==1 then return nil,'timeout' end
    me.x,me.y=x,y
    return true
end
context.postpone=function() end
local env=setmetatable({context=context,alignment=alignment,smartMove=smart,
    windower={ffxi={get_mob_by_target=function() return me end,get_mob_by_id=function() return mob end}},
    directionality={faceTarget=function() end},os={clock=function() return clock end}}, {__index=_G})
local chunk=assert(loadstring(block));setfenv(chunk,env);chunk()
me.x,me.y=-10,0.2
assert(context.aligned(mob,'rear',10) and context.aligned(mob,180,10))
me.y=0.5
assert(not context.aligned(mob,'rear',10))
me.x,me.y=10,0.2
for _,name in ipairs({'face','front','facing'}) do assert(context.aligned(mob,name,10)) end
me.x,me.y=1,0
assert(context.align(mob,nil,10,3))
assert(#attempts==2 and context.aligned(mob,nil,10))
assert(clock<=3)
me.x,me.y=1,0;attempts={};mode='cancel'
assert(not context.align(mob,'backside',10,3) and #attempts==1)
local preferred=context.action._alignment.preferred
attempts={};context.align(mob,'backside',10,3)
assert(context.action._alignment.preferred==preferred)
mode='fail';attempts={};clock=0
assert(not context.align(mob,180,10,3) and #attempts==1)
mode='fallback';attempts={};clock=0
assert(context.align(mob,'side',10,3) and #attempts==2)
assert(context.aligned(mob,'side',10))
assert(not context.aligned(mob,'frontside',10))
me.x,me.y=-10.4,0
assert(not context.aligned(mob,'backside',10))
assert(context.aligned(mob,'backside',10,0.5))
mode='success';attempts={};clock=0;me.x,me.y=-12,0
assert(context.align(mob,'backside',10,3,false,0.5))
assert(#attempts==1 and attempts[1].tolerance==0.5 and math.abs(attempts[1].y)<0.0001)
mode='moving';attempts={};clock=0;me.x,me.y=1,0
assert(not context.align(mob,'backside',10,3,false,0.5) and #attempts==1)
print('PASS: angle parsing, signed geometry, arcs, fallback, budget, cancellation and stable preference')

local moveBlock=assert(source:match('(context%.move = function.-)\n    %-%-%-%-'))
local movement={movementAvailable=function() return true end}
local current, nextId, elapsed, gap, cancelCount, replace = nil,0,0,10,0,false
local movementSmart={}
function movementSmart:getJobInfo() return current end
function movementSmart:moveTo(x,y)
    nextId=nextId+1;current={jobId=nextId,mode='position',position={x,y}};return nextId
end
function movementSmart:cancelJob() current=nil;cancelCount=cancelCount+1 end
movement.distanceTo=function() return gap end
movement.checkPosition=function() return gap<1 end
local moveEnv=setmetatable({context=movement,smartMove=movementSmart,
    context_makeXYDO=function(pos) return pos end,
    windower={ffxi={get_mob_by_target=function() return {x=0,y=0} end}},
    os={clock=function() return elapsed end},
    coroutine={sleep=function(dt)
        elapsed=elapsed+dt
        if replace then current={jobId=-1};replace=false end
    end}}, {__index=_G})
chunk=assert(loadstring(moveBlock));setfenv(chunk,moveEnv);chunk()
local ok,reason=movement.move({x=10,y=0,duration=1})
assert(not ok and reason=='timeout' and elapsed==1 and cancelCount==1)
elapsed=0;replace=true;cancelCount=0
ok,reason=movement.move({x=10,y=0,duration=1})
assert(not ok and reason=='cancelled' and cancelCount==0)
gap=0.7;elapsed=0
assert(movement.move({x=10,y=0,duration=1})) -- Legacy arrival tolerance.
elapsed=0
ok,reason=movement.move({x=10,y=0,duration=1,tolerance=0.33})
assert(not ok and reason=='timeout') -- Flexible alignment needs tighter arrival.
gap=0.1
assert(movement.move({x=10,y=0,duration=1,tolerance=0.33}))
print('PASS: move timeout/cancellation reasons and optional alignment arrival tolerance')
