-- Small per-submission records fed by the shared self-action packet observations.
-- No dependency on configured event rules or context construction.
local Wait={}
local pending={}
function Wait.register(record,kind,id,target,now)
    record.kind,record.id,record.target_id,record.created_at=kind,id,target,now
    pending[record]=true
end
function Wait.release(record)
    pending[record]=nil
end
function Wait.clear(outcome,now)
    for record in pairs(pending) do
        record.outcome=record.outcome or outcome
        record.completed_at=record.completed_at or now
        record.abandoned=true
    end
end
function Wait.observe(observation,now)
    for record in pairs(pending) do
        if record.sent_at and not record.outcome and not record.abandoned and now>=record.sent_at then
            local matches=observation.kind==record.kind and
                (observation.id==record.id or (observation.id==nil and record.started_at) or
                    (record.kind=='job_ability' and record.id==123 and observation.resource and observation.resource.type=='CorsairRoll')) and
                (observation.target_id==record.target_id or (observation.id==nil and record.started_at))
            if matches then
                if observation.phase=='mid' then record.started_at=record.started_at or now
                else record.outcome=observation.outcome; record.completed_at=now end
            elseif observation.phase=='mid' then
                record.outcome='superseded'; record.completed_at=now
            end
        end
    end
end
-- Messages without action identity are only safe to attribute to a sole dispatch.
function Wait.reject(kind,now)
    local candidate
    for record in pairs(pending) do
        if record.sent_at and not record.outcome and not record.abandoned and
            (not kind or record.kind==kind) then
            if candidate then return end
            candidate=record
        end
    end
    if candidate then candidate.outcome='failed'; candidate.completed_at=now end
end
function Wait.run(record,policy,clock,sleep)
    local began=clock()
    local deadline
    while true do
        local now=clock()
        if record.outcome then break end
        if not record.sent_at then
            if now-began>=10 then record.outcome='dispatch_timeout'; break end
        elseif policy.start and not record.started_at then
            if now-record.sent_at>=2 then record.outcome='start_timeout'; break end
        else
            deadline=deadline or ((record.started_at or record.sent_at)+policy.result_timeout)
            if now>=deadline then record.outcome='result_timeout'; break end
        end
        sleep(0.1)
    end
    record.abandoned=record.outcome~='completed' and record.outcome~='interrupted'
    Wait.release(record)
    local success=record.outcome=='completed'
    -- Readiness policy is separate from observation: retain spell recovery,
    -- ability-specific minimum pacing, and a small JA/WS result safety margin.
    if record.outcome=='completed' or record.outcome=='interrupted' then
        local untilTime=math.max((record.completed_at or clock())+(policy.padding or 0),
            (record.sent_at or began)+(policy.minimum or 0))
        if untilTime>clock() then sleep(untilTime-clock()) end
    end
    return success
end
return Wait
