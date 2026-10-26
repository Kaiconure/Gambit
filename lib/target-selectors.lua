local selectors = {}
function selectors.alphabetical(a, b)
    local an = (a.name or ''):lower()
    local bn = (b.name or ''):lower()
    if an == bn then return (a.id or 0) < (b.id or 0) end
    return an < bn
end
local jobs = {}
for job in ('WAR MNK WHM BLM RDM THF PLD DRK BST BRD RNG SAM NIN DRG SMN BLU COR PUP DNC SCH GEO RUN'):gmatch('%S+') do
    jobs[job] = true
end

local groups = {
    MELEE = 'WAR MNK THF PLD DRK BST SAM NIN DRG BLU PUP DNC RUN',
    MELEE_DPS = 'SAM WAR MNK DRG THF DRK DNC NIN',
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

-- Stable filename selectors for automatic job entry points.
function selectors.entryPointGroups(job, isLeader)
    local result = {}
    job = (job or ''):upper()
    for name, members in pairs(groups) do
        if members[job] then result[#result + 1] = name:lower() end
    end
    if isLeader then result[#result + 1] = 'leader' end
    table.sort(result)
    return result
end

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

local function matches(member, key, group)
    if key == 'LEADER' then return member.is_party_leader == true end
    local job = type(member.main_job) == 'string' and member.main_job:upper()
    return job and (job == key or (group and group[job]))
end

-- Expand jobs/groups from current party context symbols, not raw IPC/trust metadata.
-- Preserve other selectors for the existing name/semantic-marker matcher.
local function resolvePositive(context, targets)
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
        if key and (jobs[key] or group or key == 'LEADER') then
            local matching = {}
            for i = 0, 5 do
                local member = context['p' .. i]
                if member
                    and (not excludeSelf or not isSelf(context, member))
                    and matches(member, key, group) then
                    matching[#matching + 1] = member
                end
            end
            table.sort(matching, selectors.alphabetical)
            for _, member in ipairs(matching) do add(member.name or (member.mob and member.mob.name)) end
        else
            add(target)
        end
    end
    return result
end

-- Keep exclusions separate until the caller matches actual members. This lets
-- exclusions remove matches supplied by names, semantic markers, or '*'.
function selectors.resolve(context, targets)
    if type(targets) == 'string' then targets = {targets} end
    local positive, negative = {}, {}
    for _, target in ipairs(targets or {}) do
        if type(target) == 'string' and target:sub(1,1) == '~' then
            negative[#negative+1] = target:sub(2)
        else
            positive[#positive+1] = target
        end
    end
    return resolvePositive(context, positive), resolvePositive(context, negative)
end

-- Sort already-filtered matches by selector precedence, then shared entity identity.
-- Pure name expansion for coordination; does not touch context.member/members.
function selectors.orderedNames(context, targets)
    local positive, negative = selectors.resolve(context, targets)
    local roster, result, seen = {}, {}, {}
    for index = 0, 5 do
        local member = context['p' .. index]
        if member then roster[#roster+1] = member end
    end
    table.sort(roster, selectors.alphabetical)
    local function matchesName(member, name)
        local key = name:lower()
        return key == '*' or (key == 'me' and isSelf(context, member))
            or key == (member.name or ''):lower()
            or key == (member.symbol or ''):lower() or key == (member.symbol2 or ''):lower()
    end
    for _, target in ipairs(positive) do
        for _, member in ipairs(roster) do
            local name = member.name or (member.mob and member.mob.name)
            if name and not seen[name:lower()] and matchesName(member, target) then
                local excluded = false
                for _, exclusion in ipairs(negative) do
                    if matchesName(member, exclusion) then excluded = true; break end
                end
                if not excluded then result[#result+1]=name; seen[name:lower()]=true end
            end
        end
    end
    return result
end

-- Load-time selector matching for the character whose actions are being loaded.
function selectors.matchesPlayer(player, targets, isLeader)
    local member = {name=player.name, main_job=player.main_job, is_me=true, is_party_leader=isLeader}
    local context = {me=member, p0=member}
    local positive, negative = selectors.resolve(context, targets)
    local function includes(names)
        for _, name in ipairs(names) do
            local key = name:lower()
            if key == '*' or key == 'me' or key == (member.name or ''):lower() then return true end
        end
        return false
    end
    return includes(positive) and not includes(negative)
end

function selectors.order(context, members, targets)
    local positive = selectors.resolve(context, targets)
    local function rank(member)
        for i, name in ipairs(positive) do
            if name == '*' or member.isNameMatch(name:lower()) then return i end
        end
        return math.huge
    end
    table.sort(members, function(a, b)
        local ar, br = rank(a), rank(b)
        if ar ~= br then return ar < br end
        return selectors.alphabetical(a, b)
    end)
    return members
end

local function excluded(context, member, negatives)
    for _, name in ipairs(negatives) do
        local key = name:lower()
        if key == '*' or (key == 'me' and isSelf(context, member)) or
            key == (member.name or (member.mob and member.mob.name) or ''):lower() or
            key == (member.symbol or ''):lower() or key == (member.symbol2 or ''):lower() then
            return true
        end
    end
    return false
end

-- Presence-only check: never modifies the action's member enumeration.
function selectors.partyHasJob(context, targets)
    if type(targets) == 'string' then targets = {targets} end
    local _, negatives = selectors.resolve(context, targets)
    for _, target in ipairs(targets or {}) do
        local key, excludeSelf = parseSelector(target)
        local group = key and groups[key]
        if key and (jobs[key] or group or key == 'LEADER') then
            for i = 0, 5 do
                local member = context['p' .. i]
                if member and member.is_participant == true
                    and not excluded(context, member, negatives)
                    and (not excludeSelf or not isSelf(context, member))
                    and matches(member, key, group) then return true end
            end
        end
    end
    return false
end

-- Apply opt-in ordering once, after expansion, filtering and deterministic ordering.
function selectors.applyOptions(context, members, options)
    options = options or {}
    if options.randomize then
        for i = #members, 2, -1 do
            local j = math.random(i)
            members[i], members[j] = members[j], members[i]
        end
    end
    if options.self_first then selectors.selfFirst(context, members) end
    return members
end

-- Promote self without changing the relative order of the other matches.
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
