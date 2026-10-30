-- Priority exists only while loading. Runtime vars contain ordinary values.
local loader = {}
local expandKeys=require('./lib/variable-key-expansion')

local function protected(node, priority)
    if node.priority ~= nil and node.priority >= priority then return true end
    for _, child in pairs(node.children or {}) do
        if protected(child, priority) then return true end
    end
    return false
end

local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end

local function keyPriority(key, inherited)
    local prefix = type(key) == 'string' and key:sub(1, 1)
    if prefix == '!' then return 1 end
    if prefix == '^' then return -1 end
    return inherited
end

function loader.new(warn)
    local root = {children = {}}
    local function merge(original, incoming, node, source, inherited, path)
        -- Sort by effective priority so prefixed siblings do not depend on pairs order.
        local keys = {}
        for key in pairs(incoming) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b)
            local am = keyPriority(a, inherited)
            local bm = keyPriority(b, inherited)
            if am ~= bm then return am < bm end
            return tostring(a) < tostring(b)
        end)
        node.children = node.children or {}
        for _, raw in ipairs(keys) do
            local marked = type(raw) == 'string' and (raw:sub(1, 1) == '!' or raw:sub(1, 1) == '^')
            local key = marked and raw:sub(2) or raw
            local priority = keyPriority(raw, inherited)
            local value = incoming[raw]
            local child = node.children[key] or {}
            node.children[key] = child
            local name = path == '' and tostring(key) or path .. '.' .. tostring(key)
            local empty = value == '$array.empty' or value == '$object.empty' or value == '$table.empty'
            local null = value == '$object.null' or value == '$table.null'
            local object = type(value) == 'table' and value[1] == nil
            local existingObject = type(original[key]) == 'table' and original[key][1] == nil
            if object and (original[key] == nil or existingObject) and child.priority == nil then
                -- Parent priority is inherited only by supplied children.
                original[key] = original[key] or {}
                merge(original[key], value, child, source, priority, name)
            else
                local replacement = value
                if empty then replacement = {} elseif null then replacement = nil end
                -- Ordinary clearing markers retain their historical override behavior.
                local ordinaryClear = priority == 0 and (empty or null)
                local blocked = protected(child, ordinaryClear and 1 or priority)
                if priority == 1 and blocked then
                    if not equal(original[key], replacement) and warn then
                        warn('Conflicting prioritized variable ' .. name .. ' in ' .. tostring(source) ..
                            '; keeping earlier prioritized definition (' .. tostring(child.source or 'nested definition') .. ').')
                    end
                elseif not blocked and (priority > (child.priority or -math.huge) or empty or null or original[key] == nil) then
                    original[key] = copy(replacement)
                    child.priority = priority
                    child.source = source
                    child.children = nil
                    child.cleared = (empty or null) or nil
                    if ordinaryClear then
                        child.priority = nil
                        child.cleared = nil
                    end
                    if object then
                        original[key] = {}
                        child.priority = nil
                        child.cleared = nil
                        merge(original[key], value, child, source, priority, name)
                    end
                elseif not blocked and type(value) == 'table' and existingObject then
                    -- Preserve the previous empty-table/default-array behavior.
                    merge(original[key], value, child, source, priority, name)
                end
            end
        end
    end
    return {
        merge = function(original, incoming, source, priority)
            if original and incoming then
                merge(original, expandKeys(incoming,priority or 0,tostring(source or 'vars')), root, source, priority or 0, '')
            end
        end,
    }
end

return loader
