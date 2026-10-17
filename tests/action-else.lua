local guard = require('./lib/action-errors')
guard.fail=function(action, stage, expression, message)
    action._runtimeError={stage=stage, expression=expression, message=message}
end
local function make(value)
    return {_whenFn=assert(loadstring('return false')), ['else']=value}
end
for _, value in ipairs({{}, {'', '  '}, ''}) do
    local action=make(value)
    assert(guard.compileElse(action) and #action._elseCommands==0)
    assert(guard.selectBranch(action,{})==nil)
end
local action=make({[1]='', [3]='hit()', [5]='hit()'})
assert(guard.compileElse(action) and #action._elseCommands==2)
local count=0
local context={hit=function() count=count+1 end}
assert(guard.selectBranch(action,context)=='else')
assert(guard.commands(action,context,'else') and count==2)
action._preconditions={{fn=assert(loadstring('return false')),stage='precondition',expression='false'}}
assert(guard.selectBranch(action,context)==nil and not action._runtimeError)
action._preconditions=nil
action._whenFn=assert(loadstring('return true'))
assert(guard.selectBranch(action,context)=='commands')
action._whenFn=assert(loadstring('return missing()'))
assert(guard.selectBranch(action,context)==nil and action._runtimeError)
action=make({'hit()', 'missing()', 'hit()'})
assert(guard.compileElse(action))
assert(not guard.commands(action,context,'else') and count==3)
assert(action._runtimeError.stage=='else[2]')
action=make('broken(')
assert(not guard.compileElse(action) and action._runtimeError)
action=make('pause()')
assert(guard.compileElse(action))
context.pause=function() coroutine.yield('wait');count=count+1 end
local thread=coroutine.create(function() return guard.commands(action,context,'else') end)
local ok,value=coroutine.resume(thread)
assert(ok and value=='wait')
ok,value=coroutine.resume(thread)
assert(ok and value and count==4)
print('PASS: else empty normalization, sparse arrays, branches, preconditions, errors, short-circuit, yielding')
