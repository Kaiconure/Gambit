local restore=require('./lib/equipment/restore')
local baseline={[0]={id=0},[1]={id=42,bagId=8,localId=3}}
local stack={{event_baseline=true,removed=baseline},{removed={}}}
local calls=0
local inventory={restore_equipment=function(snapshot)
    calls=calls+1; assert(snapshot==baseline); return 2
end}
assert(restore(stack,inventory)==2 and #stack==0 and calls==1)
assert(restore(stack,inventory)==nil and calls==1)
stack={{removed={}}}
assert(restore(stack,inventory)==nil and #stack==1 and calls==1)
stack={{event_baseline=true,removed=baseline},{removed={}}}
assert(not pcall(restore,stack,{restore_equipment=function() error('failed') end}))
assert(#stack==2)
assert(restore(stack,{restore_equipment=function() return 0 end})==nil and #stack==0)
print('PASS: baseline restoration is direct, exact, idempotent, and preserves stacks on failure')
