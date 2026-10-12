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
local spell={id=59,name='Silence',prefix='/ma',cast_time=1}
local function run(mode, target)
    local now, restored, command = 10, false, nil
    local state={currentSpell={time=0},isActing=function() return false end}
    local context={action={}}
    local function advance(seconds)
        now=now+seconds
        if mode~='timeout' then
            state.currentSpell={time=now,spellId=mode=='wrong-spell' and 60 or 59,
                targetId=mode=='wrong-target' and 124 or 123,spell=nil,
                interrupted=mode=='interrupt'}
        end
    end
    local env=setmetatable({os={clock=function() return now end},
        coroutine={sleep=advance},actionStateManager=state,
        settings={verbosity=0},VERBOSITY_DEBUG=1,
        smartMove={cancelJob=function() return 'movement' end,
            reschedule=function(self,job) assert(job=='movement');restored=true end},
        targetedAction={send=function(category,resource,id)
            assert(category==3 and resource==spell and id==123)
            return mode~='invalid'
        end},
        sendActionCommand=function(value,ctx,seconds)
            command=value
            if type(value)=='function' and not value() then return false end
            advance(seconds);return true
        end}, {__index=_G})
    local chunk=assert(loadstring(body));setfenv(chunk,env);chunk()
    local result=env.sendSpellCastingCommand(spell,target,context)
    assert(restored)
    if target==123 then assert(type(command)=='function')
    else assert(command=='input /ma "Silence" <t>') end
    return result,context
end
assert(run('success',123))
assert(not run('interrupt',123))
assert(not run('wrong-spell',123))
assert(not run('wrong-target',123))
assert(not run('timeout',123))
assert(not run('invalid',123))
assert(run('success','t'))
print('PASS: targeted packet fields, refreshed index, invalid targets, cast correlation, interruption, timeout, movement restoration, semantic command path')
for _, path in ipairs({'lib/action-state-manager.lua'}) do
    local f=assert(io.open(path));local text=f:read('*all');f:close()
    text=text:gsub("('[^'\r\n]*'):format", '(%1):format'):gsub('("[^"\r\n]*"):format', '(%1):format')
    assert(loadstring(text,'@'..path))
end
print('PASS: state-manager syntax')
