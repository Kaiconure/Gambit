-- Run only from the normal action coroutine. Enemy event handlers just publish
-- a request. Work in bounded slices so healing and new observations can run.
local reactions=require('./lib/reactions')
local alignment=require('./lib/alignment')
local M={}
local function positionAt(actor,angle,radius)
    local heading=(actor.heading or 0)+angle*math.pi/180
    return actor.x+math.cos(heading)*radius,actor.y-math.sin(heading)*radius
end
local function satisfied(actor,me,minimum,spec,tolerance)
    local distance=math.sqrt((me.x-actor.x)^2+(me.y-actor.y)^2)
    if distance<minimum then return false,distance end
    if not spec then return true,distance end
    local angle=alignment.closest(spec,alignment.bearing(actor,me))
    local x,y=positionAt(actor,angle,distance)
    return (me.x-x)^2+(me.y-y)^2<=tolerance^2,distance
end
function M.run(deps)
    reactions.tick(true)
    local request=reactions.distanceRequest()
    if not request then return false end
    if not deps.available() then reactions.movementStatus(request,'waiting');return false end
    if request.next_move_at and deps.clock()<request.next_move_at then return false end
    local actor=deps.mob(request.actor.id)
    local me=deps.me()
    if not actor or not me or actor.x==nil or actor.y==nil or me.x==nil or me.y==nil then return false end
    local dx,dy=me.x-actor.x,me.y-actor.y
    local distance=math.sqrt(dx*dx+dy*dy)
    local minimum=request.options.distance
    local spec=require('./lib/reaction-options').angle(request.options)
    local tolerance=deps.tolerance or 0.33
    if satisfied(actor,me,minimum,spec,tolerance) then reactions.movementStatus(request,'safe',distance);return false end
    reactions.movementStatus(request,spec and 'positioning' or 'retreating',distance)
    local radius=minimum+math.max(0.5,tolerance+0.1)
    local x,y
    if spec then
        radius=math.max(radius,distance)
        x,y=positionAt(actor,alignment.closest(spec,alignment.bearing(actor,me)),radius)
    else
        if distance==0 then dx,dy=math.cos(actor.heading or 0),-math.sin(actor.heading or 0);distance=1 end
        x,y=actor.x+dx/distance*radius,actor.y+dy/distance*radius
    end
    if not reactions.claimMovement(request,nil) then return false end
    local jobId=deps.start(x,y)
    if not jobId then reactions.finishMovement(nil);return false end
    if not reactions.claimMovement(request,jobId) then deps.cancel(jobId);return true end
    local deadline=deps.clock()+0.5
    while deps.clock()<deadline do
        deps.sleep(0.05)
        reactions.tick(true)
        local current=reactions.distanceRequest()
        local job=deps.job()
        if not current or current.sequence~=request.sequence or not deps.available()
            or not job or job.jobId~=jobId then break end
        actor=deps.mob(request.actor.id);me=deps.me()
        if not actor or not me then break end
        local arrived,actual=satisfied(actor,me,minimum,spec,tolerance)
        if arrived then reactions.movementStatus(request,'safe',actual);break end
    end
    reactions.finishMovement(jobId)
    return true
end
return M
