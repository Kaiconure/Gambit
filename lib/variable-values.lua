local values = {}

function values.path(name)
    local result = {}
    for part in (name .. '.'):gmatch('(.-)%.') do
        part = part:match('^%s*(.-)%s*$')
        if part ~= '' and (part ~= 'vars' or #result > 0) then
            local number = tonumber(part)
            result[#result + 1] = number and number == math.floor(number) and number or part
        end
    end
    return result
end

function values.get(root, name)
    local levels = values.path(name)
    if #levels == 0 then return nil end
    local ref = root
    for i = 1, #levels - 1 do
        if type(ref) ~= 'table' then return nil end
        ref = ref[levels[i]]
        if type(ref) ~= 'table' then return nil end
    end
    if type(ref) ~= 'table' then return nil end
    local last = levels[#levels]
    if #levels > 1 then
        if last == '$length' then return #ref end
        if last == '$type' then return type(ref) end
    end
    return ref[last]
end

function values.copy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[key] = values.copy(child, seen) end
    return result
end

-- General opt-in shallow key normalization. Values retain their original data.
function values.caseInsensitiveKeys(value)
    assert(type(value)=='table','caseInsensitiveKeys expects a table')
    local result={}
    for key,child in pairs(value) do
        local normalized=type(key)=='string' and key:lower() or key
        assert(result[normalized]==nil,'Case-insensitive key collision: '..tostring(key))
        result[normalized]=child
    end
    return result
end
return values
