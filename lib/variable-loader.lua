local profiling=require('./lib/load-profile')
-- Priority exists only while loading. Runtime vars contain ordinary values.
local loader = {}
local expandKeys=require('./lib/variable-key-expansion')

local function protected(node, priority, rank)
    if node.priority ~= nil and (node.priority > priority or
        node.priority == priority and (node.rank or 0) <= rank) then return true end
    for _, child in pairs(node.children or {}) do
        if protected(child, priority, rank) then return true end
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

local function isArray(value)
    if type(value) ~= 'table' then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then return false end
        count = count + 1
    end
    return count == #value
end

function loader.new(warn, sourceRank)
    local root = {children = {}}
    local order = 0
    local rank = 0
    -- Array operations are overlays, not replacement values. Restore the base
    -- before each layer so child operations do not hide an inherited base.
    local function restore(original, node)
        for key, child in pairs(node.children or {}) do
            if child.operations then original[key] = copy(child.base) end
            if type(original[key]) == 'table' then restore(original[key], child) end
        end
    end
    local function render(original, node, path)
        for key, child in pairs(node.children or {}) do
            local name = path == '' and tostring(key) or path .. '.' .. tostring(key)
            if type(original[key]) == 'table' then render(original[key], child, name) end
            if child.operations then
                child.base = copy(original[key])
                -- Parent operations first; child operations have the last word.
                -- At equal priority in one layer, removal wins over append.
                table.sort(child.operations, function(a,b)
                    if a.priority ~= b.priority then return a.priority < b.priority end
                    if a.rank ~= b.rank then return a.rank > b.rank end
                    if a.order ~= b.order then return a.order > b.order end
                    return a.kind < b.kind
                end)
                for _, operation in ipairs(child.operations) do
                    local priority = child.priority
                    local allowed = priority == nil or operation.priority > priority
                        or operation.priority == priority and operation.rank <= (child.rank or 0) and
                            (not child.cleared or operation.rank < (child.rank or 0) or operation.order < child.order)
                    if allowed then
                        if original[key] ~= nil and not isArray(original[key]) then
                            if warn and not operation.warned then
                                warn('Cannot ' .. operation.kind .. ' on non-array variable ' .. name .. ' in ' .. tostring(operation.source))
                                operation.warned = true
                            end
                        elseif operation.kind == 'remove' then
                            if original[key] ~= nil then
                                local result = {}
                                for _, value in ipairs(original[key]) do
                                    local remove = false
                                    for _, unwanted in ipairs(operation.values) do
                                        if equal(value, unwanted) then remove = true; break end
                                    end
                                    if not remove then result[#result+1] = value end
                                end
                                original[key] = result
                            end
                        else
                            local result = {}
                            local function add(values)
                                for _, value in ipairs(values or {}) do
                                    local found = false
                                    for _, existing in ipairs(result) do
                                        if equal(existing, value) then found = true; break end
                                    end
                                    if not found then result[#result+1] = copy(value) end
                                end
                            end
                            add(original[key]); add(operation.values)
                            original[key] = result
                        end
                    end
                end
            end
        end
    end
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
            local operation = type(key) == 'string' and (key:match('^array%.append') and 'append' or key:match('^array%.remove') and 'remove')
            if operation then
                local target = key:match('^array%.' .. operation .. '%((.*)%)$')
                assert(target, tostring(source) .. ': malformed array.' .. operation .. ' key ' .. key)
                target = target:match('^%s*(.-)%s*$')
                assert(target ~= '', tostring(source) .. ': array.' .. operation .. ' requires a variable name')
                local child = node.children[target] or {}
                node.children[target] = child
                if not isArray(value) then
                    if warn then warn('array.' .. operation .. '(' .. target .. ') requires an array in ' .. tostring(source)) end
                else
                    child.operations = child.operations or {}
                    child.operations[#child.operations+1] = {kind=operation,values=copy(value),priority=priority,source=source,order=order,rank=rank}
                end
            else
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
                    local blocked = protected(child, priority, rank)
                    if priority == 1 and blocked then
                        if not equal(original[key], replacement) and warn then
                            -- DON'T PRINT A WARNING FOR NOW
                            -- warn('Conflicting prioritized variable ' .. name .. ' in ' .. tostring(source) ..
                            --     '; keeping earlier prioritized definition (' .. tostring(child.source or 'nested definition') .. ').')
                        end
                    elseif not blocked and (priority > (child.priority or -math.huge)
                        or priority == child.priority and rank < (child.rank or 0)
                        or empty or null or original[key] == nil) then
                        original[key] = copy(replacement)
                        child.priority = priority
                        child.source = source
                        child.rank = rank
                        child.order = order
                        child.children = nil
                        child.cleared = (empty or null) or nil
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
    end
    return {
        merge = function(original, incoming, source, priority)
            profiling.start('variable merges')
            if original and incoming then
                rank=sourceRank and sourceRank(source) or 0
                local expanded = expandKeys(incoming,priority or 0,tostring(source or 'vars'))
                order = order + 1
                restore(original, root)
                merge(original, expanded, root, source, priority or 0, '')
                render(original, root, '')
            end
            profiling.stop('variable merges')
        end,
    }
end

return loader
