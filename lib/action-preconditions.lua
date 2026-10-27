local preconditions = {}

-- Return a new list for each branch; never modify the parent's conditions.
function preconditions.collect(action)
    local result = {}
    for _, condition in ipairs(action._inheritedPreconditions or {}) do
        result[#result + 1] = {expression=condition.expression, source=condition.source}
    end
    local values = action.precondition
    if values == nil then return result end
    if type(values) ~= 'table' then values = {values} end
    for _, expression in ipairs(values) do
        if type(expression) ~= 'string' or expression:match('%S') then
            result[#result + 1] = {
                expression=expression,
                source=action.importedFrom or action.id or '(main action file)',
            }
        end
    end
    return result
end

function preconditions.inherit(parent, child)
    child._inheritedPreconditions = preconditions.collect(parent)
end

function preconditions.compile(action, guard)
    action._preconditions = preconditions.collect(action)
    for i, condition in ipairs(action._preconditions) do
        condition.stage = 'precondition[' .. i .. '] from ' .. tostring(condition.source)
        local message
        if type(condition.expression) == 'string' then
            condition.fn, message = loadstring('return ' .. condition.expression)
        else
            message = 'Precondition must be a Lua expression string'
        end
        if not condition.fn then
            guard.fail(action, 'compile ' .. condition.stage, condition.expression, message)
            return false
        end
    end
    return true
end

return preconditions
