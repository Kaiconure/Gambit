local file=assert(io.open('lib/action-state-manager.lua'))
local source=file:read('*all');file:close()
local helper=assert(source:match('(local function mobBuffId.-\nend)'))
local manager={mobBuffs={}}
local mob={id=123,index=7,name='Enemy',valid_target=true,hpp=100,spawn_type=16}
local env=setmetatable({state_manager=manager,
 windower={ffxi={get_mob_by_id=function(id) assert(id==123);return mob end}},
 SPAWN_TYPE_MOB=16,SPAWN_TYPE_TRUST=14}, {__index=_G})
for _, name in ipairs({'validateBuffsForMob','removeBuffsForMob','getBuffsForMob','getRawBuffsForMob','getBuffInfoForMob'}) do
 local body=assert(source:match('(state_manager%.'..name..' = function.-\nend)'))
 local chunk=assert(loadstring(helper..'\n'..body));setfenv(chunk,env);chunk()
end
local function reset()
 manager.mobBuffs[123]={id=123,index=7,name='Enemy',buffs={6},byMe={[6]=true}}
end
for _, target in ipairs({123,mob}) do
 reset()
 assert(manager:validateBuffsForMob(target))
 assert(manager:getBuffsForMob(target)[1]==6)
 assert(manager:getRawBuffsForMob(target)[1]==6)
 assert(manager:getBuffInfoForMob(target).details[6].byMe)
 manager:removeBuffsForMob(target)
 assert(manager.mobBuffs[123]==nil)
end
for _, target in ipairs({{},'123',0,-1,1.5,math.huge}) do
 reset()
 assert(manager:validateBuffsForMob(target)==false)
 assert(#manager:getBuffsForMob(target)==0)
 assert(#manager:getRawBuffsForMob(target)==0)
 assert(#manager:getBuffInfoForMob(target).buffs==0)
 manager:removeBuffsForMob(target)
 assert(manager.mobBuffs[123])
end
print('PASS: shared mob ID normalization, object/ID validation, retrieval, details, removal, invalid inputs')
