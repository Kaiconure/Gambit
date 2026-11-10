-- A bounded direct approach, with live recipient positions and no angle search.
local M={}
function M.run(target,distance,options,deps)
    options=options or {}
    local range=options.range or distance or 7
    local radius=math.min(distance or range,range)
    assert(type(range)=='number' and range>=0 and type(radius)=='number' and radius>=0,'Invalid approach range')
    -- Leave room for the movement engine's positional arrival tolerance, even
    -- when an existing configuration sets distance equal to range.
    radius=math.min(radius,math.max(0,range-math.max(0.5,deps.tolerance or 0.33)))
    local deadline=deps.clock()+math.max(0,options.duration or 3)
    local jobId,lastX,lastY
    local function finish(success,reason)
        if jobId then deps.cancel(jobId) end
        return success,reason
    end
    while true do
        if not deps.available() then return finish(false,'reserved') end
        if deps.immobilized() then return finish(false,'immobilized') end
        local live=deps.mob(target.id)
        local me=deps.me()
        if not live or live.index~=target.index or live.valid_target==false or live.hpp==0
            or not me or live.x==nil or live.y==nil or me.x==nil or me.y==nil then
            return finish(false,'target unavailable')
        end
        local dx,dy=me.x-live.x,me.y-live.y
        local horizontal=math.sqrt(dx*dx+dy*dy)
        local actual=type(live.distance)=='number' and math.sqrt(live.distance) or horizontal
        if actual<=range then return finish(true) end
        if deps.clock()>=deadline then return finish(false,'timeout') end
        if jobId then
            local job=deps.job(jobId)
            if not job or job.jobId~=jobId then return finish(false,'cancelled') end
        end
        -- Refresh the destination if the recipient moves, preserving the current
        -- near-side bearing. Distance and range use raw center distances.
        if not jobId or (live.x-lastX)^2+(live.y-lastY)^2>0.01 then
            if horizontal==0 then return finish(false,'out of range') end
            if jobId then deps.cancel(jobId) end
            jobId=deps.start(live.x+dx/horizontal*radius,live.y+dy/horizontal*radius)
            if not jobId then return finish(false,'cancelled') end
            lastX,lastY=live.x,live.y
        end
        deps.sleep(0.05)
    end
end
return M
