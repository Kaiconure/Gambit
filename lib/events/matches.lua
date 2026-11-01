local Aliases=require('./lib/resource-name-aliases')
local Matches={}
function Matches.attach(event)
    local id,name=event.id,event.name
    if event.kind=='status' then
        id=event.phase=='leave' and event.old_status or event.status
        name=event.category
    elseif event.kind=='zone' then
        if event.phase=='leave' then id,name=event.old_zone,event.old_zone_name
        else id,name=event.zone,event.zone_name end
    end
    local lower=(event.kind=='buff' and event.name_lower) or (type(name)=='string' and name:lower())
    if event.kind=='buff' then event.name_lower=lower or nil end
    local useAliases=event.kind=='spell' or event.kind=='enemy_spell' or event.kind=='enemy_ability'
        or event.kind=='pet_ability' or event.kind=='job_ability' or event.kind=='weapon_skill'
    local canonical=useAliases and Aliases.key(name)
    event.matches=function(value)
        if type(value)=='number' then return id~=nil and value==id end
        if type(value)~='string' then return false end
        local numeric=tonumber(value)
        if numeric then return id~=nil and numeric==id end
        if useAliases then return canonical~=nil and Aliases.key(value)==canonical end
        return lower~=nil and value:lower()==lower
    end
end
return Matches
