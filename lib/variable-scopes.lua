local values = require('./lib/variable-values')
local expandKeys = require('./lib/variable-key-expansion')
local variableLoader = require('./lib/variable-loader')
local scopes = {}

local function equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for key,value in pairs(a) do if not equal(value,b[key]) then return false end end
    for key in pairs(b) do if a[key]==nil then return false end end
    return true
end

-- Keep persistent local edits when rebasing inherited configuration. Arrays and
-- explicit replacements are atomic; object fields retain independent edits.
local function rebase(current,previous,fresh)
    if equal(current,previous) then return values.copy(fresh) end
    if type(current)~='table' or type(previous)~='table' or type(fresh)~='table'
        or current[1]~=nil or previous[1]~=nil or fresh[1]~=nil then
        return values.copy(current)
    end
    local result=values.copy(fresh)
    local keys={}
    for key in pairs(current) do keys[key]=true end
    for key in pairs(previous) do keys[key]=true end
    for key in pairs(keys) do result[key]=rebase(current[key],previous[key],fresh[key]) end
    return result
end

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
    local function owner(id, key, captured)
        local state = (captured or states)[id or 0]
        while state.parent and not state.owns[key] do state=state.parent end
        return state
    end
    local function initialize(id,definition)
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
            base[key] = values.copy(owner(definition.parent, key).data[key])
        end
        local loader = variableLoader.new(warn)
        if next(overrides) ~= nil then overrides = scopeValue(overrides) end
        loader.merge(state.data, overrides, label)
        -- Captured parent values are fallback data, not competing definitions.
        loader.merge(state.data, base, label .. ' parent snapshot', -2)
        state.original = values.copy(state.data)
        return state
    end
    for id, definition in ipairs(definitions or {}) do
        initialize(id,definition)
    end
    local result = {}
    -- Called once at action entry, never during repeated reads or after a yield.
    -- Refresh parents first so nested overrides inherit the effective live scope.
    function result.activate(id)
        if not id then return end
        local definition=assert(definitions[id],'Unknown variable scope')
        result.activate(definition.parent)
        local previous=states[id]
        local fresh=initialize(id,definition)
        for key in pairs(fresh.owns) do
            fresh.data[key]=rebase(previous.data[key],previous.original[key],fresh.original[key])
        end
        local captured={[0]=states[0]}
        local current=id
        while current do
            captured[current]=states[current]
            current=definitions[current].parent
        end
        return captured
    end
    function result.view(getId, originals, getCaptured)
        return setmetatable({}, {
            __index=function(_, key)
                local id=getId()
                local state = owner(id, key, getCaptured and getCaptured())
                if originals then return state.original[key] end
                return state.data[key]
            end,
            __newindex=function(_, key, value)
                local id=getId()
                owner(id,key,getCaptured and getCaptured()).data[key]=value
            end,
        })
    end
    function result.snapshot(getId,getCaptured)
        local id=getId()
        local captured=getCaptured and getCaptured()
        local data = {}
        for _, state in pairs(captured or states) do
            for key in pairs(state.data) do data[key]=owner(id, key,captured).data[key] end
        end
        return data
    end
    return result
end

return scopes
