local values=require('./lib/variable-values')
local errors=require('./lib/action-errors')
local scope={}
local function singleValue(...)
    assert(select('#',...)==1,'scope_expression must return exactly one value')
    return ...
end
local function equal(a,b,seen)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    seen=seen or {}
    if seen[a] and seen[a][b] then return true end
    seen[a]=seen[a] or {};seen[a][b]=true
    for key,value in pairs(a) do if not equal(value,b[key],seen) then return false end end
    for key in pairs(b) do if a[key]==nil then return false end end
    return true
end
function scope.compile(action)
    if action.scope=='expression' then
        local expression=action.scope_expression
        assert(type(expression)=='string' and expression:find('%S'),'scope_expression requires a non-empty expression')
        local factory,message=loadstring('return function(single) return function() return single('..expression..'\n) end end')
        assert(factory,message)
        action._scopeExpressionFn=factory()(singleValue)
        return
    end
    if action.scope~='variable' then return end
    local names=action.scope_variable
    if type(names)=='string' then names={names} end
    assert(type(names)=='table' and #names>0,'scope_variable requires a path or non-empty array of paths')
    local count=0
    for key,name in pairs(names) do
        assert(type(key)=='number' and key>=1 and key%1==0 and key<=#names,'scope_variable requires a contiguous array')
        assert(type(name)=='string' and #values.path(name)>0,'scope_variable requires non-empty variable paths')
        count=count+1
    end
    assert(count==#names,'scope_variable requires a contiguous array')
    action._scopeVariableNames=values.copy(names)
end
function scope.capture(action,context)
    if action.scope=='expression' then
        local ok,value=errors.evaluate(action,context,action._scopeExpressionFn,'scope_expression',action.scope_expression)
        if not ok then return end
        return {{value=values.copy(value)}}
    end
    if action.scope~='variable' then return end
    local snapshot={}
    for i,name in ipairs(action._scopeVariableNames) do
        -- Wrap nil so it remains distinct from an unexecuted scope.
        snapshot[i]={value=values.copy(values.get(context.vars,name))}
    end
    return snapshot
end
function scope.ready(action,snapshot)
    if action._runtimeError then return false end
    return not scope.active(action) or not equal(action.scopes.execution[action.scope],snapshot)
end
function scope.active(action) return action.scope=='variable' or action.scope=='expression' end
return scope
