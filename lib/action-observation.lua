-- Decode other actors' actions once; consumers own state and presentation policy.
local Observation={}
-- Compatibility projection for effect reactions. Reuse the decoded action
-- instead of parsing the incoming action chunk again in a second listener.
function Observation.effectsPacket(action)
    local packet={Actor=action.actor_id,Param=action.param,Category=action.category,
        ['Target Count']=#(action.targets or {})}
    for index,target in ipairs(action.targets or {}) do
        local prefix='Target '..index
        packet[prefix..' ID']=target.id
        local detail=target.actions and target.actions[1]
        if detail then
            packet[prefix..' Action 1 Param']=detail.param
            packet[prefix..' Action 1 Message']=detail.message
            packet[prefix..' Action 1 Reaction']=detail.reaction
        end
    end
    return packet
end
function Observation.action(action,ffxi,resources,failures,includeAllied)
    if not action then return end
    local player=ffxi.get_player()
    if not player or action.actor_id==player.id then return end
    local category=action.category
    local spell=category==4 or category==8
    if not spell and category~=7 and category~=11 then return end
    local actor=ffxi.get_mob_by_id(action.actor_id)
    if not actor then return end
    local enemy=actor.spawn_type==16
    if not enemy and not (includeAllied and spell and actor.valid_target and actor.hpp and actor.hpp>0) then return end
    local first=action.targets and action.targets[1]
    local detail=first and first.actions and first.actions[1]
    local beginning=category==7 or category==8
    local interrupted=beginning and action.param==28787
    if beginning and not interrupted and action.param~=24931 then return end
    local id=tonumber(beginning and detail and detail.param or (not beginning and action.param))
    if id and id<=0 then id=nil end
    local source=spell and resources.spells or resources.monster_abilities
    local resource=id and source and source[id]
    local phase=beginning and not interrupted and 'pre' or 'post'
    local message=detail and (tonumber(detail.message) or 0)%32768
    local outcome=phase=='post' and (interrupted and 'interrupted'
        or (failures and failures[message]) and 'failed' or 'completed') or nil
    local targets,resolved={},{}
    for _,entry in ipairs(action.targets or {}) do
        local mob=ffxi.get_mob_by_id(entry.id)
        resolved[entry.id]=mob
        targets[#targets+1]=mob or {id=entry.id}
    end
    return {kind=not enemy and 'allied_spell' or spell and 'enemy_spell' or 'enemy_ability',phase=phase,id=id,
        name=resource and resource.en,resource=resource,actor=actor,player=player,
        targets=targets,resolved_targets=resolved,target=targets[1],outcome=outcome}
end
function Observation.enemy(action,ffxi,resources,failures)
    return Observation.action(action,ffxi,resources,failures,false)
end
function Observation.selfSpell(action,ffxi,resources,failures)
    if not action then return end
    local player=ffxi.get_player()
    if not player or action.actor_id~=player.id then return end
    local start=action.category==8 and action.param==24931
    local interrupted=action.category==8 and action.param==28787
    if not start and not interrupted and action.category~=4 then return end
    local first=action.targets and action.targets[1]
    local detail=first and first.actions and first.actions[1]
    local id
    if start then id=detail and detail.param elseif action.category==4 then id=action.param end
    local resource=id and resources.spells and resources.spells[id]
    local target=first and ffxi.get_mob_by_id(first.id)
    local failed=detail and failures and failures[(tonumber(detail.message) or 0)%32768]
    return {kind='spell',phase=start and 'mid' or 'post',id=id,resource=resource,
        target=target,target_id=first and first.id,detail=detail,
        outcome=not start and (interrupted and 'interrupted' or failed and 'failed' or 'completed') or nil}
end
function Observation.selfResult(action,ffxi,resources,failures)
    if not action then return end
    local kind=(action.category==6 or action.category==14) and 'job_ability'
        or action.category==3 and 'weapon_skill'
    if not kind then return end
    local player=ffxi.get_player()
    if not player or action.actor_id~=player.id then return end
    local first=action.targets and action.targets[1]
    local detail=first and first.actions and first.actions[1]
    local source=kind=='job_ability' and resources.job_abilities or resources.weapon_skills
    local resource=source and source[action.param]
    local message=(tonumber(detail and detail.message) or 0)%32768
    return {kind=kind,phase='post',id=action.param,resource=resource,detail=detail,message=message,
        actor=ffxi.get_mob_by_id and ffxi.get_mob_by_id(action.actor_id),
        target_id=first and first.id,
        target=first and ffxi.get_mob_by_id and ffxi.get_mob_by_id(first.id),
        outcome=failures and failures[message] and 'failed' or 'completed'}
end
return Observation
