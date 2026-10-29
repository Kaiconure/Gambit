local factory = assert(loadfile('lib/movement-reservations.lua'))
local now, cancels = 0, 0
setfenv(factory, setmetatable({os={clock=function() return now end}}, {__index=_G}))
local manager = factory()
local vars={}
local function context(owner, section, scope)
    local c={action={movement_owner=owner},actionType=section or 'battle',battleScope=scope or 1,scopes={zone=1},vars=vars}
    manager.attach(c,function() cancels=cancels+1 end)
    return c
end
local rolls=context('rolls')
local follow=context(nil)
assert(rolls.reserveMovement(10) and cancels==1)
assert(rolls.movementAvailable() and not follow.movementAvailable())
assert(not context('other').reserveMovement(5))
assert(not follow.releaseMovement())
now=8
assert(context('rolls').reserveMovement(10))
now=10
assert(follow.movementAvailable() and cancels==2) -- reacquisition didn't extend
assert(rolls.reserveMovement(10))
assert(context(nil,'idle').movementAvailable()) -- phase change
local idle=context('rolls','idle')
assert(idle.reserveMovement(5))
assert(not context(nil,'idle').movementAvailable())
assert(idle.releaseMovement())
assert(context(nil,'idle').movementAvailable())
assert(rolls.reserveMovement(10))
assert(context(nil,'battle',2).movementAvailable())
assert(not pcall(follow.reserveMovement,5))
assert(not pcall(rolls.reserveMovement,math.huge))
assert(rolls.reserveMovement(10))
vars={}
assert(context(nil).movementAvailable()) -- reload snapshot
print('PASS: ownership, timeout, no renewal, phase/scope/reload release and cancellation')

local initial=context('continuation','battle',10)
assert(initial.reserveMovement(5))
now=now+5
assert(not initial.resumeMovement(5)) -- same battle cannot restart timeout
local between=context('continuation','idle',11)
assert(between.resumeMovement(5))
local nextBattle=context('continuation','battle',12)
assert(nextBattle.resumeMovement(5))
now=now+4
assert(nextBattle.resumeMovement(5))
now=now+1
assert(not nextBattle.resumeMovement(5)) -- continuation also has a hard deadline
assert(nextBattle.reserveMovement(5)) -- a new initial roll can start a new operation
assert(nextBattle.releaseMovement())
assert(not nextBattle.resumeMovement(5)) -- failed alignment/release doesn't loop
local competitor=context('other','battle',13)
assert(competitor.reserveMovement(5))
local pending=context('continuation','battle',13)
assert(not pending.resumeMovement(5))
assert(competitor.releaseMovement())
assert(pending.resumeMovement(5)) -- denied acquisition did not consume the opportunity
print('PASS: cross-battle continuation, expired/released rejection and contention retry')

local retry=context('retry','battle',14)
assert(retry.reserveMovement(20))
local deadline=now+20
now=now+2
assert(retry.releaseMovement(true))
assert(context(nil,'battle',14).movementAvailable())
local competing=context('competitor','battle',14)
assert(competing.reserveMovement(3))
assert(not retry.resumeMovement(20)) -- Contention must not erase the retry deadline.
assert(competing.releaseMovement())
assert(retry.resumeMovement(20))
now=now+3
assert(retry.releaseMovement(true))
assert(context('retry','battle',14).resumeMovement(20))
now=deadline
assert(not retry.resumeMovement(20)) -- Repeated retries cannot renew the original lease.
assert(retry.reserveMovement(20))
assert(retry.releaseMovement())
assert(not retry.resumeMovement(20)) -- Completion still closes continuation.
print('PASS: recoverable release retries across contexts and contention without extending deadline')
