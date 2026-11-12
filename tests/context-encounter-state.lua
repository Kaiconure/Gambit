local f=assert(io.open('lib/action-context.lua'))
local source=f:read('*a');f:close()
local block=assert(source:match('(    context%.encounters = %b{})'))
local calls={}
local context={bt={id=1}}
local result={phase='normal'}
local tracker={get=function(name,target)
 calls[#calls+1]={name,target};return result
end}
local env={context=context,require=function(name)
 assert(name=='./lib/encounter-state');return tracker
end}
local chunk=assert(loadstring(block));setfenv(chunk,env);chunk()
assert(context.encounter_state==nil)
assert(context.encounters.state('one')==result)
assert(context.encounter_state==result and calls[1][2]==context.bt)
local target={id=2};result={phase='charging'}
assert(context.encounters.state('two',target)==result)
assert(context.encounter_state==result and calls[2][2]==target)
result=nil
assert(context.encounters.state('unknown')==nil and context.encounter_state==nil)
print('PASS: encounter state preserves returns, publishes latest snapshot, defaults target and clears failed lookups')
