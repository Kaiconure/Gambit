local file=assert(io.open('lib/action-context.lua')); local source=file:read('*a'); file:close()
local binding=assert(source:match('(    context%.ipairs = ipairs)'))
local context={vars={entries={'first','second'}}}
local order={}
context.record=function(value) order[#order+1]=value end
local chunk=assert(loadstring(binding))
setfenv(chunk,{context=context,ipairs=ipairs}); chunk()
require('./lib/execution-factory').execute('for _, entry in ipairs(vars.entries) do record(entry) end',context)
assert(order[1]=='first' and order[2]=='second' and #order==2)
print('PASS: real context ipairs binding executes ordered action loops')
