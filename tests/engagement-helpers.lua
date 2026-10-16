local reached, reason, delay, args
local context={align=function(...) args={...};return reached,reason end,postpone=function(value) delay=value end}
require('./lib/engagement-helpers').attach(context)
local options={duration=6,tolerance=0.5,retry_delay=10,progress_retry_delay=3}
reached=false;reason='progress'
assert(not context.alignWithRetry('target',180,12,options,true,3) and delay==3)
assert(args[4]==6 and args[5]==true and args[6]==0.5)
reason='timeout'
context.alignWithRetry('target',180,12,options)
assert(delay==10)
reached=true;delay=nil
assert(context.alignWithRetry('target',180,12,options) and delay==nil)
context.alignWithRetry('target',180,12,options,true,3)
assert(delay==3)
print('PASS: engagement retry helper forwards alignment settings and preserves success/progress/failure timing')
local reserved,released=true,false
context.hasMovementReservation=function() return reserved end
context.releaseMovement=function() released=true;reserved=false end
context.hasBuff=function() return false end
local target={id=1,hpp=100,distance=20,valid_target=true}
reached=false;reason='progress'
assert(not context.alignWithReservation(target,90,5,options,true))
assert(reserved and not released and delay==3)
assert(args[1]==target and args[2]==90 and args[3]==5 and args[4]==6 and args[6]==0.5)
local replacement={id=2,hpp=100,distance=20,valid_target=true}
context.alignWithReservation(replacement,90,5,options,true)
assert(args[1]==replacement and reserved and not released)
for _, invalid in ipairs({false,{id=1,hpp=0},{id=1,is_dead=true},{id=1,valid_target=false}}) do
    reserved=true;released=false
    assert(not context.alignWithReservation(invalid,0,5,options))
    assert(released and not reserved and delay==10)
end
reserved=true;released=false
assert(not context.alignWithReservation(nil,0,5,options) and released)
reserved=false;released=false;reached=true
options.range=25
assert(not context.alignWithReservation(target,0,5,options) and released)
print('PASS: general reservation helper forwards targets/options, handles anchor replacement/loss and requires an active lease')
