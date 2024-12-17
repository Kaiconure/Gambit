local PARTY_MEMBER_FIELD_NAMES = {
    'p0', 'p1', 'p2', 'p3', 'p4', 'p5',         -- Party
}

local ALL_MEMBER_FIELD_NAMES = {
    'p0', 'p1', 'p2', 'p3', 'p4', 'p5',         -- Party
    'a10', 'a11', 'a12', 'a13', 'a14', 'a15',   -- Alliance 1
    'a20', 'a21', 'a22', 'a23', 'a24', 'a25'    -- Alliance 2
}

-----------------------------------------------------------------------------------------
-- Returns the specified args, unless the first element is a table in 
-- which case that table is returned
local function varargs(args, default)
    -- We allow a single array to be passed in as a substitute for variable length argument lists. In this
    -- case, we will simply use that array as the entire input.
    if 
        type(args) == 'table' and       -- We have an actual table
        #args == 1 and                  -- The table only has one element
        type(args[1]) == 'table' and    -- That one element is a table
        args[1][1] ~= nil               -- That one element looks to be an array
    then
        args = args[1]
    end

    -- If args is not a table, we'll promote it as appropriate
    if type(args) ~= 'table' then
        if args then
            args = {args}
        else
            args = {}
        end
    end

    -- We know that args is a table. If it's empty and we have a valid default, use that as a fallback
    if #args == 0 and default then
        args = { default }
    end

    return args
end

-----------------------------------------------------------------------------------------
--
function __context_compare(a, b) return a == b end
function __context_compare_strings(a, b) return string.lower(a) == string.lower(tostring(b or '')) end
function __context_compare_strings_fast(lower_a, b) return lower_a == string.lower(tostring(b or '')) end

local context_constants = {
    ra_distance = 25,
    spell_distance = 20,
    
    provoke_distance = 15,
    
    returnfaith_distance = 6,
    returntrust_distance = 6
}

local function context_any(search, ...)
    local cmp = __context_compare
    if type(search) == 'string' then
        search = string.lower(search)
        cmp = __context_compare_strings_fast
    end

    local _set = varargs({...})
    if type(_set) == 'table' then
        for i, v in ipairs(_set) do
            if cmp(search, v) then
                return true
            end
        end
    end
end

-----------------------------------------------------------------------------------------
--
local function context_send_command(command, ...)
    if type(command) == 'string' then
        command = command:format(...)

        if settings.verbosity >= VERBOSITY_TRACE then
            writeTrace('Sending action ' .. text_magenta(command))
        end
        
        windower.send_command(command)
    end
end

-----------------------------------------------------------------------------------------
--
local function context_iif(condition, ifYes, ifNo)
    if condition then
        return ifYes
    end

    return ifNo
end

-----------------------------------------------------------------------------------------
-- Converts a condition to a boolean (truthy to true, falsey to false)
local function context_boolean(condition)
    return context_iif(condition, true, false)
end

-----------------------------------------------------------------------------------------
--
local function context_noop() 
    return
end

-----------------------------------------------------------------------------------------
--
function context_randomize(...)
    local args = varargs({...})
    local count = args and #args or 0

    if count == 0 then return nil end
    if count == 1 then return args[1] end

    -- -- We need a deep copy of the args
    -- args = json.parse(json.stringify(args))

    local MAX_PASSES = 1

    -- This is a very basic shuffle. Iterate through the array a given number of times and
    -- swap the current element with a random one at some other location in the array. 
    for pass = 1, MAX_PASSES do 
        for i, val in ipairs(args) do
            local dest = math.random(1, count)
            if dest ~= i then
                args[i] = args[dest]
                args[dest] = val
            end
        end
    end

    return args

    --return args[math.random(1, count)]
end

-----------------------------------------------------------------------------------------
--
function context_wait(s)
    local s = math.max(tonumber(s) or 1, 0)
    writeDebug('Context waiting for %s':format(pluralize(s, 'second', 'seconds', Colors.debug)))
    coroutine.sleep(s)
end

-----------------------------------------------------------------------------------------
-- Find the smallest number in a set
function context_min(...)
    local args = varargs({...})

    -- Handle the basic cases
    local count = #args
    if count == 0 then return end
    if count == 1 then return args[1] end
    if count == 2 then return math.min(args[1], args[2]) end

    local min = args[1]
    for i = 2, count do
        local current = args[i]
        if current < min then
            min = current
        end
    end

    return min
end

-----------------------------------------------------------------------------------------
-- Find the largest number in a set
function context_max(...)
    local args = varargs({...})

    -- Handle the basic cases
    local count = #args
    if count == 0 then return end
    if count == 1 then return args[1] end
    if count == 2 then return math.max(args[1], args[2]) end

    local max = args[1]
    for i = 2, count do
        local current = args[i]
        if current > max then
            max = current
        end
    end

    return max
end

-----------------------------------------------------------------------------------------
-- Enumerates over all fields in the context named in the given keys, and returns
-- an array of all the matching results.
local function enumerateContextByExpression(context, keys, expression, ...)
    local retVal = { }

    if expression == nil or expression == '' or expression == '*' then expression = 'true' end

    if 
        type(expression) ~= 'string' or
        type(keys) ~= 'table' or
        #keys == 0 
    then
        return retVal
    end

    expression = expression:format(...)
    
    local fn = loadstring('return ' .. expression)
    if type(fn) == 'function' then
        for i, key in ipairs(keys) do
            local field = context[key]
            
            if field then
                local fenv = field

                -- Add all fields for this party member to the context
                -- for field, value in pairs(field) do
                --     if type(value) ~= 'table' then
                --         fenv[field] = value
                --     end
                -- end

                -- Apply the env to the function, and execute it. Return this member if it evaluates successfully.
                --writeDebug('Evaluating: %s':format(expression))
                setfenv(fn, fenv)
                if fn() then
                    --writeDebug('Evaluation passed!')
                    retVal[#retVal + 1] = fenv
                end
            end
        end
    end

    return retVal
end

-----------------------------------------------------------------------------------------
-- Gets the next member enumerator for the current action
local function getNextMemberEnumerator(context)
    local enumerator = context.action.enumerators.member
    if 
        type(enumerator) == 'table' and
        type(enumerator.data) == 'table' and
        type(enumerator.at) == 'number'
    then
        -- Now we will march forward until we find the next valid result,
        -- or until we run off the end of the result set
        while 
            enumerator.at < #enumerator.data 
        do
            -- Advance the index
            enumerator.at = enumerator.at + 1
            
            -- Validate the new result
            local member = enumerator.data[enumerator.at]
            if member then
                local mob = windower.ffxi.get_mob_by_index(member.index)
                if 
                    mob and
                    mob.valid_target
                then
                    context.member = member
                    return context.member
                end
            end
        end
    end

    context.member = nil
    context.action.enumerators.member = nil
    return nil
end

-----------------------------------------------------------------------------------------
-- Gets the expression required to match all of the given names. If no names are
-- provided, the expression will always evaluate to true.
local function createMemberNamesExpression(context, names)
    local expression = ''

    if type(names) ~= 'table' or #names == 0 then
        expression = 'true'
    else
        local first = true
        for i, name in ipairs(names) do
            if type(name) == 'string' then
                name = string.lower(name)
                expression = expression .. (first and ' ' or ' or ') .. 'isNameMatch("%s")':format(name)
                first = false
            end
        end
    end

    -- If it somehow wasn't set at all, we'll just never evaluate to true
    if expression == '' then
        expression = 'false'
    end

    return expression
end

-----------------------------------------------------------------------------------------
-- 
local function setPartyEnumerators(context)

    -----------------------------------------------------------------------------------------
    -- Count the number of party members matching the specified expression
    context.partyCount = function(expression)
        expression = expression or 'true'

        local fn = loadstring('return ' .. expression)
        local count = 0

        for i, name in ipairs(PARTY_MEMBER_FIELD_NAMES) do
            local member = context[name]
            if member then
                setfenv(fn, member)
                if fn() then
                    count = count + 1
                end
            end
        end

        return count
    end

    ----------------------------------------------------------------------------------------
    -- Count the number of party members and allies matching the specified expression
    context.allyCount = function(expression, ...)
        expression = (expression or 'true'):format(...)

        local fn = loadstring('return ' .. expression)
        local count = 0
        
        for i, name in ipairs(PARTY_MEMBER_FIELD_NAMES) do
            local member = context[name]
            if member then
                setfenv(fn, member)
                if fn() then
                    count = count + 1
                end
            end
        end

        return count
    end

    -----------------------------------------------------------------------------------------
    -- Find a party member who matches the given expression
    context.partyAny = function(expression, ...)
        local results = enumerateContextByExpression(context, PARTY_MEMBER_FIELD_NAMES, expression, ...)
        
        context.member = results[1]
        context.members = results
        context.action.enumerators.member = context.member and { data = results, at = 1}
        
        return context.member
    end

    -----------------------------------------------------------------------------------------
    -- 
    context.partyAll = function(expression, ...)
        return getNextMemberEnumerator(context) or context.partyAny(expression)
    end

    -----------------------------------------------------------------------------------------
    -- Find all party members with the specified names
    context.partyByName = function (...)
        return context.partyAll(
            createMemberNamesExpression(context, 
                varargs({...})
            )
        )
    end

    -----------------------------------------------------------------------------------------
    -- Find a party or alliance member who match the given expression
    context.allyAny = function(expression, ...)
        local results = enumerateContextByExpression(context, ALL_MEMBER_FIELD_NAMES, expression, ...)

        context.member = results[1]
        context.members = results
        context.action.enumerators.member = context.member and { data = results, at = 1}

        return context.member
    end

    -----------------------------------------------------------------------------------------
    -- 
    context.allyAll = function(expression, ...)
        return getNextMemberEnumerator(context) or context.allyAny(expression, ...)
    end

    -----------------------------------------------------------------------------------------
    -- Find all allies with the specified names
    context.alliesByName = function (...)
        return context.allyAll(
            createMemberNamesExpression(context, 
                varargs({...})
            )
        )
    end
end

local function setArrayEnumerators(context)
    context.iterate = function(name, ...)
        if name == nil then
            return
        end

        if not context.action.enumerators.array then
            context.action.enumerators.array = { }
        end

        local results = nil

        -- If no name was provided and our first entry was an array
        if type(name) == 'table' then
            results = name
            name = 'default'
        end

        -- Start by grabbing the current array enumerator
        local enumerator = context.action.enumerators.array[name]
        if enumerator then
            -- Advance the enumerator
            enumerator.at = enumerator.at + 1

            -- If the new enumerator is within the array bounds, return that item
            if enumerator.at <= #enumerator.data then
                -- Store the result
                context.result          = enumerator.data[enumerator.at]
                context.results[name]   = context.result

                return context.result
            end
        end

        -- If we don'thave a valid iterator, go back to the source
        if not results then
            results = varargs({...})
        end

        -- If there are any results, we'll set up a new array enumerator and return the first item
        if #results > 0 then
            context.action.enumerators.array[name] = { data = results, at = 1}
            
            enumerator = context.action.enumerators.array[name]
            
            -- Store the results
            context.result          = enumerator.data[enumerator.at]
            context.results[name]   = context.result

            return context.result
        end

        -- If we've gotten here, we'll clear the array enumerator
        context.action.enumerators.array[name] = nil
    end

    -- Get the iterator for the collection with the given name
    context.getIterator = function(name)
        return context.result and context.result[name]
    end
end

-----------------------------------------------------------------------------------------
-- 
local function setEnumerators(context)
    setPartyEnumerators(context)
    setArrayEnumerators(context)
end

-----------------------------------------------------------------------------------------
--
local function initContextTargetSymbol(context, symbol)
    if not symbol.mob then
        symbol.targets = {}
        return
    end

    -- Resource target object can have these booleans: Self, Party, NPC, Player, Ally, Enemy
    symbol.targets = {
        Self = symbol.mob.id == context.player.id,
        Party = symbol.mob.in_party,
        NPC = symbol.mob.is_npc,
        Player = symbol.mob.spawn_type == SPAWN_TYPE_PLAYER,
        Ally = symbol.mob.is_ally,
        Enemy = symbol.mob.spawn_type == SPAWN_TYPE_MOB
    }

    -- TODO: Figure out what pets show as under the targets flags

    if symbol.targets.Self then
        -- "vitals": { "max_hp": 1393, "hpp": 84, "mp": 1274, "max_mp": 1274, "mpp": 100, "hp": 1175, "tp": 0 },
        
        local player = context.player
        local vitals = player.vitals

        -- Vitals
        symbol.hp = vitals.hp
        symbol.hpp = vitals.hpp
        symbol.max_hp = vitals.max_hp
        symbol.mp = vitals.mp
        symbol.mpp = vitals.mpp
        symbol.max_mp = vitals.max_mp
        symbol.tp = vitals.tp
        
        -- Main job and main job level
        symbol.main_job = player.main_job
        symbol.main_job_level = player.main_job_level
        symbol.level = symbol.main_job_level

        -- Sub job and sub job level
        symbol.sub_job = player.sub_job
        symbol.sub_job_level = player.sub_job_level

        -- Active buffs. For the player, we'll use the live player object buffs.
        symbol.buffs = player.buffs

        -- Flag to determine if you're at the master level
        symbol.is_mastered = (player.superior_level == 5)

        symbol.symbol2 = 'me'
    elseif symbol.member then
        symbol.name = symbol.member.name
        symbol.hp = symbol.member.hp
        symbol.hpp = symbol.member.hpp
        symbol.mp = symbol.member.mp
        symbol.mpp = symbol.member.mpp
        symbol.tp = symbol.member.tp

        -- Active buffs
        if symbol.mob.spawn_type == SPAWN_TYPE_PLAYER then
            -- For player party members and allies, we'll use the global state manager driven by party buffs
            symbol.buffs = actionStateManager:getMemberBuffsFor(symbol.mob)
        elseif symbol.mob.spawn_type == SPAWN_TYPE_TRUST then
            -- For trusts, we'll use the much more limited self-initiated trust buff data we're tracking
            symbol.buffs = actionStateManager:getBuffsForMob(symbol.mob.id)
        end
    else
        symbol.name = symbol.mob.name
        symbol.hpp = symbol.mob.hpp
        symbol.buffs = actionStateManager:getBuffsForMob(symbol.mob.id)
    end

    -- Set the shared properties
    symbol.name = symbol.mob.name
    symbol.id = symbol.mob.id
    symbol.index = symbol.mob.index
    symbol.distance = math.sqrt(symbol.mob.distance or 0)
    symbol.is_trust = (symbol.mob.spawn_type == SPAWN_TYPE_TRUST)
    symbol.is_player = (symbol.mob.spawn_type == SPAWN_TYPE_PLAYER)
    symbol.x = symbol.mob.x
    symbol.y = symbol.mob.y
    symbol.z = symbol.mob.z
    symbol.valid_target = symbol.mob.valid_target
    symbol.spawn_type = symbol.mob.spawn_type
    symbol.status = symbol.mob.status

    if symbol.status == STATUS_RESTING then symbol.is_resting = true end
    if symbol.status == STATUS_ENGAGED then symbol.is_engaged = true end
    if symbol.status == 2 or symbol.status == 3 then symbol.is_dead = true end
    if symbol.status == STATUS_IDLE then symbol.is_idle = true end

    -- Trusts
    if symbol.is_trust then
        local metadata = getTrustSpellMeta(symbol.name,
            TrustSearchModes.best,
            context.player,
            context.party)
        
        if metadata then
            symbol.meta = metadata
            symbol.is_non_interactive = context_boolean(metadata.non_interactive)
            symbol.is_magic_trust = context_boolean(
                not symbol.is_non_interactive and (meta.jobs_with_mp[metadata.main_job] or meta.jobs_with_mp[metadata.sub_job]))
        end
    end

    if symbol.hpp == nil then
        symbol.hpp = 0
        symbol.hp = 0
    end

    symbol.isNameMatch = function(test)
        test = string.lower(test or '!!invalid')
        return test == string.lower(symbol.name or '') or
            test == string.lower(symbol.symbol or '') or
            test == string.lower(symbol.symbol2 or '')
    end
end

-----------------------------------------------------------------------------------------
--
local function loadContextTargetSymbols(context, target)
    -- Fill in targets
    if target then
        context.t = { symbol = 't', symbol2 = 'bt', mob = target }
        initContextTargetSymbol(context, context.t)
        context.bt = context.t
    else
        context.t = nil
        context.bt = nil
    end

    context.me = { symbol = 'me', mob = windower.ffxi.get_mob_by_target('me') }
    initContextTargetSymbol(context, context.me)
    context.self = context.me

    local pet = windower.ffxi.get_mob_by_target('pet')
    if pet then
        context.pet = { symbol = 'pet', mob = windower.ffxi.get_mob_by_target('pet') }
        initContextTargetSymbol(context, context.pet)
    else
        context.pet = nil
    end

    -- We'll store the list of trusts in our main party. Trusts can't be called in 
    -- an alliance, so this is all we need.
    context.party1_trusts = {}

    context.party1_by_id = {}
    context.party1_by_index = {}

    for i = 0, 5 do
        local p = 'p' .. i
        local a1 = 'a1' .. i
        local a2 = 'a2' .. i

        context[p] = nil
        if context.party[p] and context.party[p].mob then
            local mob = context.party[p].mob
            context[p] = { symbol = p, mob = mob, member = context.party[p], targets = {}, isParty = true, isAlly = true }
            initContextTargetSymbol(context, context[p])

            -- Store party leader info as well
            if context.party.party1_leader == mob.id then
                context[p].is_party_leader = true
                context.party_leader = context[p]
            else
                context[p].is_party_leader = false
            end

            -- Add trusts to the list
            if mob.spawn_type == SPAWN_TYPE_TRUST then
                context.party1_trusts[#context.party1_trusts + 1] = context[p]
            end

            -- Add members to the party id list
            context.party1_by_id[#context.party1_by_id + 1] = mob.id
            context.party1_by_index[#context.party1_by_index + 1] = mob.index
        end

        context[a1] = nil
        if context.party[a1] then
            local mob = context.party[a1].mob
            context[a1] = { symbol = a1, mob = mob, member = context.party[a1], targets = {}, isParty = false, isAlly = true }
            initContextTargetSymbol(context, context[a1])
        end

        context[a2] = nil
        if context.party[a2] then
            local mob = context.party[a2].mob
            context[a2] = { symbol = a2, mob = mob, member = context.party[a2], targets = {}, isParty = false, isAlly = true }
            initContextTargetSymbol(context, context[a2])
        end
    end

    -- If we are the leader, or if we are the only one in the party, save that info
    if
        context.party == nil or
        context.party.party1_count == 1 or
        context.party.party1_leader == context.me.id
    then
        -- It is indeed possible for p0 to be null; on death, for example.
        if 
            not context.p0 
        then
            context.p0 = context.me
        end

        context.party_leader = context.p0
        context.p0.is_party_leader = true
        context.me.is_party_leader = true
    end
end

-----------------------------------------------------------------------------------------
--
local function makeActionContext(actionType, time, target, mobEngagedTime, battleScope)
    local context = {
        actionType = actionType,
        time = time,
        strategy = settings.strategy,
        mobTime = mobEngagedTime or 0,
        battleScope = battleScope,
        skillchain = actionStateManager:getSkillchain(),
        party_weapon_skill = actionStateManager:getPartyWeaponSkillInfo(),
        vars = actionStateManager.vars,
    }

    context.target = target
    context.player = windower.ffxi.get_player()
    context.party = windower.ffxi.get_party()

    -- Must be called after the player and party have been assigned
    loadContextTargetSymbols(context, target)    

    --------------------------------------------------------------------------------------
    --
    context.log = function (...) 
        local messages = varargs({...})
        local output = ''
        for i, message in pairs(messages) do
            if type(message) == 'boolean' then
                message = context_iif(message, 'true', 'false')
            end
            output = output .. tostring(message or '') .. ' '
        end

        writeMessage('%s %s':format(
            text_gray('[action]'),
            text_cornsilk(output)
        ))
    end

    --------------------------------------------------------------------------------------
    --
    context.debug = function (...) 
        local messages = varargs({...})
        local output = ''
        for i, message in pairs(messages) do
            if type(message) == 'boolean' then
                message = context_iif(message, 'true', 'false')
            end
            output = output .. tostring(message or '') .. ' '
        end

        if settings.verbosity >= VERBOSITY_DEBUG then
            writeMessage('%s %s':format(
                text_gray('[action.d]', Colors.debug),
                output
            ))
        end
    end

    --------------------------------------------------------------------------------------
    --
    context.equip = function(slot, name)
        if slot == nil then return end

        if name == nil then
            if context.item == nil then return end            
            name = context.item.name

            if name == nil then
                return
            end
        end

        local command = string.format('input /equip %s "%s";',
            slot,
            name)

        writeVerbose('Equipping: %s %s %s':format(
            text_item(name, Colors.verbose),
            CHAR_RIGHT_ARROW,
            text_gearslot(slot, Colors.verbose)
        ))

        sendActionCommand(
            command,
            context,
            1.5
        )
    end

    --------------------------------------------------------------------------------------
    --
    context.canUseWeaponSkill = function (...)
        local weaponSkills = varargs({...})
        for key, _weaponSkill in ipairs(weaponSkills) do
            weaponSkill = findWeaponSkill(_weaponSkill)
            if weaponSkill then
                local target = weaponSkill.targets.Self and context.me or context.bt
                local targetOutOfRange = target and
                    target.distance and
                    target.distance > math.max(weaponSkill.range, 5)

                if not targetOutOfRange then
                    if canUseWeaponSkill(
                        context.player,
                        weaponSkill) 
                    then
                        context.weapon_skill = weaponSkill
                        return key
                    end
                else
                    -- writeDebug('Target %s is not in range of weapon skill %s':format(
                    --     text_mob(target.name),
                    --     text_weapon_skill(weaponSkill.name)
                    -- ))
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    --
    context.useWeaponSkill = function (weaponSkill)
        --if weaponSkill == nil then weaponSkill = context.weapon_skill end
        weaponSkill = weaponSkill or context.weapon_skill
        if type(weaponSkill) == 'string' then weaponSkill = findWeaponSkill(weaponSkill) end

        if 
            type(weaponSkill) == 'table' and
            type(weaponSkill.prefix) == 'string' and
            type(weaponSkill.name) == 'string' and
            type(weaponSkill.targets) ~= nil
        then
            
            local waitTime = 3.0
            local command = string.format('input %s "%s" <%s>',
                weaponSkill.prefix,
                weaponSkill.name,
                weaponSkill.targets.Self and 'me' or 't'
            )

            writeVerbose('Using weapon skill: %s':format(text_weapon_skill(weaponSkill.name)))

            return sendActionCommand(
                command,
                context,
                waitTime,
                false -- We don't need to stop walking to use weapon skills
            )
        end
    end

    --------------------------------------------------------------------------------------
    --
    context.canUseItem = function(...)
        local items = varargs({...}, context.item and context.item.name)
        if type(items) == 'table' then
            for key, _item in ipairs(items) do
                local item = _item
                
                if type(item) == 'string' then
                    item = findItem(item)
                    if item then
                        -- We first need to verify that the item is usable in general:
                        --  - Make sure we're not asleep
                        --  - Make sure it's not food, or if it is, that we're not already fed
                        --  - It's got a cast time
                        --  - It doesn't have a level requirement -OR- the level requirement is met
                        --  - It doesn't have a job requirement -OR- the job requirement is met
                        --
                        if 
                            not hasBuff(context.player, 'Sleep') and
                            (item.type ~= ITEM_TYPE_FOOD or not hasBuff(context.player, 'Food')) and
                            item.cast_time ~= nil and                            
                            (item.level == nil or context.player.main_job_level >= item.level) and
                            (item.jobs == nil or item.jobs[context.player.main_job_id] == true)
                        then

                            -- NOTE: The 'table' type check is required due to items being moved to the recycle bin turning into numbers
                            local bagItem = tableFirst(windower.ffxi.get_items(0), 
                                function (_i) 
                                    return type(_i) == 'table' and _i.id == item.id 
                                end)

                            if bagItem then
                                local ext = extdata.decode(bagItem)

                                local hasTimer = ext and ext.next_use_time
                                local secondsUntilReuse = 0
                                local secondsUntilActivation = 0
                                local chargesRemaining = 1

                                if ext then
                                    -- Countdown to when it can be equipped and used (ex: 15 minutes on Capacity Ring)
                                    if ext.next_use_time ~= nil then
                                        secondsUntilReuse = ext.next_use_time + 18000 - os.time()
                                    end
                                    
                                    -- Countdown to use once it's been equiped (ex: 5 seconds on Capacity Ring).
                                    -- It will be negative if the item is not equipped.
                                    if ext.activation_time ~= nil then
                                        secondsUntilActivation = ext.activation_time + 18000 - os.time()
                                    end

                                    if ext.charges_remaining ~= nil then
                                        chargesRemaining = ext.charges_remaining
                                    end
                                end

                                -- writeDebug('Item: %s / Reuse in: %.1fs / Equip for: %.1fs / %d charges':format(
                                --     item.name,
                                --     secondsUntilReuse,
                                --     secondsUntilActivation,
                                --     chargesRemaining
                                -- ))

                                -- This is set based on the time remaining until it is usable and the number of charges.
                                -- It doesn't take into account the activation time -- that can be handled separately
                                -- once we know the item can be used once equipped.
                                local canUse = secondsUntilReuse <= 0 and chargesRemaining > 0

                                -- Save the item to the context
                                context.item = {
                                    name = item.name,
                                    item = item,
                                    type = ext and ext.type,
                                    bagItem = bagItem,
                                    secondsUntilReuse = secondsUntilReuse,
                                    secondsUntilActivation = secondsUntilActivation,
                                    chargesRemaining = chargesRemaining,
                                    usable = (ext and ext.usable) or canUse
                                }

                                -- Return if we can use it
                                if canUse then
                                    return key
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    --
    context.useItem = function (target, itemName)
        local item = nil
        local secondsUntilActivation = 0    -- TODO: Figure out how to make this work

        if itemName == nil then
            if context.item == nil then return end

            item = context.item.item
            itemName = context.item.name

            if context.item.secondsUntilReuse <= 0 then
                if context.item.secondsUntilActivation > 0 then
                    writeDebug('Would set secondsUntilActivation=' .. context.item.secondsUntilActivation)
                    --secondsUntilActivation = context.item.secondsUntilActivation
                end
            end
        end

        if type(itemName) == 'table' and itemName.name then
            item = item.item
            itemName = itemName.name
        end

        if item == nil then
            item = findItem(itemName)
            if item == nil then return end
        end

        target = target or context.member
        if type(target) == 'string' then 
            target = context[target] 
        end

        if target == nil then
            target = context.me
        end

        -- Validate the target
        if not hasAnyFlagMatch(target.targets, item.targets) then
            target = context.bt
            if not hasAnyFlagMatch(target.targets, item.targets) then
                writeDebug(string.format(' **A valid target for [%s] could not be identified.', item.name))
                return
            end
        end

        local waitTime = secondsUntilActivation + (item.cast_time or 1) + 1
        
        -- If this item has a 'slots' field, then it's enchanted equipment. We'll need to add an
        -- additional 1.5 seconds to the cast time, just because that's how it seems to work.
        if item.slots ~= nil then
            waitTime = waitTime + 1.5
        end

        local command = string.format('%sinput /item "%s" <%s>;',
            secondsUntilActivation > 0 and string.format('wait %.1f;', secondsUntilActivation) or '',
            itemName,
            target.symbol
        )

        writeVerbose('Using item: %s':format(text_item(itemName)))

        return sendActionCommand(
            command,
            context,
            waitTime,
            true
        )        
    end

    --------------------------------------------------------------------------------------
    -- Remove all items that aren't at most the specified tier
    context.withMaxTier = function (limit, ...)

        -- Allow numbers or roman numerals for the limit
        if type(limit) == 'number' then
            limit = math.max(1, limit)
        elseif type(limit) == 'string' then
            limit = fromRomanNumeral(limit)
        else
            limit = nil
        end

        -- Create a deep copy of the variable arguments
        local items = json.parse(json.stringify(varargs({...})))

        -- If a limit was set, remove all items that do not meet that limit
        if limit then
            for i = #items, 1, -1 do
                if romanNumeralTier(items[i]) > limit then
                    table.remove(items, i)
                end
            end
        end

        return items
    end

    --------------------------------------------------------------------------------------
    -- Remove all items that aren't at least the specified tier
    context.withMinTier = function (limit, ...)

        -- Allow numbers or roman numerals for the limit
        if type(limit) == 'number' then
            limit = math.max(1, limit)
        elseif type(limit) == 'string' then
            limit = fromRomanNumeral(limit)
        else
            limit = nil
        end

        -- Create a deep copy of the variable arguments
        local items = json.parse(json.stringify(varargs({...})))

        -- If a limit was set, remove all items that do not meet that limit
        if limit then
            for i = #items, 1, -1 do
                if romanNumeralTier(items[i]) < limit then
                    table.remove(items, i)
                end
            end
        end

        return items
    end

    --------------------------------------------------------------------------------------
    -- Remove all items that aren't within the specified min and max tier range
    context.withTierRange = function(min, max, ...)
        return context.withMinTier(min, 
            context.withMaxTier(max, varargs({...}))
        )
    end

    --------------------------------------------------------------------------------------
    --
    context.canUseAbility = function (...)
        local abilities = varargs({...}, context.ability and context.ability.name)

        if type(abilities) == 'table' then
            local player = windower.ffxi.get_player()

            for key, _ability in ipairs(abilities) do
                local ability = _ability
                if type(ability) == 'string' then
                    ability = findJobAbility(ability)

                    if ability then
                        context.ability = ability

                        if canUseAbility(player, ability) then
                            return key
                        end
                    end
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    --
    context.useAbility = function (target, ability)
        if ability == nil then ability = context.ability end
        if type(ability) == 'string' then ability = findJobAbility(ability) end
        
        if ability ~= nil then
            -- Bail if the ability cannot be used. 
            -- NOTE: This is the resx canUseAbility function, not the context one.
            if not canUseAbility(nil, ability) then
                return
            end

            target = target or context.member
            if type(target) == 'string' then 
                target = context[target] 
            end

            if target == nil then
                target = context.bt
            end

            if target == nil or not hasAnyFlagMatch(target.targets, ability.targets) then
                target = context.me
                if not hasAnyFlagMatch(target.targets, ability.targets) then
                    writeDebug(' **A valid target for [%s] could not be identified.':format(text_ability(ability.name, Colors.debug)))
                    return
                end
            end

            local waitTime = 1.5
            local stopWalk = false
            if 
                ability.name == 'Sneak Attack' or
                ability.name == 'Trick Attack'
            then
                -- Some abilities have very strict timing requirements
                waitTime = 1.0
                stopWalk = false
            end

            local command = string.format('input %s "%s" <%s>',
                ability.prefix, -- /jobability, /pet
                ability.name,
                target.symbol
            )

            writeVerbose('Using ability: %s':format(text_ability(ability.name)))

            return sendActionCommand(
                command,
                context,
                waitTime,
                stopWalk -- We generally shouldn't need to stop walking to use job abilities...
            )
        end
    end

    --------------------------------------------------------------------------------------
    --
    context.canUseSpell = function (...)
        local spells = varargs({...}, context.spell and context.spell.name)
        if type(spells) == 'table' and #spells > 0 then
            for key, _spell in ipairs(spells) do
                local spell = _spell
                if type(spell) ~= 'nil' then
                    spell = findSpell(spell)
                    if spell then
                        context.spell = spell
                        
                        if canUseSpell(nil, spell) then
                            return key
                        end
                    end
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    --
    context.spellRecast = function (spell)
        if type(spell) == 'string' then
            spell = findSpell(spell)
        end

        if type(spell) == 'table' and type(spell.id) == 'number' then
            local recasts = windower.ffxi.get_spell_recasts()    
            if type(recasts) == 'table' then
                local recast = recasts[spell.recast_id or spell.id]
                if type(recast) == 'number' then
                    recast = recast / 60.0
                    writeDebug('Recast for %s is %s':format(
                        text_spell(spell.name, Colors.debug),
                        pluralize('%.1f':format(recast), 'second', 'seconds', Colors.debug)
                    ))
                    return recast
                end
            end
        end

        -- If there's no recast, we'll just return a negative value. This was an invalid spell.
        return -1
    end

    --------------------------------------------------------------------------------------
    -- Uses the specified spell on the specified target
    context.useSpell = function (target, spell, ignoreIncomplete)
        if spell == nil then spell = context.spell end
        if type(spell) == 'string' then spell = findSpell(spell) end
        
        if spell ~= nil then

            -- Bail if we cannot use the spell
            if not canUseSpell(nil, spell) then
                return
            end

            target = target or context.member
            if type(target) == 'string' then 
                target = context[target] 
            end

            if target == nil then
                target = context.bt
            end

            if target == nil then
                target = context.me
            end

            if target ~= nil then
                if not hasAnyFlagMatch(target.targets, spell.targets) then
                     target = context.me
                     if not hasAnyFlagMatch(target.targets, spell.targets) then
                        -- At this point, if we still don't have a target then we're out of targeting options
                        writeDebug(' **A valid target for [%s] could not be identified.':format(text_spell(spell.name, Colors.debug)))
                        return
                    end
                end

                -- NOTE: Spell usage is handled generally via the 'action' event handler
                --writeVerbose('Using spell: %s':format(text_spell(spell.name)))

                -- This is the newer spell casting implementation. As ooposed to the normal
                -- sendActionCommand function, this one performs a sleeping loop that will
                -- detect when spell casting has completed (for any reason) and will exit
                -- sooner. This allows us to spend a little time as possible waiting for
                -- spells to complete (fast cast, interruption, and so on can impact this).

                -- Returns a flag indicating whether the action completed successfully
                return sendSpellCastingCommand(spell, target.symbol, context, ignoreIncomplete)
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Behaves as an aggregate of:
    --
    --      canUseSpell
    --      canUseAbility
    --      canUseItem
    --
    -- Finds the first entry in the list of arguments that results in a positive result
    -- from the above checks, stores that result to the context and returns true. Returns
    -- false and clears the context if no positive checks are found.
    context.canUse = function(...)
        local names = varargs({...}, 
            (context.spell and context.spell.name) or
            (context.ability and context.ability.name) or
            (context.item and context.item.name)
        )

        -- We need to clear out all spells/abilities/items from the context here
        context.spell = nil
        context.ability = nil
        context.item = nil

        -- Now, we get to find the first hit in the set (if any) and return based on that
        if names and #names > 0 then
            for i, name in ipairs(names) do
                if context.canUseSpell(name) or context.canUseAbility(name) or context.canUseItem(name) then
                    return true
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Uses the specified spell, ability, or item, if possible.
    context.use = function(target, name)
        
        -- If a name was provided, we don't know what it is until we check if it can be used. This
        -- will set the appropriate context variable based on that if it succeeds.
        if name then
            if not context.canUse(name) then
                return
            end
        end

        -- If a spell was set, use that
        if context.spell then
            return context.useSpell(target)
        end

        -- If an ability was set, use that
        if context.ability then
            return context.useAbility(target)
        end

        if context.item then
            return context.useItem(target)
        end
    end

    --------------------------------------------------------------------------------------
    -- 
    context.facingEnemy = function (degreesThreshold)
        if degreesThreshold == nil then degreesThreshold = 10 end
        if type(degreesThreshold) ~= 'number' then return end
        if context.bt == nil or context.bt.mob == nil then return end

        degreesThreshold = math.abs(degreesThreshold)

        local angleToEnemy = directionality.facingOffsetAmount(context.bt.mob)
        if type(angleToEnemy) == 'number' then
            return directionality.radToDeg(angleToEnemy) <= degreesThreshold
        end
    end

    --------------------------------------------------------------------------------------
    --
    context.faceEnemy = function ()
        if context.bt == nil or context.bt.mob == nil then return end

        -- Cancel any follow job in progress so it doesn't interfere with our facing action
        local job = smartMove:getJobInfo()
        if job ~= nil then
            smartMove:cancelJob()
        end

        writeVerbose('Facing toward %s target: %s':format(
            text_action(context.actionType, Colors.verbose),
            text_mob(context.bt.name, Colors.verbose)
        ))
        return directionality.faceTarget(context.bt.mob) ~= nil
    end

    --------------------------------------------------------------------------------------
    --
    context.faceAway = function ()
        if context.bt == nil or context.bt.mob == nil then return end

        local angle = directionality.facingOffset(context.bt.mob)
        if type(angle) == 'number' then
            writeVerbose('Turning away from %s target: %s':format(
                text_action(context.actionType, Colors.verbose),
                text_mob(context.bt.name, Colors.verbose)
            ))
            directionality.faceDirection(angle + math.pi)

            context.wait(0.5)
        end
    end

    --------------------------------------------------------------------------------------
    -- Returns true if we're behind the mob and facing it
    context.alignedRear = function ()
        if context.bt then
            if smartMove:atMobRear(context.bt.index) then
                return true
            end
        end
    end

    context.canAlignRear = function ()
        if not context.bt then
            return false
        end

        if not settings.noRearList then
            return false
        end

        return not arrayIndexOfStrI(settings.noRearList, context.bt.name)
    end

    --------------------------------------------------------------------------------------
    -- Set up behind the mob and then face it
    context.alignRear = function (duration, failureDelay)
        if context.bt then
            if context.alignedRear() then
                return true
            end

            -- If this mob is in the list of mobs we can't align behind, then just 
            -- return false immediately. We'll also ensure this action doesn't get
            -- scheduled again for a little bit in that case.
            if not context.canAlignRear() then
                context.postpone(5)
                return false
            end

            if context.bt.distance < 5 then
                duration = math.max(tonumber(duration) or 3, 1)
                failureDelay = math.max(tonumber(failureDelay) or 5, 1)

                writeTrace('Aligning behind %s (%03X) for up to %.1fs':format(context.bt.name, context.bt.index, duration))

                local jobId = smartMove:moveBehindIndex(context.bt.index, duration)
                if jobId then
                    while true do
                        coroutine.sleep(0.5)
                        local job = smartMove:getJobInfo()
                        if job == nil or job.jobId ~= jobId then
                            writeTrace('Alignment of %d ended due to JobId=%d':format(jobId, job and job.jobId or -1))
                            local success = context.alignedRear()
                            if not success then
                                context.postpone(failureDelay)
                            end

                            return success
                        end
                    end
                end
            end
        end
    end

    -------------------------------------------------------------------------------------
    -- Check if the specified target is being followed
    context.following = function(target)
        target = target or context.member or context.bt
        
        if type(target) == 'string' then
            target = windower.ffxi.get_mob_by_target(target) 
        elseif type(target) == 'table' and target.mob then
            target = target.mob
        end

        if
            target == nil
            or type(target.index) ~= 'number' or
            not target.valid_target 
        then
            return
        end

        local jobInfo = smartMove:getJobInfo()
        if jobInfo and jobInfo.follow_index == target.index then
            return true
        end
    end

    --------------------------------------------------------------------------------------
    -- 
    context.follow = function (target, distance)
        target = target or context.member or context.bt

        -- Allow string targets
        if type(target) == 'string' then
            target = windower.ffxi.get_mob_by_target(target) 
        elseif type(target) == 'table' and target.mob then
            target = target.mob
        end

        -- Bail if we don't have a target, or if the target doesn't have a numeric id
        if target == nil or type(target.index) ~= 'number' or not target.valid_target then
            return
        end

        -- -- Issue the follow
        -- local command = makeSelfCommand('follow -index %d':format(target.index))
        -- sendActionCommand(command, context, 0.5)

        -- We can follow if there isn't already a follow in progress, or if the existing
        -- follow is already for the current target
        local jobInfo = smartMove:getJobInfo()
        if jobInfo == nil or jobInfo.follow_index ~= target.index then
            return smartMove:followIndex(target.index, distance or 1.0)
        end
    end

    context.distanceTo = function(x, y)
        if type(x) ~= 'number' or type(y) ~= 'number' then
            return
        end

        local me = windower.ffxi.get_mob_by_target('me')

        local v = V({x, y})
        local vme = V({me.x, me.y})

        return v:subtract(vme):length()
    end

    context.checkPosition = function(x, y)
        local d = context.distanceTo(x, y)
        if type(d) == 'number' then return d < 1 end
    end

    context.move = function(x, y, duration)
        local me = windower.ffxi.get_mob_by_target('me')

        if type(x) == 'number' and type(y) ~= 'number' then y = me.y end
        if type(y) == 'number' and type(x) ~= 'number' then x = me.x end

        if type(x) ~= 'number' or type(y) ~= 'number' then
            return
        end

        local jobId = smartMove:moveTo(x, y)
        if jobId then
            local start = os.time()
            local immediate = (tonumber(duration) or 1) <= 0
            duration = math.max(tonumber(duration) or 10, 3)

            if immediate then
                return true
            end

            while true do
                coroutine.sleep(1.0)

                local now = os.time()
                local job = smartMove:getJobInfo()

                -- If the job is still running and our duration has ellapsed, cancel it
                if 
                    job and
                    job.jobId == jobId and
                    (now - start) >= duration 
                then
                    smartMove:cancelJob(jobId)
                    job = nil
                end

                -- If there's no job, or the job doesn't match ours, we're done
                if 
                    job == nil or
                    job.jobId ~= jobId
                then
                    if context.checkPosition(x, y) then
                        context.log('Movement operation completed successfully.')
                        return true
                    end

                    context.log('The movement operation was not completed successfully.')
                    return
                end
            end
        end

        context.log('The movement operation could not be scheduled.')
    end

    --------------------------------------------------------------------------------------
    -- 
    context.cancelFollow = function ()
        -- local command = makeSelfCommand('follow')
        -- sendActionCommand(command, context, 0.5)
        smartMove:cancelJob()
    end

    --------------------------------------------------------------------------------------
    -- Get the mob we're following, or nil if there is no follow
    context.following = function ()
        -- if context.player and context.player.follow_index then
        --     local mob = windower.ffxi.get_mob_by_index(context.player.follow_index)
        --     if mob and mob.valid_target then
        --         return mob
        --     end
        -- end

        local jobInfo = smartMove:getJobInfo()
        if context.player and jobInfo then
            if jobInfo.follow_index then
                local mob = windower.ffxi.get_mob_by_index(jobInfo.follow_index)
                if mob and mob.valid_target then
                    return mob
                end
            end
        end
    end

    context.findMob = function(identifier, distance, withAggro)
        if distance == nil then distance = 50 end

        if 
            type(distance) == 'number' and
            distance > 0 and
            (type(identifier) == 'number' or type(identifier) == 'string')
        then
            local mobs = windower.ffxi.get_mob_array()
            local distanceSquared = distance * distance
            local isIndex = type(identifier) == 'number'
            local isName = not isIndex
            local nearest = nil

            if isName then identifier = string.lower(identifier) end

            for key, mob in pairs(mobs) do
                if
                    mob.spawn_type == SPAWN_TYPE_MOB and
                    mob.valid_target and
                    mob.hpp > 0 and
                    mob.distance <= distanceSquared
                then
                    if
                        (isIndex and identifier == mob.index) or
                        (isName and identifier == string.lower(mob.name))
                    then
                        if
                            (not withAggro or mob.status == STATUS_ENGAGED) and
                            (nearest == nil or nearest.distance > mob.distance)
                        then
                            nearest = mob
                        end
                    end
                end
            end

            if nearest then
                -- Store actual distance
                nearest.distance = math.sqrt(distance)

                -- Store any managed buffs
                nearest.buffs = actionStateManager:getBuffsForMob(nearest.id)

                writeDebug('Nearest mob match: %s (%s) (distance: %s)':format(
                    text_mob(nearest.name, Colors.debug),
                    text_number('%03X':format(nearest.index), Colors.debug),
                    text_number('%.1f':format(nearest.distance), Colors.debug)
                ))

                context.mob = nearest
                return nearest
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Returns the number of mobs within [distance] of you
    context.mobsInRange = function (distance, withAggro)
        local count = 0

        if type(distance) == 'number' and distance > 0 then
            local mobs = windower.ffxi.get_mob_array()
            local distanceSquared = distance * distance
            
            local nearest = nil

            for key, mob in pairs(mobs) do
                if 
                    mob.spawn_type == SPAWN_TYPE_MOB and
                    mob.valid_target and
                    mob.hpp > 0 and
                    mob.distance <= distanceSquared
                then
                    local hasAggro = mob.status == STATUS_ENGAGED and (
                        mob.claim_id == 0 or
                        context.party1_by_id[mob.claim_id] or
                        context.party1_by_index[mob.target_index or 0]
                    )

                    if 
                        not withAggro or
                        hasAggro
                    then
                        if nearest == nil or mob.distance < nearest.distance then
                            nearest = mob
                        end
                        count = count + 1
                    end
                end
            end
        end

        return count
    end

    -------------------------------------------------------------------------------------
    -- Try to release the specified trust
    context.releaseTrust = function (name)
        name = tostring(name)
        if name then
            name = name:lower()
            for i = 1, 5 do
                local member = context['p' .. i]
                if member and member.is_trust then
                    if tostring(member.name):lower() == name and member.distance <= 5 then
                        -- We need to give aggro a chance to cool down
                        context.wait(2)

                        sendActionCommand(
                            'input /returnfaith "%s"':format(member.name),
                            context)

                        -- There's a 6 second delay before we can reliably use any other actions once releasing
                        -- a trust. Further, there's a roughly 2 second delay before the trust stops reading as
                        -- a member of the party.
                        context.wait(6 + 2)

                        return true
                    end
                end
            end
        end
    end

    -------------------------------------------------------------------------------------
    -- Find a single member in the party, returning the matching context 
    -- party member object.
    context.findInParty = function(name)
        if type(name) ~= 'string' then return end
        name = string.lower(name)
        for i = 0, 5 do
            local symbol = 'p' .. i
            local p = context[symbol]
            if p ~= nil and string.lower(p.name) == name then
                return p
            end
        end
    end

    -------------------------------------------------------------------------------------
    -- Find the best spell name associated with the specified trust party name
    context.trustSpellName = function(partyName)
        if type(partyName) == 'string' then
            local metadata = getTrustSpellMeta(partyName,
                TrustSearchModes.best,
                context.player,
                context.party)

            if metadata then
                local spell = resources.spells[metadata.id]
                if spell then
                    return spell.name
                end
            end
        end

        -- if type(partyName) ~= 'string' then return end

        -- partyName = string.lower(partyName)
        
        -- local player = context.player
        -- local matches = {}
        -- for id, spell in pairs(globals.spells.trust) do
        --     -- Store any matching trust spells that we are able to cast
        --     if 
        --         string.lower(spell.party_name) == partyName and
        --         canUseSpell(player, spell)
        --     then
        --         matches[#matches + 1] = spell
        --     end
        -- end

        -- -- If we've found any matches...
        -- if #matches > 0 then
        --     -- If we found more than one match, we can try to disambiguate them by looking up 
        --     -- trusts already in the party. This makes the assumption that we're calling this
        --     -- to find the spell that was used to call an existing party member trust.
        --     if #matches > 1 then
        --         local p = context.findInParty(partyName)
        --         if p then
        --             for i, spell in ipairs(matches) do
        --                 if 
        --                     p.mob and
        --                     p.mob.models and
        --                     #p.mob.models > 0 and
        --                     type(spell.model) == 'number' and
        --                     spell.model == p.mob.models[1]
        --                 then
        --                     return spell.name
        --                 end
        --             end
        --         end
        --     end

        --     -- If we get here, we'll just return the first result. Either we only found one, or there
        --     -- were multiples without an in-party model reference to be found.
        --     return matches[1].name
        -- end
    end

    -------------------------------------------------------------------------------------
    -- Ensure trusts are present. Finds the first trust in the list that is ready
    -- to be called (not at max trusts, not already summoned, not in a city etc...)
    -- and summons it.
    context.needsTrust = function (...)
        local names = varargs({...})

        if
            names and
            #names > 0 and 
            context.party.party1_count < 6 and
            context.me.is_party_leader
        then
            local player = context.player
            local maxTrusts = getMaxTrusts(player)
            local numTrusts = #context.party1_trusts

            -- If there's still room to call trusts...
            if maxTrusts > numTrusts then
                for i, name in ipairs(names) do
                    local spell = findSpell(name)

                    -- If we've found the spell, it's a Trust spell, the corresponding trust isn't already in the party,
                    -- and the player is able to use the spell, then we've found our target.
                    if 
                        spell and
                        spell.type == 'Trust' and
                        not context.partyByName(spell.party_name) and
                        canUseSpell(player, spell) 
                    then
                        context.spell = spell
                        return context.spell
                    end
                end
            end
        end
    end

    -------------------------------------------------------------------------------------
    -- Calls the trust referenced by the specified spell
    context.callTrust = function(spell)
        if spell == nil then
            spell = context.spell
        elseif type(spell) == 'string' then
            spell = findSpell(spell)
        end

        if type(spell) ~= 'table' or spell.type ~= 'Trust' then
            return
        end

        return context.useSpell(context.me)
    end

    -------------------------------------------------------------------------------------
    -- Find the first party member with one of the specified buffs
    context.partyHasBuff = function (...)
        local names = varargs({...})
        for i, p in ipairs(PARTY_MEMBER_FIELD_NAMES) do
            local member = context[p]
            if member and member.buffs then
                if context.hasBuff(member, names) then
                    return true
                end
            end
        end
    end
    context.partyHasEffect = context.partyHasBuff

    context.hasBuff = function(target, ...)
        local names = varargs({...})
        local strict = target == 'use-strict' or names[1] == 'use-strict'

        -- If the target is a string that exists in the context, we'll use that
        if type(target) == 'string' and context[target] and context[target].buffs then
            target = context[target]
        end
        
        -- If the target is not a table at this point, then we'll use ourself
        if type(target) ~= 'table' then

            -- If the target is a string, it means no target was specified and the first param was 
            -- a buff. Let's add it to the list of buff names we're searching through.
            if type(target) == 'string' then
                table.insert(names, 1, target)
            end

            -- Promote the target to ourself
            target = context.me
        end

        for i = 1, #names do
            local name = names[i]
            local buff = hasBuffInArray(target.buffs, name, strict)
            if buff then
                context.effect = buff
                if target.spawn_type ~= SPAWN_TYPE_MOB then
                    context.member = target
                end
                return buff
            end
        end
    end
    context.hasEffect = context.hasBuff

    --------------------------------------------------------------------------------------
    -- Tries to use the specified action to remove an effect on the target
    context.removeEffect = function(target, effect, with)
        target = target or context.member
        
        if type(target) == 'string' then target = context[target] end
        if type(target) ~= 'table' then return end

        effect = effect or context.effect
        with = with or context.spell or context.ability or context.item

        effect = hasBuffInArray(target.buffs, effect)
        if effect and with then
            if context.canUse(with) then
                context.use(target)
                if target.spawn_type == SPAWN_TYPE_MOB or target.spawn_type == SPAWN_TYPE_TRUST then
                    if context.action.complete then
                        actionStateManager:setMobBuff(target, effect.id, false)
                    end
                end
            end
        end

        context.postpone(2)
    end

    --------------------------------------------------------------------------------------
    -- Determine if the target has the effect triggerd by the specified spell or ability.
    -- If no target is specified, it's assumed to be the player.
    context.hasEffectOf = function(target, ...)
        local names = varargs({...})
        local strict = target == 'use-strict' or names[1] == 'use-strict'

        -- If the target is a string that exists in the context, we'll use that
        if type(target) == 'string' and context[target] and context[target].buffs then
            target = context[target]
        end
        
        -- If the target is not a table at this point, then we'll use ourself
        if type(target) ~= 'table' then

            -- If the target is a string, it means no target was specified and the first param was 
            -- a buff. Let's add it to the list of buff names we're searching through.
            if type(target) == 'string' then
                table.insert(names, 1, target)
            end

            -- Promote the target to ourself
            target = context.me
        end

        for i = 1, #names do
            local name = names[i]

            local spell = findSpell(name)
            local ability = findJobAbility(name)

            local res = spell or ability
            local buffId = res and res.status

            if buffId then
                local buff = hasBuffInArray(target.buffs, buffId, strict)
                if buff then
                    context.effect = buff    
                    return buff
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Cancels a cancellable beneficial buff
    context.cancelBuff = function(...)
        local names = varargs({...})
        local cancelled = false
        for i, name in ipairs(names) do
            local buff = hasBuff(nil, name)
            if buff then
                windower.ffxi.cancel_buff(buff.id)
                cancelled = true
            end
        end

        return cancelled
    end

    --------------------------------------------------------------------------------------
    -- Get the number of finishing moves
    context.finishingMoves = function ()
        return getFinishingMoves(context.player)
    end

    --------------------------------------------------------------------------------------
    -- Returns true if the specified buff is active
    context.skillchaining = function (...)
        local names = varargs({...})

        local sc = context.skillchain
        if sc.name ~= nil and 
            (names[1] == nil or arrayIndexOfStrI(names, sc.name))
        then
            context.skillchain_trigger_time = sc.time

            -- context.log('Party skillchain: %s':format(
            --     text_weapon_skill(sc.name)
            -- ))

            -- Commenting out the below. Why *not* let multple reactions occur to the same SC?

            -- Don't let this action trigger again for the same skillchain
            -- local age = context.time - sc.time
            -- context.delay(MAX_SKILLCHAIN_TIME - age)

            return true
        end
    end

    --------------------------------------------------------------------------------------
    -- Trigger if our enemy is using a TP move
    context.enemyUsingAbility = function (...)
        if context.bt then
            local skills = varargs({...})
            local info = actionStateManager:getMobAbilityInfo(context.bt)
            if info then
                -- We'll match if either no filters were provided, or if the current  ability is in the filter list
                if 
                    skills[1] == nil or
                    arrayIndexOfStrI(skills, info.ability.name) 
                then
                    -- We'll only allow one trigger per single mob ability. TODO: Maybe change this in the future?
                    actionStateManager:clearMobAbility(context.bt)
                    context.enemy_ability = info.ability
                    return info.ability
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Need better understanding. Triggers when a skillchain opening with any of 
    -- the specified skillchain attributes (e.g. what's in the WS description)
    context.____partyOpeningSkillchain = function (...)
        -- if context.bt then
        --     local skillchains = varargs({...})
        --     local info = actionStateManager:getPartyWeaponSkillInfo()
            
        --     if 
        --         info and
        --         info.mob and
        --         info.mob.id == context.bt.id
        --     then
        --         -- We'll match if either no filters were provided, or if the requested skillchain
        --         -- attributes are matched by the triggering weapon skill
        --         if 
        --             skillchains[1] == nil or
        --             arraysIntersectStrI(skillchains, info.skillchains)
        --         then
        --             context.party_weapon_skill = info.skill
        --             context.party_weapon_skill_time = actionStateManager.time

        --             return context.party_weapon_skill
        --         end
        --     end
        -- end
    end

    --------------------------------------------------------------------------------------
    -- Trigger if a party member is using a tp move
    context.partyUsingWeaponSkill = function (...)
        if context.bt then
            local skills = varargs({...})
            local party_weapon_skill = context.party_weapon_skill
            
            if 
                party_weapon_skill and
                party_weapon_skill.mob and
                party_weapon_skill.mob.id == context.bt.id
            then
                -- We'll match if either no filters were provided, or if the requested skillchain
                -- attributes are matched by the triggering weapon skill
                if 
                    skills[1] == nil or
                    arrayIndexOfStrI(skills, party_weapon_skill.name)
                then
                    context.skillchain_trigger_time = party_weapon_skill.time

                    -- Don't let this action trigger again for the same weapon skill
                    local age = context.time - party_weapon_skill.time
                    context.delay(MAX_WEAPON_SKILL_TIME - age)

                    -- context.log('Party weapon skill: %s (delaying %s)':format(
                    --     text_weapon_skill(party_weapon_skill.name, Colors.conrsilk),
                    --     text_number('%.1fs':format(MAX_WEAPON_SKILL_TIME - age))
                    -- ))

                    return party_weapon_skill
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Close a skill chain with the specified weapon skill
    context.closeSkillchain = function (...)
        local weaponSkill = varargs({...})
        if #weaponSkill == 0 then weaponSkill = context.weapon_skill and context.weapon_skill.name end

        if context.canUseWeaponSkill(weaponSkill) then

            writeVerbose('Attempting to close skillchain with: %s':format(
                text_weapon_skill(context.weapon_skill.name, Colors.verbose)
            ))

            -- The skillchain_trigger_time value is by a triggered 'skillchaining' or 'partyUsingWeaponSkill' check.
            -- In either case, we have the possibility of closing a skillchain by following up with a weapon skill.
            if 
                context.skillchain_trigger_time > 0
            then
                -- Calculate the age of our weapon skill, and the corresponding sleep time needed
                -- to ensure we have a chance at creating a skillchain effect
                local age = context.time - context.skillchain_trigger_time
                local sleepTime = math.max(WEAPON_SKILL_DELAY - age, WEAPON_SKILL_DELAY)

                -- If we need to delay for our skillchain, do that now
                if sleepTime > 0 then
                    coroutine.sleep(sleepTime)
                end
            end

            context.useWeaponSkill()

            return true
        end
    end

    --------------------------------------------------------------------------------------
    --
    context.walk = function (direction, time)
        if direction == nil then
            return
        end

        -- If a time is specified, it must be a number
        if time ~= nil then
            time = tonumber(time)
            if time == nil then
                return
            end
        else
            time = 0
        end

        local walkCommand = makeSelfCommand(string.format('walk -direction "%s" -t %d',
            direction,
            time
        ))

        sendActionCommand(walkCommand)
    end

    --------------------------------------------------------------------------------------
    -- Determine if you have a ranged weapon and ammo equipped
    context.canShoot = function()
        if context.t then
            local items     = windower.ffxi.get_items()
            local ammo      = tonumber(items.equipment.ammo or 0)
            local ranged    = tonumber(items.equipment.range or 0)

            return ammo > 0 and ranged > 0
        end

        return false
    end

    --------------------------------------------------------------------------------------
    -- 
    context.shoot = function (duration)
        if context.t then
            return sendRangedAttackCommand(context.t, context)
        end
    end
    context.throw = context.shoot
    context.ra = context.shoot

    --------------------------------------------------------------------------------------
    --
    context.hasTarget = function ()
        return (context.t and context.t.mob) ~= nil
    end

    --------------------------------------------------------------------------------------
    -- Ensure that the current action does not execute again for at least
    -- the given number of seconds
    context.delay = function(s)
        s = math.max(0, tonumber(s) or 0)
        if s > 0 then
            writeDebug('Postponing next action execution by %.1fs':format(s))
            context.action.availableAt = math.max(context.action.availableAt, context.time + s)
        end
    end
    context.postpone = context.delay

    --------------------------------------------------------------------------------------
    -- Stay in the idle state for the given number of seconds
    context.idle = function (s, actionMessage)
        local s = math.max(tonumber(s) or 0, 2)
        
        -- Set the wake time to the new time, or the current wake time -- whichever is later
        actionStateManager.idleWakeTime = math.max(context.time + s, actionStateManager.idleWakeTime)

        -- Don't let this action trigger again until we either wake up, or the time where
        -- the action was going to trigger anway -- whichever is later.
        if context.action then
            -- context.action.availableAt = math.max(
            --     actionStateManager.idleWakeTime,
            --     context.action.availableAt or 0
            -- ) - 1

            if context.actionType ~= 'idle' then
                -- Technically, being called from a non-idle state is kind of a no-op. But...
                context.action.availableAt = math.max(
                    actionStateManager.idleWakeTime,
                    context.action.availableAt or 0
                ) - 1
            else            
                -- Wake up 1 second before the idle wake time so we can re-evaluate
                context.action.availableAt = actionStateManager.idleWakeTime - 1
            end
        end

        local message = 'Idling for ' .. pluralize(s, 'second', 'seconds')
        if actionMessage then
            message = message .. ': ' .. actionMessage
        end

        writeMessage(message)
    end

    --------------------------------------------------------------------------------------
    -- Wake from idle
    context.wake = function ()
        if actionStateManager:isIdleSnoozing() then
            actionStateManager.idleWakeTime = 0
            writeTrace('Waking from idle!')
        end
    end

    --------------------------------------------------------------------------------------
    -- Check if idle
    context.isIdling = function ()
        return actionStateManager:isIdleSnoozing()
    end

    --------------------------------------------------------------------------------------
    -- Check if resting
    context.isResting = function ()
        return context.player.status == STATUS_RESTING
    end

    --------------------------------------------------------------------------------------
    -- Take a knee if not already doing so
    context.rest = function ()
        if not context.isResting() then
            sendActionCommand('input /heal', context, 1)
        end
    end

    --------------------------------------------------------------------------------------
    -- Rise from rest if not already doing so
    context.cancelRest = function ()
        if context.isResting() then
            sendActionCommand('input /heal', context, 1)
        end
    end

    --------------------------------------------------------------------------------------
    -- Count the number of arguments
    context.count = function (...)
        local args = varargs({...})
        if args and args[1] then
            return #args
        end

        return 0
    end

    --------------------------------------------------------------------------------------
    -- Splits an amount of times in seconds by the given number of segments. Essentially
    -- returns (seconds / segments), or 0 if either argument is 0 or invalid. Think of
    -- this as a safe, positive number division operation.
    context.split_time = function (seconds, segments)
        if 
            type(seconds) == 'number' and
            type(segments) == 'number' and
            seconds > 0 and
            segments > 0
        then
            return seconds / segments
        end

        return 0
    end

    --------------------------------------------------------------------------------------
    -- If dead, return to your homepoint
    context.deathWarp = function ()
        if context.player.vitals.hpp > 0 then
            return
        end

        writeMessage(text_red('Alert: Initiating the sequence to send you back to your homepoint on death.'))

        -- Give us a bit of time here
        coroutine.sleep(5)

        -- TODO: See if this reraise handling actually works
        local reraise = hasBuff(context.player, 'Reraise')
        if reraise then
            windower.ffxi.cancel_buff(reraise.id)
            coroutine.sleep(1)
        end

        local commands = {
            'setkey enter down',    
            'wait 0.1',
            'setkey enter up',
            'wait 2',               -- At this point: We've clicked the "Go back to Home Point" button with the countdown
            'setkey left down',
            'wait 0.1',
            'setkey left up',
            'wait 2',               -- At this point, we've selected [Yes] from the [Yes] [No] "Return to home point?" confirmation prompt.
            'setkey enter down',
            'wait 0.1',
            'setkey enter up'       -- At this pint, we've clicked the [Yes] button from the above confirmation prompt. We should be returning to point point.
        }

        local command = table.concat(commands, ';')
        sendActionCommand(command, context, 10)
    end

    --------------------------------------------------------------------------------------
    -- "Static" context properties
    context.constants = context_constants
    context.const = context.constants

    --------------------------------------------------------------------------------------
    -- "Static" context functions
    context.any = context_any
    context.min = context_min
    context.max = context_max
    context.iif = context_iif
    context.bool = context_boolean
    context.noop = context_noop
    context.randomize = context_randomize
    context.send_command = context_send_command
    context.wait = context_wait

    -- Final setup
    setEnumerators(context)

    return context
end

return {
    create = function(actionType, time, target, mobEngagedTime, battleScope)
        return makeActionContext(actionType, time, target, mobEngagedTime, battleScope)
    end
}