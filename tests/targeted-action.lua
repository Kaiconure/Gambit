local submitted, fields
local mob={id=123,index=45,valid_target=true}
windower={ffxi={get_mob_by_id=function(id) assert(id==123);return mob end}}
packets={new=function(direction,id,data)
    assert(direction=='outgoing' and id==0x01A);fields=data;return data
end,inject=function(packet) submitted=packet end}
local targeted=require('./lib/targeted-action')
assert(targeted.send(3,{id=59},123))
assert(fields.Target==123 and fields['Target Index']==45 and fields.Category==3 and fields.Param==59)
assert(fields['X Offset']==0 and fields['Y Offset']==0 and fields['Z Offset']==0)
mob.index=46
assert(targeted.send(9,{id=5},123))
assert(fields['Target Index']==46 and fields.Category==9 and fields.Param==5)
submitted=nil;mob.valid_target=false
assert(not targeted.send(3,{id=59},123) and not submitted)
mob=nil;assert(not targeted.send(9,{id=5},123))
assert(not targeted.send(7,{id=5},123))

local file=assert(io.open('lib/action-processing.lua'))
local source=file:read('*all');file:close()
source=source:gsub("('[^'\r\n]*'):format", '(%1):format'):gsub('("[^"\r\n]*"):format', '(%1):format')
assert(loadstring(source))
local body=assert(source:match('(function sendSpellCastingCommand.-)function string_trim'))
local passed
local env=setmetatable({actionStateManager={isActing=function() return false end},
    actionCategories=require('./meta/outgoing-action-categories'),
    sendObservedAction=function(category,spell,target,context,policy,pause,ignore)
        assert(category==3 and target==123 and policy.start and policy.padding==2 and pause)
        passed=true; return true
    end},{__index=_G})
local chunk=assert(loadstring(body));setfenv(chunk,env);chunk()
assert(env.sendSpellCastingCommand({id=59,cast_time=1},123,{}) and passed)
print('PASS: targeted packets and spell delegation to shared wait policy')
for _, path in ipairs({'lib/action-state-manager.lua'}) do
    local f=assert(io.open(path));local text=f:read('*all');f:close()
    text=text:gsub("('[^'\r\n]*'):format", '(%1):format'):gsub('("[^"\r\n]*"):format', '(%1):format')
    assert(loadstring(text,'@'..path))
end
print('PASS: state-manager syntax')
