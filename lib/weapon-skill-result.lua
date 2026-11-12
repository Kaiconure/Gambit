-- Shared target-effect classification, separate from action execution outcome.
local copy=require('./lib/variable-values').copy
local Result={}
local meta=require('./meta/weapon-skill-results')
local hits=meta.types
function Result.targets(targets,failures)
    local results={}
    for _,target in ipairs(targets or {}) do
        local landed,missed,noEffect,failed=false,false,false,false
        local messages={}
        local amount
        local damage,effectType
        local skillchains={}
        for _,detail in ipairs(target.actions or {}) do
            local message=(tonumber(detail.message) or 0)%32768
            messages[#messages+1]=message
            landed=landed or not not hits[message]
            if hits[message] and type(detail.param)=='number' then
                amount=(amount or 0)+detail.param
                if hits[message]=='damage' then damage=(damage or 0)+detail.param end
            end
            if hits[message] then
                effectType=effectType and effectType~=hits[message] and 'mixed' or hits[message]
            end
            local scMessage=(tonumber(detail.add_effect_message) or 0)%32768
            local chain=meta.skillchains[scMessage]
            if chain then
                local scAmount=type(detail.add_effect_param)=='number' and detail.add_effect_param or nil
                skillchains[#skillchains+1]={name=chain.name,message=scMessage,animation=detail.add_effect_animation,
                    amount=scAmount,damage=chain.damage and scAmount or nil,absorbed=not not chain.absorbed,
                    dealt_damage=not not (chain.damage and scAmount and scAmount>0)}
            end
            missed=missed or message==188
            noEffect=noEffect or message==189
            failed=failed or (failures and failures[message]) or false
        end
        local effect=landed and 'landed' or missed and 'missed' or noEffect and 'no_effect' or 'unknown'
        results[#results+1]={target_id=target.id,outcome=failed and 'failed' or 'completed',effect=effect,landed=effect=='landed',
            missed=effect=='missed',no_effect=effect=='no_effect',messages=messages,amount=amount,
            damage=damage,dealt_damage=not not (damage and damage>0),effect_type=effectType,
            skillchains=skillchains,skillchain=skillchains[1],triggered_skillchain=#skillchains>0}
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
    destination.amount=effect and effect.amount or nil
    destination.damage=effect and effect.damage or nil
    destination.dealt_damage=effect and effect.dealt_damage or false
    destination.effect_type=effect and effect.effect_type or nil
    destination.skillchains=copy(effect and effect.skillchains or {})
    destination.skillchain=copy(effect and effect.skillchain)
    destination.triggered_skillchain=effect and effect.triggered_skillchain or false
    if not destination.skillchain_properties then Result.properties(destination) end
end
function Result.properties(destination,resource)
    local properties={}
    for _,key in ipairs({'skillchain_a','skillchain_b','skillchain_c'}) do
        local name=resource and resource[key]
        if type(name)=='string' and name~='' then
            local found=false
            for _,existing in ipairs(properties) do if existing==name then found=true end end
            if not found then properties[#properties+1]=name end
        end
    end
    destination.skillchain_properties=properties
    destination.has_skillchain_properties=#properties>0
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
