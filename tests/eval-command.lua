local file=assert(io.open('lib/commands.lua'))
local source=file:read('*all');file:close()
source=source:gsub("('[^'\r\n]*'):format", '(%1):format'):gsub('("[^"\r\n]*"):format', '(%1):format')
assert(loadstring(source))
local handler=assert(source:match("(handlers%['eval'%] = function.-)\n%-%-%-%-"))
local guard=require('./lib/action-errors')
local failure
guard.fail=function(action, stage, expression, message) failure=action end
local messages={}
local context
local env=setmetatable({handlers={},actionErrors=guard,
 valueOutput={write=function(name,value,label)
    assert(name=='result' and label=='Eval')
    messages[#messages+1]='Eval: '..tostring(value)
 end},
 ActionContext={createTemporary=function() return context end},
 writeMessage=function(message) messages[#messages+1]=message end}, {__index=_G})
local chunk=assert(loadstring(handler));setfenv(chunk,env);chunk()
local eval=env.handlers.eval
eval({});assert(messages[#messages]:find('Usage:',1,true))
eval({'2 + 5'});assert(messages[#messages]:find('no action context',1,true))
local currentAction={}
context={action={}, execute=function(code)
 assert(code=="2 + 5")
 return 7
end}
eval({'2','+','5'});assert(messages[#messages]=='Eval: 7')
context.execute=function() return false end
eval({'false'});assert(messages[#messages]=='Eval: false')
context.execute=function() error('test error') end
eval({'bad()'});assert(failure and failure~=currentAction and not currentAction._runtimeError)
context.execute=function() coroutine.yield('wait');return 9 end
local thread=coroutine.create(function() eval({'wait()'}) end)
local ok,value=coroutine.resume(thread);assert(ok and value=='wait')
assert(coroutine.resume(thread));assert(messages[#messages]=='Eval: 9')
print('PASS: eval usage, missing context, argument joining, result, isolated error, yield/resume, command syntax')
local contextFile=assert(io.open('lib/action-context.lua'))
local contextSource=contextFile:read('*all');contextFile:close()
local factorySource=assert(contextSource:match('local dumped = false%s*(return .*)'))
local factoryEnv=setmetatable({settings={}, globals={},
 windower={ffxi={get_player=function() return {} end,
 get_mob_by_target=function() return {} end,get_party=function() return {} end}},
 actionStateManager={setContext=function() error('must not replace latest context') end},
 makeActionContext=function() return {} end}, {__index=_G})
local factoryChunk=assert(loadstring(factorySource));setfenv(factoryChunk,factoryEnv)
local factory=factoryChunk()
local firstContext=factory.createTemporary('first')
local secondContext=factory.createTemporary('second')
assert(firstContext~=secondContext and firstContext.action~=secondContext.action)
firstContext.action.enumerators.member={}
firstContext.action.availableAt=100
assert(secondContext.action.enumerators.member==nil and secondContext.action.availableAt==0)
assert(firstContext.action.scopes.execution and firstContext.action.scopes.iteration)
assert(firstContext.results and firstContext.params)
print('PASS: temporary action initialization, independent invocation state, no latest-context replacement')
