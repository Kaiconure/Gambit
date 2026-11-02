local Observation=require('./lib/action-observation')
local SelfSpell=require('./lib/self-spell-state')
local Service=require('./lib/events/init')
local spell={id=10,en='Fire',name='Fire',element=0,cast_time=3}
local target={id=200,name='Enemy',index=2}
local globals={}
local order={}
local state={setSpellStart=function(_,resource,id)
    assert(resource==spell and id==200); order[#order+1]='state-start'
end,setSpellCompleted=function(_,interrupted)
    order[#order+1]=interrupted and 'state-interrupted' or 'state-completed'
end}
local deps={externalSelfSpells=true,externalEnemyActions=true,
    resources={spells={[10]=spell},job_abilities={}},
    windower={ffxi={get_player=function() return {id=100} end,
        get_mob_by_id=function(id) if id==200 then return target end end},
        register_event=function() end},
    observeSelfSpell=function(observation) SelfSpell.apply(observation,state,globals,function() return 50 end) end,
    afterSelfSpell=function() order[#order+1]='report' end}
local service=Service.new(deps)
service.runtime={pending={},spellStarted=function(_,id,targetId)
    assert(id==10 and targetId==200 and globals.isSpellCasting)
    assert(globals.last_spell.status=='casting'); order[#order+1]='mid'
end,complete=function(_,kind,id,_,outcome)
    assert(kind=='spell' and not globals.isSpellCasting)
    assert(globals.currentSpell==nil and globals.spellTarget==nil)
    order[#order+1]=outcome
end}
local function action(category,param,id,message)
    return {actor_id=100,category=category,param=param,
        targets={{id=200,actions={{param=id,message=message}}}}}
end
assert(service:selfSpellAction(action(8,24931,10)))
assert(table.concat(order,',')=='state-start,mid,report')
assert(globals.last_spell.target.id==200 and globals.last_spell.target.name=='Enemy')
order={}
local completed=action(4,10,123,0)
assert(service:selfSpellAction(completed))
assert(table.concat(order,',')=='state-completed,completed,report')
assert(globals.last_spell.status=='completed')
order={}; service:action(completed)
assert(#order==0) -- Later action listener must not apply/dispatch the same spell twice.
service:selfSpellAction(action(8,24931,10))
order={}; service:selfSpellAction(action(8,28787,0))
assert(table.concat(order,',')=='state-interrupted,interrupted,report')
assert(globals.last_spell.status=='interrupted')
order={}; service:selfSpellAction(completed) -- Post without start still records history and dispatches.
assert(table.concat(order,',')=='completed,report')
service:selfSpellAction(action(8,24931,10))
order={}; service:selfSpellAction(action(4,10,0,88))
assert(table.concat(order,',')=='state-completed,failed,report')
service.runtime=nil
assert(service:selfSpellAction(action(8,24931,10)))
assert(globals.isSpellCasting) -- State works without an active event file.
local unrelated=action(8,24931,10); unrelated.actor_id=300
assert(not Observation.selfSpell(unrelated,deps.windower.ffxi,deps.resources))
local unknown=action(8,24931,999)
assert(service:selfSpellAction(unknown) and globals.isSpellCasting and not globals.currentSpell)
service:selfSpellAction(action(8,28787,0))
assert(not globals.isSpellCasting)
print('PASS: self spell state/history precede lifecycle, reporting follows, interruption/rejection, post-only, dedup and no-event state')
