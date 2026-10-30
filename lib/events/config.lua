-- Select one event file and compile it independently of normal action imports.
local copy=require('./lib/variable-values').copy
local factory=require('./lib/execution-factory')
local variableLoader=require('./lib/variable-loader')
local importDocuments=require('./lib/events/imports')
local eventSlots=require('./lib/events/slots')
local Config={kinds={'spells','job_abilities','weapon_skills','pet_abilities'},phases={'pre','mid','post'}}
local statusCategories=require('./lib/events/statuses').categories
local sections={'spells','job_abilities','weapon_skills','pet_abilities','zones','loading'}
for _,category in ipairs(statusCategories) do sections[#sections+1]='statuses.'..category end
local function phases(kind)
    if kind=='loading' then return {'actions'} end
    return (kind=='zones' or kind:match('^statuses%.')) and {'enter','leave'} or Config.phases
end
local function array(value,label)
    assert(type(value)=='table',label..' must be an array')
    for key in pairs(value) do
        assert(type(key)=='number' and key>=1 and key%1==0 and key<=#value,label..' must be a dense array')
    end
    return value
end
local function expressions(value,label)
    if value==nil then return {} end
    if type(value)=='string' then value={value} end
    local result={}
    for _,code in ipairs(array(value,label)) do
        assert(type(code)=='string' and code:match('%S'),label..' requires nonempty strings')
        local ok,fn=pcall(factory.get,code)
        assert(ok,label..': '..tostring(fn))
        result[#result+1]={code=code,fn=fn}
    end
    return result
end
local function compileRule(rule,label,contributed)
    assert(type(rule)=='table',label..': rule must be an object')
    if rule.slot~=nil or rule.slots~=nil then
        assert(not contributed,label..': contributions cannot contain slots')
        for key in pairs(rule) do
            assert(key=='slot' or key=='slots' or key=='comment',label..': slots must be standalone placeholders')
        end
        return {slot=copy(rule.slot),slots=copy(rule.slots),source=label}
    end
    assert(rule.id==nil or (type(rule.id)=='string' and rule.id:match('%S')),label..': invalid rule id')
    assert(rule.disabled==nil or type(rule.disabled)=='boolean',label..': invalid disabled flag')
    assert(rule.stop==nil or type(rule.stop)=='boolean',label..': invalid stop flag')
    local commentOnly=rule.comment~=nil
    for key in pairs(rule) do
        assert(key=='id' or key=='when' or key=='commands' or key=='disabled' or key=='stop'
            or key=='comment' or (contributed and key=='priority'),label..': unsupported rule key '..tostring(key))
        if key~='comment' then commentOnly=false end
    end
    if commentOnly then return end
    return {id=rule.id,source=label,stop=rule.stop,disabled=rule.disabled,priority=rule.priority,
        conditions=not rule.disabled and expressions(rule.when,label..'.when') or {},
        commands=not rule.disabled and expressions(rule.commands,label..'.commands') or {}}
end
function Config.load(paths,read,warn,matchesRequired,entryName)
    local result={vars={},rules={},files={},vars_files={}}
    local inlineVars={}
    local layouts={}
    for _,kind in ipairs(sections) do
        result.rules[kind]={}
        for _,phase in ipairs(phases(kind)) do
            result.rules[kind][phase]={}
            layouts[#layouts+1]={section=kind,phase=phase}
        end
    end
    local slots=eventSlots.new(result.rules,layouts,paths,warn,matchesRequired,compileRule)
    local documents,selectedPath=importDocuments(paths,read,entryName)
    result.path=selectedPath
    for _,entry in ipairs(documents) do
        local path,document=entry.path,entry.document
        do
            assert(type(document)=='table',path..': expected an object')
            for key in pairs(document) do
                assert(key=='vars' or key=='imports' or key=='statuses' or key=='contributions' or (result.rules[key] and not key:find('%.')),
                    path..': unsupported key '..tostring(key))
            end
            if document.statuses~=nil then
                assert(type(document.statuses)=='table',path..': statuses must be an object')
                for category in pairs(document.statuses) do
                    assert(result.rules['statuses.'..tostring(category)],path..': unsupported status category '..tostring(category))
                end
            end
            if document.vars then
                assert(type(document.vars)=='table',path..': vars must be an object')
                for key in pairs(document.vars) do assert(type(key)=='string',path..': vars keys must be names') end
                inlineVars[#inlineVars+1]={vars=copy(document.vars),path=path}
            end
            result.files[#result.files+1]=path
            slots.collect(document,path)
            for _,kind in ipairs(sections) do
                local section=document[kind]
                local category=kind:match('^statuses%.(.+)$')
                if category then section=document.statuses and document.statuses[category] end
                if section then
                    assert(type(section)=='table',path..': '..kind..' must be an object')
                    local observational=kind=='zones' or kind=='loading' or category~=nil
                    assert(not observational or section.use_equipment_snapshot==nil,
                        path..': '..kind..' does not support use_equipment_snapshot')
                    assert(section.use_equipment_snapshot==nil or type(section.use_equipment_snapshot)=='boolean',
                        path..': '..kind..'.use_equipment_snapshot must be a boolean')
                    if section.use_equipment_snapshot~=nil then
                        result.rules[kind].use_equipment_snapshot=section.use_equipment_snapshot
                    end
                    for phase in pairs(section) do
                        assert(result.rules[kind][phase]~=nil or (not observational and phase=='use_equipment_snapshot'),path..': unknown phase '..tostring(phase))
                    end
                    for _,phase in ipairs(phases(kind)) do
                        for index,rule in ipairs(array(section[phase] or {},path..':'..kind..'.'..phase)) do
                            local list=result.rules[kind][phase]
                            local item=compileRule(rule,path..':'..kind..'.'..phase..'['..index..']')
                            if item then list[#list+1]=item end
                        end
                    end
                end
            end
        end
    end
    -- Highest specificity first: the shared loader preserves earlier values at
    -- equal priority, while ! and ^ explicitly override ordinary precedence.
    local variables=variableLoader.new(warn)
    for _,candidate in ipairs(paths) do
        local path=candidate:gsub('%.json$','.vars.json')
        local document
        if candidate:match('%.json$') then document=read(path) end
        if document~=nil then
            assert(type(document)=='table',path..': expected an object')
            for key in pairs(document) do assert(key=='vars' or key=='contributions',path..': vars files only support vars and contributions') end
            assert(document.vars~=nil or document.contributions~=nil,path..': vars files require vars or contributions')
            if document.vars~=nil then
                assert(type(document.vars)=='table',path..': vars must be an object')
                for key in pairs(document.vars) do assert(type(key)=='string',path..': vars keys must be names') end
                variables.merge(result.vars,document.vars,path)
            end
            slots.collect(document,path)
            result.vars_files[#result.vars_files+1]=path
        end
    end
    for index=#inlineVars,1,-1 do
        local entry=inlineVars[index]
        variables.merge(result.vars,entry.vars,entry.path,-1)
    end
    result.available_slots=slots.expand()
    return result
end
return Config
