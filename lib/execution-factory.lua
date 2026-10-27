-- Cache compiled factories, never functions bound to a caller's environment.
local executionFactory = {}
local cache = {}
local arraySources = setmetatable({}, { __mode = 'k' })
local order = {}
local sourceBytes = 0
local MAX_ENTRIES = 128
local MAX_SOURCE_BYTES = 1024 * 1024

local function compile(code)
    local factory, err = loadstring(
        'return function(...)\nreturn ' .. code .. '\nend',
        '=executionFactory'
    )
    if not factory then
        factory, err = loadstring(
            'return function(...)\n' .. code .. '\nend',
            '=executionFactory'
        )
    end
    if not factory then error(err, 3) end
    return factory
end

-- Release only our references; returned closures and running coroutines remain valid.
function executionFactory.clear()
    cache = {}
    arraySources = setmetatable({}, { __mode = 'k' })
    order = {}
    sourceBytes = 0
end

-- Each call returns a fresh closure sharing the cached compiled body.
-- FIFO limits bound retained source, not the total size of compiled bytecode.
function executionFactory.get(code)
    if type(code) == 'table' then
        local lines = code
        code = arraySources[lines]
        if not code then
            code = lines
            local count = 0
            local length = #code
            for index, line in pairs(code) do
                if 
                    type(index) ~= 'number' or 
                    index % 1 ~= 0 or
                    index < 1 or 
                    index > length or type(line) ~= 'string' 
                then
                    error('executionFactory.get expects a code string or an array of strings', 2)
                end
                count = count + 1
            end
            if count ~= length then
                error('executionFactory.get expects a contiguous array of strings', 2)
            end
            -- Evaluate every expression in order, returning all results from the last.
            -- A separate scope discards intermediate values without exposing a local
            -- to subsequent expressions. Newlines terminate trailing line comments.
            local expressions = {}
            for index, expression in ipairs(code) do
                if index == length then
                    expressions[index] = 'return ' .. expression .. '\n'
                else
                    expressions[index] = 'do local _ = ' .. expression .. '\nend'
                end
            end
            code = table.concat(expressions, '\n')
            -- Arrays are immutable until clear(); weak keys do not keep callers' arrays alive.
            arraySources[lines] = code
        end
    end
    
    if type(code) ~= 'string' then
        error('executionFactory.get expects a code string or an array of strings', 2)
    end

    local factory = cache[code]
    if not factory then
        factory = compile(code)
        if #code <= MAX_SOURCE_BYTES then
            while #order >= MAX_ENTRIES or sourceBytes + #code > MAX_SOURCE_BYTES do
                local oldest = table.remove(order, 1)
                cache[oldest] = nil
                sourceBytes = sourceBytes - #oldest
            end
            cache[code] = factory
            order[#order + 1] = code
            sourceBytes = sourceBytes + #code
        end
    end

    return factory()
end

function executionFactory.execute(code, fenv, ...)
    local fn = executionFactory.get(code)
    setfenv(fn, fenv)
    return fn(...)
end

return executionFactory
