local helpers = {}

function helpers.attach(context)
    -- Explicit one-shot positioning, evaluated in the caller's action coroutine.
    -- No initial-delay/range gate: a priority action must be able to approach
    -- before lower-priority casting starts. Retry policy belongs to the caller.
    context.applyEngagement = function(options,model)
        local function retry(reason)
            return false,reason
        end
        model=model or (context.vars.dynamic_engagement and context.vars.dynamic_engagement.model) or 'frontline'
        if model~='frontline' and model~='member' then return retry('unknown engagement model: '..tostring(model)) end
        local memberModel=model=='member'
        options=options or (memberModel and context.vars.member_engagement or context.vars.frontline_engagement)
        if type(options)~='table' then return retry('engagement options not configured') end
        if not context.movementAvailable() then return retry('reserved') end
        local target=context.bt
        if memberModel then
            target=context.partyAnchorByName(options.targets,options.max_distance or 30,true)
        end
        if not target or target.valid_target==false or target.hpp==0 or target.is_dead then return retry('target unavailable') end
        local distance=math.max(0.125,(options.distance or (memberModel and 2 or 0.5))+(options.distance_offset or 0))
        if memberModel and type(target.distance)=='number' and target.distance<=distance+(options.tolerance or 1) then
            return true
        end
        -- Runtime arrival flags belong to the ordinary frontline rules. An
        -- explicit application always checks the requested position afresh.
        options=require('./lib/variable-values').copy(options)
        options.arrived=false
        local angle=not memberModel and context.canAlign(target) and options.angle or nil
        local reached,reason=context.align(target,angle,
            distance,options.duration or (memberModel and 3 or nil),memberModel,options.tolerance or (memberModel and 1 or nil),options)
        if not reached then return retry(reason) end
        if not memberModel and context.movementAvailable() then context.faceEnemy() end
        return true
    end
    context.frontlineEngage = function()
        local options=context.vars.frontline_engagement
        if type(options)=='table' then
            context.setVar('frontline_engagement._distance',math.max(0.125,
                (options.distance or 0.5)+(options.distance_offset or 0)))
            context.setVar('frontline_engagement.arrived',false)
        end
        local reached,reason=context.applyEngagement(options,'frontline')
        if reached then context.setVar('frontline_engagement.arrived',true) end
        return reached,reason
    end
    local function diagnostic(options,message)
        if not options.debug or not context.log then return end
        local action=context.action
        local now=os.clock()
        if action then
            action._rollAlignmentLogs=action._rollAlignmentLogs or {}
            local previous=action._rollAlignmentLogs[message]
            if previous and now<previous+5 then return end
            action._rollAlignmentLogs[message]=now
        end
        context.log('[roll alignment] '..message)
    end
    context.resumeRollAlignment = function(options)
        local held=context.hasMovementReservation()
        local resumed=context.resumeMovement(options.timeout)
        diagnostic(options,'reservation '..(resumed and (held and 'held' or 'recovered') or 'FAILED')..
            ' section='..tostring(context.actionType)..' battle='..tostring(context.battleScope))
        return resumed
    end
    context.alignWithRetry = function(target, angle, distance, options, noFace, successDelay)
        local reached, reason = context.align(target, angle, distance, options.duration, noFace, options.tolerance, options)
        if reached then
            if successDelay then context.postpone(successDelay) end
        else
            context.postpone((reason == 'progress' or reason == 'alternatives' or reason=='immobilized') and (options.progress_retry_delay or 1) or (options.retry_delay or 10))
        end
        return reached, reason
    end

    -- The caller resolves the target and acquires/resumes the reservation.
    -- Never acquire or extend a lease here, including when the target changes.
    context.alignWithReservation = function(target, angle, distance, options, noFace)
        options = options or {}
        diagnostic(options,'position target='..tostring(target and (target.name or target.id) or 'NONE')..
            ' distance='..tostring(target and target.distance)..' range='..tostring(options.range)..
            ' reservation='..tostring(context.hasMovementReservation()))
        if type(target) == 'table' and type(target.id) == 'number' and
            not target.is_dead and target.hpp ~= 0 and target.valid_target ~= false and
            context.hasMovementReservation() and
            not context.hasBuff('Bind', 'Sleep', 'Stun', 'Petrification', 'Terror') then
            if type(options.range) == 'number' and type(target.distance) == 'number' and
                target.distance <= options.range then return true end
            local reached, reason = context.align(target, angle, distance, options.duration, noFace, options.tolerance, options)
            diagnostic(options,'movement reached='..tostring(reached)..' reason='..tostring(reason))
            if reached then return true end
            if (reason == 'progress' or reason=='immobilized') and context.hasMovementReservation() then
                context.postpone(options.progress_retry_delay or 1)
                return false
            end
        end
        context.releaseMovement(true) -- Recoverable failure; retain the original lease deadline.
        diagnostic(options,'position FAILED; released reservation for retry')
        context.postpone(options.retry_delay or 10)
        return false
    end
    context.approachWithReservation = function(target,distance,options)
        options=options or {}
        local reached,reason
        if type(target)=='table' and type(target.id)=='number' and context.hasMovementReservation() then
            reached,reason=context.approachWithinRange(target,distance,options)
        else reason='target or reservation unavailable' end
        diagnostic(options,'approach target='..tostring(target and (target.name or target.id) or 'NONE')..
            ' reached='..tostring(reached)..' reason='..tostring(reason))
        if reached then return true end
        if reason=='immobilized' and context.hasMovementReservation() then
            context.postpone(options.progress_retry_delay or 1)
        else
            context.releaseMovement(true)
            context.postpone(options.retry_delay or 10)
        end
        return false
    end
end

return helpers
