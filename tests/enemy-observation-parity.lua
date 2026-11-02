local function read(path) local f=assert(io.open(path)); local s=f:read('*a'); f:close(); return s end
local now=100
local stateSource=read('lib/action-state-manager.lua')
stateSource=stateSource:gsub('("[^"\r\n]*"):format','(%1):format'):gsub("('[^'\r\n]*'):format",'(%1):format')
local stateChunk=assert(loadstring(stateSource))
setfenv(stateChunk,setmetatable({os={clock=function() return now end}},{__index=_G}))
local state=stateChunk()
local source=read('lib/action-context.lua')
local first=assert(source:find('    context.enemyCastingSpell = function',1,true))
local last=assert(source:find('    context.partyUsingWeaponSkill = function',first,true))
local body=source:sub(first,last-1)
local mobs={
    [100]={id=100,index=1,name='Self',spawn_type=1,valid_target=true},
    [200]={id=200,index=2,name='Enemy',spawn_type=16,valid_target=true,status=1},
    [300]={id=300,index=3,name='Other',spawn_type=16,valid_target=true,status=1},
}
local bt=mobs[200]
local lookups={}
local ffxi={get_player=function() return {id=100} end,get_mob_by_id=function(id)
    lookups[id]=(lookups[id] or 0)+1; return mobs[id]
end}
local function context()
    local ctx={bt=bt,me=mobs[100],party1_by_id={[100]=mobs[100]}}
    local fn=assert(loadstring(body))
    setfenv(fn,setmetatable({context=ctx,actionStateManager=state,windower={ffxi=ffxi},
        resourceNameAliases=require('./lib/resource-name-aliases'),
        varargs=function(args) return type(args[1])=='table' and args[1] or args end},{__index=_G}))
    fn(); return ctx
end
local order,seen={},{}
local Config=require('./lib/events/config')
local Runtime=require('./lib/events/runtime')
local Service=require('./lib/events/init')
local rules={}
for _,section in ipairs({'enemy_spells','enemy_abilities'}) do
    rules[section]={pre={{commands={'record(event)'}}},post={{commands={'record(event)'}}}}
end
local resources={spells={[10]={id=10,name='Fire',en='Fire',skill=36,element=0,cast_time=3}},
    monster_abilities={[20]={id=20,name="Nature's Meditation",en="Nature's Meditation"}},
    elements={[0]={en='Fire'}},skills={[36]={en='Elemental Magic'}},job_abilities={}}
local deps={externalEnemyActions=true,windower={ffxi=ffxi,register_event=function(name) return name end,
    unregister_event=function() end},resources=resources,clock=function() return now end,
    report=function(err) error(err) end,
    observeEnemy=function(observation)
        order[#order+1]='state'; state:observeEnemyAction(observation)
        assert(observation.resource==nil or observation.resource==resources.spells[observation.id]
            or observation.resource==resources.monster_abilities[observation.id])
    end,
    afterEnemy=function() order[#order+1]='after' end,
    context=function()
        local ctx=context()
        ctx.record=function(event)
            order[#order+1]='event'; seen[#seen+1]=event
            if event.kind=='enemy_spell' then
                assert(not not ctx.enemyCastingSpell()==(event.phase=='pre'))
            elseif event.phase=='pre' and event.actor.id==bt.id then
                assert(ctx.enemyUsingAbilityNC('Nat. Meditation').id==20)
                assert(ctx.enemyUsingAbilityNC(20).id==20 and ctx.enemyUsingAbilityNC('20').id==20)
            end
        end
        return ctx
    end}
local service=Service.new(deps)
service.runtime=Runtime.new(Config.load({'test'},function() return rules end),deps)
local function emit(category,param,id,actor)
    local action={actor_id=actor or 200,category=category,param=param,
        targets={{id=100,actions={{param=id,message=0}}},{id=300,actions={{message=0}}}}}
    order={}; lookups={}
    assert(service:enemyAction(action))
    assert(table.concat(order,',')=='state,event,after')
    assert(lookups[200]==1) -- Actor identity resolved only once by the shared decoder.
    local count=#seen
    service:action(action) -- The later Windower action listener must not decode/dispatch again.
    assert(#seen==count)
end
emit(7,24931,20)
local ctx=context()
assert(#state.mobAbilities[200].targets==2)
assert(ctx.enemyUsingAbilityNC('*') and ctx.enemyUsingAbility('Nat. Meditation'))
assert(not ctx.enemyUsingAbilityNC() and ctx.enemyUsedAbilityNC('20'))
assert(ctx.enemyUsedAbility(20) and not ctx.enemyUsedAbilityNC())
now=101; emit(11,20)
assert(not context().enemyUsedAbilityNC()) -- Completion never recreates consumed tracking.
now=110; emit(7,24931,20)
now=111; emit(11,20)
assert(not context().enemyUsingAbilityNC() and context().enemyUsedAbilityNC("Nature's Meditation"))
now=116.01; assert(not context().enemyUsedAbilityNC())
now=120; emit(8,24931,10)
assert(context().enemyCastingSpell(10) and context().enemyCastingSpell('Fire'))
now=121; emit(8,28787,0)
assert(not context().enemyCastingSpell())
now=122; emit(4,10) -- Post without pre still dispatches and clears state.
now=123; emit(7,24931,20)
now=124; emit(7,28787,0)
assert(not context().enemyUsingAbilityNC() and context().enemyUsedAbilityNC())
-- An unrelated actor updates its own record; bt helper queries remain scoped.
bt=mobs[300]; now=125; emit(11,20,nil,200)
assert(not context().enemyUsedAbilityNC())
service.runtime=nil; now=130
assert(service:enemyAction({actor_id=300,category=8,param=24931,targets={{id=100,actions={{param=10}}}}}))
assert(context().enemyCastingSpell()) -- State publication is independent of event file availability.
assert(not read('lib/eventing.lua'):find('markMobAbilityStart',1,true))
assert(not read('Gambit.lua'):find('actionStateManager:setOthersSpellStart',1,true))
-- Allied casting shares decoding/state publication without enemy event dispatch.
mobs[400]={id=400,index=4,name='Ally',spawn_type=1,valid_target=true,hpp=100}
service.runtime=Runtime.new(Config.load({'test'},function() return rules end),deps)
local eventCount=#seen
local function allied(category,param,id,target)
    return service:enemyAction({actor_id=400,category=category,param=param,
        targets={{id=target or 100,actions={{param=id}}}}})
end
now=200
assert(allied(8,24931,10))
assert(state:getOthersSpellInfo(mobs[400]).spell==resources.spells[10])
assert(state:getOthersSpellInfo(mobs[400]).targetId==100)
assert(#seen==eventCount)
assert(allied(4,10))
assert(not state:getOthersSpellInfo(mobs[400]))
assert(allied(8,24931,10) and allied(8,28787,0))
assert(not state:getOthersSpellInfo(mobs[400]))
assert(allied(8,24931,10,999)) -- Unknown target retains the old no-start behavior.
assert(not state:getOthersSpellInfo(mobs[400]))
mobs[400].hpp=0
assert(not allied(8,24931,10))
mobs[400].hpp=100
assert(not allied(7,24931,20)) -- Non-enemy abilities are not enemy observations.
assert(#seen==eventCount)
service.runtime=nil
assert(allied(8,24931,10))
assert(state:getOthersSpellInfo(mobs[400]))
now=217
assert(not state:getOthersSpellInfo(mobs[400])) -- Existing cast-time-based expiry is preserved.
print('PASS: shared resource/state/event identity, immediate helper parity, single dispatch, consumption/expiry and allied casting')
