local f=assert(io.open('lib/action-processing.lua'))
local source=f:read('*a');f:close()
local body=assert(source:match('(                    %-%- Manual strategy leaves cursor acquisition.-)                    %-%- Give some time'))
local calls={}
local env={settings={strategy='manual'},STATUS_ENGAGED=1,
    player={status=0},mob={id=10,index=20},mobDistance=3,
    windower={ffxi={get_mob_by_target=function()return nil end}},
    lockTarget=function()calls.lock=true end,
    sendActionCommand=function(command)calls.command=command end,
    string=string}
local chunk=assert(loadstring('return function() local command=""; local hasCommand=false; '..body..' end'))
setfenv(chunk,env)
local run=chunk()
-- Repeated idle pull cycles must never engage before JSON releases the DD.
run();run();assert(not calls.lock and not calls.command)
env.settings.strategy='leader';run()
assert(calls.lock and calls.command:find('/attack',1,true))
calls={};env.settings.strategy='nearest';run()
assert(calls.lock and calls.command)
print('PASS: manual pull cycles never acquire or engage; automatic strategies retain pull engagement')
