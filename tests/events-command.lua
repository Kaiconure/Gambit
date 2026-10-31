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
assert(count==1 and output[#output]=='Usage: gbt events [status|s | reload|r [-e <file>|-r] [-verbose|-v]]')
local flags={}
service.reload=function(_,flag) flags[#flags+1]=flag; return {} end
env.handlers.events({'reload','-v'})
env.handlers.events({'reload','-verbose'})
assert(flags[1]==true and flags[2]==true)
local selected
service.reload=function(self,verbose,name) selected=name; self.selectedFile=name; return {} end
env.handlers.events({'r','-e','empty','-v'}); assert(selected=='empty')
env.handlers.events({'r','-r'}); assert(selected=='empty')
env.handlers.events({'r'}); assert(selected==nil)
env.handlers.events({'r','-reload'}); assert(selected=='selected')
env.handlers.events({'s'}); assert(output[#output]:find('Event variables:',1,true))
local errorCount=#output
env.handlers.events({'r','-e'}); assert(#output==errorCount+1 and output[#output]:find('Usage:',1,true))
env.handlers.events({'r','-r','-e','empty'}); assert(output[#output]:find('Usage:',1,true))
service.reload=function() error('invalid event JSON') end
env.handlers.events({'reload'}); assert(#errors==1 and errors[1]:find('invalid event JSON',1,true))
service.reload=function() return nil end
env.handlers.events({'reload'}); assert(output[#output]:find('No character',1,true))
env.globals.event_system=nil
env.handlers.events({'reload'}); assert(output[#output]=='Event system is unavailable.')
print('PASS: event-only reload command, errors, usage, unavailable service and logged-out state')
