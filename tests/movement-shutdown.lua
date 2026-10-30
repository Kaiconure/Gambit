local file=assert(io.open('lib/smart-move.lua'))
local source=file:read('*a'); file:close()
source=source:gsub("('[^'\r\n]*'):format",'(%1):format')
local scheduled,commands={},{}
local env=setmetatable({
    V=function(value) return value end,
    require=function(name) assert(name=='resources'); return {zones={}} end,
    windower={ffxi={
        follow=function(value) commands[#commands+1]={'follow',value} end,
        run=function(value) commands[#commands+1]={'run',value} end,
    }},
    coroutine={schedule=function(fn) scheduled[#scheduled+1]=fn end,
        sleep=function() error('shutdown must not yield') end},
}, {__index=_G})
local chunk=assert(loadstring(source)); setfenv(chunk,env)
local movement=chunk()
movement.queue={{is_valid=function() error('queued job resumed') end}}
movement.current={jobId=1}
movement.previousJob={reschedule=function() error('old job resumed') end}
movement:shutdown()
assert(movement.current==nil and movement.previousJob==nil and #movement.queue==0)
assert(commands[1][1]=='follow' and commands[1][2]==-1)
assert(commands[2][1]=='run' and commands[2][2]==false)
assert(movement:reschedule()==nil and movement:moveTo(1,2)==nil)
assert(movement:cancelJob()==nil)
scheduled[1]() -- A previously scheduled worker cannot resume movement.
movement:shutdown() -- Repeated cleanup is safe.
print('PASS: shutdown stops run/follow, clears jobs, blocks resumption and never yields')
