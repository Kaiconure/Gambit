local inventory=require('./lib/inventory')
local copy=require('./lib/variable-values').copy
local calls={}
local items={equipment={left_ring=1,left_ring_bag=8},wardrobe={[1]={id=101},[2]={id=202}}}
resources={items={[101]={id=101},[202]={id=202}}}
findItem=function(query)
    if type(query)=='table' then query=query.name end
    if query=='Roll Ring' then return resources.items[202] end
end
windower={ffxi={get_items=function() return items end,
    set_equip=function(localId,slot,bag) calls[#calls+1]={localId,slot,bag} end}}
arrayAppend=function(t,v) t[#t+1]=v end
local previous={id=101,name='Original Ring',localId=1,bagId=8}
local temporary={id=202,name='Roll Ring',localId=2,bagId=8,raw_slots={[13]=true}}
inventory.find_equipment_in_slot=function() return copy(previous) end
inventory.find_item=function(query,flags)
    assert(query.name=='Roll Ring')
    assert(flags.equipped==false)
    return copy(temporary)
end
local file=assert(io.open('lib/action-context.lua')); local source=file:read('*a'); file:close()
local body=assert(source:match('(    context.equipPush = function.-)%s*%-%- Push a stop request'))
body=body:gsub("('[^'\r\n]*'):format",'(%1):format')
local vars={_={eq_stack={}}}
local function context()
    local ctx={vars=vars,sanitizeEquipmentList=function(_,entries) return entries end}
    local chunk=assert(loadstring(body))
    setfenv(chunk,setmetatable({context=ctx,inventory=inventory,Colors={},
        writeVerbose=function() end,pluralize=function() return '' end},{__index=_G}))
    chunk()
    return ctx
end
local pre=context()
local set={ring1={name='Roll Ring'},meta={stop=true,note='retained'}}
assert(pre.equipPush(set)==1)
assert(set.meta.stop and set.meta.note=='retained' and set.meta.slot==nil)
assert(calls[1][1]==2 and calls[1][2]==13 and calls[1][3]==8)
local saved=vars._.eq_stack[1].removed.ring1
assert(saved.id==101 and saved.localId==1 and saved.bagId==8)
-- The cache STILL says Original Ring is worn. Pop must nevertheless submit its
-- restore after the Roll Ring request, including from a fresh post context.
assert(context().equipPop()==1)
assert(#calls==2 and calls[2][1]==1 and calls[2][2]==13 and calls[2][3]==8)
assert(#vars._.eq_stack==0)
context().equipPop(); assert(#calls==2)
-- Do not restore a different item now occupying the recorded bag slot.
items.wardrobe[1]={id=999}
assert(inventory.restore_equipment({ring1=saved})==0 and #calls==2)
-- An originally empty slot must be restored to empty as well.
inventory.find_equipment_in_slot=function() return nil end
items.equipment.left_ring=0
assert(context().equipPush({ring1={name='Roll Ring'}})==1)
assert(vars._.eq_stack[1].removed.ring1.empty)
assert(context().equipPop()==1 and calls[#calls][1]==0)
print('PASS: actual push/pop with stale equipment cache, exact item identity, fresh post context and empty-slot restoration')
