local f=assert(io.open('lib/action-context.lua'));local source=f:read('*all');f:close()
local body=assert(source:match('(context%.mobById = function.-)\n    %-%-%-%-'))
local member={name='Party member'}
local context={alliance_by_id={[42]={member=member}},member='unchanged',mob='unchanged'}
local mob={id=42,index=7,in_party=true,in_alliance=true}
local initialized
local env=setmetatable({context=context,
 windower={ffxi={get_mob_by_id=function(id) if id==42 then return mob end end, get_mob_by_index=function(index) if index==7 then return mob end end}},
 initContextTargetSymbol=function(ctx,entity)
    assert(ctx==context);initialized=entity
    entity.id=entity.mob.id;entity.index=entity.mob.index
 end}, {__index=_G})
local chunk=assert(loadstring(body));setfenv(chunk,env);chunk()
assert(context.mobByIndex(7).id == 42)
assert(not pcall(context.mobByIndex, 42))
assert(not pcall(context.mobByIndex, nil))
local entity=context.mobById(42)
assert(entity==initialized and entity.id==42 and entity.index==7)
assert(entity.member==member and entity.in_party and type(entity.buffs)=='table')
assert(context.member=='unchanged' and context.mob=='unchanged')
assert(context.mobById(42)~=entity)
for _, id in ipairs({0,-1,1.5,'42',math.huge,99}) do
 assert(not pcall(context.mobById,id))
end
assert(not pcall(context.mobById,nil))
mob=nil;assert(not pcall(context.mobById,42))
print('PASS: entity initialization, party metadata, empty buffs, independent objects, no selection mutation, invalid/unavailable IDs')
