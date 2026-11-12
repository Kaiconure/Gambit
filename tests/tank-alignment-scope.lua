local json=require('./lib/jsonlua')
local scope=require('./lib/action-variable-scope')
local f=assert(io.open('settings/_namespaces/_base/actions/lib/tank-alignment.json'))
local document=json.parse(f:read('*a'));f:close()
assert(#document.actions==1)
local action=document.actions[1];action.scopes={execution={}}
scope.compile(action)
local primary=true
local angle,original='front','backside'
local writes=0
local ctx={vars={primary_tank_precondition={'me.is_party_leader'}},
 evaluateAllConditions=function()return primary end,
 resetVar=function()angle=original;writes=writes+1 end,
 setVar=function(_,value)angle=value;writes=writes+1 end}
local when=assert(loadstring('return '..action.when));setfenv(when,ctx)
local command=assert(loadstring('return '..action.commands[1]));setfenv(command,ctx)
local otherwise=assert(loadstring('return '..action['else'][1]));setfenv(otherwise,ctx)
local function tick()
 local snapshot=scope.capture(action,ctx)
 if not scope.ready(action,snapshot)then return false end
 if when()then command()else otherwise()end
 action.scopes.execution.expression=snapshot;return true
end
assert(tick() and angle=='backside')
angle='front';assert(not tick() and angle=='front')
primary=false;assert(tick() and angle=='backside')
angle='side';assert(not tick() and angle=='side')
primary=true;assert(tick() and angle==original)
primary=false;assert(tick() and angle=='backside')
angle='front';assert(not tick() and angle=='front' and writes==4)
action.scopes={execution={}};original=nil;primary=true
assert(tick() and angle==nil)
angle='front';assert(not tick() and angle=='front')
print('PASS: tank alignment handles repeated role transitions, consumes already-correct angles, preserves manual changes and supports nil originals/reload')
