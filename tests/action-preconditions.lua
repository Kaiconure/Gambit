-- lua tests/action-preconditions.lua
local conditions = require('./lib/action-preconditions')
local guard = require('./lib/action-errors')
-- Keep this test independent of Windower's output and filesystem APIs.
guard.fail = function(action, stage, expression, message)
    action._runtimeError = {stage=stage, expression=expression, message=message}
end
local outer = {precondition={'outer()', '', '  '}, importedFrom='outer-file'}
local inner = {precondition='inner()', importedFrom='inner-file'}
conditions.inherit(outer, inner)
local leaf = {precondition='leaf()', when='own()', _whenFn=assert(loadstring('return own()'))}
conditions.inherit(inner, leaf)
assert(conditions.compile(leaf, guard))
assert(#leaf._preconditions == 3)
assert(leaf._preconditions[1].source == 'outer-file')
assert(leaf._preconditions[2].source == 'inner-file')
local calls = {}
local context = {}
for _, name in ipairs({'outer', 'inner', 'leaf', 'own'}) do
    local label = name
    context[label] = function() calls[#calls+1]=label;return true end
end
assert(guard.when(leaf, context))
assert(table.concat(calls, ',') == 'outer,inner,leaf,own')
for _, falseValue in ipairs({false, 'nil'}) do
    calls = {}
    context.inner = function() calls[#calls+1]='inner';if falseValue == false then return false end end
    assert(not guard.when(leaf, context) and not leaf._runtimeError)
    assert(table.concat(calls, ',') == 'outer,inner')
end
local sibling = {precondition={}}
conditions.inherit(outer, sibling)
assert(#conditions.collect(sibling) == 1)
sibling._inheritedPreconditions[1].expression = 'false'
assert(conditions.collect(inner)[1].expression == 'outer()')
for _, action in ipairs({{}, {precondition=''}, {precondition='  '}, {precondition={}}}) do
    assert(#conditions.collect(action) == 0)
end
local invalid = {precondition='broken('}
assert(not conditions.compile(invalid, guard) and invalid._runtimeError.stage:find('compile precondition',1,true))
context.inner = function() error('bad precondition') end
assert(not guard.when(leaf, context))
assert(leaf._runtimeError.expression == 'inner()')
assert(leaf._runtimeError.stage:find('inner-file',1,true))
leaf._runtimeError = nil
context.inner = function() coroutine.yield('wait');return true end
local thread = coroutine.create(function() return guard.when(leaf, context) end)
local ok, value = coroutine.resume(thread)
assert(ok and value == 'wait')
ok, value = coroutine.resume(thread)
assert(ok and value == true and coroutine.status(thread) == 'dead')
print('PASS: nested inheritance, branch isolation, empty values, order, short-circuit, errors, yields')
-- Windower permits string-literal method syntax that stock Lua does not.
for _, path in ipairs({'lib/settings.lua', 'lib/action-processing.lua'}) do
    local file = assert(io.open(path))
    local source = file:read('*all'); file:close()
    source = source:gsub("('[^'\r\n]*'):format", '(%1):format')
        :gsub('("[^"\r\n]*"):format', '(%1):format')
    assert(loadstring(source, '@' .. path))
end
print('PASS: import loader and action compiler syntax')
