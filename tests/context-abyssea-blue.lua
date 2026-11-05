local f=assert(io.open('lib/action-context.lua'));local source=f:read('*a');f:close()
local body=assert(source:match('(context.abyssea = {}.-)    context.usableWeaponSkills ='))
local Weakness=require('./lib/abyssea-weakness');Weakness.clear()
local target={id=200,index=2,hpp=90,spawn_type=16,status=1}
local gear={main={id=1,bagId=0,localId=1,item={skill=2}},
    range={id=2,bagId=0,localId=2,item={skill=25}},ammo={id=3,bagId=0,localId=3,item={skill=0}}}
local resources={Dagger={skill=2},Bow={skill=25}}
local attempts,validator=0
local zone=218
local context={bt=target,player={main_job_id=1,main_job_level=99},log=function() end,
    vars=setmetatable({},{__index=function() error('blue must not read action variable paths') end}),
    usableWeaponSkills=function(names) return names end,canUseWeaponSkill=function() return true end,
    useWeaponSkill=function(name,validate,strict,id)
        assert(name=='Bow' and strict and id==200);attempts=attempts+1;validator=validate;return true
    end}
local env=setmetatable({writeDebug=function() end,context=context,variableValues=require('./lib/variable-values'),
    inventory={find_equipment_in_slot=function(slot) return gear[slot] end},findWeaponSkill=function(name) return resources[name] end,
    windower={ffxi={get_info=function() return {zone=zone} end,get_mob_by_target=function() return nil end,get_mob_by_id=function() return target end}}},{__index=_G})
local chunk=assert(loadstring(body));setfenv(chunk,env);chunk()
local config={all_ws={'Dagger','Bow'}}
Weakness.update(218,target,'archery',false,nil,'blue')
context.abyssea.runBlueProc(config);assert(attempts==1 and validator())
gear.ammo.localId=4;assert(not validator(),'queued ranged WS must guard ammunition identity')
gear.ammo.localId=3
Weakness.update(218,target,nil,true,'Ally','red');assert(validator())
Weakness.update(218,target,nil,true,'Ally','yellow');assert(validator())
Weakness.update(218,target,nil,true,'Ally','blue');assert(not validator())
context.abyssea.runBlueProc(config);assert(attempts==1)
config.on_stagger='full_rotation';assert(validator())
gear.ammo=nil;assert(not validator())
config._blue_rotation=nil;context.abyssea.runBlueProc({all_ws={'Bow'}})
assert(attempts==1,'do not dispatch ranged WS without ammunition')
assert(not pcall(context.abyssea.runBlueProc))
zone=1;gear.ammo={id=3,bagId=0,localId=3,item={skill=0}}
gear.main=gear.range
local outside={all_ws={'Bow'}}
context.abyssea.runBlueProc(outside);assert(attempts==1)
outside.allow_outside_abyssea=true
context.abyssea.runBlueProc(outside);assert(attempts==2 and validator())
assert(not pcall(context.abyssea.runBlueProc,{all_ws={},allow_outside_abyssea=1}))
print('PASS: explicit blue context, ranged equipment/ammo guards and color-specific stagger handling')
