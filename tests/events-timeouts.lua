local Config=require('./lib/events/config')
local Runtime=require('./lib/events/runtime')
local now,posts,dispatches=0,0,0
local config=Config.load({'test'},function() return {
    job_abilities={post={{commands={'finished()'}}}},
    weapon_skills={post={{commands={'finished()'}}}},
    spells={post={{commands={'finished()'}}}},
    pet_abilities={post={{commands={'finished()'}}}}
} end)
local runtime=Runtime.new(config,{
    clock=function() return now end,report=function(message) error(message) end,
    context=function() return {finished=function() posts=posts+1 end} end,
    equipmentSession=function() return {inventory={snapshot_equipment=function() return {} end},
        discard=function() end,commit=function() end} end,
    barrier=function(fn) fn(true) end
})
local diagnostics={}
runtime.deps.debug=function(message) diagnostics[#diagnostics+1]=message end
local function submit(kind,cast)
    runtime:submit({kind=kind,id=1,target={id=2},cast_time=cast},function() dispatches=dispatches+1 end)
end
submit('job_ability'); now=2.99; submit('job_ability'); assert(dispatches==1 and posts==0)
now=3; submit('job_ability'); assert(dispatches==2 and posts==1 and #runtime.pending==1)
assert(diagnostics[#diagnostics]:find('3.000s since creation',1,true))
assert(diagnostics[#diagnostics]:find('3.000s since dispatch',1,true))
runtime:clear('reloaded')
for _,entry in ipairs({{'weapon_skill',3},{'spell',23,10},{'pet_ability',30}}) do
    local start=now; submit(entry[1],entry[3])
    if entry[1]=='spell' then assert(runtime:spellStarted(1,2)) end
    now=start+entry[2]-0.01; runtime:tick(); assert(#runtime.pending==1)
    now=start+entry[2]; runtime:tick(); assert(#runtime.pending==0)
end
print('PASS: short JA/WS timeouts, duplicate recovery, cast-aware spell and pet timeouts')

-- Long spells that never start expire quickly; confirmed casts keep their window.
submit('spell',15); local castDispatch=now
assert(not runtime:spellStarted(2,2) and not runtime:spellStarted(1,3))
now=castDispatch+2.99; runtime:tick(); assert(#runtime.pending==1)
now=castDispatch+3; runtime:tick(); assert(#runtime.pending==0)
submit('spell',15); castDispatch=now
now=castDispatch+2; assert(runtime:spellStarted(1,2))
now=castDispatch+10; assert(runtime:spellStarted(1,2))
now=castDispatch+34.99; runtime:tick(); assert(#runtime.pending==1)
now=castDispatch+35; runtime:tick(); assert(#runtime.pending==0)
submit('spell',15)
assert(runtime:complete('spell',1,2,'completed') and #runtime.pending==0)

-- A ready ordinary ability can recover sooner, but not during the grace period.
runtime.deps.retryReady=function() return true end
local before=posts; local sent=dispatches
submit('job_ability'); local start=now
now=start+0.99; submit('job_ability'); assert(dispatches==sent+1 and posts==before)
now=start+1; submit('job_ability'); assert(dispatches==sent+2 and posts==before+1)
runtime:clear('reloaded')

-- An equipment wait has its own bound; its late callback must not dispatch.
local release
runtime.deps.barrier=function(fn) release=fn end
sent=dispatches; submit('job_ability'); start=now
now=start+9.99; runtime:tick(); assert(#runtime.pending==1)
now=start+10; runtime:tick(); assert(#runtime.pending==0)
assert(diagnostics[#diagnostics]:find('10.000s since creation, not dispatched',1,true))
release(true); assert(dispatches==sent)

-- A rejection of the new JA must not be lost behind an older pending spell.
local Service=require('./lib/events/init')
local finished
local old={sent_at=now-5,event={kind='spell'}}
local newer={sent_at=now-0.5,event={kind='job_ability'}}
local service=setmetatable({deps={clock=function() return now end},runtime={
    pending={old,newer},diagnostic=function() end,
    finish=function(_,request,outcome) finished=request; assert(outcome=='failed') end
}}, {__index=Service})
service:reject(); assert(finished==newer)
finished=nil; old.sent_at=newer.sent_at
service:reject(); assert(finished==nil) -- Ambiguity must remain conservative.

local lost={event={target={id=42,is_mob=true}}}
service.runtime.pending={lost}
service.runtime.diagnostic=function() end
service.deps.windower={ffxi={get_mob_by_id=function() return {valid_target=true,hpp=0} end}}
service:validatePendingTargets(); assert(finished==lost)
print('PASS: readiness recovery grace, bounded dispatch wait, stale-spell rejection correlation and target loss')
