-- Observational status and zone notifications. Arrival waits for live player state.
local statusCategories=require('./lib/events/statuses').byId
local transitions={}
function transitions.attach(service,listen)
    local deps=service.deps
    local ffxi=deps.windower.ffxi
    local function info() return ffxi.get_info and ffxi.get_info() end
    local initial=info()
    local currentZone=initial and initial.zone
    local departing,pending
    local function zoneEvent(zone,old)
        local zones=deps.resources.zones or {}
        local current,previous=zones[zone],zones[old]
        return {kind='zone',zone=zone,zone_name=current and current.en,zone_search=current and current.search,
            old_zone=old,old_zone_name=previous and previous.en,old_zone_search=previous and previous.search}
    end
    local function emit(event,phase)
        local player=ffxi.get_player()
        event.actor_id=player and player.id
        if service.runtime then service.runtime:observe(event,phase) end
    end
    local function leave(destination,old)
        if departing then return end
        departing=true
        service:clear('zoned')
        emit(zoneEvent(destination,old or currentZone),'leave')
    end
    listen('status change',function(status,old)
        if departing or status==old then return end
        local previous,current=statusCategories[old],statusCategories[status]
        if previous==current then return end
        if previous then emit({kind='status',category=previous,status=status,old_status=old},'leave') end
        if current then emit({kind='status',category=current,status=status,old_status=old},'enter') end
    end)
    service.transitionIncoming=function(id,original,modified,injected,blocked)
        if id==0x00B and not injected and not blocked then leave(nil,currentZone) end
    end
    listen('zone change',function(zone,old)
        if zone==nil then return end
        if (pending and pending.zone==zone) or (not departing and currentZone==zone) then return end
        local previous=old or currentZone
        leave(zone,previous)
        currentZone=zone
        pending=zoneEvent(zone,previous)
    end)
    service.transitionTick=function()
        if not pending then return end
        local state=info()
        local player=ffxi.get_player()
        local mob=ffxi.get_mob_by_target and ffxi.get_mob_by_target('me')
        if not state or state.zone~=pending.zone or state.logged_in==false
            or not player or not mob or mob.id~=player.id or not mob.valid_target then return end
        local event=pending
        pending=nil
        departing=false
        emit(event,'enter')
    end
    service.transitionLogout=function() currentZone=nil; pending=nil; departing=nil end
end
return transitions
