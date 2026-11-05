local Blue=require('./lib/abyssea-blue')
local now=0
local resources={Dagger={skill=2},Sword={skill=3},Bow={skill=25},Gun={skill=26},Fist={skill=1}}
local main={id=1,key='dagger',skill=2,slot='main'}
local range={id=2,key='bow',skill=25,slot='range'}
local fired,swaps={},{}
local config={all_ws={'Dagger','Sword','Bow','Gun','Fist'},weapons={{id=3,key='sword',skill=3,slot='main'}}}
local target={id=200,index=2,hpp=100}
local observation={blue={}}
local currentSlot='main'
local deps={clock=function() return now end,log=function() end,resource=function(name) return resources[name] end,
    current=function(slot) currentSlot=slot;return slot=='range' and range or main end,
    usable=function(names) return names end,ready=function() return true end,allowed=function() return true end,
    use=function(name) fired[#fired+1]=name;return false end,
    resolve=function(gear) return gear end,equip=function(gear) swaps[#swaps+1]=gear;return true end}
local function step() Blue.step(config,target,observation,deps) end
Blue.validate(config)
step();assert(fired[1]=='Dagger')
step();step();assert(fired[2]=='Bow','use an already equipped ranged weapon before changing gear')
assert(config._blue_rotation and not config._rotation,'red and blue state must be independent')
observation.blue.weapon_type='sword';step();assert(swaps[1].id==3)
main=config.weapons[1];now=3;step();assert(#fired==2)
now=5;step();assert(fired[3]=='Sword')
observation.red={triggered=true};observation.yellow={triggered=true};step()
observation.blue.triggered=true
local count=#fired;local changed=#swaps;step();assert(#fired==count and #swaps==changed)
config.on_stagger='full_rotation';step();assert(config._blue_rotation.element==nil)
assert(#Blue.candidates(config,'archery',deps.resource)==1)
assert(#Blue.candidates(config,'marksmanship',deps.resource)==1)
assert(#Blue.candidates(config,'unknown',deps.resource)==0)
config.all_ws={'Fist'};observation={blue={weapon_type='hand-to-hand'}}
main={id=0,key='unarmed',skill=1,slot='main'}
step();assert(fired[#fired]=='Fist')
assert(not pcall(Blue.validate,{}))
print('PASS: blue weapon hints, shared main/ranged rotation, unarmed H2H, candidate pools and independent completion')
