local M={}
local alignment=require('./lib/alignment')
local states=setmetatable({}, {__mode='k'})
local function finite(value)
    return type(value)=='number' and value==value and math.abs(value)<math.huge
end
local function position(value,lookup)
    if type(value)~='table' then return end
    value=value.mob or value
    if type(value)~='table' then return end
    if value.id and lookup then
        local live=lookup(value.id)
        if not live or (value.index and live.index~=value.index) then return end
        value=live
    end
    if value.valid_target==false or not finite(value.x) or not finite(value.y) then return end
    return value
end
local function gap(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
local function identity(value)
    return value.id and ('mob:'..value.id..':'..tostring(value.index)) or ('point:'..value.x..':'..value.y)
end

-- Zero is the target-to-partner ray. Positive angles follow align's convention.
function M.point(target,partner,angle,distance,observer)
    target,partner=position(target),position(partner)
    distance=distance==nil and 5 or distance
    if not target or not partner or (type(angle)~='string' and not finite(angle)) or not finite(distance) or distance<0 then return end
    local dx,dy=partner.x-target.x,partner.y-target.y
    local length=math.sqrt(dx*dx+dy*dy)
    if length<0.000001 then return end
    local spec=alignment.parse(angle)
    observer=position(observer)
    local bearing=0
    if observer then
        bearing=alignment.bearing({x=target.x,y=target.y,heading=-math.atan2(dy,dx)},observer)
    end
    angle=alignment.closest(spec,bearing)
    local radians=angle*math.pi/180
    local c,s=math.cos(radians),math.sin(radians)
    return {x=target.x+distance*(dx*c+dy*s)/length,
        y=target.y+distance*(dy*c-dx*s)/length,z=target.z}
end

function M.attach(context,deps)
    local function available()
        if not context.movementAvailable() then return false,'reserved' end
        if deps.immobilized() then return false,'immobilized' end
        return true
    end
    context.alignRelative=function(target,partner,angle,distance)
        local allowed,reason=available()
        if not allowed then return false,reason end
        local me=position(deps.me())
        local point=M.point(position(target,deps.mob),position(partner,deps.mob),angle,distance,me)
        if not point or not me then return false,'invalid position' end
        if gap(me,point)<=deps.tolerance then
            local job=deps.job()
            local other=position(partner,deps.mob)
            if job and other and other.index and job.follow_index==other.index then deps.cancel(job.jobId) end
            return true
        end
        point.duration=3
        point.tolerance=deps.tolerance
        return context.move(point)
    end

    -- Called by the follow action even when already following or already aligned.
    context.followLeader=function(partner,config)
        config=config or context.vars.follow_leader or {}
        partner=partner or context.party_leader
        local allowed,reason=available()
        if not allowed then return false,reason end
        local state=states[config]
        local me=deps.me()
        local rawPartner=type(partner)=='table' and (partner.mob or partner)
        if rawPartner and (partner.is_me or rawPartner==me or
            (me and me.id and rawPartner.id==me.id)) then
            if state then
                if state.job then deps.cancel(state.job) end
                states[config]=nil
            end
            return false,'self'
        end
        if not state then state={};states[config]=state end
        local relative=config.align_relative
        local leader=position(partner,deps.mob)
        local target
        if type(relative)=='table' and not relative.disabled and leader then
            if relative.target_expression~=nil then
                assert(type(relative.target_expression)=='string','align_relative.target_expression must be a string')
                target=context.execute(relative.target_expression)
            else target=relative.target end
            if type(target)=='string' then target=context.findByName(target) end
            target=position(target,deps.mob)
        end
        local zone=context.game_info and context.game_info.zone
        if target and leader then
            state.lastTarget={x=target.x,y=target.y,id=target.id,index=target.index}
            state.lastPartner=identity(leader)
            state.lastZone=zone
        elseif type(relative)=='table' and not relative.disabled and relative.hold_on_target_loss
            and state.active and leader and state.lastPartner==identity(leader) and state.lastZone==zone then
            target=state.lastTarget
        end
        local point
        if target and leader then
            local activate=relative.activate_distance or 5
            local release=relative.release_distance or activate+2
            assert(finite(activate) and activate>=0 and finite(release) and release>=activate,
                'align_relative requires 0 <= activate_distance <= release_distance')
            local key=identity(target)..'/'..identity(leader)..'/'..tostring(context.game_info and context.game_info.zone)
            local threshold=state.active and state.key==key and release or activate
            if gap(leader,target)<=threshold then
                point=M.point(target,leader,relative.angle or 180,relative.distance,me)
                -- Keep a valid in-flight destination instead of shifting it as
                -- the player travels across an allowed arc.
                local job=state.job and deps.job(state.job)
                if point and me and gap(me,point)>deps.tolerance and job and job.position then
                    local destination={x=job.position[1],y=job.position[2]}
                    local projected=M.point(target,leader,relative.angle or 180,relative.distance,destination)
                    if projected and gap(destination,projected)<=deps.tolerance then point=destination end
                end
            end
            state.key=key
        end
        if point then
            state.active=true
            local me=position(deps.me())
            if not me then return false,'invalid position' end
            local job=deps.job(state.job) or deps.job()
            if gap(me,point)<=deps.tolerance then
                if job and (job.jobId==state.job or (leader.index and job.follow_index==leader.index)) then deps.cancel(job.jobId) end
                state.job=nil
                return true
            end
            -- Do not restart an unchanged route each time the action is checked.
            local destination=job and job.position
            if job and job.jobId==state.job and destination
                and (destination[1]-point.x)^2+(destination[2]-point.y)^2<=deps.tolerance^2 then return true end
            state.job=deps.start(point.x,point.y)
            return state.job~=nil
        end
        state.active=false;state.key=nil
        if state.job then deps.cancel(state.job);state.job=nil end
        return context.following(partner) or context.follow(partner,config.distance)
    end
end
return M
