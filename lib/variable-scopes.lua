local values = require('./lib/variable-values')
local scopes = {}

function scopes.prepare(container, action)
    if action.with_vars == nil or action._ownVariableScope then return end
    assert(type(action.with_vars) == 'table', 'with_vars must be an object')
    for key in pairs(action.with_vars) do
        assert(type(key) == 'string' and not key:match('^[!^]'), 'with_vars requires ordinary variable names')
    end
    container._variableScopes = container._variableScopes or {}
    local definitions = container._variableScopes
    local id = #definitions + 1
    definitions[id] = {parent=action._variableScope, overrides=action.with_vars}
    action._variableScope = id
    action._ownVariableScope = true
end

function scopes.inherit(parent, child)
    child._variableScope = parent._variableScope
end

local function merge(base, override)
    if override == '$object.null' then return nil end
    if override == '$object.empty' or override == '$array.empty' then return {} end
    if type(override) ~= 'table' then return override end
    if next(override) == nil or override[1] ~= nil then return values.copy(override) end
    local result = type(base) == 'table' and values.copy(base) or {}
    for key, value in pairs(override) do result[key] = merge(result[key], value) end
    return result
end

function scopes.build(global, original, definitions)
    local states = {[0]={data=global, original=original}}
    local function owner(id, key)
        local state = states[id or 0]
        while state.parent and not state.owns[key] do state=state.parent end
        return state
    end
    for id, definition in ipairs(definitions or {}) do
        local state = {parent=states[definition.parent or 0], owns={}, data={}, original={}}
        states[id] = state
        for key, value in pairs(definition.overrides) do
            state.owns[key] = true
            state.data[key] = merge(owner(definition.parent, key).original[key], value)
            state.original[key] = values.copy(state.data[key])
        end
    end
    local result = {}
    function result.view(getId, originals)
        return setmetatable({}, {
            __index=function(_, key)
                local state = owner(getId(), key)
                if originals then return state.original[key] end
                return state.data[key]
            end,
            __newindex=function(_, key, value) owner(getId(), key).data[key]=value end,
        })
    end
    function result.snapshot(getId)
        local data = {}
        for _, state in pairs(states) do
            for key in pairs(state.data) do data[key]=owner(getId(), key).data[key] end
        end
        return data
    end
    return result
end

return scopes
