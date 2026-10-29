-- Select one event file and compile it independently of normal action imports.
local copy=require('./lib/variable-values').copy
local factory=require('./lib/execution-factory')
local variableLoader=require('./lib/variable-loader')
local Config={kinds={'spells','job_abilities','weapon_skills'},phases={'pre','mid','post'}}
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
function Config.load(paths,read,warn)
    local result={vars={},rules={},files={},vars_files={}}
    local inlineVars
    for _,kind in ipairs(Config.kinds) do
        result.rules[kind]={pre={},mid={},post={}}
    end
    for _,path in ipairs(paths) do
        local document=read(path)
        if document~=nil then
            assert(type(document)=='table',path..': expected an object')
            for key in pairs(document) do
                assert(key=='vars' or result.rules[key],path..': unsupported key '..tostring(key))
            end
            if document.vars then
                assert(type(document.vars)=='table',path..': vars must be an object')
                for key in pairs(document.vars) do assert(type(key)=='string',path..': vars keys must be names') end
                inlineVars=copy(document.vars)
            end
            result.files[#result.files+1]=path
            result.path=path
            for _,kind in ipairs(Config.kinds) do
                local section=document[kind]
                if section then
                    assert(type(section)=='table',path..': '..kind..' must be an object')
                    assert(section.use_equipment_snapshot==nil or type(section.use_equipment_snapshot)=='boolean',
                        path..': '..kind..'.use_equipment_snapshot must be a boolean')
                    result.rules[kind].use_equipment_snapshot=section.use_equipment_snapshot==true
                    for phase in pairs(section) do
                        assert(phase=='pre' or phase=='mid' or phase=='post' or phase=='use_equipment_snapshot',path..': unknown phase '..tostring(phase))
                    end
                    for _,phase in ipairs(Config.phases) do
                        for index,rule in ipairs(array(section[phase] or {},path..':'..kind..'.'..phase)) do
                            assert(type(rule)=='table',path..': rule must be an object')
                            assert(rule.id==nil or (type(rule.id)=='string' and rule.id:match('%S')),path..': invalid rule id')
                            assert(rule.disabled==nil or type(rule.disabled)=='boolean',path..': invalid disabled flag')
                            assert(rule.stop==nil or type(rule.stop)=='boolean',path..': invalid stop flag')
                            local commentOnly=rule.comment~=nil
                            for key in pairs(rule) do
                                assert(key=='id' or key=='when' or key=='commands' or key=='disabled' or key=='stop' or key=='comment',
                                    path..': unsupported rule key '..tostring(key))
                                if key~='comment' then commentOnly=false end
                            end
                            local list=result.rules[kind][phase]
                            if rule.id then
                                for i=#list,1,-1 do if list[i].id==rule.id then table.remove(list,i) end end
                            end
                            if not rule.disabled and not commentOnly then
                                local label=path..':'..kind..'.'..phase..'['..index..']'
                                list[#list+1]={id=rule.id,source=label,stop=rule.stop,
                                    conditions=expressions(rule.when,label..'.when'),
                                    commands=expressions(rule.commands,label..'.commands')}
                            end
                        end
                    end
                end
            end
            break -- Even an empty file intentionally suppresses all fallbacks.
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
            for key in pairs(document) do assert(key=='vars',path..': vars files only support vars') end
            assert(type(document.vars)=='table',path..': vars must be an object')
            for key in pairs(document.vars) do assert(type(key)=='string',path..': vars keys must be names') end
            variables.merge(result.vars,document.vars,path)
            result.vars_files[#result.vars_files+1]=path
        end
    end
    variables.merge(result.vars,inlineVars,result.path,-1)
    return result
end
return Config
