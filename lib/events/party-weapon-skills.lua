local Result=require('./lib/weapon-skill-result')
local metadata=require('./lib/target-metadata')
local party={}
function party.action(service,action,failures,selfOnly)
    if not action or action.category~=3 or not service.runtime then return end
    local config=service.runtime.config
    local section=selfOnly and 'weapon_skills' or 'party_weapon_skills'
    if not config.rules[section] or #config.rules[section].post==0 then return end
    local deps=service.deps
    local ffxi=deps.windower.ffxi
    local player=ffxi.get_player()
    local actor=ffxi.get_mob_by_id(action.actor_id)
    if not player or not actor then return end
    if selfOnly and actor.id~=player.id then return end
    if actor.id~=player.id and actor.spawn_type~=1 and actor.spawn_type~=13 then return end
    local inParty=actor.id==player.id or actor.in_party==true
    local inAlliance=inParty or actor.in_alliance==true
    -- Party records can be more complete than mob membership flags.
    local roster=ffxi.get_party and ffxi.get_party() or {}
    for key,member in pairs(roster) do
        local index=type(key)=='string' and tonumber(key:match('^p(%d+)$'))
        local allianceSlot=type(key)=='string' and key:match('^a[12][0-5]$')
        local id=type(member)=='table' and (member.mob and member.mob.id or member.id)
        if (index and index<=17 or allianceSlot) and id==actor.id then
            inAlliance=true
            if index and index<=5 then inParty=true end
        end
    end
    local options=config.vars.party_weapon_skills or {}
    if not inParty and not (options.include_alliance and inAlliance) then return end
    local first=action.targets and action.targets[1]
    local detail=first and first.actions and first.actions[1]
    local message=(tonumber(detail and detail.message) or 0)%32768
    local template=deps.resources.action_messages and deps.resources.action_messages[message]
    if template and template.en and template.en:find('{ability}',1,true) then return end
    local resource=deps.resources.weapon_skills and deps.resources.weapon_skills[action.param]
    if not resource or not first then return end
    local results=Result.targets(action.targets,failures)
    local targetId=first.id
    if actor.id==player.id then
        targetId=service.wsObservedTargets and service.wsObservedTargets[action] or targetId
        for _,request in ipairs(service.runtime.pending) do
            local event=request.event
            if request.sent_at and event.kind=='weapon_skill' and event.id==action.param
                and event.target and Result.find(results,event.target.id) then
                targetId=event.target.id;break
            end
        end
    end
    local event={kind=selfOnly and 'weapon_skill' or 'party_weapon_skill',id=resource.id or action.param,name=resource.en or resource.name,
        actor_id=actor.id,actor=metadata.snapshot(actor,actor,player.id),
        target=metadata.snapshot({id=first.id},ffxi.get_mob_by_id(first.id),player.id),targets={}}
    event.actor.is_party_member=inParty
    event.actor.is_alliance_member=inAlliance
    event.actor.is_me=actor.id==player.id
    for _,target in ipairs(action.targets) do
        local mob=ffxi.get_mob_by_id(target.id)
        event.targets[#event.targets+1]=metadata.snapshot({id=target.id,name=mob and mob.name,index=mob and mob.index},mob,player.id)
    end
    event.target=event.targets[1]
    for _,target in ipairs(event.targets) do if target.id==targetId then event.target=target;break end end
    Result.properties(event,resource)
    Result.apply(event,results,targetId)
    local result=Result.find(event.results,targetId)
    event.outcome=result and result.outcome or 'completed'
    event.completed=event.outcome=='completed';event.failed=event.outcome=='failed'
    service.runtime:observe(event,'post')
    return true
end
return party
