-- JSON-safe diagnostic: compiled order and source strings, never Lua closures.
local copy=require('./lib/variable-values').copy
return function(config)
    local result={vars=copy(config.vars),_sources={entry=config.path,files=copy(config.files),
        vars_files=copy(config.vars_files),slots=copy(config.available_slots)}}
    for section,phases in pairs(config.rules) do
        local output={}
        local populated=false
        for phase,rules in pairs(phases) do
            if phase=='use_equipment_snapshot' then output[phase]=rules
            elseif #rules>0 then
                populated=true
                output[phase]={}
                for _,rule in ipairs(rules) do
                    local item={id=rule.id,stop=rule.stop,_source=rule.source,when={},commands={}}
                    for _,condition in ipairs(rule.conditions) do item.when[#item.when+1]=condition.code end
                    for _,command in ipairs(rule.commands) do item.commands[#item.commands+1]=command.code end
                    output[phase][#output[phase]+1]=item
                end
            end
        end
        if populated or output.use_equipment_snapshot~=nil then
            local category=section:match('^statuses%.(.+)$')
            if category then
                result.statuses=result.statuses or {}
                result.statuses[category]=output
            else result[section]=output end
        end
    end
    return result
end
