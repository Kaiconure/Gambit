local manager = {}
local reservation
local acquisitions = {}

local function sameContext(record, context)
    return record and record.section == context.actionType and record.scope == context.battleScope
        and record.zone == context.scopes.zone and record.vars == context.vars
end

local function current(context)
    if reservation and (os.clock() >= reservation.expires
        or reservation.section ~= context.actionType
        or reservation.scope ~= context.battleScope
        or reservation.zone ~= context.scopes.zone or reservation.vars ~= context.vars) then
        reservation.cancel()
        reservation = nil
    end
    return reservation
end

function manager.attach(context, cancel)
    local function owner() return context.action and context.action.movement_owner end
    context.movementAvailable = function()
        local active = current(context)
        return not active or active.owner == owner()
    end
    context.hasMovementReservation = function()
        local active = current(context)
        return active ~= nil and active.owner == owner()
    end
    context.reserveMovement = function(seconds)
        local name = owner()
        assert(type(name) == 'string' and name ~= '', 'reserveMovement requires action.movement_owner')
        assert(type(seconds) == 'number' and seconds > 0 and seconds < math.huge, 'reservation duration must be finite and positive')
        local active = current(context)
        if active then return active.owner == name end -- never silently extend a lease
        cancel()
        reservation = {owner=name, expires=os.clock()+seconds, section=context.actionType,
            scope=context.battleScope, zone=context.scopes.zone, vars=context.vars, cancel=cancel}
        acquisitions[name] = {section=context.actionType, scope=context.battleScope,
            zone=context.scopes.zone, vars=context.vars, expires=reservation.expires}
        return true
    end
    -- Continue an operation in a new context, but never restart an expired or
    -- completed reservation in the same context. Recoverable releases may resume
    -- only within their original deadline. Fresh operations use reserveMovement.
    context.resumeMovement = function(seconds)
        if context.hasMovementReservation() then return true end
        local previous=acquisitions[owner()]
        if sameContext(previous, context) then
            if previous.retryable and os.clock()<previous.expires then
                return context.reserveMovement(previous.expires-os.clock())
            end
            return false
        end
        return context.reserveMovement(seconds)
    end
    context.releaseMovement = function(retryable)
        if not context.hasMovementReservation() then return false end
        local previous=acquisitions[owner()]
        if previous then previous.retryable=retryable==true end
        cancel()
        reservation = nil
        return true
    end
    current(context)
end

return manager
