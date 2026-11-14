local Waypoint={frames=32}
local tau=math.pi*2

local function finite(value)
    return type(value)=='number' and value==value and value~=math.huge and value~=-math.huge
end

local function sameZone(config,context)
    if type(config.zone)=='number' then return context.zone_id==config.zone end
    local expected=tostring(config.zone):lower()
    local zone=context.zone
    return type(zone)=='table' and ((type(zone.name)=='string' and zone.name:lower()==expected)
        or (type(zone.en)=='string' and zone.en:lower()==expected))
        or type(context.zone_name)=='string' and context.zone_name:lower()==expected
end

local function position(config,context,lastKnown)
    local entity
    if config.mob_id~=nil and type(context.mobById)=='function' then
        local ok,value=pcall(context.mobById,config.mob_id)
        if ok then entity=value end
    end
    if entity==nil and config.mob_name~=nil and type(context.findByName)=='function' then
        local ok,value=pcall(context.findByName,config.mob_name)
        if ok then entity=value end
    end
    local mob=type(entity)=='table' and (entity.mob or entity) or nil
    if mob and mob.valid_target~=false and finite(mob.x) and finite(mob.y) then
        return mob.x,mob.y,true,mob.id
    end
    local id=config.mob_id or mob and mob.id or type(lastKnown)=='table' and lastKnown.id
    if id~=nil and type(context.ipcPositionById)=='function' then
        local ok,value=pcall(context.ipcPositionById,id)
        if ok and type(value)=='table' and value.zone==context.zone_id
            and finite(value.x) and finite(value.y) then
            return value.x,value.y,true,id
        end
    end
    if finite(config.x) and finite(config.y) then return config.x,config.y,false,id end
end

function Waypoint.resolve(config,context,lastKnown)
    if not sameZone(config,context) then return nil end
    local me=context.me
    if type(me)~='table' or not finite(me.x) or not finite(me.y) or not finite(me.heading) then return nil end
    local dynamic=config.mob_id~=nil or config.mob_name~=nil
    local x,y,current,id=position(config,context,lastKnown)
    if x==nil and dynamic and type(lastKnown)=='table'
        and finite(lastKnown.x) and finite(lastKnown.y) then
        x,y,id=lastKnown.x,lastKnown.y,lastKnown.id
        current=false
    end
    if x==nil then return nil end
    local dx,dy=x-me.x,y-me.y
    local distance=math.sqrt(dx*dx+dy*dy)
    local stale=dynamic and not current
    local color=stale and 'gray'
        or distance<=config.near and 'green'
        or distance<=config.mid and 'yellow' or 'red'
    local desired=-math.atan2(dy,dx)
    local relative=(desired-me.heading)%tau
    local frame=math.floor(relative/tau*Waypoint.frames+0.5)%Waypoint.frames
    local label=''
    if config.show_distance then
        local ok,value=pcall(string.format,config.distance_format,distance)
        label=ok and value or '[error]'
    end
    return {distance=distance,color=color,frame=frame,label=label,
        x=x,y=y,id=id,current=current==true}
end

return Waypoint
