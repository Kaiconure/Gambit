local scope=require('./lib/action-variable-scope')
local errors=require('./lib/action-errors')
errors.fail=function(action,stage,expression,message)
 action._runtimeError={stage=stage,expression=expression,message=message}
end
local function action(expression)
 local a={scope='expression',scope_expression=expression,scopes={execution={}}}
 scope.compile(a);return a
end
local ctx=setmetatable({vars={distance=2,config={items={1,2}}}},{__index=_G})
local a=action('vars.distance % 2')
local fn=a._scopeExpressionFn
a.scopes.execution.expression=scope.capture(a,ctx)
ctx.vars.distance=4;assert(not scope.ready(a,scope.capture(a,ctx)))
ctx.vars.distance=5;assert(scope.ready(a,scope.capture(a,ctx)))
assert(a._scopeExpressionFn==fn) -- Compile once, bind the context per evaluation.
a=action('nil');assert(scope.ready(a,scope.capture(a,ctx)))
a.scopes.execution.expression=scope.capture(a,ctx);assert(not scope.ready(a,scope.capture(a,ctx)))
a=action('false');a.scopes.execution.expression=scope.capture(a,ctx)
assert(not scope.ready(a,scope.capture(a,ctx)))
a=action('vars.config');a.scopes.execution.expression=scope.capture(a,ctx)
ctx.vars.config.items[2]=3;assert(scope.ready(a,scope.capture(a,ctx)))
assert(a.scopes.execution.expression[1].value.items[2]==2)
for _,expression in ipairs({'missingFunction()', '(function() return 1,2 end)()', '(function() end)()'})do
 a=action(expression);assert(scope.capture(a,ctx)==nil)
 assert(a._runtimeError and a._runtimeError.stage=='scope_expression')
 assert(not scope.ready(a,nil))
end
for _,expression in ipairs({'','  ','broken(',false,{}})do assert(not pcall(action,expression))end
print('PASS: compiled expression scopes, derived/nil/false/table values, snapshots and quarantined syntax/runtime/multiple-result errors')
