local Blue=require('./lib/abyssea-blue')
local now=0
local old={id=1,key='old',skill=8}
local wanted={id=2,key='new',name='Great Sword',skill=4}
local current=old
local checked,logs=0,{}
local config={all_ws={'Ground Strike'},weapons={wanted}}
local target={id=200,index=2,hpp=100}
local deps={clock=function() return now end,log=function(a,b) logs[#logs+1]=tostring(a)..' '..tostring(b) end,
    resource=function() return {skill=4} end,current=function(slot) if slot=='main' then return current end end,
    usable=function(names) checked=checked+1;return names end,ready=function() return false end,
    allowed=function() return true end,resolve=function(gear) return gear end,equip=function() return true end}
Blue.step(config,target,nil,deps)
local before=checked
now=8;current=wanted;Blue.step(config,target,nil,deps)
assert(checked==before and config._blue_rotation.pending.confirmedAt==8)
now=9.9;Blue.step(config,target,nil,deps);assert(checked==before)
now=10;Blue.step(config,target,nil,deps);assert(checked==before+1,'refresh delay starts at observed confirmation, not request')
-- A request that never became current is a failed probe, not proof of no WS.
now=0;current=old;config._blue_rotation=nil
Blue.step(config,target,nil,deps)
now=10;Blue.step(config,target,nil,deps)
assert(config._blue_rotation.retryPending and not config._blue_rotation.exhausted)
assert(logs[#logs]:find('pass incomplete',1,true))
print('PASS: delayed equipment confirmation, post-confirmation refresh gap and unconfirmed-probe classification')
