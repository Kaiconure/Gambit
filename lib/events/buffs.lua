-- Self buff notifications from Windower, independent of automation enablement.
local buffs={}
function buffs.attach(service,listen)
    local deps=service.deps
    local function emit(id,phase)
        if not service.runtime or type(id)~='number' or id<0 or id%1~=0 then return end
        local player=deps.windower.ffxi.get_player()
        if not player then return end
        local resource=deps.resources.buffs and deps.resources.buffs[id]
        local name=resource and resource.en
        service.runtime:observe({kind='buff',id=id,name=name,name_lower=name and name:lower(),
            actor_id=player.id},phase)
    end
    listen('gain buff',function(id) emit(id,'added') end)
    listen('lose buff',function(id) emit(id,'removed') end)
end
return buffs
