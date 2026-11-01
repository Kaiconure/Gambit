-- Independent observations: no pending lifecycles, inferred completions or waits.
local metadata=require('./lib/target-metadata')
local magicSkills=require('./meta/magic-skills')
local cureSpell=require('./lib/cure-spell')
local enemies={}
function enemies.action(service,action,failures)
    local deps=service.deps
    local ffxi=deps.windower.ffxi
    local player=ffxi.get_player()
    if not player then return false end
    if action.actor_id==player.id then return false end
    local actor=ffxi.get_mob_by_id(action.actor_id)
    if not actor or actor.spawn_type~=16 then return false end
    local category=action.category
    local spell=category==4 or category==8
    local ability=category==7 or category==11
    if not spell and not ability then return false end
    local first=action.targets and action.targets[1]
    local detail=first and first.actions and first.actions[1]
    local beginning=category==7 or category==8
    local interrupted=beginning and action.param==28787
    if beginning and not interrupted and action.param~=24931 then return false end
    local id=tonumber(beginning and detail and detail.param or (not beginning and action.param))
    if id and id<=0 then id=nil end
    local resources=deps.resources
    local source=spell and resources.spells or resources.monster_abilities
    local resource=id and source and source[id]
    local phase=beginning and not interrupted and 'pre' or 'post'
    local message=detail and (tonumber(detail.message) or 0)%32768
    local outcome=phase=='post' and (interrupted and 'interrupted'
        or (failures and failures[message]) and 'failed' or 'completed') or nil
    local function target(identity)
        local mob=identity and ffxi.get_mob_by_id(identity.id)
        return metadata.snapshot(identity and {id=identity.id,name=mob and mob.name,index=mob and mob.index},mob,player.id) or {}
    end
    local element=resource and resources.elements and resources.elements[resource.element]
    local skill=resource and resources.skills and resources.skills[resource.skill]
    local event={kind=spell and 'enemy_spell' or 'enemy_ability',id=id,name=resource and resource.en,
        actor_id=actor.id,actor=metadata.snapshot(actor,actor,player.id),
        target=target(first),targets={},type=resource and resource.type,
        cast_time=spell and resource and resource.cast_time or nil,
        element=resource and resource.element,element_name=element and element.en,
        skill=resource and resource.skill,skill_name=skill and skill.en,
        outcome=outcome,completed=outcome=='completed',interrupted=outcome=='interrupted',failed=outcome=='failed'}
    for _,entry in ipairs(action.targets or {}) do event.targets[#event.targets+1]=target(entry) end
    if spell and resource then
        for name,skillId in pairs(magicSkills) do event[name]=resource.skill==skillId end
        event.curing=cureSpell(resource)
    end
    service.runtime:observe(event,phase)
    return true
end
return enemies
