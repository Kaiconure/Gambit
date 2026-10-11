-- lua tests/action-errors.lua (including stock Lua 5.1).
local messages={}
local entries={}
local originalOpen=io.open
windower={addon_path='test/',ffxi={get_player=function() return {name='Steris'} end},
 dir_exists=function() return true end}
io.open=function(path,mode)
 assert(path:match('^test/%.data/action%-errors/Steris/Steris%-%d%d%d%d%d%d%d%d%.log$') and mode=='a')
 return {write=function(self,entry) entries[#entries+1]=entry;return self end,
 close=function() return true end}
end
writeMessage=function(message) messages[#messages+1]=message end
globals={enabled=true}
local guard=dofile('lib/action-errors.lua')
local count=0
local context={bad=function() error('broken helper') end,good=function() count=count+1 end}
local function compiled(code) return assert(loadstring('return '..code)) end
local action={when='bad()',_whenFn=compiled('bad()'),importedFrom='heals/example',_errorLabel='battle[2]'}
assert(not guard.when(action,context))
assert(action._runtimeError.stage=='when' and #messages==1)
assert(messages[1]:find('heals/example',1,true))
assert(not guard.when(action,context) and #messages==1)
assert(#entries==1 and entries[1]:find('Source: heals/example',1,true))
assert(entries[1]:find('Expression:\nbad()',1,true))
assert(action.disabled==nil)
local normal={when='false',_whenFn=compiled('false')}
assert(not guard.when(normal,context) and normal._runtimeError==nil)
local commands={commands={{command='good()',_commandFn=compiled('good()')},
 {command='bad()',_commandFn=compiled('bad()')},{command='good()',_commandFn=compiled('good()')}}}
assert(not guard.commands(commands,context) and count==1)
assert(commands._runtimeError.stage=='commands[2]')
assert(not guard.commands(commands,context) and count==1)
local healthy={commands={{command='good()',_commandFn=compiled('good()')}}}
assert(guard.commands(healthy,context) and count==2)
commands._runtimeError=nil
context.bad=function() return false end
assert(guard.commands(commands,context) and count==4)
local yielding={commands={{command='pause()',_commandFn=compiled('pause()')}}}
context.pause=function() coroutine.yield('sleep');count=count+1 end
local thread=coroutine.create(function() return guard.commands(yielding,context) end)
local ok,result=coroutine.resume(thread)
assert(ok)
assert(coroutine.status(thread)=='suspended' and result=='sleep')
assert(coroutine.resume(thread));assert(not yielding._runtimeError)
assert(coroutine.status(thread)=='dead' and globals.enabled)
-- Preserve nils and resume arguments through repeated yields, then quarantine
-- an error after resuming without executing the next command.
context.pause=function()
 local a,b,c=coroutine.yield(nil,'delay',nil)
 assert(a==12 and b==nil and c==34)
 coroutine.yield('again')
 error('failure after sleep')
end
local before=count
local failing={commands={{command='pause()',_commandFn=compiled('pause()')},
 {command='good()',_commandFn=compiled('good()')}}}
thread=coroutine.create(function() return guard.commands(failing,context) end)
local function pack(...) return {n=select('#',...),...} end
local values=pack(coroutine.resume(thread))
assert(values.n==4 and values[1] and values[2]==nil and values[3]=='delay' and values[4]==nil)
ok,result=coroutine.resume(thread,12,nil,34)
assert(ok and result=='again')
ok,result=coroutine.resume(thread)
assert(ok and result==false and coroutine.status(thread)=='dead')
assert(failing._runtimeError.stage=='commands[1]' and count==before and globals.enabled)
-- Conditions can also yield and retain their final result.
context.pause=function() coroutine.yield('condition');return true end
local condition={when='pause()',_whenFn=compiled('pause()')}
thread=coroutine.create(function() return guard.when(condition,context) end)
ok,result=coroutine.resume(thread)
assert(ok and result=='condition')
ok,result=coroutine.resume(thread)
assert(ok and result==true and not condition._runtimeError)
print('PASS: yield/resume, nil payloads, resumed errors, command ordering, yielding conditions')
print('PASS: condition quarantine, false condition, command short-circuit, healthy action, explicit reset, source report, no saved disabled flag')
local multiline='first()\nsecond()'
guard.fail({},'commands[3]',multiline,'test failure')
assert(entries[#entries]:find(multiline,1,true))
local closed=false
io.open=function() return {write=function() error('disk full') end,
 close=function() closed=true;return true end} end
local diskFailure={}
guard.fail(diskFailure,'when','bad()','test failure')
assert(closed and diskFailure._runtimeError and globals.enabled)
assert(messages[#messages]:find('Could not write action error log:',1,true))
io.open=originalOpen
print('PASS: daily character log, full expressions, one entry per quarantine, contained write failure')
