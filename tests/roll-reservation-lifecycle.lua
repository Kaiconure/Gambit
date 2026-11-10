local json=require('./lib/jsonlua')
local f=assert(io.open('actions/lib/abilities/use-rolls.json'));local doc=json.parse(f:read('*a'));f:close()
local now=0
local factory=assert(loadfile('lib/movement-reservations.lua'))
setfenv(factory,setmetatable({os={clock=function()return now end}},{__index=_G}))
local manager=factory()
local vars={use_rolls={alignment={enabled=true,timeout=90,targets={'PLD'},range=3,distance=3},
 _alignment_roll="Tactician's Roll",logic={["Tactician's Roll"]={double_up={1,2,3,4,6}}}}}
local chance=false
local context={vars=vars,actionType='idle',battleScope=1,scopes={zone=1},
 action={movement_owner='corsair-rolls'},
 latestRoll={name="Tactician's Roll",count=1},
 member={id=2,name='Carbonite',distance=2.5,valid_target=true},
 hasBuff=function(name)if name=='Double-Up Chance' then return chance end;return false end,
 any=function(value,items)for _,item in ipairs(items)do if value==item then return true end end;return false end,
 canUse=function()return false end,postpone=function()end,
 align=function()error('A nearby PLD should not require movement')end}
context.approachWithinRange=function(target,_,options)return target.distance<=options.range end
context.getLatestRoll=function()return context.latestRoll end
context.partyAnchorByName=function()return context.member end
context.setVar=function(_,value)vars.use_rolls._alignment_roll=value end
manager.attach(context,function()end)
require('./lib/engagement-helpers').attach(context)
local function evaluate(expression)
 local fn=assert(loadstring('return '..expression));setfenv(fn,context);return fn()
end
assert(context.reserveMovement(90))
-- Cleanup can observe missing Chance while result/buff updates are settling.
assert(evaluate(doc.actions[1].when[2]))
for _,command in ipairs(doc.actions[1].commands)do evaluate(command)end
assert(not context.hasMovementReservation())
now=1;chance=true
assert(evaluate(doc.macros.roll_alignment_window[1]),'Cleanup permanently closed the active roll reservation')
assert(evaluate(doc.macros.roll_alignment[1]))
-- Recovery must not extend the original deadline or displace another owner.
assert(context.releaseMovement(true))
context.action={movement_owner='other'};assert(context.reserveMovement(5))
context.action={movement_owner='corsair-rolls'}
assert(not evaluate(doc.macros.roll_alignment_window[1]))
context.action={movement_owner='other'};assert(context.releaseMovement())
context.action={movement_owner='corsair-rolls'}
assert(evaluate(doc.macros.roll_alignment_window[1]))
assert(context.releaseMovement(true));now=90
assert(not evaluate(doc.macros.roll_alignment_window[1]))
print('PASS: initial roll cleanup, nearby PLD, Double-Up reservation recovery, contention and unchanged deadline')
