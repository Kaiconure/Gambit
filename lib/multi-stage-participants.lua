local selectors = require('./lib/target-selectors')
local values = require('./lib/variable-values')
local participants = {}
local cache = setmetatable({}, {__mode='k'})
local protectedLists = setmetatable({}, {__mode='k'})

function participants.isProtected(list, name)
    local protected = protectedLists[list]
    return protected and protected[name:lower()] or false
end

function participants.copyList(list)
    local copy = {unpack(list)}
    protectedLists[copy] = protectedLists[list]
    return copy
end

local function resolveParticipants(context, targets)
    if type(targets) == 'string' then targets = {targets} end
    local cleaned, positives, forced = {}, {}, {}
    for _, selector in ipairs(targets) do
        assert(type(selector) == 'string', 'Participants must be selectors or character names')
        if selector:sub(1,1) == '!' then
            selector = selector:sub(2)
            assert(selector:match('%S') and not selector:match('^[!~]'), 'Invalid protected participant selector')
            forced[#forced+1] = selector
        end
        cleaned[#cleaned+1] = selector
        if selector:sub(1,1) ~= '~' then positives[#positives+1] = selector end
    end
    local protected, allowed = {}, {}
    for _, name in ipairs(selectors.orderedNames(context, forced)) do protected[name:lower()] = true end
    for _, name in ipairs(selectors.orderedNames(context, cleaned)) do allowed[name:lower()] = true end
    local result = {}
    for _, name in ipairs(selectors.orderedNames(context, positives)) do
        if allowed[name:lower()] or protected[name:lower()] then result[#result+1] = name end
    end
    protectedLists[result] = protected
    return result
end

-- Keep unresolved definitions outside the compiled plan. TP, engagement, death
-- and distance remain runtime eligibility checks and never reorder the plan.
local function rosterKey(context)
    local rows = {}
    for index = 0, 5 do
        local member = context['p' .. index]
        if member then
            rows[#rows+1] = table.concat({tostring(member.name), tostring(member.id),
                tostring(member.main_job), tostring(member.is_party_leader),
                tostring(member.symbol), tostring(member.symbol2), tostring(member.is_me)}, '|')
        end
    end
    table.sort(rows)
    return table.concat(rows, '\n')
end

local function expand(config, context)
    if config.participants ~= nil then
        local original = config.participants
        config.participants = resolveParticipants(context, original)
        -- Empty resolved requirements must not become an unrestricted closer.
        if #original > 0 and #config.participants == 0 then
            config.participants = {'--no-matching-participant--'}
        end
    end
    for key, targets in pairs(config.stage_participants or {}) do
        local holder = {participants=targets}
        expand(holder, context)
        config.stage_participants[key] = holder.participants
    end
    if config.exclusions then
        local expanded = {}
        for selector, stages in pairs(config.exclusions) do
            assert(type(selector) == 'string' and selector:sub(1,1) ~= '!',
                '! is supported only in participant lists, not exclusion keys')
            for _, name in ipairs(selectors.orderedNames(context, {selector})) do
                expanded[name] = expanded[name] or {}
                for _, stage in ipairs(stages) do expanded[name][#expanded[name]+1] = stage end
            end
        end
        config.exclusions = expanded
    end
    for _, stage in ipairs(config.stages or {}) do expand(stage, context) end
    for _, entry in ipairs(config.on_ws or {}) do expand(entry, context) end
end

function participants.prepare(config, context, compile)
    local state = cache[config]
    if not state then
        state = {source=values.copy(config)}
        cache[config] = state
    end
    local key = rosterKey(context)
    if config._compiled and state.key == key then return end
    local resolved = values.copy(state.source)
    expand(resolved, context)
    -- Compile a separate plan so a failure cannot destroy the last usable plan.
    compile(resolved)
    for field in pairs(config) do config[field] = nil end
    for field, value in pairs(resolved) do config[field] = value end
    state.key = key
end

return participants
