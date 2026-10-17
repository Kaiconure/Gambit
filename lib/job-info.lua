local info = {}
local jobs = {}
for job in ('WAR MNK WHM BLM RDM THF PLD DRK BST BRD RNG SAM NIN DRG SMN BLU COR PUP DNC SCH GEO RUN'):gmatch('%S+') do
    jobs[job] = true
end

function info.name(value)
    if type(value) ~= 'string' or not value:match('^[A-Za-z]+$') or #value < 3 or #value > 15 then
        return nil, 'Character names must contain 3–15 letters.'
    end
    return value:sub(1,1):upper() .. value:sub(2):lower()
end

function info.record(main, mainLevel, sub, subLevel)
    main = type(main)=='string' and main:upper()
    if not jobs[main] then return nil, 'Invalid main job.' end
    local function level(value)
        if value == nil or value == '' then return 1 end
        value = tonumber(value)
        if value and value >= 1 and value <= 99 and value == math.floor(value) then return value end
    end
    mainLevel = level(mainLevel)
    if not mainLevel then return nil, 'Job levels must be whole numbers from 1 to 99.' end
    if sub == 'n/a' or sub == '' then sub=nil end
    if sub then
        sub=sub:upper()
        if not jobs[sub] then return nil, 'Invalid subjob.' end
        subLevel=level(subLevel)
        if not subLevel then return nil, 'Job levels must be whole numbers from 1 to 99.' end
    else subLevel=nil end
    return {main_job=main,main_job_level=mainLevel,sub_job=sub,sub_job_level=subLevel}
end

function info.parse(spec)
    if type(spec) ~= 'string' then return nil, 'A job specification is required.' end
    local main, mainLevel, sub, subLevel = spec:match('^(%a%a%a)(%d*)/(%a%a%a)(%d*)$')
    if not main then main,mainLevel=spec:match('^(%a%a%a)(%d*)$') end
    if not main then return nil, 'Use a job specification such as WHM, WHM/RDM, or WHM75/BLM37.' end
    return info.record(main,mainLevel,sub,subLevel)
end

function info.apply(records, name, record)
    local normalized = info.name(name)
    if not normalized then return false end
    local valid = info.record(record.main_job,record.main_job_level,record.sub_job,record.sub_job_level)
    if not valid then return false end
    valid.t=os.clock()
    records[normalized]=valid
    return true
end

function info.message(name, record)
    local message = ('job -n %s -main %s -main-l %d'):format(name,record.main_job,record.main_job_level)
    if record.sub_job then
        message=message .. (' -sub %s -sub-l %d'):format(record.sub_job,record.sub_job_level)
    end
    return message
end
return info
