local f=assert(io.open('lib/action-processing.lua'))
local source=f:read('*a');f:close()
assert(not source:find('if targetReady and mobTime > 1 then',1,true),
    'target acquisition must not suppress positioning and engagement pull actions')
local body=assert(source:match("(                    if settings.strategy ~= 'manual'.-)                    if mobTime > 1 then"))
local calls={}
local env={settings={strategy='manual'},STATUS_ENGAGED=1,
    player={status=0},mob={id=10,index=20},mobDistance=3,
    windower={ffxi={get_mob_by_target=function()return nil end}},
    targetAndEngage=function(id)calls.engage=id end,
    sendActionCommand=function(command)calls.command=command end,
    string=string}
local chunk=assert(loadstring('return function() local command=""; local hasCommand=false; '..body..' end'))
setfenv(chunk,env)
local run=chunk()
-- Repeated idle pull cycles must never engage before JSON releases the DD.
run();run();assert(not calls.engage and not calls.command)
env.settings.strategy='leader';run()
assert(calls.engage==10 and not calls.command)
calls={};env.settings.strategy='nearest';run()
assert(calls.engage==10 and not calls.command)
print('PASS: manual pull cycles never engage; automatic strategies use packet-only engagement')
