local file=assert(io.open('Gambit.lua')); local source=file:read('*a'); file:close()
local body=assert(source:match('(abilityReady=function.-)\n    %}%)'))
local timers,charges={[1]=60,[231]=120,[195]=30,[102]=30},1
local chunk=assert(loadstring('return {'..body..'}'))
setfenv(chunk,{type=type,windower={ffxi={get_ability_recasts=function() return timers end}},
    getAvailableStratagems=function() return charges end})
local check=chunk().abilityReady
assert(check({},{recast_id=1})==false)
timers[1]=0; assert(check({},{recast_id=1})==true)
assert(check({},{recast_id=2})==nil)
assert(check({},{recast_id=231})==true)
charges=0; assert(check({},{recast_id=231})==false)
assert(check({},{recast_id=195})==nil and check({},{recast_id=102})==nil)
timers=nil; assert(check({},{recast_id=1})==nil)
print('PASS: pre recast gate, ready/missing timers, available stratagems and conservative charge handling')
