SPAWN_TYPE_PLAYER   = 13
SPAWN_TYPE_TRUST    = 14
SPAWN_TYPE_MOB      = 16

ITEM_SLOTS_EARRING  = 6144
ITEM_SLOTS_RING     = 24576

ITEM_TYPE_FOOD      = 7

BUFF_SLEEP1         = 2
BUFF_SLEEP2         = 19
BUFF_FOOD           = 251


STATUS_IDLE           = 0
STATUS_ENGAGED        = 1
STATUS_DEAD           = 2
STATUS_RESTING        = 33

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
function arrayIndexOfStrI(array, search)
    if isArray(array) and search ~= nil then
        search = string.lower(search)
        for index, value in ipairs(array) do
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


