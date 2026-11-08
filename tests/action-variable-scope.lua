local scope=require('./lib/action-variable-scope')
local function action(paths)
 local a={scope='variable',scope_variable=paths,scopes={execution={},iteration={}},
  enumerators={},availableAt=0,delay=0,frequency=0,miss_frequency=0}
 scope.compile(a);return a
end
local a=action({'vars.distance','offset','config'})
local ctx={vars={distance=1,config={items={1,2}}}}
local first=scope.capture(a,ctx);assert(scope.ready(a,first))
a.scopes.execution.variable=first;assert(not scope.ready(a,scope.capture(a,ctx)))
ctx.vars.offset=false;assert(scope.ready(a,scope.capture(a,ctx)));ctx.vars.offset=nil
ctx.vars.config.items[2]=3;assert(scope.ready(a,scope.capture(a,ctx)))
assert(first[3].value.items[2]==2)
for _,paths in ipairs({'',{},false,{'a',3},{[2]='a'},'vars.'})do
 assert(not pcall(action,paths))
end
assert(action('distance')._scopeVariableNames[1]=='distance')
-- Exercise the scheduler itself, including effective with_vars binding.
local f=assert(io.open('lib/action-processing.lua'));local source=f:read('*a');f:close()
source=source:gsub("('[^'\r\n]*'):format",'(%1):format')
local selectSource=assert(source:match('(local function getNextBattleAction.-)local function executeBattleAction'))
local executeSource=assert(source:match('(local function executeBattleAction.-)function processNextAction'))
local now,hits,condition=10,0,true
local fail,incomplete,mutate=false,false,false
local globalsVars={distance=999}
a=action('distance')
local other=action('distance');other.as_function=true
local c=setmetatable({action=other,actionType='idle',scopes={battle=1,zone=1},time=now},
 {__index=function(self,key)if key=='vars'then return self.action==a and ctx.vars or globalsVars end end})
local env=setmetatable({variableActionScope=scope,settings={verbosity=0},VERBOSITY_TRACE=3,VERBOSITY_DEBUG=2,
 globals={actionsEnabled=true},os={clock=function()return now end},writeDebug=function()end,
 windower={ffxi={get_player=function()return {}end}},
 newActionScopes=function()return {execution={},iteration={}}end,
 actionStateManager={actions={idle={a}},isActionSnoozing=function()return false end,
  setActionType=function()end,elapsedTimeInType=function()return 100 end},
 actionErrors={selectBranch=function()if condition then return 'commands'end end,
  commands=function()
   if fail then return false end
   hits=hits+1;if mutate then ctx.vars.distance=ctx.vars.distance+1 end
   a.incomplete=incomplete;return true
  end}}, {__index=_G})
local chunk=assert(loadstring(selectSource..executeSource..'return getNextBattleAction,executeBattleAction'))
setfenv(chunk,env);local select,execute=chunk()
ctx.vars.distance=nil
condition=false;assert(not select(c) and not a.scopes.execution.variable)
condition=true;assert(select(c)==a);execute(c,a);assert(hits==1)
assert(not select(c)) -- Nil is a consumed value, not a missing snapshot.
ctx.vars.distance=5;c.time=20;now=20;assert(select(c)==a)
mutate=true;execute(c,a);mutate=false
assert(a.scopes.execution.variable[1].value==5 and ctx.vars.distance==6)
assert(select(c)==a);execute(c,a);assert(not select(c))
ctx.vars.distance=7;a.availableAt=30;assert(not select(c)) -- Frequency still applies.
c.time=now+20;now=c.time;assert(select(c)==a)
fail=true;execute(c,a);fail=false;assert(scope.ready(a,scope.capture(a,c)))
a.availableAt=0;incomplete=true;assert(select(c)==a);execute(c,a);incomplete=false
assert(not a.scopes.execution.variable)
c.time=now+2;now=c.time;assert(select(c)==a);execute(c,a);assert(not select(c))
a.scopes={execution={},iteration={}};assert(select(c)==a) -- Reload/reset re-arms.
a={scope='expression',scope_expression='vars.distance % 2',scopes={execution={},iteration={}},
 enumerators={},availableAt=0,delay=0,frequency=0,miss_frequency=0}
scope.compile(a);env.actionStateManager.actions.idle={a};c.select=_G.select;c.error=_G.error
ctx.vars.distance=2;assert(select(c)==a);execute(c,a)
assert(a.scopes.execution.expression and not select(c))
ctx.vars.distance=4;assert(not select(c))
ctx.vars.distance=5;assert(select(c)==a)
env.actionErrors.selectBranch=function()return 'else'end
c._actionBranch='else'
execute(c,a);assert(not select(c)) -- Else transitions also consume the current value.
ctx.vars.distance=6;assert(select(c)==a)
print('PASS: variable scope validation, nil/multiple/table snapshots, scoped lookup, failed conditions/commands, pre-execution values, frequency, incomplete retry and reset')
