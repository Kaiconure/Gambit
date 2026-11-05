local Blue=require('./lib/abyssea-blue')
local now=0
local a={id=1,key='a',skill=3,slot='main'}
local b={id=2,key='b',skill=3,slot='main'}
local current={id=99,key='other',skill=2,slot='main'}
local swaps={}
local target={id=200,index=2,hpp=100}
local config={all_ws={'Sword'},weapons={a,b}}
local observation={blue={}}
local deps={clock=function() return now end,log=function() end,
    current=function(slot) if slot=='main' then return current end end,
    resource=function() return {skill=3} end,usable=function() return {} end,
    ready=function() error('no usable WS') end,allowed=function() return true end,
    resolve=function(gear) return gear end,equip=function(gear) swaps[#swaps+1]=gear;return true end}
local function step() Blue.step(config,target,observation,deps) end
step();assert(swaps[1]==a)
current=a;now=2;step();assert(#swaps==1,'successful acknowledgement must not bypass minimum swap spacing')
now=4.9;step();assert(#swaps==1)
now=5;step();assert(swaps[2]==b)
current=b;now=7;step();now=9;step()
assert(config._blue_rotation.retryAt==19,'empty pass waits ten seconds after confirmed refresh')
assert(config._blue_rotation.exhausted and next(config._blue_rotation.visited),
    'retain exhausted-pass identity and visited weapons during the wait')
now=10;step();now=18.9;step();assert(#swaps==2)
now=19;step();assert(swaps[3]==a,'retry later rather than permanently excluding the rotation')
-- New information should not have to wait out the empty-pass cooldown.
current=a;now=21;step();now=23;step();now=24;step();current=b;now=26;step();now=28;step()
local before=#swaps
observation.blue.weapon_type='sword';now=29;step()
assert(#swaps==before+1,'new hint releases exhausted-pass delay')
assert(not pcall(Blue.validate,{all_ws={'Sword'},swap_delay=-1}))
assert(not pcall(Blue.validate,{all_ws={'Sword'},empty_pass_delay=math.huge}))
print('PASS: minimum swap interval, exhausted-pass backoff, retry and immediate hint invalidation')
