local file=assert(io.open('lib/action-context.lua')); local source=file:read('*a'); file:close()
local body=assert(source:match('(    context.sendWindowerCommands = function.-)\n    context.sendText ='))
local sent={}
local context={}
local chunk=assert(loadstring(body))
setfenv(chunk,setmetatable({context=context,windower={send_command=function(command) sent[#sent+1]=command end}},
    {__index=_G}))
chunk()
assert(context.sendWindowerCommands({'input /echo 100% ready','  ','wait 1; input /echo later','lua c other start'})==3)
assert(sent[1]=='input /echo 100% ready' and sent[2]=='wait 1; input /echo later' and sent[3]=='lua c other start')
assert(context.sendWindowerCommands({})==nil)
assert(context.sendWindowerCommands('input /echo single')==1 and sent[4]=='input /echo single')
assert(context.sendWindowerCommands('  ')==nil and #sent==4)
assert(not pcall(context.sendWindowerCommands,nil))
for _,invalid in ipairs({false,{'valid',false},{[2]='hole'}}) do
    assert(not pcall(context.sendWindowerCommands,invalid) and #sent==4)
end
-- Both actual hook files compile under the status schema and call the dispatcher.
local json=require('./lib/jsonlua')
local Config=require('./lib/events/config')
for _,name in ipairs({'battle','idle'}) do
    local path='events/lib/on-'..name..'.json'
    local f=assert(io.open(path)); local doc=json.parse(f:read('*a')); f:close()
    local config=Config.load({'test'},function() return doc end)
    local rules=config.rules['statuses.'..name].enter
    assert(#rules==2 and rules[2].commands[1].code=='sendWindowerCommands(vars.on_'..name..'.windower_commands)')
end
print('PASS: literal ordered Windower dispatch, percent/semicolon preservation, validation and battle/idle hook compilation')
