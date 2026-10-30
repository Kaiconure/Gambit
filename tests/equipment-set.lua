local file=assert(io.open('lib/action-context.lua')); local source=file:read('*a'); file:close()
local body=assert(source:match('(    context.equipMany = function.-)%s*%-%- Push a stop request'))
local context={vars={_={eq_stack={}}}}
local count,expected,sanitizeFails,snapshotFails=0,nil,false,false
local sanitized={head={name='Hat'}}
context.sanitizeEquipmentList=function()
    assert(context.equipment_set==nil)
    if sanitizeFails then error('bad input') end
    return sanitized
end
local inventory={
    equip_many=function(entries)
        assert(entries==sanitized and context.equipment_set==expected)
        return count
    end,
    snapshot_equipment=function()
        if snapshotFails then error('unavailable') end
        return {}
    end,
}
local chunk=assert(loadstring(body))
setfenv(chunk,setmetatable({context=context,inventory=inventory},{__index=_G})); chunk()
local input={head={name='Hat'},meta={stop=true}}
expected=input
assert(context.equipMany(input)==nil and context.equipment_set==input)
assert(context.equipment_set.meta.stop and input.meta.slot==nil)
count=1; assert(context.equipPush(input)==1 and context.equipment_set==input)
count=0; assert(context.equipPush(input)==nil and context.equipment_set==input)
assert(context.equipPush()==true and context.equipment_set==nil)
expected=sanitized
assert(context.equipMany('head','Hat')==nil and context.equipment_set==sanitized)
assert(context.equipPush('head','Hat')==nil and context.equipment_set==sanitized)
sanitizeFails=true
assert(not pcall(context.equipMany,input) and context.equipment_set==nil)
context.equipment_set=input
assert(not pcall(context.equipPush,input) and context.equipment_set==nil)
sanitizeFails=false; snapshotFails=true; context.equipment_set=input
assert(not pcall(context.equipPush,input) and context.equipment_set==nil)
print('PASS: original equipment_set references, metadata, no-op returns, no-arg push, alternate formats and stale-state clearing')
