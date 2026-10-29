local file=assert(io.open('lib/commands.lua')); local source=file:read('*a'); file:close()
local body=assert(source:match("(handlers%['equipment'%] = function.-)\nhandlers%['events'%]"))
local messages,errors={},{}
local count=0
local manager={resync=function() count=count+1 end}
local env=setmetatable({handlers={},globals={equipment_manager=manager},
    writeMessage=function(message) messages[#messages+1]=message end,
    writeError=function(message) errors[#errors+1]=message end},{__index=_G})
local chunk=assert(loadstring(body)); setfenv(chunk,env); chunk()
env.handlers.equipment({'RESYNC'}); assert(count==1 and messages[#messages]:find('resynced',1,true))
env.handlers.equipment({}); env.handlers.equipment({'resync','extra'}); assert(count==1)
manager.resync=function() error('test failure') end
env.handlers.equipment({'resync'}); assert(#errors==1)
env.globals.equipment_manager=nil
env.handlers.equipment({'resync'}); assert(messages[#messages]=='Equipment manager is unavailable.')
print('PASS: explicit equipment resync command, argument validation and contained errors')
