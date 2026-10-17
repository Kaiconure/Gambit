local helpers = {}

function helpers.attach(context)
    context.alignWithRetry = function(target, angle, distance, options, noFace, successDelay)
        local reached, reason = context.align(target, angle, distance, options.duration, noFace, options.tolerance)
        if reached then
            if successDelay then context.postpone(successDelay) end
        else
            context.postpone(reason == 'progress' and (options.progress_retry_delay or 1) or (options.retry_delay or 10))
        end
        return reached, reason
    end

    -- The caller resolves the target and acquires/resumes the reservation.
    -- Never acquire or extend a lease here, including when the target changes.
    context.alignWithReservation = function(target, angle, distance, options, noFace)
        options = options or {}
        if type(target) == 'table' and type(target.id) == 'number' and
            not target.is_dead and target.hpp ~= 0 and target.valid_target ~= false and
            context.hasMovementReservation() and
            not context.hasBuff('Bind', 'Sleep', 'Stun', 'Petrification', 'Terror') then
            if type(options.range) == 'number' and type(target.distance) == 'number' and
                target.distance <= options.range then return true end
            local reached, reason = context.align(target, angle, distance, options.duration, noFace, options.tolerance)
            if reached then return true end
            if reason == 'progress' and context.hasMovementReservation() then
                context.postpone(options.progress_retry_delay or 1)
                return false
            end
        end
        context.releaseMovement()
        context.postpone(options.retry_delay or 10)
        return false
    end
end

return helpers
