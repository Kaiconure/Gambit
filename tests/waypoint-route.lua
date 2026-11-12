local Route=require('./lib/waypoint-route')
local function point(x,y,options)
    options=options or {};options.x=x;options.y=y;return options
end
local bounce=Route.new({mode='bounce',points={point(0,0),point(10,0),point(20,0)}},{x=19,y=0},5)
assert(bounce.index==3 and bounce:point().x==20)
local turn=bounce:advance(6)
assert(bounce.index==2 and bounce.step==-1 and turn.reversed and turn.stop and turn.pause==0.35)
local middle=bounce:advance(7)
assert(bounce.index==1 and not middle.reversed and not middle.stop)
turn=bounce:advance(8)
assert(bounce.index==2 and bounce.step==1 and turn.reversed and turn.stop)

local cycle=Route.new({mode='cycle',corner_radius=2,tolerance=0.5,turn_pause=0.7,
    points={point(0,0),point(10,0,{corner_radius=3,pause=1,duration=4}),point(20,0)}},{x=1,y=0},10)
assert(cycle.index==1 and cycle:threshold(0.33)==2)
local transition=cycle:advance(11)
assert(cycle.index==2 and not transition.stop)
assert(cycle:threshold(0.33)==3 and not cycle:timedOut(14.9) and cycle:timedOut(15))
transition=cycle:advance(16)
assert(cycle.index==3 and transition.stop and transition.pause==1 and not transition.reversed)
cycle:advance(17);assert(cycle.index==1)

local exact=Route.new({points={point(0,0,{tolerance=0.1}),point(1,0)},corner_radius=0},{x=0,y=0},0)
assert(exact:threshold(0.33)==0.1)
for _,bad in ipairs({{}, {points={}}, {mode='bad',points={point(0,0)}},
    {points={{x='0',y=0}}}, {points={point(0,0)},corner_radius=-1},
    {points={point(0,0,{pause=-1})}}}) do
    assert(not pcall(Route.new,bad,{x=0,y=0},0))
end
print('PASS: nearest starts, cycle/bounce transitions, endpoint turns, radii, pauses, durations and validation')
