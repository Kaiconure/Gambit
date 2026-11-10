local scopes=require('./lib/variable-scopes')
local values=require('./lib/variable-values')
local container={}
local action={with_vars={frontline_engagement={duration=5}}}
scopes.prepare(container,action)
local nested={with_vars={frontline_engagement={tolerance=2}}}
scopes.inherit(action,nested);scopes.prepare(container,nested)
local operations={with_vars={frontline_engagement={['array.append(targets)']={'extra'}}}}
scopes.prepare(container,operations)
local global={frontline_engagement={angle='lefter',duration=20,count=0,targets={'first'}}}
local original=values.copy(global)
local state=scopes.build(global,original,container._variableScopes)
local file=assert(io.open('lib/action-context.lua'));local source=file:read('*a');file:close()
local binding=assert(source:match('(    local globalVars = .-)    context.skillchain_trigger_time'))
local body=assert(source:match('(local function attachVariableHelpers%(.-)local function context_iif'))
local attach=assert(loadstring(body..'\nreturn attachVariableHelpers'))
setfenv(attach,setmetatable({variableValues=values,get_action_variable_path=values.path},{__index=_G}))
attach=attach()
local function context(which)
    local c={action=which}
    local bind=assert(loadstring(binding))
    setfenv(bind,setmetatable({context=c,actionStateManager={vars=global,originalVars=original,variableScopes=state},
        checklist=require('./lib/checklist'),variableValues=values,attachVariableHelpers=attach},{__index=_G}))
    bind();attach(c);return c
end
-- Reproduce Shockmaw: tank status updates the angle after compilation.
global.frontline_engagement.angle='front'
local first=context(action)
assert(first.vars.frontline_engagement.angle=='front')
assert(first.vars.frontline_engagement.duration==5 and global.frontline_engagement.duration==20)
assert(first.getOriginalVar('frontline_engagement.angle')=='front')
first.setVar('frontline_engagement.angle','aft')
first.resetVar('frontline_engagement.angle')
assert(first.vars.frontline_engagement.angle=='front')
first.varIncrement('frontline_engagement.count')
-- A running action keeps its baseline even if another evaluation is started.
local co=coroutine.create(function()
    assert(first.vars.frontline_engagement.angle=='front');coroutine.yield()
    assert(first.vars.frontline_engagement.angle=='front')
    assert(first.getOriginalVar('frontline_engagement.angle')=='front')
end)
assert(coroutine.resume(co))
global.frontline_engagement.angle='righter'
local second=context(action)
assert(second.vars.frontline_engagement.angle=='righter')
assert(second.vars.frontline_engagement.count==1) -- persistent local counter
assert(second.getOriginalVar('frontline_engagement.count')==0)
assert(coroutine.resume(co))
second.setVar('frontline_engagement.duration',9)
local child=context(nested)
assert(child.vars.frontline_engagement.angle=='righter' and child.vars.frontline_engagement.duration==9)
assert(child.vars.frontline_engagement.tolerance==2)
assert(child.getOriginalVar('frontline_engagement.duration')==9)
child.setVar('frontline_engagement.count',7)
assert(second.vars.frontline_engagement.count==1)
local a=context(operations)
assert(#a.vars.frontline_engagement.targets==2)
global.frontline_engagement.targets={'replacement'}
local b=context(operations)
assert(#b.vars.frontline_engagement.targets==2 and b.vars.frontline_engagement.targets[1]=='replacement')
assert(b.vars.frontline_engagement.targets[2]=='extra') -- no repeated append
second.resetVar('frontline_engagement')
assert(second.vars.frontline_engagement.duration==5)
assert(original.frontline_engagement.angle=='lefter' and global.frontline_engagement.angle=='righter')
print('PASS: live tank angle, per-entry reset baseline, persistent edits, nested parent state, yield stability and live array operations')
