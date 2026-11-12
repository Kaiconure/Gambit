local f=assert(io.open('lib/directionality.lua'));local source=f:read('*a');f:close()
source=source:gsub("('[^'\r\n]*'):format",'(%1):format')
local facing=assert(loadstring(source))().facing
local me={x=0,y=0,heading=0}
assert(facing(me,{x=5,y=0}))
assert(not facing(me,{x=-5,y=0}))
assert(not facing(me,{x=0,y=5}))
me.heading=-math.pi/2;assert(facing(me,{x=0,y=5},0))
me.heading=math.pi/2;assert(facing(me,{x=0,y=-5},0))
local function point(degrees)
 local r=degrees*math.pi/180;return {x=math.cos(r)*5,y=-math.sin(r)*5}
end
me.heading=0
assert(facing(me,point(10)) and facing(me,point(-10)))
assert(not facing(me,point(10.01)) and not facing(me,point(-10.01)))
assert(facing(me,point(15),20) and facing(me,point(15),-20))
me.heading=179*math.pi/180
assert(facing(me,point(-179),2) and not facing(me,point(-179),1))
me.heading=4*math.pi;assert(facing(me,point(0),0))
assert(facing({mob=me},{mob=point(0)}))
assert(facing({x=10,y=20,heading=0},{x=11,y=20})) -- No IDs required.
assert(not facing(me,me) and not facing(nil,point(0)))
assert(not facing({heading=0},point(0)) and not facing(me,{heading=0}))
assert(not facing({x=0,y=0},point(0)))
assert(not facing(me,point(0),'10'))
assert(not facing(me,{x=math.huge,y=0}) and not facing(me,point(0),0/0))
-- Verify the action-context entry point forwards both entities and tolerance.
f=assert(io.open('lib/action-context.lua'));source=f:read('*a');f:close()
local block=assert(source:match('(context%.facing = function.-)\n    end'))..'\n    end'
local env={context={},directionality={facing=facing}}
local chunk=assert(loadstring(block));setfenv(chunk,env);chunk()
assert(env.context.facing(me,point(0),0))
assert(not env.context.facing(me,point(20)))
print('PASS: generic facing, cardinal directions, angular boundaries/wraparound, context symbols, plain points and invalid inputs')
