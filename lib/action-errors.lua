-- Failure state belongs to compiled actions only, never the saved JSON actions.
local guard = {}

local function report(message)
    -- Attempt both outputs independently, even if one logger fails.
    pcall(writeMessage, message)
    pcall(print, message)
end

local function appendLog(action, stage, expression, message, location, label)
    local player = windower.ffxi.get_player()
    local player = player and player.name or 'Unknown'
    local directory = windower.addon_path .. '.data/'
    if not windower.dir_exists(directory) then assert(windower.create_dir(directory)) end
    directory = directory .. 'action-errors/' .. player .. '/'
    if not windower.dir_exists(directory) then assert(windower.create_dir(directory)) end
    local path = directory .. player:gsub('[^%w_-]', '_') .. os.date('-%Y%m%d.log')
    local entry = string.format(
        '[%s] Player: %s\nAction: %s\nSource: %s\nStage: %s\nError: %s\nExpression:\n%s\n\n',
        os.date('%Y-%m-%d %H:%M:%S %z'), player, tostring(label), tostring(location),
        tostring(stage), tostring(message), tostring(expression))
    local file = assert(io.open(path, 'a'))
    -- Close even if writing fails; a logging failure must not escape the guard.
    local ok, result, err = pcall(file.write, file, entry)
    local closed, closeError = file:close()
    if not ok then error(result) end
    assert(result, err)
    assert(closed, closeError)
end

function guard.fail(action, stage, expression, message)
    if action._runtimeError then return end
    action._runtimeError = {stage=stage, expression=expression, message=tostring(message)}
    local location = action.importedFrom or action.id or '(main action file)'
    local label = action.name or action._errorLabel or '(unnamed action)'
    -- Reporting must not turn an already-contained action error into an addon error.
    report(string.format(
        'Action disabled: %s [%s], %s: %s | %s',
        tostring(label), tostring(location), stage, tostring(message), tostring(expression)))
    local ok, err = pcall(appendLog, action, stage, expression, message, location, label)
    if not ok then
        report('Could not write action error log: ' .. tostring(err))
    end
end

function guard.evaluate(action, context, fn, stage, expression)
    if action._runtimeError then return false end
    -- resume catches errors without placing a non-yieldable pcall around fn.
    -- Relay all yielded/resumed values, including nils, to the owning scheduler.
    local function pack(...)
        return {n=select('#', ...), ...}
    end
    local thread = coroutine.create(function()
        setfenv(fn, context)
        return fn()
    end)
    local result = pack(coroutine.resume(thread))
    while result[1] and coroutine.status(thread) ~= 'dead' do
        local args = pack(coroutine.yield(unpack(result, 2, result.n)))
        result = pack(coroutine.resume(thread, unpack(args, 1, args.n)))
    end
    local ok, value = result[1], result[2]
    if not ok then
        guard.fail(action, stage, expression, value)
        return false
    end
    return true, value
end

function guard.when(action, context)
    local ok, value = guard.evaluate(action, context, action._whenFn, 'when', action.when)
    return ok and value
end

function guard.commands(action, context)
    if action._runtimeError then return false end
    for i, command in ipairs(action.commands or {}) do
        if not guard.evaluate(action, context, command._commandFn,
            'commands[' .. i .. ']', command.command) then return false end
    end
    return true
end

return guard
