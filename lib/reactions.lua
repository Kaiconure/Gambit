-- Shared across isolated event contexts. No waits, scheduled action coroutines,
-- or mutations of the legacy suppression counters.
local copy=require('./lib/variable-values').copy
local M={}
local deps,holds,sequence,lastTick,lastUnlock,lastFacing,movement
local debugging=false
local function trace(action,hold,detail)
    if not debugging or not deps or not deps.log then return end
    local identity=hold and string.format(' actor=%s(%s) key=%s trigger=%s/%s(%s)',
        hold.actor.name or '?',tostring(hold.actor.id),tostring(hold.options.key or hold.id),
        hold.kind,hold.name or '?',tostring(hold.id)) or ''
    -- Logging must never prevent a turn, release, or movement cleanup.
    pcall(deps.log,'[Gambit reactions] '..action..identity..(detail and (' '..detail) or ''))
end
function M.setDebug(enabled)
    if enabled and not debugging then debugging=true;trace('debug enabled')
    elseif not enabled then debugging=false end
end
function M.clear(reason)
    for _,hold in pairs(holds or {}) do trace('end',hold,'reason='..(reason or 'cleared')) end
    if movement and deps and deps.cancelReactionMovement then deps.cancelReactionMovement(movement.jobId) end
    movement=nil
    holds={};sequence=sequence or 0;lastTick=nil;lastUnlock=nil;lastFacing=nil
end
M.clear()
function M.attach(options) M.clear('reinitialized');deps=options;debugging=false end
local function duration(value,default)
    value=value==nil and default or value
    assert(type(value)=='number' and value>=0 and value<math.huge,'Reaction durations must be finite and nonnegative')
    return value
end
local function key(event,options)
    return tostring(event.actor.id)..':'..(options and options.key or (event.kind..':'..tostring(event.id)))
end
function M.tick(force)
    if not deps then return end
    local now=deps.clock()
    if not force and lastTick and now-lastTick<0.1 then return end
    lastTick=now
    local player=deps.player()
    if not deps.enabled() then M.clear('automation disabled');return end
    if not player or (player.vitals and player.vitals.hp==0) then
        M.clear(player and 'player defeated' or 'player unavailable');return
    end
    local chosen
    for id,hold in pairs(holds) do
        local actor=deps.mob(hold.actor.id)
        if hold.zone~=deps.zone() or not actor or actor.index~=hold.actor.index
            or actor.valid_target==false or actor.hpp==0 then
            trace('end',hold,'reason='..(hold.zone~=deps.zone() and 'zone changed'
                or actor and actor.hpp==0 and 'enemy defeated' or 'enemy unavailable or invalid'))
            holds[id]=nil
            if lastFacing==hold.actor.id then lastFacing=nil end
        elseif (hold.expires and now>=hold.expires) or (hold.release_at and now>=hold.release_at) then
            trace('end',hold,'reason='..(hold.expires and now>=hold.expires and 'timeout' or 'release wait elapsed'))
            holds[id]=nil
        elseif not hold.options.no_turn and (not chosen or hold.sequence>chosen.sequence) then
            chosen=hold
        end
    end
    local request=M.distanceRequest()
    if movement and (not request or request.sequence~=movement.sequence) then
        if deps.cancelReactionMovement then deps.cancelReactionMovement(movement.jobId) end
        movement=nil
    end
    if request and not chosen and not movement then deps.cancelMovement() end
    if chosen then
        if not movement then deps.cancelMovement() end
        if player.target_locked and (not lastUnlock or now-lastUnlock>=0.5) then
            deps.unlock();lastUnlock=now
        end
        if not movement then deps.faceAway(deps.mob(chosen.actor.id)) end
        lastFacing=chosen.actor.id
    elseif lastFacing and not movement then
        deps.restore(lastFacing)
        lastFacing=nil
    end
end
function M.faceAway(event,options)
    if not deps or not deps.enabled() then return false end
    assert(event and event.actor and event.actor.id and event.kind and event.id,'Face-away requires an enemy event')
    options=copy(options or {})
    local id=key(event,options)
    local now=deps.clock()
    local timeout=require('./lib/reaction-options').timeout(options.timeout)
    if options.timeout==math.huge then options.timeout='infinity' end
    local wait=duration(options.wait,0.25)
    require('./lib/reaction-options').angle(options)
    if options.distance~=nil then
        duration(options.distance,0)
    end
    -- Repeated readying packets must not extend a live request indefinitely.
    if holds[id] and not holds[id].release_at then return true end
    sequence=sequence+1
    holds[id]={actor=copy(event.actor),kind=event.kind,id=event.id,name=event.name,options=options,
        zone=deps.zone(),expires=timeout and now+timeout or nil,wait=wait,sequence=sequence}
    trace('start',holds[id],string.format('phase=%s bracket=%s no_turn=%s suppress_ws=%s suppress_magic=%s distance=%s angle=%s wait=%s timeout=%s',
        tostring(event.phase),tostring(not not options.bracket),tostring(not not options.no_turn),
        tostring(not options.allow_weapon_skills),tostring(not options.allow_offensive_magic),
        tostring(options.distance or 'none'),tostring(options.angle or 'none'),tostring(wait),tostring(timeout or 'infinity')))
    M.tick(true)
    return true
end
function M.release(event,options)
    if not deps or not event or not event.actor then return false end
    local hold=holds[key(event,options)]
    if not hold then return false end
    if not hold.release_at then trace('release',hold,'reason=explicit/bracket trigger='..tostring(event.name or event.id)..' wait='..hold.wait) end
    hold.release_at=hold.release_at or (deps.clock()+hold.wait)
    M.tick(true)
    return true
end
function M.observe(event)
    if not deps or event.phase~='post' then return end
    for _,hold in pairs(holds) do
        if not hold.options.bracket and hold.actor.id==event.actor.id and hold.kind==event.kind
            and (hold.id==event.id or (event.id==nil and event.interrupted)) then
            if not hold.release_at then trace('release',hold,'reason='..tostring(event.outcome or (event.interrupted and 'interrupted') or 'completion')..' wait='..hold.wait) end
            hold.release_at=hold.release_at or (deps.clock()+hold.wait)
        end
    end
    M.tick(true)
end
function M.active()
    return next(holds)~=nil
end
function M.blocksMovement()
    for _,hold in pairs(holds) do if not hold.options.no_turn or hold.options.distance~=nil then return true end end
    return false
end
function M.distanceRequest()
    local newest
    for _,hold in pairs(holds) do
        if hold.options.distance~=nil and (not newest or hold.sequence>newest.sequence) then newest=hold end
    end
    if not newest then return end
    local selected=newest
    for _,hold in pairs(holds) do
        if hold.actor.id==newest.actor.id and hold.options.distance~=nil
            and hold.options.distance>selected.options.distance then selected=hold end
    end
    return copy(selected)
end
function M.claimMovement(request,jobId)
    local current=M.distanceRequest()
    if not current or current.sequence~=request.sequence then return false end
    movement={sequence=request.sequence,jobId=jobId}
    return true
end
function M.movementStatus(request,status,distance)
    if not debugging then return end
    for _,hold in pairs(holds) do
        if hold.sequence==request.sequence and hold.debugMovementStatus~=status then
            hold.debugMovementStatus=status
            trace('distance '..status,hold,'minimum='..hold.options.distance..' current='..tostring(distance or '?'))
        end
    end
end
function M.finishMovement(jobId)
    if movement and movement.jobId==jobId then
        for _,hold in pairs(holds) do
            if hold.sequence==movement.sequence then hold.next_move_at=deps.clock()+0.25 end
        end
        if deps.cancelReactionMovement then deps.cancelReactionMovement(jobId) end
        movement=nil
        M.tick(true)
    end
end
function M.suppresses(kind)
    for _,hold in pairs(holds) do
        if kind=='weapon_skills' and not hold.options.allow_weapon_skills then return true end
        if kind=='offensive_magic' and not hold.options.allow_offensive_magic then return true end
    end
    return false
end
function M.state() return copy(holds) end
function M.blocksAction(kind,resource)
    if kind=='weapon_skill' then return M.suppresses('weapon_skills') end
    local targets=resource and resource.targets
    return kind=='spell' and M.suppresses('offensive_magic') and targets and targets.Enemy
        and not targets.Self and not targets.Party and not targets.Ally or false
end
-- Raw definitions remain supported for direct callers. Stock event settings
-- supply a precompiled immutable handle instead.
function M.handle(event,rules,allowStart)
    local query=type(rules)=='function' and rules or require('./lib/reaction-rules').compile(rules)
    local matched=false
    for _,entry in ipairs(query(event)) do
        if entry.operation=='release' then
            matched=M.release(event,entry.options) or matched
        elseif allowStart~=false then
            matched=M.faceAway(event,entry.options) or matched
        else
            trace('start skipped',{actor=event.actor,kind=event.kind,id=event.id,name=event.name,options=entry.options},
                'reason=actor is not the current or fallback battle target')
        end
    end
    return matched
end
return M
