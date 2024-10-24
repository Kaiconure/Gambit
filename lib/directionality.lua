local directionality = {}
local DISTANCE_TOLERANCE = 0.5

directionality.radToDeg = function(rad)
    return rad * 180.0 / math.pi
end

directionality.degToRad = function(deg)
    return deg * math.pi / 180.0
end

directionality.vectorAngle = function(vn1, vn2)
    local dot = vector.dot(vn1, vn2)
    local det = (vn1[1] * vn2[2]) - (vn1[2] * vn2[1])

    return math.atan2(det, dot)
end

    -------------------------------------------------------------------------------------
    -- Convert a named direction into its radians equivalent. Numeric inputs will be
    -- passed through as-is, so it's safe to call with actual radian values.
directionality.directionToRadians = function (direction)
    local radians = nil

    if type(direction) == 'string' then
        direction = string.lower(direction)
        
        if direction == 'e' then
            radians = 0
        elseif direction == 'se' then
            radians = math.pi / 4
        elseif direction == 's' then
            radians = math.pi / 2
        elseif direction == 'sw' then
            radians = 3 * math.pi / 4
        elseif direction == 'w' then
            radians = -math.pi
        elseif direction == 'nw' then
            radians = -3 * math.pi / 4
        elseif direction == 'n' then
            radians = -math.pi / 2
        elseif direction == 'ne' then
            radians = -math.pi / 4
        end
    elseif type(direction) == 'number' then
        radians = direction
    end

    return radians
end

-------------------------------------------------------------------------------------
-- Face the specified direction (semantic or actual radian value)
directionality.faceDirection = function (direction)
    direction = directionality.directionToRadians(direction)
    if direction ~= nil then
        windower.ffxi.turn(direction)
        return direction
    end
end

-------------------------------------------------------------------------------------
-- Returns the directional difference between the direction you are
-- facing and the target's current location.
directionality.facingOffset = function (target)
    if type(target) == 'table' then
        local me = windower.ffxi.get_mob_by_target('me')
        if me and me.id ~= target.id then
            local current = vector.from_radian(me.heading)
            local toTarget = vector.normalize(V({
                (target.x - me.x),
                (target.y - me.y)
                
            }))

            return -directionality.vectorAngle(current, toTarget)
        end
    end

    return nil
end

-------------------------------------------------------------------------------------
-- Returns the absolute difference between the direction you are
-- facing and the target's current location.
directionality.facingOffsetAmount = function (target)
    local facingOffset = directionality.facingOffset(target)
    if type(facingOffset) == 'number' then
        return math.abs(facingOffset)
    end

    return nil
end

-------------------------------------------------------------------------------------
-- Calculate the angle required to face the specified mob, and turn to face it,
-- returning the new heading angle. If the calculationOnly flag is set, then the
-- turn portion will be skipped and the return value can be used to turn directly later.
directionality.faceTarget = function (target, calculationOnly)
    if type(target) == 'table' then
        local me = windower.ffxi.get_mob_by_target('me')
        if me and (target.id == nil or me.id ~= target.id) then
            local forward = V({1, 0})
            local toTarget = vector.normalize(V({
                (target.x - me.x),
                (target.y - me.y)
                
            }))

            local heading = -directionality.vectorAngle(forward, toTarget)
            if not calculationOnly then
                return directionality.faceDirection(heading)
            end

            return heading
        end
    end

    return nil
end

-------------------------------------------------------------------------------------
directionality.isAtMobRear = function (mob, distanceBehind)
    local vMob = V({mob.x, mob.y})
    local vMobFwd = vector.from_radian(mob.heading or 0):normalize()

    distanceBehind = tonumber(distanceBehind) or 1.0
    tolerance = math.abs(distanceBehind) * 1.0-- DISTANCE_TOLERANCE

    local me = windower.ffxi.get_mob_by_target('me')
    
    local vme = V({me.x, me.y})
    local vRearSpot = vMob:add(vMobFwd:scale(-distanceBehind))
    local toRearSpot = vRearSpot:subtract(vme)

    return toRearSpot:length() <= tolerance
end

directionality.isAtMobFront = function (mob, distanceAhead)
    -- We'll just negate the distance ahead value and call the is at rear check
    return directionality.isAtMobRear(mob, -distanceAhead)
end

-------------------------------------------------------------------------------------
directionality.walkToMobRear = function(mob, distanceBehind, maxDuration, continueFn)
    local vMob = V({mob.x, mob.y})
    local vMobFwd = vector.from_radian(mob.heading):normalize()

    distanceBehind = tonumber(distanceBehind) or 1.0
    
    -- Set the target to a location behind the mob
    local vRearSpot = vMob:add(vMobFwd:scale(-distanceBehind))

    -- x, y, distance tolerance, max walk time, continuation function
    local result = directionality.walkTo(vRearSpot[1], vRearSpot[2], maxDuration, continueFn)
    if result and mob.index then
        sendActionCommand(
            makeSelfCommand('follow -index %d; wait 1':format(mob.index)) ..
                makeSelfCommand('follow'),
            nil,
            1)
    end

    return result
end

-------------------------------------------------------------------------------------
directionality.walkToMobFront = function(mob, distanceAhead, maxDuration, continueFn)
    -- We'll just negate the distance ahead value and call the walk to rear func
    return directionality.walkToMobRear(mob, -distanceAhead, maxDuration, continueFn)
end

-------------------------------------------------------------------------------------
-- Walks to the specified location, giving up if the specified maximum duration has
-- been exceeded. Passing nil will cause it to walk forever (maybe ill advised)
directionality.walkTo = function(x, y, maxDuration, continueFn)
    -- Tolerance is how close we're allowed to get to the target before saying we're there.
    -- The tolerance value will be clamped to [1, 4]
    tolerance = DISTANCE_TOLERANCE

    maxDuration = tonumber(maxDuration) or 2

    local vtarget = V({x, y})
    local distance = nil
    local startTime = os.clock()
    local totalTime = 0
    local started = false
    local player = windower.ffxi.get_player()
    local followIndex = player.follow_index or 0

    continueFn = type(continueFn) == 'function' and continueFn or function (time, distance) return true end

    local target = { x = vtarget[1], y = vtarget[2] }

    local continue = true
    while continue do
        -- Get the player mob, and construct a TO vector from there to the target position
        local me = windower.ffxi.get_mob_by_target('me')
        local vme = V({me.x, me.y})
        local vto = vtarget:subtract(vme)

        local newDistance = vto:length()
        -- if newDistance < 20 then
        --     windower.ffxi.toggle_walk(true)
        -- end
        
        totalTime = os.clock() - startTime

        if 
            newDistance <= tolerance 
            or (distance ~= nil and newDistance > distance)
            or (distance ~= nil and math.abs(newDistance - distance) < (tolerance * 0.25))
        then
            continue = false
        elseif
            -- We only do a time check if there was a positive max duration set
            maxDuration > 0 and  totalTime > maxDuration
        then
            continue = false
        elseif not continueFn(totalTime, newDistance) then
            continue = false
        else
            if not started then
                started = true            
            
                local direction = directionality.faceTarget(target, true)
                windower.ffxi.run(direction)            
            -- if not started then
            --     started = true
                writeDebug('Initiating walk on heading %03d degrees.':format(directionality.radToDeg(direction)))
            end

            coroutine.sleep(0.25)
        end
        writeDebug('d=%.2f, nd=%.2f':format(distance ~= nil and distance or '-1337', newDistance))
        distance = newDistance
    end

    windower.ffxi.run(false)

    writeDebug('Walk to (%.1f, %.1f) is exiting after %.2fs with d=%.2f':format(
        x, y,
        (os.clock() - startTime),
        distance
    ))

    -- Success will be gauged on whether we got close enough to the target
    return distance < tolerance
end

return directionality