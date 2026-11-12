-- Stable per-character spacing; no waits, wandering, or per-tick randomness.
local M={}
function M.profile(identity)
    local hash=0
    for byte in tostring(identity or ''):lower():gmatch('.') do
        hash=(hash*131+byte:byte())%104729
    end
    return {distance=0.15+(hash%997)/996*0.6,
        resume=0.75+(math.floor(hash/997)%101)/100*0.6,
        lateral=(hash%991)/990*2-1}
end
function M.heading(previous,desired,distance)
    if previous and distance>3 then
        local delta=desired-previous
        if math.abs(math.atan2(math.sin(delta),math.cos(delta)))<math.pi/24 then
            return previous
        end
    end
    return desired
end
return M
