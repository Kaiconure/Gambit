-------------------------------------------------------------------------------
-- Known spawn types
SPAWN_TYPE_PLAYER   = 13
SPAWN_TYPE_TRUST    = 14
SPAWN_TYPE_MOB      = 16

-------------------------------------------------------------------------------
-- Known item slots
ITEM_SLOTS_EARRING  = 6144
ITEM_SLOTS_RING     = 24576

-------------------------------------------------------------------------------
-- Known item types
ITEM_TYPE_FOOD      = 7

-------------------------------------------------------------------------------
-- Known buffs
BUFF_SLEEP1         = 2
BUFF_SLEEP2         = 19
BUFF_SILENCE        = 6
BUFF_PETRIFIED      = 7
BUFF_STUN           = 10
BUFF_AMNESIA        = 16
BUFF_TERROR         = 28
BUFF_SABER_DANCE    = 410
BUFF_FAN_DANCE      = 411
BUFF_FOOD           = 251
BUFF_ELVORSEAL      = 603
BUFF_BATTLEFIELD    = 254

-------------------------------------------------------------------------------
-- Known statuses
STATUS_IDLE           = 0
STATUS_ENGAGED        = 1
STATUS_DEAD           = 2
STATUS_RESTING        = 33

-------------------------------------------------------------------------------
-- Known packet id's
PACKET_TARGET_LOCK    = 0x058

-- Math helper to get the sign indicator of a given number. Returns -1 if negative, 0 if 0, and +1 if positive
math.sign = math.sign or 
    function (num) 
        return (num < 0 and -1) or (num > 0 and 1) or (0) 
    end

-- Math helper to clamp a number to a given range. Return value is in the range [min, max].
math.clamp = math.clamp or 
    function(num, min, max)
        local _min = math.min(min, max)
        local _max = math.max(min, max)

        return math.min(_max, math.max(_min, num))
    end


--------------------------------------------------------------------------------------
-- Write out a named value
function makeDisplayValue(name, value, ignoreTables, prefix)
    prefix = prefix or '  '

    if value == nil then
        return string.format('%s%s: %s', prefix, colorize(Colors.gray, name), colorize(Colors.gray, 'nil'))
    elseif type(value) == 'number' then
        return string.format('%s%s: %s', prefix, colorize(Colors.gray, name), colorize(Colors.blue, tostring(value)))
    elseif type(value) == 'string' then
        return string.format('%s%s: "%s"', prefix, colorize(Colors.gray, name), colorize(Colors.coral, tostring(value)))
    elseif type(value) == 'boolean' then
        return string.format('%s%s: %s', prefix, colorize(Colors.gray, name), colorize(Colors.blue, tostring(value and 'true' or 'false')))
    elseif type(value) == 'table' and not ignoreTables then
        local result = string.format('%s%s: {\n', prefix, colorize(Colors.gray, name))

        local indentPrefix = '  ' .. prefix
        local first = true
        for i, v in pairs(value) do
            result = result .. (first and '' or '\n') .. makeDisplayValue(i, v, ignoreTables, prefix .. ' ')
            first = false
        end

        result = result .. '\n' .. prefix .. '}'

        return result
    end
end

--------------------------------------------------------------------------------------
-- Write an object to a file as JSON
function writeJsonToFile(fileName, obj)
    local file = files.new(fileName)
    file:write(json.stringify(obj))
end

--------------------------------------------------------------------------------------
-- Write an object to a file as JSON
function writeStringToFile(fileName, str)
    local file = files.new(fileName)
    file:write(str)
end

--------------------------------------------------------------------------------------
-- Check if an object is an array
function isArray(value)
    return value ~= nil and type(value) == 'table' and #value > 0
end

--------------------------------------------------------------------------------------
-- Determine if the two arrays have a non-empty intersect set
function arraysIntersect(a1, a2)
    if 
        a1 ~= nil and #a1 > 0 and
        a2 ~= nil and #a2 > 0
    then
        for i, val in ipairs(a1) do
            if arrayIndexOf(a2, val) then
                return true
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Append an item to an array
function arrayAppend(array, item)
    array[#array + 1] = item
end

--------------------------------------------------------------------------------------
-- Determine if the two string arrays have a non-empty intersect set, with
-- a case-insensitive comparison operation
function arraysIntersectStrI(a1, a2)
    if 
        a1 ~= nil and #a1 > 0 and
        a2 ~= nil and #a2 > 0
    then
        for i, val in ipairs(a1) do
            if arrayIndexOfStrI(a2, val) then
                return true
            end
        end
    end
end

--------------------------------------------------------------------------------------
-- Find the index of the specified array key, or nil
function arrayIndexOf(array, search)
    if array ~= nil then
        for index, value in ipairs(array) do
            if value == search then
                return index
            end
        end
    end
end

--------------------------------------------------------------------------------------
-- Find the first in an array that matches one of the specified search parameters
function arrayIndexOfAny(array, ...)
    local searches = {...}
    if array ~= nil then
        for index, value in ipairs(array) do
            if arrayIndexOf(searches, value) then
                return index
            end
        end
    end
end

--------------------------------------------------------------------------------------
-- Find the index of the specified array key, or nil
function arrayIndexOfStrI(array, search, start)
    if isArray(array) and search ~= nil then
        search = string.lower(search)
        --for index, value in ipairs(array) do
        for index = (start or 1), #array do
            local value = array[index]
            if value ~= nil and string.lower(tostring(value)) == search then
                return index
            end
        end
    end
end

--------------------------------------------------------------------------------------
-- Find the first element of an array
function arrayFirst(array, fn)
    if array == nil or #array == 0 then return end

    for index, val in ipairs(array) do
        if fn == nil or fn(val, index) then return val end
    end
end

--------------------------------------------------------------------------------------
-- Find the first element of a table
function tableFirst(table, fn)
    if type(table) ~= 'table' then return table end

    for key, val in pairs(table) do
        if fn == nil or fn(val, key) then return val end
    end
end

--------------------------------------------------------------------------------------
-- Build an array of all elements of table that have a truthful result from fn
function tableAll(table, fn)
    local results = { }

    if type(table) == 'table' and type(fn) == 'function' then
        for key, val in pairs(table) do
            if fn(val, key) then 
                arrayAppend(results, val)
            end
        end
    end

    return results
end

--------------------------------------------------------------------------------------
-- Trims leading and trailing whitespace from a string
function trimString(s)
    if type(s) == 'string' then
        return string.match(s, '^()%s*$') and '' or string.match(s, '^%s*(.*%S)')
    end

    return ''
 end


-------------------------------------------------------------------------------
-- Returns true if the specified id belongs to a party member
function isPartyId(id, party)
    party = party or windower.ffxi.get_party()
    if party then
        return 
            (party.p0 and party.p0.mob and party.p0.mob.id == id) or
            (party.p1 and party.p1.mob and party.p1.mob.id == id) or
            (party.p2 and party.p2.mob and party.p2.mob.id == id) or
            (party.p3 and party.p3.mob and party.p3.mob.id == id) or
            (party.p4 and party.p4.mob and party.p4.mob.id == id) or
            (party.p5 and party.p5.mob and party.p5.mob.id == id)
    end
end

-------------------------------------------------------------------------------
-- Returns true if any member of the party is engaged
function isPartyEngaged(party)
    party = party or windower.ffxi.get_party()
    if party then
        return
            (party.p1 and party.p1.mob.status == STATUS_ENGAGED) or
            (party.p2 and party.p2.mob.status == STATUS_ENGAGED) or
            (party.p3 and party.p3.mob.status == STATUS_ENGAGED) or
            (party.p4 and party.p4.mob.status == STATUS_ENGAGED) or
            (party.p5 and party.p5.mob.status == STATUS_ENGAGED)
    end
end

-------------------------------------------------------------------------------
-- Returns true if any trusts in the party are engaged
function isPartyTrustEngaged(party)
    party = party or windower.ffxi.get_party()
    if party then
        return
            (party.p1 and party.p1.mob.spawn_type == SPAWN_TYPE_TRUST and party.p1.mob.status == STATUS_ENGAGED) or
            (party.p2 and party.p2.mob.spawn_type == SPAWN_TYPE_TRUST and party.p2.mob.status == STATUS_ENGAGED) or
            (party.p3 and party.p3.mob.spawn_type == SPAWN_TYPE_TRUST and party.p3.mob.status == STATUS_ENGAGED) or
            (party.p4 and party.p4.mob.spawn_type == SPAWN_TYPE_TRUST and party.p4.mob.status == STATUS_ENGAGED) or
            (party.p5 and party.p5.mob.spawn_type == SPAWN_TYPE_TRUST and party.p5.mob.status == STATUS_ENGAGED)
    end
end

-------------------------------------------------------------------------------
-- 
function stringStartsWith(str, start)
    if type(str) == 'string' and type('start') == 'string' then
        local sub = str:sub(1, #start)
        if sub == start then
            return true
        end
    end

    return false
end

-------------------------------------------------------------------------------
--
function stringStartsWithI(str, start)
    if type(str) == 'string' and type('start') == 'string' then
        local sub = str:sub(1, #start)
        if sub:lower() == start:lower() then
            return true
        end
    end

    return false
end

-------------------------------------------------------------------------------
-- Searches an action message for field names
function fieldsearch(message)
    local fieldarr = {}
    string.gsub(message,'{(.-)}', function(a) fieldarr[a] = true end)
    return fieldarr
end