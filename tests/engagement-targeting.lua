local file=assert(io.open('lib/target-processing.lua'))
local source=file:read('*a')
file:close()

local body=assert(source:match('(local engagementAttempt.-)\nlocal targetScope'))
local lockStart=assert(source:find('function lockTarget',1,true))
local engageStart=assert(source:find('local engagementAttempt',lockStart,true))
local lockBody=source:sub(lockStart,engageStart-1)
assert(not lockBody:find('targetAndEngage',1,true),
    'lockTarget must not perform engagement packet retries')

local selector=assert(source:match('local function setTargetMob.-\nend\n\nlocal function shouldAquireNewTarget'))
assert(selector:find("if engage~=false then targetAndEngage(mob.id) end",1,true),
    'explicit target requests must retain optional immediate engagement')
assert(source:find('setTargetMob(mobToTarget, false)',1,true),
    'automated target selection must defer engagement until pull processing')
assert(source:find('setTargetMob(t, false)',1,true),
    'leader target selection must defer engagement until pull processing')

local mob
local injected={}
local now=10
local env={
    SPAWN_TYPE_MOB=16,
    windower={ffxi={get_mob_by_id=function() return mob end}},
    os={clock=function() return now end},
    packets={
        new=function(direction,id,fields)
            assert(direction=='outgoing' and id==0x01A)
            return fields
        end,
        inject=function(packet) injected[#injected+1]=packet end,
    },
}
setmetatable(env,{__index=_G})
local chunk=assert(loadstring(body))
setfenv(chunk,env)
chunk()

mob={id=100,index=20,spawn_type=16,valid_target=true,hpp=100,distance=30*30}
assert(not env.targetAndEngage(100) and #injected==0)

mob.distance=29.9*29.9
assert(env.targetAndEngage(100) and #injected==1)
assert(injected[1].Target==100 and injected[1]['Target Index']==20 and injected[1].Category==2)

assert(not env.targetAndEngage(100) and #injected==1,'same-cycle retry must be throttled')
now=10.5
assert(env.targetAndEngage(100) and #injected==2,'later action cycle may retry')

mob.valid_target=false
assert(not env.targetAndEngage(100) and #injected==2)

print('PASS: engagement targeting is one packet-only, range-bounded attempt')
