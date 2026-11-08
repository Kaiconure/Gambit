local values = require('./lib/variable-values')
local expandKeys = require('./lib/variable-key-expansion')
local variableLoader = require('./lib/variable-loader')
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

local function scopeValue(value)
    if type(value) ~= 'table' then return value end
    -- Preserve with_vars' existing explicit-empty replacement behavior.
    if next(value) == nil then return '$table.empty' end
    if value[1] ~= nil then return values.copy(value) end
    local result = {}
    for key, child in pairs(value) do
        if type(key) == 'string' and (key:match('^array%.append%(') or key:match('^array%.remove%(')
            or key:match('^[!^]array%.append%(') or key:match('^[!^]array%.remove%(')) then
            result[key] = values.copy(child)
        else
            result[key] = scopeValue(child)
        end
    end
    return result
end

function scopes.build(global, original, definitions, warn)
    local states = {[0]={data=global, original=original}}
    local function owner(id, key)
        local state = states[id or 0]
        while state.parent and not state.owns[key] do state=state.parent end
        return state
    end
    for id, definition in ipairs(definitions or {}) do
        local state = {parent=states[definition.parent or 0], owns={}, data={}, original={}}
        states[id] = state
        local label = 'with_vars scope ' .. id
        local overrides = expandKeys(definition.overrides, 0, label)
        local base = {}
        for raw in pairs(overrides) do
            assert(type(raw) == 'string' and not raw:match('^[!^]'), 'with_vars requires ordinary variable names')
            local key = raw:match('^array%.append%((.*)%)$') or raw:match('^array%.remove%((.*)%)$') or raw
            key = key:match('^%s*(.-)%s*$')
            state.owns[key] = true
            base[key] = values.copy(owner(definition.parent, key).original[key])
        end
        local loader = variableLoader.new(warn)
        if next(overrides) ~= nil then overrides = scopeValue(overrides) end
        loader.merge(state.data, overrides, label)
        -- Captured parent values are fallback data, not competing definitions.
        loader.merge(state.data, base, label .. ' parent snapshot', -2)
        state.original = values.copy(state.data)
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
