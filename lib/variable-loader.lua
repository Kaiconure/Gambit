-- Priority exists only while loading. Runtime vars contain ordinary values.
local loader = {}

local function protected(node)
    if node.important then return true end
    for _, child in pairs(node.children or {}) do
        if protected(child) then return true end
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

function loader.new(warn)
    local root = {children = {}}
    local function merge(original, incoming, node, source, inherited, path)
        -- Ordinary keys first: !foo always beats foo in the same file.
        local keys = {}
        for key in pairs(incoming) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b)
            local am = type(a) == 'string' and a:sub(1, 1) == '!'
            local bm = type(b) == 'string' and b:sub(1, 1) == '!'
            if am ~= bm then return not am end
            return tostring(a) < tostring(b)
        end)
        node.children = node.children or {}
        for _, raw in ipairs(keys) do
            local marked = type(raw) == 'string' and raw:sub(1, 1) == '!'
            local key = marked and raw:sub(2) or raw
            local important = inherited or marked
            local value = incoming[raw]
            local child = node.children[key] or {}
            node.children[key] = child
            local name = path == '' and tostring(key) or path .. '.' .. tostring(key)
            local empty = value == '$array.empty' or value == '$object.empty' or value == '$table.empty'
            local null = value == '$object.null' or value == '$table.null'
            local object = type(value) == 'table' and value[1] == nil
            local existingObject = type(original[key]) == 'table' and original[key][1] == nil
            if object and (original[key] == nil or existingObject) and not child.important then
                -- Parent priority is inherited only by supplied children.
                if not child.cleared or important then
                    original[key] = original[key] or {}
                    merge(original[key], value, child, source, important, name)
                end
            else
                local replacement = value
                if empty then replacement = {} elseif null then replacement = nil end
                local blocked = protected(child)
                if important and blocked then
                    if not equal(original[key], replacement) and warn then
                        warn('Conflicting prioritized variable ' .. name .. ' in ' .. tostring(source) ..
                            '; keeping earlier prioritized definition (' .. tostring(child.source or 'nested definition') .. ').')
                    end
                elseif not blocked and (important or empty or null or original[key] == nil) then
                    original[key] = copy(replacement)
                    child.important = important or nil
                    child.source = source
                    child.children = nil
                    child.cleared = important and (empty or null) or nil
                    if object then
                        original[key] = {}
                        child.important = nil
                        merge(original[key], value, child, source, important, name)
                    end
                elseif not blocked and type(value) == 'table' and existingObject then
                    -- Preserve the previous empty-table/default-array behavior.
                    merge(original[key], value, child, source, important, name)
                end
            end
        end
    end
    return {
        merge = function(original, incoming, source)
            if original and incoming then merge(original, incoming, root, source, false, '') end
        end,
    }
end

return loader
