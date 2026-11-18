local followDistance = {}

local runtimeDistance

local function persistentDistance(settings)
    return math.max(tonumber(settings and settings.followCommandDistance) or 1, 1)
end

function followDistance.get(settings)
    if runtimeDistance ~= nil then
        return runtimeDistance
    end

    return persistentDistance(settings)
end

function followDistance.set(value)
    value = tonumber(value)
    if value == 0 then
        runtimeDistance = 0
        return 0, true
    end

    runtimeDistance = nil
    return value, false
end

function followDistance.resetTransient()
    if runtimeDistance == 0 then
        runtimeDistance = 1
        return true
    end

    return false
end

return followDistance
