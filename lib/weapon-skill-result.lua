-- Shared target-effect classification, separate from action execution outcome.
local copy=require('./lib/variable-values').copy
local Result={}
local hits={[185]=true,[187]=true,[197]=true,[225]=true,[264]=true,
    [747]=true,[748]=true,[750]=true}
function Result.targets(targets,failures)
    local results={}
    for _,target in ipairs(targets or {}) do
        local landed,missed,noEffect,failed=false,false,false,false
        local messages={}
        for _,detail in ipairs(target.actions or {}) do
            local message=(tonumber(detail.message) or 0)%32768
            messages[#messages+1]=message
            landed=landed or not not hits[message]
            missed=missed or message==188
            noEffect=noEffect or message==189
            failed=failed or (failures and failures[message]) or false
        end
        local effect=landed and 'landed' or missed and 'missed' or noEffect and 'no_effect' or 'unknown'
        results[#results+1]={target_id=target.id,outcome=failed and 'failed' or 'completed',effect=effect,landed=effect=='landed',
            missed=effect=='missed',no_effect=effect=='no_effect',messages=messages}
    end
    return results
end
function Result.find(results,target)
    for _,result in ipairs(results or {}) do if result.target_id==target then return result end end
end
function Result.apply(destination,results,target)
    destination.results=copy(results or {})
    local effect=Result.find(results,target)
    destination.effect=effect and effect.effect or 'unknown'
    destination.landed=effect and effect.landed or false
    destination.missed=effect and effect.missed or false
    destination.no_effect=effect and effect.no_effect or false
end
function Result.summary(record)
    local result={outcome=record.outcome,target_id=record.target_id,
        dispatched=record.sent_at~=nil,
        started=record.started_at~=nil or record.outcome=='completed' or record.outcome=='interrupted',
        completed=record.outcome=='completed',interrupted=record.outcome=='interrupted',
        failed=record.outcome=='failed',cancelled=record.outcome=='cancelled',
        timed_out=not not (record.outcome and record.outcome:find('timeout',1,true))}
    Result.apply(result,record.results,record.target_id)
    return result
end
return Result
