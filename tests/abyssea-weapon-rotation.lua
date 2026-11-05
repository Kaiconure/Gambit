local Red=require('./lib/abyssea-red')
local Blue=require('./lib/abyssea-blue')
local resources={Cyclone={skill=2},['Seraph Blade']={skill=3},Dagger={skill=2},Sword={skill=3},Bow={skill=25}}
local main={id=1,key='dagger',skill=2,slot='main'}
local range
local sword={id=2,key='sword',skill=3,slot='main'}
local bow={id=3,key='bow',skill=25,slot='range'}
local swaps,logs={},{}
local target={id=200,index=2,hpp=100}
local deps={clock=function() return 0 end,log=function(a,b) logs[#logs+1]=tostring(a)..' '..tostring(b) end,
    current=function(slot) if slot=='range' then return range end;return main end,
    resource=function(name) return resources[name] end,
    usable=function(names) return names end,ready=function() return false end,
    allowed=function() return true end,use=function() error('no TP; should only equip') end,
    resolve=function(gear) return gear end,equip=function(gear) swaps[#swaps+1]=gear;return true end}
-- Current dagger has no candidates in this pool: rotate without requiring TP.
local config={all_ws={'Sword'},weapons={sword}}
Blue.step(config,target,nil,deps)
assert(swaps[1]==sword)
-- A fresh hint supersedes an outstanding old weapon request immediately.
config={all_ws={'Dagger','Sword'},weapons={sword},_blue_rotation={target=200,index=2,
    pool='Dagger\0Sword',used={},visited={},pending={id=99,key='old',time=0},lastWeapon='dagger'}}
Blue.step(config,target,{blue={weapon_type='sword'}},deps)
assert(#swaps==2 and swaps[2]==sword)
-- Empty ranged slot must not prevent equipping the configured bow.
config={all_ws={'Bow'},weapons={bow}}
Blue.step(config,target,{blue={weapon_type='archery'}},deps)
assert(#swaps==3 and swaps[3]==bow)
-- Red must rotate away from a weapon that cannot satisfy the element hint.
config={all_ws={'Cyclone','Seraph Blade'},weapons={sword}}
Red.step(config,target,{red={element='light'}},deps)
assert(#swaps==4 and swaps[4]==sword)
main=nil
Red.step({all_ws={'Seraph Blade'},weapons={sword}},target,nil,deps)
assert(#swaps==5,'empty main slot must not stop configured red rotation')
-- Missing or incompatible pools should explain the wait without repeated spam.
config={all_ws={'Dagger'},weapons={sword}}
local before=#logs
Blue.step(config,target,{blue={weapon_type='sword'}},deps)
Blue.step(config,target,{blue={weapon_type='sword'}},deps)
assert(#logs==before+1 and logs[#logs]:find('supplied pool',1,true))
-- No weapon list is a supported current-equipment-only configuration.
main=sword
deps.usable=function(names) return names end;deps.ready=function() return true end
local attempted
deps.use=function(name) attempted=name;return true end
deps.resolve=function() error('no configured sets should be resolved') end
deps.equip=function() error('current-equipment-only mode must not request swaps') end
Red.step({all_ws={'Seraph Blade'}},target,nil,deps)
assert(attempted=='Seraph Blade')
attempted=nil
Blue.step({all_ws={'Sword'}},target,nil,deps)
assert(attempted=='Sword')
print('PASS: incompatible/empty current weapons, hint replacing pending swap, no-TP swaps and deduplicated diagnostics')
