local PARTY_MEMBER_FIELD_NAMES = {
    'p0', 'p1', 'p2', 'p3', 'p4', 'p5',         -- Party
}

local ALL_MEMBER_FIELD_NAMES = {
    'p0', 'p1', 'p2', 'p3', 'p4', 'p5',         -- Party
    'a10', 'a11', 'a12', 'a13', 'a14', 'a15',   -- Alliance 1
    'a20', 'a21', 'a22', 'a23', 'a24', 'a25'    -- Alliance 2
}

---------------------------------------------------------------------
-- Job abilities needing special timing due to enhancement of
-- the next attack
local SPECIAL_NEXT_ATTACK_JOB_ABILITIES = {
    'Sneak Attack',
    'Trick Attack',
    'Climactic Flourish',
    'Ternary Flourish',
    'Striking Flourish',
    'Boost',
    "Assassin's Charge"
}

---------------------------------------------------------------------
-- Job abilities that we want to have complete faster than the
-- standard ability time
local FAST_JOB_ABILITIES = {
    'Provoke',
    'Animated Flourish',
    'Chi Blast'
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
-- Gets the full path to a variable under the 'vars' action object. This splits on
-- all the dot (.) characters, and omits the 'vars' parent.
local function get_action_variable_path(s)
    result = {};
    for match in (s..'.'):gmatch('(.-)%.') do
        match = trimString(match)
        if 
            match ~= '' and
            (match ~= 'vars' or #result > 0)
        then
            result[#result + 1] = match
        end
    end
    return result;
end

-----------------------------------------------------------------------------------------
-- Determine if the specified symbol string is something we can handle for
-- direct targeting.
local function is_known_targeting_symbol(symbol)
    return 
        symbol == 't' or
        symbol == 'bt' or
        symbol == 'st' or
        symbol == 'lastst' or
        symbol == 'pet' or
        symbol == 'ft' or
        symbol == 'scan'
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
            writeTrace('Sending command: %s':format(
                text_magenta(command, Colors.trace)
            ))
        end
        
        windower.send_command(command)

        return true
    end
end

-----------------------------------------------------------------------------------------
-- Send multiple commands at once
local function context_send_commands(...)
    local commands = varargs({...})
    local result = ''
    local count = 0
    for i, _command in ipairs(commands) do
        local command = trimString(_command)
        if command ~= '' then
            result = result .. command .. ';'
            count = count + 1
        end
    end

    if count > 0 then
        if settings.verbosity >= VERBOSITY_TRACE then
            writeTrace('Sending %s: %s':format(
                pluralize(count, 'command', 'commands', Colors.trace),
                text_magenta(result, Colors.trace)
            ))
        end
        
        windower.send_command(result)

        return true
    else
        writeMessage('No valid commands were provided.')
    end
end

-----------------------------------------------------------------------------------------
--
local function context_send_text(command, ...)
    if type(command) == 'string' then
        command = ('input ' .. command):format(...)

        if settings.verbosity >= VERBOSITY_TRACE then
            writeTrace('Sending command: %s':format(
                text_magenta(command, Colors.trace)
            ))
        end
        
        windower.send_command(command)

        return true
    end
end

-----------------------------------------------------------------------------------------
--
local function context_key_tap(key, wait)
    if type(key) == 'string' then
        windower.send_command('setkey %s down;  wait 0.2; setkey %s up;':format(key, key))
        coroutine.sleep((tonumber(wait) or 0.2) + 0.2)
    end
end

-----------------------------------------------------------------------------------------
--
local function context_array_length(array)
    if type(array) == 'table' and array[1] then
        return #array
    end

    return 0
end

-----------------------------------------------------------------------------------------
--
local function context_array_merge(...)
    local arrays = {...}
    local result = { }

    if #arrays > 0 and arrays[1] then
        result = { unpack(arrays[1]) }
    end

    for i = 2, #arrays do
        local current = arrays[i]
        if type(current) == 'table' and current[1] then
            -- For arrays, each element will be appended individually
            for j = 1, #current do
                local value = current[j]
                if value ~= nil then
                    arrayAppend(result, value)
                end
            end
        else
            -- For non-arrays, append the element directly (unless nil)
            if current ~= nil then
                arrayAppend(result, current)
            end
        end
    end

    return result
end

-----------------------------------------------------------------------------------------
--
local function context_is_array(array)
    return context_array_length(array) > 0
end

-----------------------------------------------------------------------------------------
-- Determine if an array contains all elements of another array
--  - array:    The array to check.
--  - all:      An second array, of all elements that must be in the first one.
local function context_array_contains_all(array, all)
    if 
        type(array) == 'table' and
        type(all) == 'table' and
        array[1] and
        all[1]
    then
        for i, val in ipairs(array) do
            if not arrayIndexOf(all, val) then
                return false
            end
        end

        return true
    end
end

-----------------------------------------------------------------------------------------
-- Determine if all fields in a table are represented in an array.
--  - array:    The table  to check.
--  - all:      An array of all field names that must be in the first table.
local function context_table_contains_all(array, all)
    if 
        type(array) == 'table' and
        type(all) == 'table'
    then
        for key, val in pairs(array) do
            if not arrayIndexOf(all, key) then
                return false
            end
        end

        return true
    end
end

-----------------------------------------------------------------------------------------
-- Determine if a table contains field names for all elements in an array.
local function context_table_has_all_field_names(table, array)
    if 
        type(table) == 'table' and
        type(array) == 'table' and
        array[1]
    then
        for i, val in pairs(array) do
            if table[val] == nil then
                return false
            end
        end

        return true
    end
end

-----------------------------------------------------------------------------------------
-- Determine if a value is within a min/max range (min inclusive, max exclusive)
local function context_in_range(value, min, max)
    return value >= min and value < max
end



-----------------------------------------------------------------------------------------
--
local function context_is_apex(mob)
    if type(mob) == 'table' then mob = mob.name end
    return type(mob) == 'string' and stringStartsWithI(mob, 'apex ')
end
local function context_is_locus(mob)
    if type(mob) == 'table' then mob = mob.name end
    return type(mob) == 'string' and stringStartsWithI(mob, 'locus ')
end
local function context_is_apex_tier(mob)
    return context_is_apex(mob) or context_is_locus(mob)
end

-----------------------------------------------------------------------------------------
-- Sets an action context variable by name, allowing for dot ('.') syntax. The leading
-- 'vars' name is implicit, and can be either provided or omitted with the same result.
local function context_set_var(name, value)
    local levels = get_action_variable_path(name)

    -- If only one level is necessary, we'll just set it now and be done
    if #levels == 1 then
        actionStateManager.vars[levels[1]] = value
        return value
    end

    local ref = actionStateManager.vars

    -- Go through all levels --except-- the final one that we'll actually set below
    for i = 1, #levels - 1 do
        local level = levels[i]
        local cur = ref[level]
        
        if type(cur) == 'nil' then
            -- If the current level does not exist, we will create it
            ref[level] = { }
            cur = ref[level]            
        elseif type(cur) ~= 'table' then
            -- We will not allow a scalar to be overwritten with a table as part of this
            return nil
        end

        ref = cur
    end

    ref[levels[#levels]] = value
    return value
end

-----------------------------------------------------------------------------------------
-- Gets an action context variable by name, allowing for dot ('.') syntax. The leading
-- 'vars' name is implicit, and can be either provided or omitted with the same result.
local function context_get_var(name)
    local levels = get_action_variable_path(name)

    -- If only one level is necessary, we'll just set it now and be done
    if #levels == 1 then
        return actionStateManager.vars[levels[1]]
    end

    local ref = actionStateManager.vars

    -- Go through all levels to find the final value
    for i = 1, #levels - 1 do
        local level = levels[i]
        local cur = ref[level]

        -- If this is not a table, we've reached the end of the search
        if type(cur) ~= 'table' then
            return nil
        end

        ref = cur
    end

    -- Return the final level
    return ref[levels[#levels]]
end

-----------------------------------------------------------------------------------------
-- Creates or updates a field under the specified variable name.
local function context_set_var_field(name, field, value)
    if 
        type(name) == 'string' and
        type(field) == 'string'
    then
        local val = context_get_var(name)
        if val == nil then
            val = context_set_var(name, {})
        elseif type(val) ~= 'table' then
            return
        end

        val[field] = value
        return value
    end
end

-----------------------------------------------------------------------------------------
-- Gets a field under the specified variable name.
local function context_get_var_field(name, field)
    if 
        type(name) == 'string' and
        type(field) == 'string' 
    then
        local val = context_get_var(name)
        if type(val) == 'table' then
            return val[field]
        end
    end
end

-----------------------------------------------------------------------------------------
-- Increments a numeric variable value by a specified amount, or 1 if no amount is provided.
-- Defaults to 1 if the variable does not exist yet.
local function context_var_increment(name, amount, default)
    local value = context_get_var(name)
    if value == nil then
        value = tonumber(default) or 1
    elseif type(value) == 'number' then
        value = value + (tonumber(amount) or 1)
    else
        return
    end
    return context_set_var(name, value)
end

-----------------------------------------------------------------------------------------
-- Decrements a numeric variable value by a specified amount, or 1 if no amount is provided.
-- Defaults to 0 if the variable does not exist yet.
local function context_var_decrement(name, amount, default)
    return context_var_increment(
        name,
        -1 * (tonumber(amount) or 1),
        0)
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
-- Gets a numeric value, or a default if not a valid number
local function context_number(value, default)
    return tonumber(value) or tonumber(default)
end

-----------------------------------------------------------------------------------------
-- Gets a recast timer value, or a default fallback if not a valid number. The fallback will
-- have a value of 100,000 by default, but it can be overridden with the second argument.
local function context_recastTime(value, default)
    return math.max(
        context_number(value, tonumber(default) or 100000),
        0)
end

-----------------------------------------------------------------------------------------
-- Determine if the specified recast time value represents a "ready" status.
local function context_recastReady(value)
    return context_recastTime(value) <= 0
end

-----------------------------------------------------------------------------------------
--
local function context_noop() 
    return true
end

-----------------------------------------------------------------------------------------
-- Generate a random number.
function context_rand(...)
    return math.random(...)
end

-----------------------------------------------------------------------------------------
-- Return the absolute value of a number
function context_abs(n)
    return math.abs(tonumber(n) or 0)
end

-----------------------------------------------------------------------------------------
-- Randomize the order of elements in an array.
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
function context_wait(s, ...)
    local args = varargs({...})
    local followJob = nil
    if arrayIndexOfStrI(args, 'pause-follow') then
        followJob = smartMove:cancelJob()
    end

    s = math.max(tonumber(s) or 1, 0)
    if settings.verbosity >= VERBOSITY_DEBUG then
        writeDebug('Context waiting for %s':format(pluralize(s, 'second', 'seconds', Colors.debug)))
    end
    coroutine.sleep(s)

    if followJob then
        smartMove:reschedule(followJob)
    end

    return s
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
-- Make an x,y,duration tuple from the given args
context_makeXYDO = function(...)
    local args = {...}

    if type(args[1]) == 'table' then
        -- If it's a table with x,y members, then we're good
        if 
            type(args[1].x) == 'number' and
            type(args[1].y) == 'number' 
        then
            return args[1]
        end
    elseif
        type(args[1]) == 'number' and
        type(args[2]) == 'number'
    then
        return {
            x = args[1],
            y = args[2],
            duration = tonumber(args[3]),
            offset = tonumber(args[4]) or 0
        }
    end

    return
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
                fenv.vars = context.vars

                -- Add all fields for this party member to the context
                -- for field, value in pairs(field) do
                --     if type(value) ~= 'table' then
                --         fenv[field] = value
                --     end
                -- end

                -- Apply the env to the function, and execute it. Return this member if it evaluates successfully.
                setfenv(fn, fenv)

                local result = fn()
                fenv.vars = nil

                if result then
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
        return getNextMemberEnumerator(context, ...) or context.partyAny(expression, ...)
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
        return getNextMemberEnumerator(context, ...) or context.allyAny(expression, ...)
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
    -- Iterate through an array
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
        if 
            enumerator and
            enumerator.data and
            #enumerator.data > 0 
        then
            -- Advance the enumerator
            enumerator.at = enumerator.at + enumerator.step

            -- If the new enumerator is within the array bounds, return that item
            if enumerator.at <= #enumerator.data then
                -- Store the result
                context.result          = enumerator.data[enumerator.at]
                context.results[name]   = context.result
                context.is_new_result   = true

                context.action.enumerators.array_name = name

                return context.result
            end
        end

        -- If we don'thave a valid iterator, go back to the source
        if not results then
            results = varargs({...})
        end

        -- If there are any results, we'll set up a new array enumerator and return the first item
        if #results > 0 then
            context.action.enumerators.array[name] = { name = name, data = results, at = 1, step = 1}
            
            enumerator = context.action.enumerators.array[name]
            
            -- Store the results
            context.result          = enumerator.data[enumerator.at]
            context.results[name]   = context.result
            context.is_new_result   = true

            context.action.enumerators.array_name = name

            return context.result
        end

        -- If we've gotten here, we'll clear the array enumerator
        context.action.enumerators.array[name] = nil
    end

    ---------------------------------------------------------------------------
    -- Cycle through an array, starting over once the end is reached
    context.cycle = function(name, ...)
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
        if 
            enumerator and
            enumerator.data and
            #enumerator.data > 0 
        then
            -- Advance the enumerator
            enumerator.at = enumerator.at + enumerator.step

            -- Loop the enumerator if we've run off the end
            if enumerator.at > #enumerator.data then
                enumerator.at = 1
            end

            -- If the new enumerator is within the array bounds, return that item
            if enumerator.at <= #enumerator.data then
                -- Store the result
                context.result          = enumerator.data[enumerator.at]
                context.results[name]   = context.result
                context.is_new_result      = true

                context.action.enumerators.array_name = name

                return context.result
            end
        end

        -- If we don'thave a valid iterator, go back to the source
        if not results then
            results = varargs({...})
        end

        -- If there are any results, we'll set up a new array enumerator and return the first item
        if #results > 0 then
            context.action.enumerators.array[name] = { name = name, data = results, at = 1, step = 1}
            
            enumerator = context.action.enumerators.array[name]
            
            -- Store the results
            context.result          = enumerator.data[enumerator.at]
            context.results[name]   = context.result
            context.is_new_result      = true

            context.action.enumerators.array_name = name

            return context.result
        end

        -- If we've gotten here, we'll clear the array enumerator
        context.action.enumerators.array[name] = nil
    end

    ---------------------------------------------------------------------------
    -- Same as cycle, but starts at the nearest point
    context.cycleNearest = function(name, ...)
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
        if 
            enumerator and
            enumerator.data and
            #enumerator.data > 0 
        then
            -- Advance the enumerator
            enumerator.at = enumerator.at + enumerator.step

            -- Loop the enumerator if we've run off the end
            if enumerator.at > #enumerator.data then
                enumerator.at = 1
            end

            -- If the new enumerator is within the array bounds, return that item
            if enumerator.at <= #enumerator.data then
                -- Store the result
                context.result          = enumerator.data[enumerator.at]
                context.results[name]   = context.result
                context.is_new_result      = true

                context.action.enumerators.array_name = name

                return context.result
            end
        end

        -- If we don'thave a valid iterator, go back to the source
        if not results then
            results = varargs({...})
        end

        -- If there are any results, we'll set up a new array enumerator and return the first item
        if #results > 0 then
            local start = context.nearestIndex(results) or 1
            context.action.enumerators.array[name] = { name = name, data = results, at = start, step = 1}
            
            enumerator = context.action.enumerators.array[name]
            
            -- Store the results
            context.result          = enumerator.data[enumerator.at]
            context.results[name]   = context.result
            context.is_new_result      = true

            context.action.enumerators.array_name = name

            return context.result
        end

        -- If we've gotten here, we'll clear the array enumerator
        context.action.enumerators.array[name] = nil
    end

    ---------------------------------------------------------------------------
    -- Cycle through an array, starting over once the end is reached
    context.bounce = function(name, ...)
        if name == nil then
            return
        end

        if not context.action.enumerators.array then
            context.action.enumerators.array = { }
        end

        if not context.action.results then
            context.action.results = {}
        end

        local results = nil

        -- If no name was provided and our first entry was an array
        if type(name) == 'table' then
            results = name
            name = 'default'
        end

        -- Start by grabbing the current array enumerator
        local enumerator = context.action.enumerators.array[name]

        -- Enumerator structure:
        --  - name: string
        --  - data: []
        --  - at: number
        --  - step: number

        if 
            enumerator and
            enumerator.data and
            #enumerator.data > 0 
        then
            local count = #enumerator.data 

            if 
                enumerator.at <= 1 and
                enumerator.step == -1
            then
                enumerator.at = 2
                enumerator.step = 1
            elseif 
                enumerator.at >= count and
                enumerator.step == 1
            then
                enumerator.at = count - 1
                enumerator.step = -1
            else
                enumerator.at = enumerator.at + enumerator.step
            end

            -- If the new enumerator is within the array bounds, return that item
            if enumerator.at <= count and enumerator.at >= 1 then
                -- Store the result
                context.result          = enumerator.data[enumerator.at]
                context.results[name]   = context.result
                context.is_new_result   = true

                context.action.enumerators.array_name = name

                return context.result
            end
        end

        -- If we don'thave a valid iterator, go back to the source
        if not results then
            results = varargs({...})
        end

        -- If there are any results, we'll set up a new array enumerator and return the first item
        if #results > 0 then
            context.action.enumerators.array[name] = { name = name, data = results, at = 1, step = 1}
            
            enumerator = context.action.enumerators.array[name]
            
            -- Store the results
            context.result          = enumerator.data[enumerator.at]
            context.results[name]   = context.result
            context.is_new_result      = true

            context.action.enumerators.array_name = name

            return context.result
        end

        -- If we've gotten here, we'll clear the array enumerator
        context.action.enumerators.array[name] = nil
    end

    ---------------------------------------------------------------------------
    -- Same as bounce, but starts from the nearest point
    context.bounceNearest = function(name, ...)
        if name == nil then
            return
        end

        if not context.action.enumerators.array then
            context.action.enumerators.array = { }
        end

        if not context.action.results then
            context.action.results = {}
        end

        local results = nil

        -- If no name was provided and our first entry was an array
        if type(name) == 'table' then
            results = name
            name = 'default'
        end

        -- Start by grabbing the current array enumerator
        local enumerator = context.action.enumerators.array[name]

        -- Enumerator structure:
        --  - name: string
        --  - data: []
        --  - at: number
        --  - step: number

        if 
            enumerator and
            enumerator.data and
            #enumerator.data > 0 
        then
            local count = #enumerator.data 

            if 
                enumerator.at <= 1 and
                enumerator.step == -1
            then
                enumerator.at = 2
                enumerator.step = 1
            elseif 
                enumerator.at >= count and
                enumerator.step == 1
            then
                enumerator.at = count - 1
                enumerator.step = -1
            else
                enumerator.at = enumerator.at + enumerator.step
            end

            -- If the new enumerator is within the array bounds, return that item
            if enumerator.at <= count and enumerator.at >= 1 then
                -- Store the result
                context.result          = enumerator.data[enumerator.at]
                context.results[name]   = context.result
                context.is_new_result   = true

                context.action.enumerators.array_name = name

                return context.result
            end
        end

        -- If we don'thave a valid iterator, go back to the source
        if not results then
            results = varargs({...})
        end

        -- If there are any results, we'll set up a new array enumerator and return the first item
        if #results > 0 then
            local start = context.nearestIndex(results) or 1
            context.action.enumerators.array[name] = { name = name, data = results, at = start, step = 1}
            
            enumerator = context.action.enumerators.array[name]
            
            -- Store the results
            context.result          = enumerator.data[enumerator.at]
            context.results[name]   = context.result
            context.is_new_result      = true

            context.action.enumerators.array_name = name

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
        Ally = symbol.mob.in_alliance,
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

        symbol.skills = player.skills
        symbol.item_level = player.item_level

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
    symbol.is_me = (symbol.id == context.player.id)
    symbol.is_mob = (symbol.mob.spawn_type == SPAWN_TYPE_MOB)
    symbol.x = symbol.mob.x
    symbol.y = symbol.mob.y
    symbol.z = symbol.mob.z
    symbol.heading = symbol.mob.heading
    symbol.valid_target = symbol.mob.valid_target
    symbol.spawn_type = symbol.mob.spawn_type
    symbol.status = symbol.mob.status
    symbol.target_index = symbol.mob.target_index

    if symbol.status == STATUS_RESTING then symbol.is_resting = true end
    if symbol.status == STATUS_ENGAGED then symbol.is_engaged = true end
    if symbol.status == 4 then symbol.is_cutscene = true end
    if symbol.status == 2 or symbol.status == 3 then symbol.is_dead = true end
    if symbol.status == 85 or symbol.status == 5 then symbol.is_mounted = true end
    if symbol.status == STATUS_IDLE then symbol.is_idle = true end
    if symbol.status == 44 then symbol.is_crafting = true end
    if symbol.is_idle or symbol.is_engaged or symbol.is_mounted or symbol.is_resting then symbol.can_follow = true end

    if symbol.is_mob then
        -- Set the has_claim flag when someone in the party has claimed the mob
        if tonumber(symbol.mob.claim_id or 0) > 0 and context.party1_by_id[symbol.mob.claim_id] then
            symbol.has_claim = true
        end
    end

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

    -----------------------------------------------------------------
    -- Save the vertical/z distance offset
    if  context.me and context.me.z and symbol.z then
        symbol.offset_z     = symbol.z - context.me.z
        symbol.delta_z      = math.abs(symbol.offset_z)
        symbol.distance_z   = symbol.delta_z
    end

    -----------------------------------------------------------------
    -- Perform a name match on the specified value
    symbol.isNameMatch = function(test)
        if type(test) == 'string' then
            test = string.lower(test or '')
            return 
                test ~= '' and (
                test == string.lower(symbol.name or '') or
                test == string.lower(symbol.symbol or '') or
                test == string.lower(symbol.symbol2 or '')
            )
        end
    end

    -----------------------------------------------------------------
    -- Check for buffs
    symbol.hasBuff = function(buffs)
        return context.hasBuff(symbol, buffs)
    end
    symbol.hasEffect = symbol.hasBuff
end

-----------------------------------------------------------------------------------------
--
local function loadContextTargetSymbols(context, target)
    -- Fill in all symbols

    -- Set up the "me" symbol
    context.me = { symbol = 'me', mob = windower.ffxi.get_mob_by_target('me') }
    initContextTargetSymbol(context, context.me)
    context.self = context.me
    
    -- Set up the t/bt symbols
    if type(target) == 'table' then
        context.t = { 
            symbol = 't',
            symbol2 = 'bt',
            mob = target,
            is_apex = context_is_apex(target.name),
            is_locus = context_is_locus(target.name),
            is_apex_tier = context_is_apex_tier(target.name)
        }
        initContextTargetSymbol(context, context.t)
        context.bt = context.t
    else
        context.t = nil
        context.bt = nil
    end

    -- Set up the pet symbol
    local pet = windower.ffxi.get_mob_by_target('pet')
    if pet then
        context.pet = { symbol = 'pet', mob = pet }
        initContextTargetSymbol(context, context.pet)
    else
        context.pet = nil
    end

    -- Set up the scan symbol
    local scan = windower.ffxi.get_mob_by_target('scan')
    if scan then
        context.scan = { symbol = 'scan', mob = scan }
        initContextTargetSymbol(context, context.scan)
    else
        context.scan = nil
    end

    -- We'll store the list of trusts in our main party. Trusts can't be called in 
    -- an alliance, so this is all we need.
    context.party1_trusts = {}
    context.pinfo = {}

    local cpi = actionStateManager:getCapacityPointInfo()
    context.jobPoints = tonumber(cpi and cpi.jobPoints) or 0

    local mpi = actionStateManager:getMeritPointInfo()
    context.meritPoints = tonumber(mpi and mpi.current) or 0

    for i = 0, 5 do
        local p = 'p' .. i
        local a1 = 'a1' .. i
        local a2 = 'a2' .. i

        context[p] = nil
        if context.party[p] and context.party[p].mob then
            local mob = context.party[p].mob
            context[p] = { symbol = p, mob = mob, member = context.party[p], targets = {}, in_party = true, in_alliance = true }
            initContextTargetSymbol(context, context[p])

            context.party1_by_id[mob.id] = context[p]
            context.party1_by_index[mob.index] = context[p]

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

            -- Save an array of members by name
            context.pinfo[mob.name] = context[p]
        end

        context[a1] = nil
        if context.party[a1] then
            local mob = context.party[a1].mob
            context[a1] = { symbol = a1, mob = mob, member = context.party[a1], targets = {}, in_party = false, in_alliance = true }
            initContextTargetSymbol(context, context[a1])
        end

        context[a2] = nil
        if context.party[a2] then
            local mob = context.party[a2].mob
            context[a2] = { symbol = a2, mob = mob, member = context.party[a2], targets = {}, in_party = false, in_alliance = true }
            initContextTargetSymbol(context, context[a2])
        end
    end

    context.party1_count = (context.party and tonumber(context.party.party1_count)) or 1
    context.party_count = context.party1_count
    context.pinfo.count = context.party_count

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

    -- Set up an easy way to identify the party leader's target and battle target
    local leader = context.party_leader
    if leader and leader.valid_target and leader.target_index and leader.target_index > 0 then
        --print('leader2: %s':format(leader and leader.name or 'nil'))
        local leader_t = windower.ffxi.get_mob_by_index(leader.target_index)
        context.party_leader_t = leader_t
        if leader_t and leader_t.valid_target then
            leader_t.distance = math.sqrt(leader_t.distance)
            leader_t.buffs = 
                leader_t.spawn_type == SPAWN_TYPE_PLAYER and
                    actionStateManager:getMemberBuffsFor(leader_t) or
                    actionStateManager:getBuffsForMob(leader_t)
            if leader.is_engaged then            
                if leader_t.claim_id and leader_t.claim_id > 0 and context.party1_by_id[leader_t.claim_id] then
                    context.party_leader_bt = leader_t
                end
            end
        end
    end
end

-----------------------------------------------------------------------------------------
--
local function makeActionContext(actionType, time, target, mobEngagedTime, battleScope, party)
    local context = {
        actionType = actionType,
        time = time,
        game_info = windower.ffxi.get_info(),
        strategy = settings.strategy,
        mobTime = mobEngagedTime or 0,
        battleScope = battleScope,
        skillchain = actionStateManager:getSkillchain(target),
        party_weapon_skill = actionStateManager:getPartyWeaponSkillInfo(target),
        vars = actionStateManager.vars,
    }

    context.skillchain_trigger_time = 
        (context.skillchain and context.skillchain.time) or 
        (context.party_weapon_skill and context.party_weapon_skill.time) or
        0

    context.target = target
    context.player = windower.ffxi.get_player()
    context.party = party or windower.ffxi.get_party() or {}

    context.game_time = { hour = 0, minute = 0, day = 0 }
    if context.game_info then
        ------------------------------------
        -- Time info
        if context.game_info.time then
            -- game_info.time is the number of game minutes since Vanadiel midnight
            context.game_time.hour = math.floor(context.game_info.time / 60)
            context.game_time.minute = context.game_info.time % 60

            -- game_info.day is the id of the current day, from 0-7:
            --  Firesday, Earthsday, Watersday, Windsday, Iceday, Lightningday, Lightsday, Darksday
            local day = resources.days[context.game_info.day]
            context.game_time.day = day.id
            context.game_time.day_name = day.name
            context.game_time.day_element = day.element
            context.game_time.yesterday = (day.id - 1) % 8
            context.game_time.tomorrow = (day.id + 1) % 8
        end

        ------------------------------------
        -- Zone info
        context.zone_id = context.game_info.zone
        context.zone = context.zone_id and resources.zones[context.zone_id] or nil

        ------------------------------------
        -- Weather info
        context.weather_id = context.game_info.weather
        context.weather = context.weather_id and resources.weather[context.weather_id]
        context.weather_element = context.weather and context.weather.element and resources.elements[context.weather.element] and resources.elements[context.weather.element].name

        ------------------------------------
        -- Moon info
        context.moon_phase_id = context.game_info.moon_phase
        context.moon_phase = context.moon_phase_id and resources.moon_phases[context.moon_phase_id]
    end

    -- Store a mapping of id->member and index->member for the party
    context.party1_by_id = {}
    context.party1_by_index = {}
    -- if context.party then
    --     for i = 0, 5 do
    --         local key = 'p' .. i
    --         local member = context.party[key]
    --         if member and member.mob then
    --             context.party1_by_id[member.mob.id] = member
    --             context.party1_by_index[member.mob.index] = member
    --         end
    --     end
    -- end

    -- Must be called after the player and party have been assigned
    loadContextTargetSymbols(context, target)    

    --------------------------------------------------------------------------------------
    -- Writes a concatenation of all arguments to the action log
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

        return true
    end

    --------------------------------------------------------------------------------------
    -- Writes each argument to the log as a separate line item
    context.logEach = function(...)
        local logs = varargs({...})
        for i, _log in ipairs(logs) do
            local log = trimString(_log)
            if log ~= '' then
                context.log('  ' .. log)
            end
        end
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

            return true
        end
    end

    --------------------------------------------------------------------------------------
    --
    context.equip = function(slot, name)
        if type(slot) == 'table' then
            name = slot.name
            slot = slot.slot
        end

        -- Get the item name
        if name == nil then
            if context.item == nil then return end            
            name = context.item.name

            if name == nil then
                return
            end
        end

        -- Get the item slot
        if slot == nil then
            if context.item then
                slot = context.item.slot
            end
            if slot == nil then
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
            0.1
        )

        return true
    end

    context.equipMany = function(...)
        local entries = varargs({...})

        if #entries == 0 then return end

        if type(entries[1]) == 'string' then
            local _entries = {}
            for i = 1, #entries, 2 do 
                local slot = entries[i]
                local equipment = entries[i + 1]

                if slot and equipment then
                    arrayAppend(_entries, {equipment = equipment, slot = slot })
                end
            end
            entries = _entries
        end
        
        if type(entries[1]) == 'table' then
            local count = inventory.equip_many(entries)
            if count > 0 then
                writeVerbose('Equipped: %s':format(
                    pluralize(count, 'gear item', 'gear items', Colors.verbose)
                ))
            end
        end
    end

    context.equipMany_OLD = function(...)
        local entries = varargs({...})

        if #entries == 0 then return end

        local count = 0
        local commands = {}

        if type(entries[1]) == 'string' then
            for i = 1, #entries, 2 do 
                local slot = entries[i]
                local equipment = entries[i + 1]

                if slot and equipment then
                    if context.findUnequippedItem(equipment) then
                        arrayAppend(commands, 'input /equip %s "%s"':format(slot, equipment))
                        count = count + 1
                    end
                end
            end
        elseif type(entries[1]) == 'table' then
            for i, entry in ipairs(entries) do
                if type(entry) == 'table' then
                    local slot = entry.slot
                    local equipment = entry.equipment or entry.item or entry.gear

                    if slot and equipment then
                        if context.findUnequippedItem(equipment) then
                            arrayAppend(commands, 'input /equip %s "%s"':format(slot, equipment))
                            count = count + 1
                        end
                    end
                end
            end
        end

        if count > 0 then
            writeVerbose('Equipping: %s':format(
                pluralize(count, 'gear item', 'gear items', Colors.verbose)
            ))

            sendActionCommand(
                table.concat(commands, ';'),
                context,
                0.0
            )

            return true
        end
    end

    context.stopFunction = function()
        if context.action and context.action._running then
            context.action._fn_exiting = true
            return true
        end
    end
    context.stopFunc = context.stopFunction

    --------------------------------------------------------------------------------------
    --
    context.canUseWeaponSkill = function (...)
        local weaponSkills = varargs({...})
        local abilities = windower.ffxi.get_abilities()

        for key, _weaponSkill in ipairs(weaponSkills) do
            weaponSkill = findWeaponSkill(_weaponSkill)
            if weaponSkill then
                local target    = weaponSkill.targets.Self and context.me or context.bt
                local suppress  = context.vars.__suppress_weapon_skills and target == context.bt

                if not suppress then
                    local targetOutOfRange = target and
                        target.distance and
                        target.distance > math.max(weaponSkill.range, 6)

                    if not targetOutOfRange then
                        if canUseWeaponSkill(
                            context.player,
                            weaponSkill,
                            abilities) 
                        then
                            context.weapon_skill = weaponSkill
                            return key
                        end
                    end
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Given a list of spells, find the usable subset
    context.usableSpells = function (...)
        local spells = varargs({...})
        local results = {}

        local known_spells = windower.ffxi.get_spells()
        local recasts = windower.ffxi.get_spell_recasts()
        local player = windower.ffxi.get_player()

        for key, _spell in ipairs(spells) do
            spell = findSpell(_spell)
            if canUseSpell(player, spell, recasts, known_spells) ~= nil then
                arrayAppend(results, spell.name)
            end
        end

        return results
    end

    --------------------------------------------------------------------------------------
    -- Given a list of weapon skills, find the usable subset
    context.usableWeaponSkills = function (...)
        local weaponSkills = varargs({...})
        local abilities = windower.ffxi.get_abilities()
        local results = {}

        for key, _weaponSkill in ipairs(weaponSkills) do
            weaponSkill = findWeaponSkill(_weaponSkill)
            if isUsableWeaponSkill(
                weaponSkill,
                abilities) 
            then
                arrayAppend(results, weaponSkill.name)
            end
        end

        return results
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

            local target = weaponSkill.targets.Self and context.me or context.bt
            if type(weaponSkill.range) == 'number' and type(target.model_size) == 'number' then
                if target and target.distance > ((2 * weaponSkill.range) + target.model_size) then
                    writeVerbose('WARNING: Target is out of weapon skill range. Continuing, but consider skipping.')
                    -- return
                end
            end

            --writeVerbose('Using weapon skill: %s':format(text_weapon_skill(weaponSkill.name)))

            return sendActionCommand(
                command,
                context,
                waitTime,
                false -- We don't need to stop walking to use weapon skills
            )
        end
    end

    --------------------------------------------------------------------------------------
    -- Find items in any of your bags
    context.findItem = function(item)
        context.item = inventory.find_item(item)
        return context.item
    end

    --------------------------------------------------------------------------------------
    -- Find usable items in any of your bags
    context.findUsableItem = function(item)
        context.item = inventory.find_item(item, { usable = true })
        return context.item
    end

    -- Find the item equipped in the specified slot
    context.findEquipmentInSlot = function(slot)
        context.item = inventory.find_equipment_in_slot(slot)
        return context.item
    end

    --------------------------------------------------------------------------------------
    -- Determine if all of the specified items are in the inventory. The argument list
    -- is the names of all items to check, with each item optionally followed by
    -- a number representing how many are required. If no number is specified, the
    -- count is assumed to be one (1).
    context.findItemsInInventory = function (...)
        local args = varargs({...})
        local num_missed = 0
        local num_hit = 0

        local flags = {
            usable = true,
            inventory = true
        }

        local items = windower.ffxi.get_items()

        local i = 1
        local count = #args
        local verbose = not arrayIndexOfStrI(args, '-silent')
        local last_result = nil

        while i <= count do
            local item = args[i]

            if item == '-silent' then
                verbose = false  -- This should already be set
            else
                if type(item) == 'string' then
                    -- If we actually got a count, skip past it the next time
                    local count = tonumber(args[i + 1])
                    if count then
                        i = i + 1
                    else
                        count = 1
                    end

                    local result = inventory.find_item(item, flags, items)
                    if result and result.count >= count then
                        num_hit = num_hit + 1
                        last_result = result
                    else
                        if verbose then
                            context.log('Item was not found in inventory: %s%s':format(
                                text_item(item, Colors.cornsilk),
                                count > 1 and text_number(' x%d':format(count), Colors.cornsilk) or ''
                            ))
                        end
                        num_missed = num_missed + 1
                    end
                else
                    num_missed = num_missed + 1
                end
            end

            i = i + 1
        end

        context.item = last_result

        -- writeMessage('num_hit: %d, num_missed: %d':format(num_hit, num_missed))

        return num_hit > 0 and num_missed == 0
    end

    --------------------------------------------------------------------------------------
    -- 
    context.freeInventorySlots = function()
        -- safe: {
        --     1: {
        --         count: int,
        --         status: int,
        --         id: int,
        --         slot: int,
        --         bazaar: int,
        --         extdata: string,
        --     },
        --     2: {...},
        --     ...
        -- }
        -- locker: {...}
        -- sack: {...}
        -- case: {...}
        -- satchel: {...}
        -- inventory: {...}
        -- storage: {...}
        -- temporary: {...}
        -- wardrobe: {...}
        -- treasure: {...}
        -- gil: int

        local bag_info = windower.ffxi.get_bag_info()
        --writeJsonToFile('./data/get_bag_info.json', bag_info)

        if bag_info and bag_info.inventory then
            return bag_info.inventory.max - bag_info.inventory.count
        end

        return 0
        
    end

    --------------------------------------------------------------------------------------
    -- Determine if an item is in the specified slot. Optionally require a strict
    -- match, which looks at the specific item instance. Strict matches are only
    -- available when a context item was set with all the appropriate metadata.
    context.isEquipmentInSlot = function(slot, item, strict, all_items)
        if item == nil then
            item = context.item
        elseif type(item) == 'string' then
            item = findItem(item)
        end

        if type(item) ~= 'table' then return end

        slot = slot or (item and item.slot)
        if slot == nil then return end

        strict = strict and item and item.bagId and item.localId

        if type(all_items) ~= 'table' or type(all_items.equipment) ~= 'table' then
            all_items = windower.ffxi.get_items()
        end

        local itemInSlot = inventory.find_equipment_in_slot(slot, all_items)
        if itemInSlot then
            local match = item.id == itemInSlot.id

            -- When strict, we'll need to match up all the id's rather than just the underlying item id
            if strict and match then
                match =
                    item.bagId == itemInSlot.bagId and
                    item.localId == itemInSlot.localId
            end

            if match then
                context.item = itemInSlot
                return context.item
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Find equippable items in any of your bags
    context.findEquippableItem = function(...)
        local items = varargs({...})
        context.item = nil
        if #items > 0 then
            local all_items = windower.ffxi.get_items()
            for key, item in ipairs(items) do
                context.item = inventory.find_item(
                    item,
                    { equippable = true },
                    all_items
                )

                if context.item then
                    return context.item
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Find the first equippable item from the list that is NOT currently equipped
    context.findUnequippedItem = function(...)
        local items = varargs({...})
        context.item = nil

        if #items > 0 then
            local flags = { equippable = true, equipped = false }
            local all_items = windower.ffxi.get_items()
            for key, item in ipairs(items) do
                local item = inventory.find_item(
                    item,
                    flags,
                    all_items)

                if item then
                    if not context.isEquipmentInSlot(item.slot, item, true, all_items) then
                        context.item = item
                        return context.item
                    end
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Find the first equippable item from the list that is NOT currently equipped.
    -- Uses a strict match (excact item match required)
    context.findUnequippedItemStrict = function(...)
        local items = varargs({...})
        context.item = nil

        if #items > 0 then
            local flags = { equippable = true, equipped = false }
            local all_items = windower.ffxi.get_items()
            for key, item in ipairs(items) do
                local item = inventory.find_item(item,
                    flags,
                    all_items)

                if item then
                    if not context.isEquipmentInSlot(item.slot, item, true, all_items) then
                        context.item = item
                        return context.item
                    end
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Get information about the ranged gear you have equipped
    context.canRangedAttack = function()
        local info = inventory.get_ranged_equipment()
        context.ranged = info

        return info and info.valid
    end
    context.canRA = context.canRangedAttack

    --------------------------------------------------------------------------------------
    --
    context.canUseItem = function(...)

        if hasBuff(context.player, 'Sleep') then
            return
        end

        local items = varargs({...}, context.item and context.item.name)
        if type(items) == 'table' then
            for key, _item in ipairs(items) do
                local info = inventory.find_item(_item, { usable = true })   
                if info then
                    local item = info.item
                    --writeJsonToFile('./data/%s.info.json':format(_item), info)
                    if 
                        (item.level == nil or context.player.main_job_level >= item.level) and
                        (item.jobs == nil or item.jobs[context.player.main_job_id] == true)
                    then
                        context.item = info
                        return key
                    end
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    --
    context.useItem = function (target, itemName)
        local bypass_target_check = false
        if is_known_targeting_symbol(target) then 
            local t = windower.ffxi.get_mob_by_target(target)
            if t == nil then
                return
            end

            t.symbol = target
            target = t
            bypass_target_check = true
        end
        
        local item = nil
        local secondsUntilActivation = 0    -- TODO: Figure out how to make this work

        if itemName == nil then
            if context.item == nil then return end

            item = context.item.item
            itemName = context.item.name

            if type(context.item.secondsUntilReuse) == 'number' then
                if context.item.secondsUntilReuse <= 0 then
                    if context.item.secondsUntilActivation > 0 then
                        writeDebug('Would set secondsUntilActivation=' .. context.item.secondsUntilActivation)
                        --secondsUntilActivation = context.item.secondsUntilActivation
                    end
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
        if not bypass_target_check then
            if not hasAnyFlagMatch(target.targets, item.targets) then
                target = context.bt
                if not hasAnyFlagMatch(target.targets, item.targets) then
                    writeDebug(string.format(' **A valid target for [%s] could not be identified.', item.name))
                    return
                end
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
    -- Get the spell tier from a roman numeral-based spell name
    context.spellTierFromName = function(spell)
        if type(spell) == 'table' then
            spell = spell.name
        end

        if type(spell) ~= 'string' then
            return 1
        end

        return romanNumeralTier(spell)
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
    -- Get the recast timer (in seconds) for the specified ability
    context.abilityRecast = function(...)
        local abilities = varargs({...}, context.ability and context.ability.name)

        if type(abilities) == 'table' then
            local player = windower.ffxi.get_player()
            local recasts = windower.ffxi.get_ability_recasts()

            for key, _ability in ipairs(abilities) do
                local ability = _ability
                if type(ability) ~= 'nil' then
                    ability = findJobAbility(ability)

                    if ability and type(ability.recast_id) == 'number' then
                        local usable, recast = canUseAbility(player, ability, recasts)
                        
                        if type(recast) == 'number' then
                            context.ability = ability
                            context.ability_recast = recast

                            return recast
                        end
                    end
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Determine if the specified spell is available
    context.hasAbility = function(...)
        return context.abilityRecast(...) ~= nil
    end

    --------------------------------------------------------------------------------------
    --
    context.canUseAbility = function (...)
        local abilities = varargs({...}, context.ability and context.ability.name)

        if type(abilities) == 'table' then
            local player = windower.ffxi.get_player()
            local recasts = windower.ffxi.get_ability_recasts()

            context.ability = nil
            context.ability_recast = nil

            for key, _ability in ipairs(abilities) do
                local ability = _ability
                if type(ability) ~= 'nil' then
                    ability = findJobAbility(ability)

                    if ability then
                        local canUse, recast = canUseAbility(player, ability, recasts)

                        context.ability = ability
                        context.ability_recast = recast

                        if canUse then
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
        local bypass_target_check = false
        if is_known_targeting_symbol(target) then 
            local t = windower.ffxi.get_mob_by_target(target)
            if t == nil then
                return
            end

            t.symbol = target
            target = t
            bypass_target_check = true
        end

        if ability == nil then
            ability = context.ability
        end
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

            if not bypass_target_check then
                if target == nil or not hasAnyFlagMatch(target.targets, ability.targets) then
                    target = context.me
                    if not hasAnyFlagMatch(target.targets, ability.targets) then
                        writeDebug(' **A valid target for [%s] could not be identified.':format(text_ability(ability.name, Colors.debug)))
                        return
                    end
                end
            end

            local waitTime = 1.5
            local stopWalk = false
            if 
                SPECIAL_NEXT_ATTACK_JOB_ABILITIES[ability.name] 
            then
                waitTime = 2.0
                stopWalk = false
            elseif 
                FAST_JOB_ABILITIES[ability.name]
            then
                waitTime = 0.5
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
    -- Get the recast timer (in seconds) for the specified spell
    context.spellRecast = function(...)
        local spells = varargs({...}, context.spell and context.spell.name)

        if type(spells) == 'table' then
            local player = windower.ffxi.get_player()
            local recasts = windower.ffxi.get_spell_recasts()

            for key, _spell in ipairs(spells) do
                local spell = _spell
                if type(spell) ~= 'nil' then
                    spell = findSpell(spell)

                    if spell and type(spell.recast_id) == 'number' then
                        local usable, recast = canUseSpell(player, spell, recasts)
                        if type(recast) == 'number' then
                            context.spell = spell
                            context.spell_recast = recast

                            return recast
                        end
                    end
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Get the recast timer (in seconds) for the specified spell, or zero if there is none
    context.spellRecastOrZero = function(...)
        return context.spellRecast(...) or 0
    end

    --------------------------------------------------------------------------------------
    -- Determine if the specified spell is available
    context.hasSpell = function(...)
        return context.spellRecast(...) ~= nil
    end

    --------------------------------------------------------------------------------------
    --
    context.canUseSpell = function (...)
        local spells = varargs({...}, context.spell and context.spell.name)
        if type(spells) == 'table' and #spells > 0 then
            local player = windower.ffxi.get_player()
            local recasts = windower.ffxi.get_spell_recasts()

            context.spell = nil
            context.spell_recast = nil

            for key, _spell in ipairs(spells) do
                local spell = _spell
                if type(spell) ~= 'nil' then
                    spell = findSpell(spell)
                    if spell then
                        -- We will identify offensive spells as those that can target an enemy but not a player.
                        -- There's a bit of a gray area here, mainly around curative spells cast on undead, but
                        -- this logic should be correct in 99% of cases or more.
                        local suppress = context.vars.__suppress_offensive_magic and
                            spell.targets.Enemy and 
                            not spell.targets.Self and
                            not spell.targets.Party and
                            not spell.targets.Ally

                        if not suppress then
                            local canUse, recast = canUseSpell(player, spell, recasts)

                            context.spell = spell
                            context.spell_recast = recast
                            
                            if canUse then
                                return key
                            end
                        end
                    end
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Uses the specified spell on the specified target
    context.useSpell = function (target, spell, ignoreIncomplete)
        local bypass_target_check = false
        if is_known_targeting_symbol(target) then 
            local t = windower.ffxi.get_mob_by_target(target)
            if t == nil then
                return
            end

            t.symbol = target
            target = t
            bypass_target_check = true
        end


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
                if not bypass_target_check then
                    local original_effect = context.effect
                    if 
                        (
                            target.in_party or
                            (target.targets and target.targets.Party) or
                            (target.mob and target.mob.in_party)
                        ) and
                        spell.targets.Self and
                        (
                            (context.hasBuff('Entrust') and spell.type == 'Geomancy') or
                            (context.hasBuff('Pianissimo') and spell.type == 'BardSong')
                        )
                    then
                        writeMessage('%s detected! %s can be cast on party members.':format(
                            text_buff(effect.name),
                            text_spell(spell.name)
                        ))
                    else
                        if not hasAnyFlagMatch(target.targets, spell.targets) then
                            target = context.me
                            if not hasAnyFlagMatch(target.targets, spell.targets) then
                                -- At this point, if we still don't have a target then we're out of targeting options
                                writeDebug(' **A valid target for [%s] could not be identified.':format(text_spell(spell.name, Colors.debug)))
                                return
                            end
                        end
                    end

                    -- We need to restore the original effect, because the hasBuff call 
                    -- above would have overwritten it
                    context.effect = original_effect
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
            for i, _name in ipairs(names) do
                local name = _name
                if type(name) == 'table' then
                    name = name.name or name
                end

                if 
                    context.canUseSpell(name) or
                    context.canUseAbility(name) or
                    context.canUseItem(name) 
                then
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
        if context.spell and context.canUseSpell(context.spell) then
            return context.useSpell(target)
        end

        -- If an ability was set, use that
        if context.ability and context.canUseAbility(context.ability) then
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

        -- writeVerbose('Facing toward %s target: %s':format(
        --     text_action(context.actionType, Colors.verbose),
        --     text_mob(context.bt.name, Colors.verbose)
        -- ))
        return directionality.faceTarget(context.bt.mob) ~= nil
    end

    --------------------------------------------------------------------------------------
    --
    context.faceAway = function (target)
        target = target or context.bt
        if type(target) == 'string' then target = context[target] end
        if type(target) ~= 'table' or target.id == nil then return end

        -- Cancel any follow job in progress so it doesn't interfere with our facing action
        local job = smartMove:getJobInfo()
        if job ~= nil then
            smartMove:cancelJob()
        end

        -- Unlock from the target so we can face away
        local player = windower.ffxi.get_player()
        if player.target_locked then
            windower.send_command('input /lockon')
            context.wait(0.25)
        end

        if directionality.faceAwayFromTarget(target) then
            --context.wait(0.125)
            return true
        else
            writeMessage('WARNING: Unable to face away from target!')
        end
    end

    --------------------------------------------------------------------------------------
    --
    context.aligned = function(target, angle, distance)
        -- Convert degrees to radians if an angle was provided
        angle = tonumber(angle)
        if type(angle) == 'number' then
            angle = angle * math.pi / 180
        end

        return smartMove:atMobOffset(target, angle, distance)
    end

    --------------------------------------------------------------------------------------
    --
    context.align = function(target, angle, distance, duration, noFace)
        -- Nothing to do if we're already aligned
        if context.aligned(target, angle, distance) then
            return
        end

        -- Convert degrees to radians if an angle was provided
        angle = tonumber(angle)
        if type(angle) == 'number' then
            angle = angle * math.pi / 180
        end

        local position = smartMove:findMobOffset(target, angle, distance)
        local success = context.move(
            position[1],
            position[2],
            math.max(tonumber(duration or 3), 1))
        
        if not noFace then
            directionality.faceTarget(target)
        end
        if not success then
            -- TODO: Make this configurable? Parameterized?
            context.postpone(2)
            return false
        end

        return true
    end

    --------------------------------------------------------------------------------------
    -- Returns true if we're behind the mob and facing it
    context.alignedRear = function (target)
        target = target or context.bt
        if target then
            if smartMove:atMobRear(target.index) then
                return true
            end
        end
    end

    context.getMatchingBracketedFaceAwayStart = function(faceaways, abilityName, mobName)
        -- writeMessage('Entering getMatchingBracketedFaceAwayStart with: %s, %s, %s':format(
        --     type(faceaways),
        --     abilityName and abilityName.name or 'n/a',
        --     mobName and mobName.name or 'n/a'
        -- ))

        -- Ensure that we have a valid face away description table
        if type(faceaways) ~= 'table' then return end
        
        -- We can convert mob objects to their name. Then validate that we have something.
        if mobName == nil then mobName = context.bt end
        if type(mobName) == 'table' then mobName = mobName.name end
        if type(mobName) ~= 'string' then return end

        -- We can convert ability objects to their name. Then validate that we have something.
        if type(abilityName) == 'table' then abilityName = abilityName.name end
        if type(abilityName) ~= 'string' then return end

        -- Check the mob-specific rule set
        local entry = faceaways[mobName]
        if type(entry) == 'table' and type(entry.initiators) == 'table' then
            local rules = entry.initiators[abilityName] or entry.initiators["*"]
            if rules ~= nil then
                if type(rules) == 'boolean' then
                    if rules then
                        rules = {}
                    else
                        rules = nil
                    end
                end

                context.ability_face_away_start = rules
                return context.ability_face_away_start
            end
        end

        -- Check the general rule set
        entry = faceaways["*"]
        if type(entry) == 'table' and type(entry.initiators) == 'table' then
            local rules = entry.initiators[abilityName] or entry.initiators["*"]
            if rules ~= nil then
                if type(rules) == 'boolean' then
                    if rules then
                        rules = {}
                    else
                        rules = nil
                    end
                end

                context.ability_face_away_start = rules
                return context.ability_face_away_start
            end
        end
    end

    context.getMatchingBracketedFaceAwayEnd = function(faceaways, abilityName, mobName)
        -- writeMessage('Entering getMatchingBracketedFaceAwayEnd with: %s, %s, %s':format(
        --     type(faceaways),
        --     abilityName and abilityName.name or 'n/a',
        --     mobName and mobName.name or 'n/a'
        -- ))

        -- Ensure that we have a valid face away description table
        if type(faceaways) ~= 'table' then return end
        
        -- We can convert mob objects to their name. Then validate that we have something.
        if mobName == nil then mobName = context.bt end
        if type(mobName) == 'table' then mobName = mobName.name end
        if type(mobName) ~= 'string' then return end

        -- We can convert ability objects to their name. Then validate that we have something.
        if type(abilityName) == 'table' then abilityName = abilityName.name end
        if type(abilityName) ~= 'string' then return end

        -- Check the mob-specific rule set
        local entry = faceaways[mobName]
        if type(entry) == 'table' and type(entry.terminators) == 'table' then
            local rules = entry.terminators[abilityName] or entry.terminators["*"]
            if rules ~= nil then
                if type(rules) == 'boolean' then
                    if rules then
                        rules = {}
                    else
                        rules = nil
                    end
                end

                context.ability_face_away_end = rules
                return context.ability_face_away_end
            end
        end

        -- Check the general rule set
        entry = faceaways["*"]
        if type(entry) == 'table' and type(entry.terminators) == 'table' then
            local rules = entry.terminators[abilityName] or entry.terminators["*"]
            if rules ~= nil then
                if type(rules) == 'boolean' then
                    if rules then
                        rules = {}
                    else
                        rules = nil
                    end
                end

                context.ability_face_away_end = rules
                return context.ability_face_away_end
            end
        end
    end

    context.getMatchingAbilityFaceAway = function(faceaways, abilityName, mobName)
        -- writeMessage('Entering getMatchingAbilityFaceAway with: %s, %s, %s':format(
        --     type(faceaways),
        --     abilityName and abilityName.name or 'n/a',
        --     mobName and mobName.name or 'n/a'
        -- ))

        -- Ensure that we have a valid face away description table
        if type(faceaways) ~= 'table' then return end
        
        -- We can convert mob objects to their name. Then validate that we have something.
        if mobName == nil then mobName = context.bt end
        if type(mobName) == 'table' then mobName = mobName.name end
        if type(mobName) ~= 'string' then return end

        -- We can convert ability objects to their name. Then validate that we have something.
        if type(abilityName) == 'table' then abilityName = abilityName.name end
        if type(abilityName) ~= 'string' then return end

        -- Check the mob-specific rule set
        local entry = faceaways[mobName]
        if type(entry) == 'table' and type(entry.abilities) == 'table' then
            local rules = entry.abilities[abilityName] or entry.abilities["*"]
            if rules ~= nil then
                if type(rules) == 'boolean' then
                    if rules then
                        rules = {}
                    else
                        rules = nil
                    end
                end

                context.ability_face_away = rules
                return context.ability_face_away
            end
        end

        -- Check the general rule set
        entry = faceaways["*"]
        if type(entry) == 'table' and type(entry.abilities) == 'table' then
            local rules = entry.abilities[abilityName] or entry.abilities["*"]
            if rules ~= nil then
                if type(rules) == 'boolean' then
                    if rules then
                        rules = {}
                    else
                        rules = nil
                    end
                end

                context.ability_face_away = rules
                return context.ability_face_away
            end
        end
    end

    context.getMatchingSpellFaceAway = function(faceaways, spellName, mobName)
        -- writeMessage('Entering getMatchingSpellFaceAway with: %s, %s, %s':format(
        --     type(faceaways),
        --     spellName and spellName.name or 'n/a',
        --     mobName and mobName.name or 'n/a'
        -- ))
        
        -- Ensure that we have a valid face away description table
        if type(faceaways) ~= 'table' then return end
        
        -- We can convert mob objects to their name. Then validate that we have something.
        if mobName == nil then mobName = context.bt end
        if type(mobName) == 'table' then mobName = mobName.name end
        if type(mobName) ~= 'string' then return end

        -- We can convert spell objects to their name. Then validate that we have something.
        if type(spellName) == 'table' then spellName = spellName.name end
        if type(spellName) ~= 'string' then return end

        -- Check the mob-specific rule set
        local entry = faceaways[mobName]
        if type(entry) == 'table' and type(entry.spells) == 'table' then
            local rules = entry.spells[spellName] or entry.spells["*"]
            if rules ~= nil then
                if type(rules) == 'boolean' then
                    if rules then
                        rules = {}
                    else
                        rules = nil
                    end
                end

                context.spell_face_away = rules
                return context.spell_face_away
            end
        end

        -- Check the general rule set
        entry = faceaways["*"]
        if type(entry) == 'table' and type(entry.spells) == 'table' then
            local rules = entry.spells[spellName] or entry.spells["*"]
            if rules ~= nil then
                if type(rules) == 'boolean' then
                    if rules then
                        rules = {}
                    else
                        rules = nil
                    end
                end

                context.spell_face_away = rules
                return context.spell_face_away
            end
        end
    end

    --------------------------------------------------------------------------------------
    --Determine if rear alignment on this mob is possible
    context.canAlignRear = function (target)
        target = target or context.bt
        if not target or not target.name then
            return false
        end

        if not settings.noRearList then
            return false
        end

        if context.hasEffect('Bind', 'Sleep', 'Terror', 'Petrification', 'Stun') then
            context.postpone(5)
            return false
        end

        return not arrayIndexOfStrI(settings.noRearList, target.name)
    end
    context.canAlign = context.canAlignRear

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

                if settings.verbosity >= VERBOSITY_TRACE then
                    writeTrace('Aligning behind %s (%03X) for up to %.1fs':format(context.bt.name, context.bt.index, duration))
                end

                local jobId = smartMove:moveBehindIndex(context.bt.index, duration)
                if jobId then
                    while true do
                        coroutine.sleep(0.5)
                        local job = smartMove:getJobInfo()
                        if job == nil or job.jobId ~= jobId then
                            if settings.verbosity >= VERBOSITY_TRACE then
                                writeTrace('Alignment of %d ended due to JobId=%d':format(jobId, job and job.jobId or -1))
                            end
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
    context.following0 = function(target)
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
    -- Get the mob we're following, or nil if there is no follow
    context.following = function (target)
        -- if context.player and context.player.follow_index then
        --     local mob = windower.ffxi.get_mob_by_index(context.player.follow_index)
        --     if mob and mob.valid_target then
        --         return mob
        --     end
        -- end

        if type(target) == 'string' then
            target = windower.ffxi.get_mob_by_target(target)
        end

        if type(target) ~= 'table' or not target.id or not target.index then
            return
        end

        local jobInfo = smartMove:getJobInfo()
        if context.player and jobInfo then
            if jobInfo.follow_index then
                if target.index == jobInfo.follow_index and target.valid_target then
                    return target, jobInfo.jobId
                end
                -- local mob = windower.ffxi.get_mob_by_index(jobInfo.follow_index)
                -- if mob and mob.valid_target then
                --     if target == nil or (target.id == mob.id and target.index == mob.index) then
                --         return mob, jobInfo.jobId
                --     end
                -- end
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- 
    context.follow = function (target, distance)
        target = target or context.member or context.bt

        local _mob, _job_id = context.following(target)
        if _mob and _job_id then
            return _job_id
        end

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
        
        -- Validate the distance value. If no value is provided, or it is invalid,
        -- we will fall back to the follow command distance. If that is not valid,
        -- we will fall back to a default of 1.0.
        if type(distance) ~= 'number' or distance < 0 then
            distance = math.max(tonumber(settings.followCommandDistance) or 1, 1)
        end

        if settings and type(settings.minDistanceList[target.name]) == 'number' then
            distance = math.max(settings.minDistanceList[target.name], distance)
        end

        -- We can follow if there isn't already a follow in progress, or if the existing
        -- follow is already for the current target
        local jobInfo = smartMove:getJobInfo()
        if jobInfo == nil or jobInfo.follow_index ~= target.index then
            return smartMove:followIndex(target.index, distance)
        end
    end

    ---------------------------------------------------------------------------
    -- Returns the parameter representing the furthest point from the player
    context.furthestIndex = function(...)
        local args = varargs({...})
        local me = windower.ffxi.get_mob_by_target('me')
        local vme = V({me.x, me.y})

        local furthestd = math.huge
        local furthesti = nil

        -- Find the nearest entry
        for i, p in ipairs(args) do
            if type(p.distance) == 'number' then
                if p.distance < furthestd then
                    furthestd = p.distance
                    furthesti = i
                end
            else
                local dx = p.x - me.x
                local dy = p.y - me.y
                local d = math.sqrt((dx*dx) + (dy*dy))

                if d < furthestd then
                    furthestd = d
                    furthesti = i
                end
            end
        end

        return furthesti
    end
    context.farthestIndex = context.furthestIndex

    context.furthest = function(...)
        local args = varargs({...})
        local furthesti = context.furthestIndex(args)
        if furthesti then
            context.point = args[furthesti]
            context.furthest_result = context.point
            context.farthest_result = context.point
            return context.point
        end
    end
    context.farthest = context.furthest

    context.nearestIndex = function(...)
        local args = varargs({...})
        local me = windower.ffxi.get_mob_by_target('me')
        local vme = V({me.x, me.y})

        local nearestd = math.huge
        local nearesti = nil

        -- Find the nearest entry
        for i, p in ipairs(args) do
            if type(p.distance) == 'number' then
                if p.distance < nearestd then
                    nearestd = p.distance
                    nearesti = i
                end
            else
                local dx = p.x - me.x
                local dy = p.y - me.y
                local d = math.sqrt((dx*dx) + (dy*dy))

                if d < nearestd then
                    nearestd = d
                    nearesti = i
                end
            end
        end

        return nearesti
    end

    context.nearest = function(...)
        local args = varargs({...})
        local nearesti = context.nearestIndex(args)
        if nearesti then
            context.point = args[nearesti]
            context.nearest_result = context.point
            return context.point
        end
    end

    ---------------------------------------------------------------------------
    --
    context.distanceTo = function(...)
        local pos = context_makeXYDO(...)
        if not pos then return end

        local me = windower.ffxi.get_mob_by_target('me')
        local v = V({pos.x, pos.y})
        local vme = V({me.x, me.y})

        return v:subtract(vme):length()
    end

    ---------------------------------------------------------------------------
    --
    context.checkPosition = function(...)
        local d = context.distanceTo(...)
        --writeVerbose('cp.distance: %.2f':format(d))
        if type(d) == 'number' then return d < 1 end
    end

    ---------------------------------------------------------------------------
    --
    context.move = function(...)
        local pos = context_makeXYDO(...)
        if not pos then return end

        local me = windower.ffxi.get_mob_by_target('me')

        local x = pos.x
        local y = pos.y
        local duration = pos.duration

        if type(pos.offset) == 'number' and pos.offset ~= 0 then
            local vme = V({me.x, me.y})
            local vpos = V({pos.x, pos.y})
            local vto = vpos:subtract(vme)
            local len = vto:length()
            if len ~= pos.offset then
                vto = vto:normalize():scale(len + pos.offset)

                x = me.x + vto[1]
                y = me.y + vto[2]
            end
        end

        -- If there's an existing job that exactly matches the newly requested one,
        -- then let's just let that job continue.
        local existingJob = smartMove:getJobInfo()
        if existingJob then
            if existingJob.mode == 'position' then
                local jp = existingJob.position
                if 
                    jp and
                    jp[1] == pos.x and
                    jp[2] == pos.y
                then
                    return true
                end
            end
        end

        local jobId = smartMove:moveTo(x, y)
        if jobId then
            local immediate = (tonumber(duration) or 0) <= 0
            if immediate then
                return true
            end

            local start = os.time()
            duration = math.max(duration, 0.5)

            coroutine.sleep(0.5)

            while true do
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

                -- If we're already in position, we can stop
                if context.checkPosition(x, y) then
                    -- If the current job is still the one we started, we can cancel that
                    if job and job.jobId == jobId then
                        smartMove:cancelJob(jobId)
                    end
                    --context.log('The movement operation completed successfully.')
                    return true
                end

                -- If there's no job, or the job doesn't match ours, we've finished
                -- before we got into position for some reason (manual follow cancel, etc)
                if 
                    job == nil or
                    job.jobId ~= jobId
                then
                    --context.log('The movement operation was not completed.')
                    return
                end

                coroutine.sleep(0.25)
            end
        end

        --context.log('The movement operation could not be scheduled.')
    end

    --------------------------------------------------------------------------------------
    -- 
    context.cancelFollow = function ()
        -- local command = makeSelfCommand('follow')
        -- sendActionCommand(command, context, 0.5)
        smartMove:cancelJob()
    end

    context.findFieldItem = function(name)
        -- Note:
        --  Emblazoned Reliquary (Blue)
        --      - "spawn_type": 2, "models": [965]
        --  Emblazoned Reliquary (Brown)
        --      - "spawn_type": 2, "models": [966]
        --  Emblazoned Reliquary (Gold)
        --      - "spawn_type": 2, "models": [967]
        return
    end

    --------------------------------------------------------------------------------------
    -- Find a player by name
    context.findPlayer = function(name)
        context.player_result = nil

        if type(name) == 'string' then
            local mobs = windower.ffxi.get_mob_array()
            if mobs then
                name = string.lower(name)
                for key, mob in pairs(mobs) do
                    if mob.spawn_type == SPAWN_TYPE_PLAYER or mob.spawn_type == 1 then
                        if string.lower(mob.name) == name then
                            local _mob = windower.ffxi.get_mob_by_id(mob.id)
                            if _mob and _mob.valid_target then
                                local p = { symbol = _mob.name, mob = _mob }
                                initContextTargetSymbol(context, p)

                                context.player_result = p
                                return context.player_result
                            end
                        end
                    end
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Find a player by name
    context.findByName = function(name)
        context.find_result = nil

        if type(name) == 'string' then
            local mobs = windower.ffxi.get_mob_array()
            if mobs then
                name = string.lower(name)
                for key, mob in pairs(mobs) do
                    if string.lower(mob.name) == name then
                        local _mob = windower.ffxi.get_mob_by_id(mob.id)
                        if _mob and _mob.valid_target then
                            local f = { symbol = _mob.name, mob = _mob }
                            initContextTargetSymbol(context, f)

                            context.find_result = f
                            return context.find_result
                        end
                    end
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

                
                if mob.distance <= distanceSquared then
                    if
                        mob.spawn_type == SPAWN_TYPE_MOB and
                        mob.valid_target and
                        mob.hpp > 0
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
            end

            if nearest then
                -- Store actual distance
                nearest.distance = math.sqrt(distance)

                -- Store any managed buffs
                nearest.buffs = actionStateManager:getBuffsForMob(nearest.id)

                if settings.verbosity >= VERBOSITY_DEBUG then
                    writeDebug('Nearest mob match: %s (%s) (distance: %s)':format(
                        text_mob(nearest.name, Colors.debug),
                        text_number('%03X':format(nearest.index), Colors.debug),
                        text_number('%.1f':format(nearest.distance), Colors.debug)
                    ))
                end

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

    --------------------------------------------------------------------------------------
    -- Returns all mobs with the given name(s) within the specified distance. If the 
    -- first argument is a number, it will be treated as the search radius; otherwise,
    -- a distance value of 50 will be used by default.
    context.findMobs = function(...)
        local count = 0
        local distance = 50
        local names = varargs({...})
        local results = { }
        local start = nil

        if type(names[1]) == 'number' then
            distance = names[1]
            start = 2
        end

        if distance > 0 then
            local mobs = windower.ffxi.get_mob_array()
            local distanceSquared = distance * distance

            for key, mob in pairs(mobs) do
                if 
                    mob.spawn_type == SPAWN_TYPE_MOB and
                    mob.valid_target and
                    mob.hpp > 0 and
                    mob.distance <= distanceSquared
                then
                    if 
                        names[1] == nil or
                        arrayIndexOfStrI(names, mob.name, start) 
                    then
                        mob.buffs = actionStateManager:getBuffsForMob(mob)
                        arrayAppend(results, mob)
                        count = count + 1
                    end
                end
            end
        end

        return count > 0 and results or nil
    end

    --------------------------------------------------------------------------------------
    -- Forces the next battle target to the specified mob (id or object)
    context.setBattleTarget = function(mob)
        if type(mob) == 'table' and mob[1] then mob = mob[1] end
        if type(mob) == 'table' then mob = mob.id end
        if type(mob) == 'number' then
            actionStateManager.user_target_id = mob
            return true
        end
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

    context.hasBuff = function(...)
        local args = {...}

        local start_index = 1
        local target = context.me

        -- Find a target override
        if
            type(args[start_index]) == 'table' and
            type(args[start_index].buffs) == 'table'
        then
            target = args[start_index]
            start_index = start_index + 1
        elseif
            type(args[start_index]) == 'string' and
            type(context[args[start_index]]) == 'table' and
            type(context[args[start_index]].buffs) == 'table'
        then
            target = context[args[start_index]]
            start_index = start_index + 1
        elseif
            args[start_index] == nil
        then
            start_index = start_index + 1
        end

        -- Find a strictness override
        local use_strict = false
        if
            args[start_index] == 'use-strict' or
            args[start_index] == 'not-strict'
        then
            if args[start_index] == 'use-strict' then
                use_strict = true
            end
            start_index = start_index + 1
        end

        local names = args
        if
            type(args[start_index]) == 'table' and
            #args[start_index] > 0
        then
            names = args[start_index]
            start_index = 1
        end

        -- local buffs = target.buffs
        -- if target.id == context.me.id then
        --     local player = windower.ffxi.get_player()
        --     buffs = player.buffs
        -- end

        for i = start_index, #names do
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
    context.hasEffectOf = function(...)
        local args = {...}

        local start_index = 1
        local target = context.me

        -- Find a target override
        if
            type(args[start_index]) == 'table' and
            type(args[start_index].buffs) == 'table'
        then
            target = args[start_index]
            start_index = start_index + 1
        elseif
            type(args[start_index]) == 'string' and
            type(context[args[start_index]]) == 'table' and
            type(context[args[start_index]].buffs) == 'table'
        then
            target = context[args[start_index]]
            start_index = start_index + 1
        elseif
            args[start_index] == nil
        then
            start_index = start_index + 1
        end

        -- Find a strictness override
        local use_strict = false
        if
            args[start_index] == 'use-strict' or
            args[start_index] == 'not-strict'
        then
            if args[start_index] == 'use-strict' then
                use_strict = true
            end
            start_index = start_index + 1
        end

        local names = args
        if
            type(args[start_index]) == 'table' and
            #args[start_index] > 0
        then
            names = args[start_index]
            start_index = 1
        end

        for i = start_index, #names do
            local name = names[i]

            if type(name) == 'table' then
                name = name.name or name
            end

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
    -- Get the number for the specified roll
    context.rollNumber = function (roll)
        local ability = findJobAbility(roll)
        if ability and ability.type == 'CorsairRoll' then
            return actionStateManager:getRollCount(ability.id)
        end

        return 0
    end

    --------------------------------------------------------------------------------------
    -- Get the latest roll
    context.getLatestRoll = function(name)
        local latest = actionStateManager:getLatestRoll()

        if latest ~= nil then
            latest = json.parse(json.stringify(latest))
            if 
                type(latest.name) == 'string' and
                type(name) == 'string'
            then
                -- If we have a roll and a name was provided, match those up
                if latest.name:lower() == name:lower() then
                    context.latestRoll = latest
                end
            else
                context.latestRoll = latest
            end
        end

        return context.latestRoll
    end

    --------------------------------------------------------------------------------------
    -- Clears tracking of the current weapon skill and skillchain info (if any)
    context.resetSkillchain = function()
        actionStateManager:clearSkillchain(context.bt)
        --actionStateManager:setSkillchain(nil, context.bt)
        actionStateManager:clearPartyWeaponSkills()

        context.skillchain = nil
        context.party_weapon_skill = nil
    end

    --------------------------------------------------------------------------------------
    -- Returns true if the specified buff is active
    context.skillchaining = function (...)
        local names = varargs({...})

        local skillchain = context.skillchain
        if
            skillchain and
            skillchain.name ~= nil and 
            (names[1] == nil or arrayIndexOfStrI(names, skillchain.name))
        then
            context.skillchain_trigger_time = skillchain.time
            context.skillchain_age = os.clock() - skillchain.time
            return true
        end
    end

    --------------------------------------------------------------------------------------
    -- Similar to skillchaining, but only triggers if a minimum amount
    -- of time has ellapsed since the weapon skill was used.
    context.skillchaining2 = function(...)
        local result = context.skillchaining(...)
        if result then
            local age = os.clock() - context.skillchain_trigger_time
            if age >= settings.skillchainDelay - 1 then
                return result
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Suppresses offensive magic spells via canUseSpell (and canUse)
    context.suppressOffensiveMagic = function()
        if context and context.vars then
            if type(context.vars.__suppress_offensive_magic) == 'number' then
                context.vars.__suppress_offensive_magic = context.vars.__suppress_offensive_magic + 1
            else
                context.vars.__suppress_offensive_magic = 1
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Cancells suppression of offensive magic spells via canUseSpell (and canUse)
    context.resumeOffensiveMagic = function()
        if context and context.vars then
            if type(context.vars.__suppress_offensive_magic) == 'number' then
                context.vars.__suppress_offensive_magic = context.vars.__suppress_offensive_magic - 1
            end

            if (tonumber(context.vars.__suppress_offensive_magic) or 0) < 1 then
                context.vars.__suppress_offensive_magic = false
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Suppresses weapon skills via canUseWeaponSkill
    context.suppressWeaponSkills = function()
        if context and context.vars then
            if type(context.vars.__suppress_weapon_skills) == 'number' then
                context.vars.__suppress_weapon_skills = context.vars.__suppress_weapon_skills + 1
            else
                context.vars.__suppress_weapon_skills = 1
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Cancells suppression of weapon skills spells via canUseWeaponSkill
    context.resumeWeaponSkills = function()
        if context and context.vars then
            if type(context.vars.__suppress_weapon_skills) == 'number' then
                context.vars.__suppress_weapon_skills = context.vars.__suppress_weapon_skills - 1
            end

            if (tonumber(context.vars.__suppress_offensive_magic) or 0) < 1 then
                context.vars.__suppress_weapon_skills = false
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Trigger if our enemy is in the process of casting a spell
    context.enemyCastingSpell = function (...)
        if context.bt then
            local spells = varargs({...})
            local info = actionStateManager:getOthersSpellInfo(context.bt)
            if info then
                -- We'll match if either no filters were provided, or if the current spell is in the filter list
                if 
                    spells[1] == nil or
                    arrayIndexOf(spells, "*") or
                    arrayIndexOfStrI(spells, info.spell.name) 
                then
                    context.enemy_spell = info.spell

                    if info.targetId == context.bt.id then
                        context.enemy_spell_target = context.bt
                    elseif context.party1_by_id[info.targetId] then
                        context.enemy_spell_target = context.party1_by_id[info.targetId]
                    else
                        context.enemy_spell_target = windower.ffxi.get_mob_by_id(info.targetId)
                    end

                    return info.spell
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Trigger if our enemy is in the process of using a TP move. The ability WILL be
    -- cleared in windowed, so it will be detectable on certain subsequent calls.
    context.enemyUsingAbility = function (...)
        if context.bt then
            local skills = varargs({...})

            -- We do NOT want to use Windowed mode (second param) for any "using" function; the "using"
            -- functions are looking for things that are happening right now, and Windowed mode
            -- is all about detecting when something happened recently (even if it's already done).
            local info = actionStateManager:getMobAbilityInfo(context.bt, false)
            if info then
                -- We'll match if either no filters were provided, or if the current ability is in the filter list
                if 
                    skills[1] == nil or
                    arrayIndexOf(skills, "*") or
                    arrayIndexOfStrI(skills, info.ability.name) 
                then
                    -- Clear the mob ability. It will still be available for what we're calling 'windowed' detection via
                    -- context.enemyUsedAbility. That is, the ability will be detectable for a certain window of time.
                    actionStateManager:clearMobAbility(context.bt)

                    context.enemy_ability = info.ability
                    return info.ability
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Trigger if our enemy is in the process of using a TP move. The ability will NOT be
    -- cleared, so it will be detectable on subsequent calls.
    context.enemyUsingAbilityNC = function (...)
        if context.bt then
            local skills = varargs({...})

            -- We do NOT want to use Windowed mode (second param) for any "using" function; the "using"
            -- functions are looking for things that are happening right now, and Windowed mode
            -- is all about detecting when something happened recently (even if it's already done).
            local info = actionStateManager:getMobAbilityInfo(context.bt, false)
            if info then
                -- We'll match if either no filters were provided, or if the current ability is in the filter list
                if 
                    skills[1] == nil or
                    arrayIndexOf(skills, "*") or
                    arrayIndexOfStrI(skills, info.ability.name) 
                then
                    -- We do NOT clear the ability at all here. It will still be available for subsequent
                    -- calls, until the ability ends. A call to enemyUsingAbility(enemy_ability) from
                    -- a gambit can force the actual clear to happen.

                    context.enemy_ability = info.ability
                    return info.ability
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Trigger if our enemy used a TP move recently. The ability will be cleared, so
    -- it will NOT be detectable on subsequent calls.
    context.enemyUsedAbility = function (...)
        if context.bt then
            local skills = varargs({...})
            local info = actionStateManager:getMobAbilityInfo(context.bt, true)
            if info then
                -- We'll match if either no filters were provided, or if the current  ability is in the filter list
                if 
                    skills[1] == nil or
                    arrayIndexOfStrI(skills, info.ability.name) 
                then
                    -- Clear the mob ability for good. When the second argument is true, it will no longer be tracked.
                    actionStateManager:clearMobAbility(context.bt, true)

                    context.enemy_ability = info.ability
                    return info.ability
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Trigger if our enemy used a TP move recently. The ability will NOT be cleared, so
    -- it will be detectable on subsequent calls.
    context.enemyUsedAbilityNC = function (...)
        if context.bt then
            local skills = varargs({...})
            local info = actionStateManager:getMobAbilityInfo(context.bt, true)
            if info then
                -- We'll match if either no filters were provided, or if the current  ability is in the filter list
                if 
                    skills[1] == nil or
                    arrayIndexOfStrI(skills, info.ability.name) 
                then
                    -- Clear the mob ability for good. When the second argument is false, it will continue to be tracked.
                    actionStateManager:clearMobAbility(context.bt, false)

                    context.enemy_ability = info.ability
                    return info.ability
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Trigger if a party member is using a weapon skill or TP move
    context.partyUsingWeaponSkill = function (...)
        if context.bt then
            local skills = varargs({...})
            local party_weapon_skill = context.party_weapon_skill
            
            if 
                party_weapon_skill and
                party_weapon_skill.mob and
                party_weapon_skill.mob.id == context.bt.id
            then
                -- We'll match if either no filters were provided, or if the requested weapon skill
                -- attributes are matched by the triggering weapon skill
                if 
                    skills[1] == nil or
                    arrayIndexOfStrI(skills, party_weapon_skill.name)
                then
                    context.skillchain_trigger_time = party_weapon_skill.time
                    return party_weapon_skill
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Similar to partyUsingWeaponSkill, but only triggers if a minimum amount
    -- of time has ellapsed since the weapon skill was used.
    context.partyUsingWeaponSkill2 = function(...)
        local result = context.partyUsingWeaponSkill(...)
        if result then
            local age = os.clock() - context.skillchain_trigger_time
            if
                --(not context.skillchain and age >= SKILLCHAIN_START_DELAY) or
                (age >= settings.skillchainDelay - 1)
            then
                --writeVerbose('partyUsingWeaponSkill2: %s':format(result and text_green('true') or text_red('false')))
                return result
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Wait the appropriate amount of time to close a skillchain. Returns
    context.waitSkillchain = function(seconds)
        if
            context.partyUsingWeaponSkill() and
            context.skillchain_trigger_time > 0
        then
            seconds = math.max(
                tonumber(seconds) or tonumber(settings.skillchainDelay) or SKILLCHAIN_DELAY,
                0)

             -- If there's no skillchain active, we don't need to space things out too far
             if not context.skillchain then
                --writeVerbose('shrinking sc time now with seconds=%.1f, age=%.1f':format(seconds, os.clock() - context.skillchain_trigger_time))
                seconds = math.min(seconds, SKILLCHAIN_START_DELAY)
            end

            -- Calculate the age of our weapon skill, and the corresponding sleep time needed
            -- to ensure we have a chance at creating a skillchain effect. Note that we will
            -- subtract a small amount of time to account for the general execution delay, 
            -- since timing needs to be very precise here.
            local age = os.clock() - context.skillchain_trigger_time
            local sleepTime = math.max(seconds - age, 0)

            writeVerbose('Delaying %s for skillchaining...':format(
                pluralize('%.1f':format(sleepTime), 'second', 'seconds', Colors.verbose)
            ))

            -- If we need to delay for our skillchain, do that now
            if sleepTime > 0 then                
                context.wait(sleepTime)
                return sleepTime
            end

            -- We'll return 0 here, since that will distinguish between having no need to wait, and
            -- the other condition in which there was no weapon skill trigger present at all (nil).
            return 0
        end
    end
    context.waitSC = context.waitSkillchain

    --------------------------------------------------------------------------------------
    -- Similar to waitSkillchain above, except it waits for a shorter time period to
    -- allow for use of an ability (SA, TA, flourishes, etc)
    context.waitSkillchainWithAbility = function(abilityCount)
        if context.ability_recast and context.ability_recast <= 0 then

            local scd = tonumber(settings.skillchainDelay) or SKILLCHAIN_DELAY
            local modifier = (tonumber(abilityCount) or 1) + 0.5

            scd = math.max(scd - modifier, 0)
            context.waitSkillchain(scd)

            return true
        else
            context.waitSkillchain()
        end
    end
    context.waitSCWithAbility = context.waitSkillchainWithAbility

    --------------------------------------------------------------------------------------
    -- Determine if a skillchain can be opened without interfering with an
    -- existing weapon skill already in use.
    context.canOpenSkillchain = function()
        local party_weapon_skill = context.party_weapon_skill
        if
            party_weapon_skill == nil or
            party_weapon_skill.time == 0
            or (os.clock() - party_weapon_skill.time) > MAX_WEAPON_SKILL_TIME
        then
            return true
        end
    end
    context.canOpenSC = context.canOpenSkillchain

    --------------------------------------------------------------------------------------
    -- Close a skill chain with the specified weapon skill
    context.closeSkillchain = function (...)
        local weaponSkill = varargs({...})
        if #weaponSkill == 0 then weaponSkill = context.weapon_skill and context.weapon_skill.name end

        if context.canUseWeaponSkill(weaponSkill) then

            writeVerbose('Attempting to close skillchain with: %s':format(
                text_weapon_skill(context.weapon_skill.name, Colors.verbose)
            ))

            -- Space it out in time
            context.waitSkillchain()

            -- Use the weapon skill
            context.useWeaponSkill()

            return true
        end
    end
    context.closeSC = context.closeSkillchain

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
            return sendRangedAttackCommand(context.t, context, duration or 1.0)
        end
    end
    context.throw = context.shoot
    context.ra = context.shoot
    context.RA = context.shoot

    --------------------------------------------------------------------------------------
    --
    context.hasTarget = function ()
        return (context.t and context.t.mob) ~= nil
    end

    --------------------------------------------------------------------------------------
    -- Ensure that the current action does not execute again for at least
    -- the given number of seconds
    context.postpone = function(s)
        if type(s) == 'number' then
            if s > 0 then
                if settings.verbosity >= VERBOSITY_DEBUG then
                    writeDebug('Postponing next action execution by %s':format(
                        text_number('%.1fs':format(s), Colors.debug)
                    ))
                end
                context.action.availableAt = math.max(context.action.availableAt, os.clock() + s)
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Stay in the idle state for the given number of seconds
    context.idle = function (s, actionMessage)
        local s = math.max(tonumber(s) or 0, 2)
        
        -- Set the wake time to the new time, or the current wake time -- whichever is later
        actionStateManager.idleWakeTime = math.max(os.clock() + s, actionStateManager.idleWakeTime)

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
    -- Determine if we're already at the merit point cap
    context.hasCappedMerits = function()
        local mpi = actionStateManager:getMeritPointInfo()
        if 
            mpi and
            type(mpi.current) == 'number' and
            mpi.current == mpi.max
        then
            return true
        end
    end

    --------------------------------------------------------------------------------------
    -- Performs a "touch" on a mob, which is to target it and hit enter
    context.touch = function(identifier, max_distance)
        local mob = identifier

        if type(identifier) == 'number' then
            mob = {}
            mob.id = identifier
        elseif type(identifier) == 'string' then
            mob = context.findByName(identifier)
        end

        if type(mob) == 'table' then
            mob = windower.ffxi.get_mob_by_id(mob.id)
        end

        if type(mob) == 'table' then
            max_distance = math.max(tonumber(max_distance) or 10, 0)
            if mob.distance <= (max_distance * max_distance) then
                local player = windower.ffxi.get_player()

                local lt = lockTarget(player, mob)
                local t = windower.ffxi.get_mob_by_target('t')
                if t == nil or t.id ~= mob.id then
                    coroutine.sleep(0.1)
                    lt = lockTarget(player, mob)
                    t = windower.ffxi.get_mob_by_target('t')
                    if t == nil or t.id ~= mob.id then
                        t = nil
                    end
                end

                -- if settings.debugging then
                --     writeMessage('DBG: touch targeting ended with lt=%s, t=%s':format(
                --         lt and text_green('true') or text_red('false'),
                --         t and text_number(t.id) or text_red('nil')
                --     ))
                -- end

                if t ~= nil then
                    -- if settings.debugging then
                    --     writeMessage('DBG: touch sending enter key press...')
                    -- end

                    coroutine.sleep(1)

                    -- Activate the target
                    context.keyTap('enter', 0.5)
                else
                    writeMessage(text_red('Warning: Targeting failed!'))
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Performs a "tap" on a mob, which is to target it and hit enter and escape
    context.tap = function(identifier, max_distance)
        local mob = identifier

        if type(identifier) == 'number' then
            mob = {}
            mob.id = identifier
        elseif type(identifier) == 'string' then
            mob = context.findByName(identifier)
        end

        if type(mob) == 'table' then
            mob = windower.ffxi.get_mob_by_id(mob.id)
        end

        if mob then
            max_distance = math.max(tonumber(max_distance) or 5, 0)
            if mob.distance <= (max_distance * max_distance) then
                local player = windower.ffxi.get_player()
                if lockTarget(player, mob) then
                    coroutine.sleep(1)
                    
                    -- Activate the target
                    context.keyTap('enter', 0.5)
                    
                    -- We'll double-escape: Once to exit dialog (if any), and again to clear the target.
                    context.keyTap('escape', 0.5)
                    context.keyTap('escape', 0.5)
                else
                    writeMessage(text_red('Warning: Targeting failed!'))
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- Try to set the target cursor to the specified mob
    context.setTargetCursor = function(mob)
        local id = type(mob) == 'table' and mob.id or mob
        if type(id) == 'number' then
            mob = windower.ffxi.get_mob_by_id(id)
            if mob and mob.valid_target then
                if context.me and context.me.target_index ~= mob.index then
                    return lockTarget(context.player, mob)
                end
            end
        end
    end

    --------------------------------------------------------------------------------------
    -- "Static" context properties
    context.constants = context_constants
    context.const = context.constants

    -- Expose some timing related values
    context.state_time  = actionStateManager:elapsedTimeInType()
    context.mob_time    = globals.target:runtime()
    if context.bt then
        context.bt.mob_time = context.mob_time
    end

    --------------------------------------------------------------------------------------
    -- "Static" context functions
    context.any = context_any
    context.min = context_min
    context.max = context_max
    context.iif = context_iif
    context.bool = context_boolean
    context.number = context_number
    context.recastTime = context_recastTime
    context.recastReady = context_recastReady
    context.noop = context_noop
    context.rand = context_rand
    context.abs = context_abs
    context.randomize = context_randomize
    context.sendCommand = context_send_command
    context.sendCommands = context_send_commands
    context.sendText = context_send_text
    context.keyTap = context_key_tap
    context.isApex = context_is_apex
    context.isLocus = context_is_locus
    context.isApexTier = context_is_apex_tier
    context.isArray = context_is_array
    context.arrayLength = context_array_length
    context.arrayCount = context.arrayLength
    context.arrayMerge = context_array_merge
    context.arrayAll = context_array_contains_all
    context.tableAll = context_table_contains_all
    context.hasAllFieldNames = context_table_has_all_field_names
    context.inRange = context_in_range
    context.wait = context_wait
    context.setVar = context_set_var
    context.getVar = context_get_var
    context.setVarField = context_set_var_field
    context.getVarField = context_get_var_field
    context.varIncrement = context_var_increment
    context.varDecrement = context_var_decrement

    -- Final setup
    setEnumerators(context)

    return context
end

return {
    create = function(actionType, time, target, mobEngagedTime, battleScope, party)
        local context = makeActionContext(actionType, time, target, mobEngagedTime, battleScope, party)

        -- Store the most recently created context
        actionStateManager:setContext(context)

        return context
    end
}