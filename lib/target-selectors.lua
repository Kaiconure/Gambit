local selectors = {}
local jobs = {}
for job in ('WAR MNK WHM BLM RDM THF PLD DRK BST BRD RNG SAM NIN DRG SMN BLU COR PUP DNC SCH GEO RUN'):gmatch('%S+') do
    jobs[job] = true
end

local groups = {
    MELEE = 'WAR MNK THF PLD DRK BST SAM NIN DRG BLU PUP DNC RUN',
    RANGED = 'RNG COR',
    MAGE = 'WHM BLM RDM BRD SMN BLU SCH GEO',
    HEALER = 'WHM RDM SCH',
    NUKER = 'BLM RDM BLU SCH GEO',
    SUPPORT = 'RDM BRD COR SMN DNC SCH GEO',
    TANK = 'PLD NIN RUN',
}
for name, members in pairs(groups) do
    local lookup = {}
    for job in members:gmatch('%S+') do lookup[job] = true end
    groups[name] = lookup
end

-- Plural aliases share the same membership tables as their singular names.
groups.MAGES = groups.MAGE
groups.HEALERS = groups.HEALER
groups.NUKERS = groups.NUKER
groups.TANKS = groups.TANK

local function parseSelector(target)
    if type(target) ~= 'string' then return nil end
    local key = target:upper()
    local excludeSelf = key:sub(1, 1) == '^'
    if excludeSelf then key = key:sub(2) end
    return key, excludeSelf
end

local function isSelf(context, member)
    local me = context.me
    return member.is_me == true or (me ~= nil and
        (member == me or (me.id ~= nil and member.id == me.id)))
end

-- Expand jobs/groups from current party context symbols, not raw IPC/trust metadata.
-- Preserve other selectors for the existing name/semantic-marker matcher.
function selectors.resolve(context, targets)
    if type(targets) == 'string' then targets = {targets} end
    local result, seen = {}, {}
    local function add(value)
        if type(value) ~= 'string' then return end
        local key = value:lower()
        if not seen[key] then
            seen[key] = true
            result[#result + 1] = value
        end
    end
    for _, target in ipairs(targets or {}) do
        local key, excludeSelf = parseSelector(target)
        local group = key and groups[key]
        if key and (jobs[key] or group) then
            for i = 0, 5 do
                local member = context['p' .. i]
                if member and type(member.main_job) == 'string'
                    and (not excludeSelf or not isSelf(context, member))
                    and (member.main_job:upper() == key or
                        (group and group[member.main_job:upper()])) then
                    add(member.name or (member.mob and member.mob.name))
                end
            end
        else
            add(target)
        end
    end
    return result
end

-- Presence-only check: never modifies the action's member enumeration.
function selectors.partyHasJob(context, targets)
    if type(targets) == 'string' then targets = {targets} end
    for _, target in ipairs(targets or {}) do
        local key, excludeSelf = parseSelector(target)
        local group = key and groups[key]
        if key and (jobs[key] or group) then
            for i = 0, 5 do
                local member = context['p' .. i]
                local job = member and type(member.main_job) == 'string' and member.main_job:upper()
                if job and member.is_participant == true
                    and (not excludeSelf or not isSelf(context, member))
                    and (job == key or (group and group[job])) then return true end
            end
        end
    end
    return false
end

-- Only reorder existing matches; retain everyone else's randomized order.
function selectors.selfFirst(context, members)
    local me = context.me
    if not me then return members end
    for i, member in ipairs(members) do
        if member == me or (me.id and member.id == me.id) then
            if i > 1 then table.insert(members, 1, table.remove(members, i)) end
            break
        end
    end
    return members
end

return selectors
