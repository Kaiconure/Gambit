local M={}
function M.enabled(options)
    return type(options)=='table' and type(options.anchor)=='table'
        and (options.anchor.capture=='battle_start' or options.anchor.capture=='when_established')
end
local function options(context) return context.vars.frontline_engagement end
local function publishPosition(context,config,point)
    if type(config)~='table' or type(config.anchor)~='table' then return end
    local old=config.anchor.position
    if not point and old==nil then return end
    if point and type(old)=='table' and old.x==point.x and old.y==point.y and old.zone==point.zone then return end
    -- Public coordinates are a snapshot, never the mutable internal state.
    local position=point and {x=point.x,y=point.y,zone=point.zone} or nil
    if config==options(context) then
        context.setVar('frontline_engagement.anchor.position',position)
    else
        config.anchor.position=position
    end
end
function M.capture(context)
    local config=options(context)
    if not M.enabled(config) or context.actionType~='battle' then
        publishPosition(context,config,nil)
        return
    end
    local previous=config._anchor
    local zone=context.zone_id
    if previous and previous.battle==context.battleScope and previous.zone==zone then
        publishPosition(context,config,previous)
        return
    end
    publishPosition(context,config,nil)
    if config.anchor.capture=='when_established'
        and (context.state_time or 0)<math.max(0,tonumber(config.anchor.capture_delay) or 10) then return end
    local me=context.me
    if not me or type(me.x)~='number' or type(me.y)~='number' then return end
    local point={x=me.x,y=me.y,battle=context.battleScope,zone=zone,returning=false}
    context.setVar('frontline_engagement._anchor',point)
    publishPosition(context,config,point)
end
local function state(context,config)
    config=config or options(context)
    if not M.enabled(config) or context.actionType~='battle' then
        publishPosition(context,config,nil)
        return
    end
    -- Configuration overrides tune the return; the battle-start point remains
    -- owned by the ordinary frontline state and must never be recaptured here.
    local defaults=options(context)
    local point=defaults and defaults._anchor
    if point and point.battle==context.battleScope and point.zone==context.zone_id then
        publishPosition(context,config,point)
        if point.cancelled then return end
        if config.anchor.cancel_when~=nil and context.evaluateAll(config.anchor.cancel_when) then
            -- Keep the battle identity as a tombstone so capture cannot recreate
            -- the anchor on the next context update.
            context.setVar('frontline_engagement._anchor.cancelled',true)
            context.setVar('frontline_engagement._anchor.returning',false)
            context.setVar('frontline_engagement.arrived',false)
            return
        end
        return point,config.anchor
    end
    publishPosition(context,config,nil)
end
function M.active(context,config)
    config=config or options(context)
    if context.actionType~='battle' or not M.enabled(config) then
        publishPosition(context,config,nil)
        return false
    end
    -- Delayed capture leaves ordinary positioning enabled until this battle
    -- actually has a saved point; never reuse an earlier battle's anchor.
    local point=state(context,config)
    local defaults=options(context)
    local saved=defaults and defaults._anchor
    if saved and saved.battle==context.battleScope and saved.zone==context.zone_id and saved.cancelled then return false end
    if config.anchor.capture=='when_established' then return point~=nil end
    return true
end
function M.needsReturn(context,config)
    local point,anchor=state(context,config)
    if not point then return false end
    local distance=context.distanceTo(point.x,point.y)
    if type(distance)~='number' then return false end
    local tolerance=math.max(0.01,tonumber(anchor.tolerance) or 0.5)
    local threshold=math.max(tolerance,tonumber(anchor.return_distance) or 2)
    if point.returning and distance<=tolerance then
        context.setVar('frontline_engagement._anchor.returning',false)
        return false
    end
    return distance>(point.returning and tolerance or threshold)
end
function M.run(context,config)
    local point,anchor=state(context,config)
    if not point then return false,'anchor unavailable' end
    if not context.movementAvailable() then return false,'reserved' end
    if not M.needsReturn(context,config) then return true end
    context.setVar('frontline_engagement._anchor.returning',true)
    local reached,reason=context.move({x=point.x,y=point.y,
        duration=math.max(0.01,tonumber(anchor.duration) or 10),
        tolerance=math.max(0.01,tonumber(anchor.tolerance) or 0.5)})
    if reached then context.setVar('frontline_engagement._anchor.returning',false) end
    if reached and context.movementAvailable() then context.faceEnemy() end
    return reached,reason
end
return M
