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
local resumedBounce=Route.new({mode='bounce',points={point(0,0),point(10,0),point(20,0)}},
    {x=20,y=0},20,{index=2,step=-1})
assert(resumedBounce.index==2 and resumedBounce.step==-1 and resumedBounce:point().x==10)

local cycle=Route.new({mode='cycle',corner_radius=2,tolerance=0.5,turn_pause=0.7,
    points={point(0,0),point(10,0,{corner_radius=3,pause=1,duration=4}),point(20,0)}},{x=1,y=0},10)
assert(cycle.index==1 and cycle:threshold(0.33)==2)
local transition=cycle:advance(11)
assert(cycle.index==2 and not transition.stop)
assert(cycle:threshold(0.33)==3 and not cycle:timedOut(14.9) and cycle:timedOut(15))
transition=cycle:advance(16)
assert(cycle.index==3 and transition.stop and transition.pause==1 and not transition.reversed)
cycle:advance(17);assert(cycle.index==1)
local resumedCycle=Route.new({mode='cycle',points={point(0,0),point(10,0),point(0,0)}},
    {x=0,y=0},20,{index=3,step=-1})
assert(resumedCycle.index==3 and resumedCycle.step==1)
local snapshot=resumedCycle:snapshot()
assert(snapshot.index==3 and snapshot.step==1)

local exact=Route.new({points={point(0,0,{tolerance=0.1}),point(1,0)},corner_radius=0},{x=0,y=0},0)
assert(exact:threshold(0.33)==0.1)
for _,bad in ipairs({{}, {points={}}, {mode='bad',points={point(0,0)}},
    {points={{x='0',y=0}}}, {points={point(0,0)},corner_radius=-1},
    {points={point(0,0,{pause=-1})}}}) do
    assert(not pcall(Route.new,bad,{x=0,y=0},0))
end
print('PASS: nearest and resumed starts, cycle/bounce transitions, endpoint turns, radii, pauses, durations and validation')

local file=assert(io.open('lib/smart-move.lua'))
local source=file:read('*a')
file:close()
source=source:gsub("('[^'\r\n]*'):format",'(%1):format')
local me={x=1,y=0}
local player={status=0}
local stops=0
local env=setmetatable({
    V=function(value) return value end,
    require=function(name)
        if name=='resources' then return {zones={[1]={}}} end
        return require(name)
    end,
    windower={ffxi={
        get_info=function() return {zone=1} end,
        get_player=function() return player end,
        get_mob_by_target=function() return me end,
        follow=function() end,
        run=function(value) if value==false then stops=stops+1 end end,
    }},
    coroutine={schedule=function() end,sleep=function() end},
},{__index=_G})
local chunk=assert(loadstring(source))
setfenv(chunk,env)
local move=chunk()
move:setLogger()
local config={points={point(0,0),point(10,0),point(20,0)}}
move:waypointRoute(config,nil,'test')
local running=move.queue[1]
move.current,move.previousJob,move.queue=running,running,{}
running:advance(0,1,0.33)
assert(move.waypointProgress.test.index==2)

config.points={point(40,0),point(50,0),point(60,0)}
local oldStops=stops
local replacement=move:waypointRoute(config,nil,'test')
assert(move.cancel and stops==oldStops+1 and move.previousJob==nil)
assert(move.queue[1]:pos()[1]==40 and replacement~=running.jobId)
assert(move:waypointRoute(config,nil,'test')==replacement, 'Refresh the queued replacement during cancellation')

local queued=move.queue[1]
move.current,move.previousJob,move.cancel=queued,queued,false
queued:advance(0,2,0.33)
assert(move.waypointProgress.test.index==2)

file=assert(io.open('Gambit.lua'))
local addonSource=file:read('*a')
local reload=assert(addonSource:match('(function reloadSettings%(.-\nend)'))
file:close()
local function noop() end
env.smartMove=move
env.settings={actions={}}
env.loadSettings=function(_, bypassActions)
    assert(bypassActions, 'Exercise settings-only reload with the same action configuration')
    return env.settings
end
env.profiling={begin=noop,start=noop,stop=noop,finish=noop}
env.executionFactory={clear=noop}
env.inventory={}
env.logging_settings={}
env.globals={}
env.isDebugging=function() return false end
env.actionStateManager={needsRecompile=true}
chunk=assert(loadstring(reload))
setfenv(chunk,env)
chunk()
oldStops=stops
env.reloadSettings(nil,true)
assert(move.cancel and stops==oldStops+1 and move.previousJob==nil and #move.queue==0)
assert(next(move.waypointProgress)==nil and next(move.waypointProgressByConfig)==nil)
move.current,move.cancel=nil,false
me.x=41
move:waypointRoute(config,nil,'test')
assert(move.queue[1]:pos()[1]==40, 'Start from the nearest point after resetting, even for the same route')

local positionJob={mode='position'}
move.current,move.previousJob,move.queue=positionJob,positionJob,{positionJob}
move:resetWaypointRoutes()
assert(move.current==positionJob and move.previousJob==positionJob and move.queue[1]==positionJob and not move.cancel)
print('PASS: route replacement, reset of running and queued routes, and preservation of other movement')

file=assert(io.open('lib/action-context.lua'))
local waypointHandler=assert(file:read('*a'):match('(context%.waypointRoute = function.-\n    end)'))
file:close()
local context={movementAvailable=function() return true end,vars={},scopes={}}
env.context=context
chunk=assert(loadstring(waypointHandler))
setfenv(chunk,env)
chunk()

for _, scoped in ipairs({true,false}) do
    move.current,move.previousJob,move.queue=nil,nil,{}
    move:resetWaypointRoutes()
    local route={scoped=scoped,points={point(0,0),point(10,0),point(20,0)}}
    context.vars.waypoints_ex={active='resume',data={resume=route}}
    context.scopes.battle=1
    me.x=19
    local started,id=context.waypointRoute()
    assert(started)
    local job=move.queue[1]
    move.current,move.previousJob,move.queue=job,job,{}
    job:advance(0,1,0.33)
    assert(job.routePlan.step==-1 and job:pos()[1]==10)

    me.x=18
    move:cancelJob(id,true)
    move.current,move.cancel=nil,false
    assert(move:reschedule(id), 'Resume automatically after an item-style interruption')
    job=move.queue[1]
    assert(job:pos()[1]==10 and job.routePlan.step==-1)

    move.current,move.previousJob,move.queue=job,job,{}
    context.scopes.battle=2
    local refreshed,nextId=context.waypointRoute()
    assert(refreshed and (nextId~=job.jobId)==scoped)
    job=scoped and move.queue[1] or move.current
    assert(job:pos()[1]==(scoped and 20 or 10))
    assert(job.routePlan.step==(scoped and 1 or -1))
end
print('PASS: temporary pauses preserve route progress, and a battle scope change resets scoped routes only')

move.current,move.previousJob,move.queue,move.cancel=nil,nil,{},false
move:resetWaypointRoutes()
local unscoped={scoped=false,corner_radius=3,points={point(0,0),point(10,0),point(20,0)}}
context.vars.waypoints_ex={active='resume',data={resume=unscoped}}
context.scopes.battle=3
me.x=10
assert(context.waypointRoute())
local outbound=move.queue[1]
assert(outbound:pos()[1]==20)
move.current,move.previousJob,move.queue=outbound,outbound,{}
move:stop()
move.current,move.cancel=nil,false

-- Battle ended inside the endpoint's corner radius, but short of arrival.
me.x=18
context.scopes.battle=4
assert(context.waypointRoute())
local resumed=move.queue[1]
assert(resumed:pos()[1]==20 and resumed.routePlan.step==1)
assert(not resumed:advance(2,1,0.33), 'Keep moving toward the saved endpoint after battle')
assert(resumed:advance(0.25,2,0.33).reversed and resumed:pos()[1]==10)
assert(resumed.routePlan:threshold(0.33)==3, 'Restore normal cornering after reaching the saved point')
print('PASS: unscoped battle resume keeps the saved endpoint even inside its corner radius')

local timed={duration=5,points={point(0,0,{duration=0}),point(10,0),point(20,0,{duration=2})}}
local plan=Route.new(timed,{x=0,y=0},0)
assert(plan:point().duration==0 and not plan:timedOut(100))
plan:advance(0)
assert(plan:point().duration==5 and not plan:timedOut(4) and plan:timedOut(5))
plan:advance(5)
assert(plan:point().duration==2 and plan:timedOut(7))

move.current,move.previousJob,move.queue,move.cancel=nil,nil,{},false
move:resetWaypointRoutes()
local now=0
env.os={clock=function() return now end}
env.coroutine.sleep=coroutine.yield
context.vars.waypoints_ex={active='timed',data={timed=timed}}
me.x=0
local function request() assert(context.waypointRoute()) end
local action=coroutine.create(request)
assert(coroutine.resume(action))
local leg=move.queue[1]
assert(leg.blocking and leg:pos()[1]==10 and coroutine.status(action)=='suspended')
move.current,move.queue=leg,{}
now=1
assert(coroutine.resume(action) and coroutine.status(action)=='suspended')
local arrival=leg:advance(0,now,0.33)
assert(arrival.finish and arrival.stop and leg:pos()[1]==20)
assert(coroutine.resume(action) and coroutine.status(action)=='dead')
assert(#move.queue==0, 'Leave the next leg to a later action request')

move.current=nil
me.x=10
action=coroutine.create(request)
assert(coroutine.resume(action))
leg=move.queue[1]
assert(leg.blocking and leg:pos()[1]==20)
move.current,move.queue=leg,{}
now=3
assert(coroutine.resume(action) and coroutine.status(action)=='dead' and move.cancel)
print('PASS: route duration defaults, point overrides, per-leg action wait, arrival and timeout')

file=assert(io.open('lib/commands.lua'))
local commands=assert(file:read('*a'):match("(handlers%['actions'%] = function.-\nend)"))
file:close()
env.handlers={}
env.arrayIndexOfStrI=function(args, value)
    for i, arg in ipairs(args) do if arg==value then return i end end
end
env.text_red=tostring
env.writeMessage=noop
env.loadActions=function() return {},'replacement.json' end
env.recompileActions=noop
env.saveSettings=noop
chunk=assert(loadstring(commands))
setfenv(chunk,env)
chunk()

for _, cancel in ipairs({
    function() move:stop() end,
    function() env.reloadSettings(nil,true) end,
    function() env.handlers.actions({'-off'}) end,
    function() env.handlers.actions({'-load','replacement'}) end,
}) do
    move.current,move.queue,move.cancel=nil,{},false
    action=coroutine.create(request)
    assert(coroutine.resume(action) and coroutine.status(action)=='suspended')
    leg=move.queue[1]
    move.current,move.queue=leg,{}
    cancel()
    assert(move.cancel)
    assert(coroutine.resume(action) and coroutine.status(action)=='dead')
end
print('PASS: automation stop, settings reload, actions off and action-set load release a timed leg')
