local f=assert(io.open('lib/action-context.lua'))
local source=f:read('*a');f:close()
local engaged=false
local reportedStatus=0
local commands={}
local env={STATUS_IDLE=0,STATUS_ENGAGED=1,SPAWN_TYPE_MOB=16,
    windower={ffxi={get_player=function()return {status=reportedStatus} end}},
    context={getMobByTarget=function()return {spawn_type=16} end,wait=function()end}}
env.context.sendCommand=function(command)
    commands[#commands+1]=command
    if command=='input /attack on' then engaged=true
    elseif command=='input /attack off' then engaged=false
    else engaged=not engaged end
end
local function helper(name)
    local body=assert(source:match('context%.'..name..' = function %(%)(.-)\n    end'))
    local chunk=assert(loadstring('return function()'..body..' end'))
    setfenv(chunk,env)
    return chunk()
end
local engage,disengage=helper('engage'),helper('disengage')
engage();assert(engaged)
-- Target-cursor acquisition has engaged already, but player status is stale.
engage();assert(engaged and commands[#commands]=='input /attack on')
reportedStatus=1
disengage();assert(not engaged)
-- A second pending disengagement must also be safe with stale status.
disengage();assert(not engaged and commands[#commands]=='input /attack off')
reportedStatus=0
local count=#commands
env.context.getMobByTarget=function()return nil end
engage();assert(#commands==count)
print('PASS: engagement and disengagement remain idempotent during player-status latency')
