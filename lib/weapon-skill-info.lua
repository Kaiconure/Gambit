local info = {records={}, revision=0}
local names = require('./lib/job-info')

function info.encode(ids)
    if type(ids) ~= 'table' then return nil end
    local sorted, seen = {}, {}
    for _, id in ipairs(ids) do
        if type(id) ~= 'number' or id < 1 or id > 65535 or id ~= math.floor(id) then return nil end
        if not seen[id] then sorted[#sorted+1]=id; seen[id]=true end
    end
    table.sort(sorted)
    return #sorted > 0 and table.concat(sorted, ',') or '-'
end

function info.apply(name, encoded)
    name = names.name(name)
    if not name or type(encoded) ~= 'string' then return false end
    local ids = {}
    if encoded ~= '-' then
        if not encoded:match('^%d[%d,]*%d$') and not encoded:match('^%d+$') then return false end
        if encoded:find(',,', 1, true) then return false end
        for id in encoded:gmatch('%d+') do ids[#ids+1]=tonumber(id) end
    end
    local canonical = info.encode(ids)
    if not canonical then return false end
    local previous = info.records[name]
    if not previous or previous.encoded ~= canonical then
        info.records[name]={ids=ids, encoded=canonical}
        info.revision=info.revision+1
    end
    return true
end

function info.filter(participants, skills, helper)
    if not participants or #participants == 0 then return participants end
    local normalized = {}
    for _, skill in ipairs(skills or {}) do normalized[#normalized+1]=skill:lower() end
    local result = {}
    for _, name in ipairs(participants) do
        if name == '--no-matching-participant--' then return participants end
        local record = info.records[name]
        if record and helper.filter_weapon_skills(normalized, record.ids) then
            result[#result+1]=name
        end
    end
    -- Empty participant lists mean unrestricted participation at runtime.
    return #result > 0 and result or {'--no-capable-participant--'}
end

return info
