local file=assert(io.open('lib/commands.lua'))
local source=file:read('*a'); file:close()
local handler=assert(source:match("(handlers%['slots'%] = function.-)\nhandlers%['eval'%]"))
local output={}
local env=setmetatable({handlers={},writeMessage=function(message) output[#output+1]=message end,
    text_action_type=function(value) return '[type]'..value end,
    text_action_value=function(value) return '[slot]'..value end,
    hasArg=function(args, flag)
        for _, arg in ipairs(args) do if arg==flag then return true end end
    end,
    getArgValue=function(args, flag)
        for i, arg in ipairs(args) do if arg==flag then return args[i+1] end end
    end,
},{__index=_G})
local chunk=assert(loadstring(handler)); setfenv(chunk,env); chunk()
env.handlers.slots({})
assert(output[1]:find('unavailable',1,true))
env.settings={actions={_availableSlots={zeta={idle=1},alpha={idle=2,battle=1}}}}
output={}
env.handlers.slots({})
assert(#output==6 and output[2]=='  [type]battle:' and output[3]=='    [slot]alpha')
assert(output[4]=='  [type]idle:' and output[5]=='    [slot]zeta' and output[6]=='    [slot]alpha')
output={}; env.handlers.slots({'-t','IDLE'})
assert(#output==4 and output[2]=='  [type]idle:')
assert(output[3]=='    [slot]zeta' and output[4]=='    [slot]alpha')
output={}; env.handlers.slots({'-t','battle'})
assert(#output==3 and output[2]=='  [type]battle:' and output[3]=='    [slot]alpha')
output={}; env.handlers.slots({'-t','unknown'})
assert(#output==1 and output[1]:find('action type [type]unknown',1,true))
output={}; env.handlers.slots({'-t'})
assert(#output==1 and output[1]=='Usage: gbt slots [-t <action-type>]')
env.settings.actions._availableSlots={}
output={}; env.handlers.slots({})
assert(output[1]=='No contribution slots are available.')
print('PASS: slot command preserves placement order, colors types/names and handles missing/empty metadata')
