local file=assert(io.open('lib/action-context.lua'));local source=file:read('*a');file:close()
local body=assert(source:match('(context.abyssea = {}.-)    context.usableWeaponSkills ='))
local Weakness=require('./lib/abyssea-weakness')
Weakness.clear()
local target={id=200,index=2,hpp=90,status=1,spawn_type=16,distance=10}
local liveTarget=target
local zone=218
local resources={Fire={element=0},Stone={element=3},['Ice Threnody']={element=0},['Katon: Ni']={element=0}}
local spells,validators={},{}
local tools,bag,opened=false,true,0
local context={bt=target,me={id=100},log=function() end,
    vars=setmetatable({},{__index=function() error('yellow helper must not read action variables') end}),
    canUseSpell=function() return true end,
    findItemInInventory=function() return tools end,
    findUsableItem=function() return bag end,freeInventorySlots=function() return 2 end,
    useItem=function() opened=opened+1;tools=true;return true end,wait=function() end,
    useSpell=function(mob,name,ignoreIncomplete,validate)
        assert(mob.id==target.id and not ignoreIncomplete)
        spells[#spells+1]=name;validators[#validators+1]=validate;return false,{started=true,outcome='interrupted'}
    end}
local env=setmetatable({context=context,variableValues=require('./lib/variable-values'),
    actionStateManager={isActing=function() return false end},
    findSpell=function(name) return resources[name] end,
    windower={ffxi={get_info=function() return {zone=zone} end,
        get_mob_by_target=function() return nil end,
        get_mob_by_id=function(id) if id==target.id then return liveTarget end end}}},
    {__index=_G})
local chunk=assert(loadstring(body));setfenv(chunk,env);chunk()
local config={spells={'Stone','Ice Threnody','Katon: Ni'},tools={['Katon: Ni']={items={'Uchitake'},bags={'Toolbag (Uchi)'}}}}
context.abyssea.runYellowProc(config)
assert(spells[1]=='Stone' and validators[1]())
liveTarget={id=target.id,index=target.index+1,hpp=90}
assert(not validators[1](),'a replaced monster must invalidate a queued cast')
liveTarget={id=target.id,index=target.index,hpp=0}
assert(not validators[1](),'a dead monster must invalidate a queued cast')
liveTarget=target
Weakness.update(218,target,'fire',false,nil,'yellow')
assert(not validators[1](),'new hint invalidates queued spells of other elements')
context.abyssea.runYellowProc(config);assert(spells[2]=='Ice Threnody')
context.abyssea.runYellowProc(config);assert(spells[3]=='Katon: Ni' and opened==1 and validators[3]())
Weakness.update(218,target,nil,true,'Ally','red')
assert(validators[3](),'red confirmation must not invalidate yellow requests')
Weakness.update(218,target,nil,true,'Ally','yellow')
assert(not validators[3](),'yellow confirmation must cancel queued yellow spells')
local count=#spells;context.abyssea.runYellowProc(config);assert(#spells==count)
config.on_stagger='full_rotation';assert(validators[3]())
config.enabled=false;assert(not validators[3]())
assert(context.abyssea.weaknesses.yellow.triggered)
assert(not pcall(context.abyssea.runYellowProc))
zone=1
local outside={spells={'Stone'}}
count=#spells
context.abyssea.runYellowProc(outside);assert(#spells==count)
outside.allow_outside_abyssea=true
context.abyssea.runYellowProc(outside);assert(#spells==count+1 and validators[#validators]())
assert(not pcall(context.abyssea.runYellowProc,{spells={},allow_outside_abyssea='true'}))
print('PASS: explicit yellow context API, dynamic hint/stagger dispatch guard, direct casting and toolbag preparation')
