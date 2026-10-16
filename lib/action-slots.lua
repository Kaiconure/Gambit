local values = require('./lib/variable-values')
local preconditions = require('./lib/action-preconditions')
local scopes = require('./lib/variable-scopes')
local slots = {}
local settingsPaths = require('./lib/settings-paths')

-- Lower values have higher precedence. Namespace proximity precedes file specificity.
function slots.priority(source, namespaces, playerName, mainJob)
    source = source:gsub('\\', '/'):gsub('^%./', ''):lower()
    local layer, relative = #namespaces * 2 + 2, source
    for index, namespace in ipairs(namespaces) do
        local prefix = settingsPaths.namespacePath(namespace):gsub('^%./', ''):lower() .. '/'
        if source:sub(1, #prefix) == prefix then
            layer, relative = (index-1)*2, source:sub(#prefix+1)
            local personal = 'players/' .. playerName:lower() .. '/'
            if relative:sub(1, #personal) == personal then
                relative = relative:sub(#personal+1)
            else layer = layer + 1 end
            break
        end
    end
    if layer == #namespaces * 2 + 2 then
        local personal = 'settings/' .. playerName:lower() .. '/'
        if source:sub(1, #personal) == personal then
            layer, relative = #namespaces*2, source:sub(#personal+1)
        elseif source:sub(1,9) == 'settings/' then
            layer, relative = #namespaces*2+1, source:sub(10)
        end
    end
    local specificity = 0 -- Entry points and explicit libraries precede common defaults.
    local name = relative:match('/common/([^/]+)%.json$')
    if name then
        if name == mainJob:lower() then specificity = 1
        elseif name:match('^%(.+%)$') then specificity = 2
        else specificity = 3 end
    elseif relative:match('/common%.json$') then specificity = 3 end
    return layer*10 + specificity
end

local function validateArray(value)
    assert(type(value) == 'table', 'slot/slots must be a string or array')
    for index in pairs(value) do
        assert(type(index) == 'number' and index >= 1 and index <= #value and index % 1 == 0,
            'Slot lists must be arrays')
    end
end

local function validateName(name)
    assert(type(name) == 'string' and name:match('%S'), 'Slot names must be nonempty strings')
end

function slots.names(action)
    local result = {}
    for _, key in ipairs({'slot', 'slots'}) do
        local names = action[key]
        if names ~= nil then
            if type(names) == 'string' then names = {names} end
            validateArray(names)
            for _, name in ipairs(names) do
                if type(name) == 'table' then
                    validateArray(name)
                    for _, alternative in ipairs(name) do validateName(alternative) end
                else
                    validateName(name)
                end
                result[#result+1] = name
            end
        end
    end
    return result
end

function slots.new(container, priority, warn)
    local groups, seen, used = {}, {}, {}
    local serial = 0
    local result = {}
    function result.collect(document, source, parent)
        if document.contributions == nil then return end
        assert(not (parent and parent._slotContribution), 'Contributed imports cannot define contributions')
        assert(type(document.contributions) == 'table', 'contributions must be an object')
        local key = source .. ':' .. tostring(parent and parent._variableScope or 0)
        if seen[key] then return end
        seen[key] = true
        local declared = {}
        for names, actions in pairs(document.contributions) do
            validateName(names)
            assert(type(actions) == 'table', 'Slot contributions must be arrays')
            for index in pairs(actions) do
                assert(type(index) == 'number' and index >= 1 and index <= #actions and index % 1 == 0,
                    'Slot contributions must be arrays')
            end
            for part in (names .. ','):gmatch('(.-),') do
            local name = part:match('^%s*(.-)%s*$')
            local replace = name:sub(1,1) == '!'
            local fallback = name:sub(1,1) == '^'
            if replace or fallback then name = name:sub(2):match('^%s*(.-)%s*$') end
            validateName(name)
            assert(not name:match('^[!^]'), 'Only one ! or ^ prefix is allowed on a contribution name')
            assert(not declared[name], 'Duplicate contribution name: ' .. name)
            declared[name] = true
            groups[name] = groups[name] or {}
            groups[name][#groups[name]+1] = {
                actions=values.copy(actions), parent=values.copy(parent or {}),
                source=source, priority=priority(source), order=#groups[name]+1, replace=replace, fallback=fallback,
            }
            end
        end
    end
    function result.expand(types)
        for _, group in pairs(groups) do
            table.sort(group, function(a,b)
                if a.priority ~= b.priority then return a.priority < b.priority end
                return a.order < b.order
            end)
            local hasExplicit = false
            for _, contribution in ipairs(group) do
                if not contribution.fallback then hasExplicit = true; break end
            end
            -- Presence, including an empty definition, suppresses defaults regardless
            -- of proximity. Otherwise retain only the closest fallback definition.
            for index = #group, 1, -1 do
                if (hasExplicit and group[index].fallback) or (not hasExplicit and index > 1) then
                    table.remove(group, index)
                end
            end
            for index, contribution in ipairs(group) do
                if contribution.replace then
                    for tail = #group, index+1, -1 do table.remove(group, tail) end
                    break
                end
            end
        end
        for _, kind in ipairs(types) do
            local output = {}
            for _, placeholder in ipairs(container[kind]) do
                if placeholder.slot == nil and placeholder.slots == nil then
                    output[#output+1] = placeholder
                else
                    for _, entry in ipairs(slots.names(placeholder)) do
                    local name
                    local alternatives = type(entry) == 'table' and entry or {entry}
                    for _, alternative in ipairs(alternatives) do
                        -- Unselected fallbacks are intentional, not unmatched slots.
                        used[alternative] = true
                        if not name and groups[alternative] ~= nil then name = alternative end
                    end
                    for _, group in ipairs((name and groups[name]) or {}) do
                        -- Each occurrence owns a copy of the contribution's scope chain.
                        local parent = values.copy(group.parent)
                        local function cloneScope(id)
                            if not id then return placeholder._variableScope end
                            local definition = container._variableScopes[id]
                            local ancestor = cloneScope(definition.parent)
                            local proxy = {with_vars=values.copy(definition.overrides), _variableScope=ancestor}
                            scopes.prepare(container, proxy)
                            return proxy._variableScope
                        end
                        parent._variableScope = cloneScope(parent._variableScope)
                        local inherited = preconditions.collect(placeholder)
                        for _, condition in ipairs(preconditions.collect(parent)) do
                            inherited[#inherited+1] = condition
                        end
                        for _, definition in ipairs(group.actions) do
                            assert(type(definition) == 'table', 'Slot actions must be objects')
                            local action = values.copy(definition)
                            assert(action.slot == nil and action.slots == nil, 'Contributions cannot contain slots')
                            serial = serial + 1
                            action._inheritedPreconditions = values.copy(inherited)
                            action._variableScope = parent._variableScope
                            action.importedFrom = group.source
                            action._slotContribution = serial
                            output[#output+1] = action
                        end
                    end
                    end
                end
            end
            container[kind] = output
        end
        local names = {}
        for name in pairs(groups) do if not used[name] then names[#names+1]=name end end
        table.sort(names)
        for _, name in ipairs(names) do warn('No action slot found for contributions: ' .. name) end
    end
    return result
end

return slots
