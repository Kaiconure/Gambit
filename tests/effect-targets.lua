local file=assert(io.open('lib/action-context.lua'))
local source=file:read('*all');file:close()
local helper=assert(source:match('(local function isEffectTarget.-\nend)'))
local buff={id=6}
local resource={id=59,name='Silence',status=6}
local context={me={buffs={buff}},mob={id=123,index=45}}
local checked, strict
local env=setmetatable({context=context,
    hasBuffInArray=function(buffs,name,useStrict)
        checked=buffs;strict=useStrict
        if type(buffs)=='table' then return buffs[1] end
    end,
    arrayCountOccurences=function() return 1 end,
    findSpell=function(name) if name=='Silence' then return resource end end,
    findJobAbility=function() return nil end,
}, {__index=_G})
for _, name in ipairs({'hasBuff','hasEffectOf'}) do
    local body=assert(source:match('(context%.'..name..' = function.-)\n    %-%-%-%-'))
    local chunk=assert(loadstring(helper..'\n'..body));setfenv(chunk,env);chunk()
    local fn=context[name]
    assert(fn('Silence')==buff and checked==context.me.buffs)
    assert(not fn(context.mob,'Silence') and checked==nil)
    assert(not fn('mob','Silence') and checked==nil)
    context.mob.buffs={}
    assert(not fn(context.mob,'Silence') and checked==context.mob.buffs)
    context.mob.buffs={buff}
    assert(fn(context.mob,'use-strict','Silence')==buff and strict==true)
    assert(fn('mob',{'Silence'})==buff)
    assert(fn({buffs={buff}},'Silence')==buff)
    context.mob.buffs=nil
end
assert(context.hasEffectOf(resource)==buff and checked==context.me.buffs)
assert(not context.hasEffectOf(context.mob,resource) and checked==nil)
assert(context.hasEffectOf({'Silence'})==buff)
print('PASS: raw and named mobs without buffs, no self fallback, empty/known buffs, strictness, arrays, legacy targets, resource arguments')
