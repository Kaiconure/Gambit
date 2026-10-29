local file=assert(io.open('lib/commands.lua')); local source=file:read('*a'); file:close()
local body=assert(source:match("(handlers%['events'%] = function.-)\nhandlers%['eval'%]"))
local output,errors={},{}
local count=0
local service={runtime={config={path='selected.json'}},reload=function() count=count+1; return {files={'selected.json'}} end}
local env=setmetatable({handlers={},globals={event_system=service},
    text_file=function(value) return '<file>'..value..'</file>' end,
    writeMessage=function(value) output[#output+1]=value end,
    writeError=function(value) errors[#errors+1]=value end,
    reloadSettings=function() error('must not reload normal settings') end},{__index=_G})
local chunk=assert(loadstring(body)); setfenv(chunk,env); chunk()
env.handlers.events({'RELOAD'})
assert(count==1 and output[#output]=='Event rules reloaded.')
env.handlers.events({}); assert(output[#output]=='Active event file: <file>selected.json</file>' and count==1)
env.handlers.events({'status'}); assert(output[#output]=='Active event file: <file>selected.json</file>')
service.runtime.config.vars_files={'character.vars.json','shared.vars.json'}
env.handlers.events({'status'})
assert(output[#output-1]=='Event variables: <file>character.vars.json</file>')
assert(output[#output]=='Event variables: <file>shared.vars.json</file>')
env.handlers.events({'reload','extra'})
assert(count==1 and output[#output]=='Usage: gbt events [status | reload]')
service.reload=function() error('invalid event JSON') end
env.handlers.events({'reload'}); assert(#errors==1 and errors[1]:find('invalid event JSON',1,true))
service.reload=function() return nil end
env.handlers.events({'reload'}); assert(output[#output]:find('No character',1,true))
env.globals.event_system=nil
env.handlers.events({'reload'}); assert(output[#output]=='Event system is unavailable.')
print('PASS: event-only reload command, errors, usage, unavailable service and logged-out state')
