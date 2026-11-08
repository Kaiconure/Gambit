-- Independent observations: no pending lifecycles, inferred completions or waits.
local metadata=require('./lib/target-metadata')
local magicSkills=require('./meta/magic-skills')
local cureSpell=require('./lib/cure-spell')
local Observation=require('./lib/action-observation')
local enemies={}
function enemies.action(service,action,failures)
    local deps=service.deps
    local observation=Observation.action(action,deps.windower.ffxi,deps.resources,failures,true)
    if not observation then return false end
    require('./lib/encounter-state').enemy(observation)
    if deps.observeEnemy then
        local ok,err=pcall(deps.observeEnemy,observation)
        if not ok then deps.report('Enemy state observation: '..tostring(err)) end
    end
    -- Allied casting uses the same observation/state path, but does not emit
    -- enemy events or enemy-only reporting.
    if observation.kind=='allied_spell' then return true end
    if not service.runtime then
        if deps.afterEnemy then deps.afterEnemy(observation) end
        return true
    end
    local actor,player,resource=observation.actor,observation.player,observation.resource
    local spell=observation.kind=='enemy_spell'
    local id,phase,outcome=observation.id,observation.phase,observation.outcome
    local resources=deps.resources
    local function target(identity)
        local mob=identity and observation.resolved_targets[identity.id]
        return metadata.snapshot(identity and {id=identity.id,name=mob and mob.name,index=mob and mob.index},mob,player.id) or {}
    end
    local element=resource and resources.elements and resources.elements[resource.element]
    local skill=resource and resources.skills and resources.skills[resource.skill]
    local event={kind=spell and 'enemy_spell' or 'enemy_ability',id=id,name=resource and resource.en,
        actor_id=actor.id,actor=metadata.snapshot(actor,actor,player.id),
        target=target(observation.target),targets={},type=resource and resource.type,
        cast_time=spell and resource and resource.cast_time or nil,
        element=resource and resource.element,element_name=element and element.en,
        skill=resource and resource.skill,skill_name=skill and skill.en,
        outcome=outcome,completed=outcome=='completed',interrupted=outcome=='interrupted',failed=outcome=='failed'}
    for _,entry in ipairs(observation.targets) do event.targets[#event.targets+1]=target(entry) end
    if spell and resource then
        for name,skillId in pairs(magicSkills) do event[name]=resource.skill==skillId end
        event.curing=cureSpell(resource)
    end
    service.runtime:observe(event,phase)
    if deps.afterEnemy then deps.afterEnemy(observation) end
    return true
end
return enemies
