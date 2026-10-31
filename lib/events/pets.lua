-- Pet commands use player dispatch, but execution packets belong to the pet.
local pets={}
function pets.current(ffxi)
    if ffxi.get_mob_by_target then
        local pet=ffxi.get_mob_by_target('pet')
        if pet then return pet end
    end
    local player=ffxi.get_player()
    if player and ffxi.get_mob_by_index then
        local owner=player.index and ffxi.get_mob_by_index(player.index)
        local index=player.pet_index or owner and owner.pet_index
        if index then return ffxi.get_mob_by_index(index) end
    end
end
local function selectRequest(service,actor,id,name)
    local selected
    for _,request in ipairs(service.runtime.pending) do
        local event=request.event
        if request.sent_at and event.kind=='pet_ability' and event.pet and event.pet.id==actor
            and (id==nil and name==nil or id and event.id==id or name and event.name==name) then
            if selected then return end -- Never guess among ambiguous requests.
            selected=request
        end
    end
    return selected
end
local failures={ [17]=true,[18]=true,[55]=true,[56]=true,[78]=true,[84]=true,[87]=true,[88]=true,
    [89]=true,[90]=true,[94]=true,[104]=true,[154]=true,[191]=true,[308]=true,[313]=true,
    [325]=true,[328]=true,[410]=true,[428]=true,[429]=true,[561]=true,[574]=true,
    [579]=true,[580]=true,[581]=true,[661]=true,[665]=true }
function pets.action(service,action)
    local player=service.deps.windower.ffxi.get_player()
    if not player then return false end
    local actor=action.actor_id
    local petRequest=selectRequest(service,actor)
    -- Multiple outstanding requests still identify a pet actor, but require
    -- resource matching before any lifecycle can advance.
    local isPet=petRequest~=nil
    for _,request in ipairs(service.runtime.pending) do
        if request.event.kind=='pet_ability' and request.event.pet and request.event.pet.id==actor then isPet=true end
    end
    local first=action.targets and action.targets[1]
    local detail=first and first.actions and first.actions[1]
    local message=detail and (tonumber(detail.message) or 0)%32768
    local category=action.category
    local resources=service.deps.resources
    if message==328 and (actor==player.id or isPet) then
        if not pets.reject(service,actor,detail and detail.param) then pets.reject(service,actor) end
        return true
    end
    if actor==player.id then
        if failures[message] then
            local ability=resources.job_abilities and resources.job_abilities[action.param]
            if ability and ability.prefix=='/pet' then
                pets.reject(service,actor,action.param)
                return true
            end
            if pets.reject(service,actor) then return true end
        end
        -- Simple commands (Heel, Stay, etc.) may complete on the player's JA
        -- acknowledgment and have no separate pet execution notification.
        if category==6 or category==14 or category==15 then
            local ability=resources.job_abilities and resources.job_abilities[action.param]
            if ability and ability.prefix=='/pet' and ability.type=='PetCommand' then
                for _,request in ipairs(service.runtime.pending) do
                    if request.sent_at and request.event.kind=='pet_ability' and request.event.id==ability.id then
                        service.runtime:finish(request,'completed'); return true
                    end
                end
            end
        end
        return false
    end
    if not isPet then return false end
    local beginning=category==7 or category==8 or category==9 or category==12
    if beginning and action.param==28787 then
        if petRequest then service.runtime:finish(petRequest,'interrupted') end
        return true
    end
    local id=beginning and detail and detail.param or action.param
    local resource
    if category==7 or category==11 then
        local text=resources.action_messages and resources.action_messages[message]
        if category==7 and text and text.en and text.en:find('${ability}',1,true) then
            resource=resources.job_abilities and resources.job_abilities[id]
        else resource=resources.monster_abilities and resources.monster_abilities[id] end
    elseif category==6 or category==13 or category==14 or category==15 then
        resource=resources.job_abilities and resources.job_abilities[id]
    elseif category==4 or category==8 then
        resource=resources.spells and resources.spells[id]
    end
    local request=resource and selectRequest(service,actor,nil,resource.en)
    if request then
        if failures[message] then service.runtime:finish(request,'failed')
        elseif beginning then
            if message and message~=0 and not request.pet_started then
                request.pet_started=true
                service.runtime:run(request,'mid')
            end
        elseif category==3 or category==4 or category==6 or category==11 or category==13 or category==14 or category==15 then
            service.runtime:finish(request,'completed')
        end
    elseif failures[message] then pets.reject(service,actor) end
    return true
end
function pets.reject(service,actor,id)
    local player=service.deps.windower.ffxi.get_player()
    local selected
    for _,request in ipairs(service.runtime.pending) do
        local event=request.event
        if id==nil and player and actor==player.id and request.sent_at and event.kind~='pet_ability' then
            return false -- An unidentified player rejection could belong to this action.
        end
        if request.sent_at and event.kind=='pet_ability' and event.pet
            and (actor==event.pet.id or player and actor==player.id)
            and (id==nil or event.id==id) then
            if selected then return false end
            selected=request
        end
    end
    if selected then service.runtime:finish(selected,'failed'); return true end
    return false
end
function pets.incoming(service,packet)
    local message=(tonumber(packet.Message) or 0)%32768
    if message==6 or message==20 or message==113 or message==406 or message==605 or message==646 then
        local affected={}
        for _,request in ipairs(service.runtime.pending) do
            local event=request.event
            if event.kind=='pet_ability' and (event.target and event.target.id==packet.Target
                or event.pet and event.pet.id==packet.Target) then affected[#affected+1]=request end
        end
        for _,request in ipairs(affected) do service.runtime:finish(request,'failed') end
        return #affected>0
    end
    if not failures[message] then return false end
    -- Message parameters are not universally ability IDs. Only use the ID for
    -- the explicit out-of-range BP message; otherwise require one candidate.
    if message==328 and pets.reject(service,packet.Actor,packet['Param 1']) then return true end
    return pets.reject(service,packet.Actor)
end
function pets.tick(service)
    if not service.runtime then return end
    local current=pets.current(service.deps.windower.ffxi)
    local pending={}
    for _,request in ipairs(service.runtime.pending) do pending[#pending+1]=request end
    for _,request in ipairs(pending) do
        if request.event.kind=='pet_ability' and request.event.pet
            and (not current or current.id~=request.event.pet.id or current.status==2 or current.status==3
                or current.hpp==0) then service.runtime:finish(request,'failed') end
    end
end
return pets
