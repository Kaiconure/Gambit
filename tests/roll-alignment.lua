local json=dofile('lib/jsonlua.lua')
local file=assert(io.open('actions/lib/abilities/use-rolls.json'))
local document=json.parse(file:read('*a'));file:close()
local expression=assert(loadstring('return '..document.macros.roll_alignment[1]))
local reason, reached, reserved, released, delay, anchor, locked
local env=setmetatable({
    vars={use_rolls={alignment={enabled=true,targets={'WAR'},range=7,distance=5,duration=3}}},
    member={id=1,distance=15},
    partyAnchorByName=function() return anchor end,
    hasBuff=function() return locked end,
    align=function() return reached,reason end,
    hasMovementReservation=function() return reserved end,
    releaseMovement=function() released=true;reserved=false end,
    postpone=function(value) delay=value end,
}, {__index=_G})
setfenv(expression,env)
require('./lib/engagement-helpers').attach(env)
local function reset()
    reason='progress';reached=false;reserved=true;released=false;delay=nil;anchor=true;locked=false
    env.member.distance=15
end
reset()
assert(expression()==false and reserved and not released and delay==1)
reached=true;delay=nil
assert(expression()==true and reserved and delay==nil)
for _, failure in ipairs({'timeout','cancelled','reserved'}) do
    reset();reason=failure
    assert(expression()==false and released and not reserved and delay==10)
end
reset();reserved=false
assert(expression()==false and released and delay==10)
reset();anchor=false
assert(expression()==false and released and delay==10)
reset();locked=true
assert(expression()==false and released and delay==10)
reset();env.member.distance=6
assert(expression()==true and not released and delay==nil)
reset();env.vars.use_rolls.alignment.enabled=false
assert(expression()==true and not released and delay==nil)
print('PASS: roll alignment retains progress reservation, retries, and releases on failure or expiry')

local releaseCheck=assert(loadstring('return '..document.actions[1].when[2]))
local chance=true
env.vars.use_rolls.alignment.enabled=true
env.vars.use_rolls._alignment_roll='Chaos Roll'
env.vars.use_rolls.logic={['Chaos Roll']={double_up={1,2,3,5},snake_eye={8,10}}}
env.latestRoll={name='Chaos Roll',count=2}
env.getLatestRoll=function() return env.latestRoll end
env.hasBuff=function(name) assert(name=='Double-Up Chance');return chance end
env.any=function(value,items)
    for _, item in ipairs(items) do if value==item then return true end end
    return false
end
local snakeEyeReady=true
env.canUse=function(name)
    assert(name=='Snake Eye', 'Double-Up recast must not release the reservation')
    return snakeEyeReady
end
setfenv(releaseCheck,env)
assert(not releaseCheck(), 'Keep reservation between Double-Ups')
chance=false
assert(releaseCheck(), 'Expired Double-Up Chance must release even at an unfinished total')
chance=true;env.latestRoll.count=4
assert(releaseCheck(), 'Accepted total should release immediately')
env.latestRoll.count=8
assert(not releaseCheck(), 'Snake Eye opportunity should retain reservation')
snakeEyeReady=false
assert(releaseCheck(), 'Snake Eye-only total must release when Snake Eye is unavailable')
env.latestRoll.count=2
assert(not releaseCheck(), 'Ordinary Double-Up total retains reservation without Snake Eye')
env.latestRoll.count=4
assert(releaseCheck(), 'Finished total releases while Double-Up Chance is still active')
env.vars.use_rolls._alignment_roll=nil;chance=false
assert(not releaseCheck(), 'Initial positioning must not require Double-Up Chance')
local prepareCheck=assert(loadstring('return '..document.actions[2].when[3]))
setfenv(prepareCheck,env)
env.setVar=function(name,value) assert(name=='use_rolls._alignment_roll');env.vars.use_rolls._alignment_roll=value end
reserved=false;env.vars.use_rolls._alignment_roll='Old Roll'
assert(prepareCheck() and env.vars.use_rolls._alignment_roll==nil, 'Fresh positioning clears stale roll tracking')
reserved=true;env.vars.use_rolls._alignment_roll='Chaos Roll'
assert(prepareCheck() and env.vars.use_rolls._alignment_roll=='Chaos Roll', 'Active sequence retains tracking')
assert(document.vars['^use_rolls'].alignment.timeout==90)
print('PASS: roll completion and expired Double-Up Chance release without interrupting cooldowns or initial positioning')
