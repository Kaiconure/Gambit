local classify = require('./lib/equipment/slot-info')
local flags = {'one_handed','two_handed','shield','h2h','archery','marksmanship','throwing'}
local expected = {[1]='h2h',[2]='one_handed',[3]='one_handed',[4]='two_handed',
    [5]='one_handed',[6]='two_handed',[7]='two_handed',[8]='two_handed',
    [9]='one_handed',[10]='two_handed',[11]='one_handed',[12]='two_handed',
    [25]='archery',[26]='marksmanship',[27]='throwing'}
for skill=0,48 do
    local resource={skill=skill}
    local result=classify({id=123,name='Example',item=resource},'main')
    assert(result.id==123 and result.name=='Example' and result.item==resource and result.slot=='main')
    for _,flag in ipairs(flags) do assert(result[flag]==(expected[skill]==flag),skill..': '..flag) end
    assert(resource.two_handed==nil)
end
assert(classify({item={shield_size=5}},'sub').shield)
assert(not classify({item={shield_size=0}},'sub').shield)
for _,flag in ipairs(flags) do assert(classify({item={}},'head')[flag]==false) end
assert(classify(nil,'main')==nil)

-- Exercise the actual context wrapper, including confirmed reads and stale state.
local f=assert(io.open('lib/action-context.lua'));local source=f:read('*a');f:close()
local block=assert(source:match('(context%.slotInfo = function.-)\n    end'))..'\n    end'
local equipped={item={skill=4}}
local calls=0
local env=setmetatable({context={item='selected'},equipmentHelpers={slotInfo=classify},inventory={
    find_equipment_in_slot=function(slot,items,confirmed)
        calls=calls+1;assert(items==nil and confirmed==true)
        return slot=='main' and equipped or nil
    end,
}}, {__index=_G})
local chunk=assert(loadstring(block));setfenv(chunk,env);chunk()
local context=env.context
assert(context.slotInfo('main')==context.slot_info and context.slot_info.two_handed)
assert(context.item=='selected')
equipped=nil
assert(context.slotInfo('main')==nil and context.slot_info==nil)
assert(context.slotInfo('invalid')==nil)
assert(context.slotInfo({})==nil and calls==3)
print('PASS: equipment classifications, shields, empty/invalid slots, confirmed reads and context isolation')
