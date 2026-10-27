local scopes = require('./lib/variable-scopes')
local values = require('./lib/variable-values')
local container = {}
local idle = {with_vars={haste_cycle={targets={'me'}}}}
scopes.prepare(container, idle)
local a, b = {}, {}
scopes.inherit(idle,a); scopes.inherit(idle,b)
local nested = {with_vars={haste_cycle={targets={'WHM'}}}}
scopes.inherit(idle,nested); scopes.prepare(container,nested)
local separate = {with_vars={haste_cycle={targets={'GEO'}}}}
scopes.prepare(container,separate)
local global = {haste_cycle={targets={'mages'},spells={'Haste II','Haste'},count=0}, shared=1}
local state = scopes.build(global,values.copy(global),container._variableScopes)
local function context(action)
    local c={action=action}
    local id=function() return c.action._variableScope end
    c.vars=state.view(id);c._originalVars=state.view(id,true)
    return c
end
local ca, cb, cn, cs = context(a),context(b),context(nested),context(separate)
local f=assert(io.open('lib/action-context.lua'));local source=f:read('*a');f:close()
local body=assert(source:match('(local function attachVariableHelpers%(.-)local function context_iif'))
local attach=assert(loadstring(body .. '\nreturn attachVariableHelpers'))
setfenv(attach,setmetatable({variableValues=values,get_action_variable_path=values.path},{__index=_G}))
attach=attach()
for _, c in ipairs({ca,cb,cn,cs}) do attach(c) end
assert(ca.vars.haste_cycle.targets[1]=='me' and ca.vars.haste_cycle.spells[1]=='Haste II')
ca.vars.haste_cycle.count=4
assert(cb.getVar('haste_cycle.count')==4 and cn.getVar('haste_cycle.count')==0)
assert(global.haste_cycle.count==0 and cs.vars.haste_cycle.targets[1]=='GEO')
cn.setVar('haste_cycle.count',9)
assert(ca.vars.haste_cycle.count==4 and cn.vars.haste_cycle.count==9)
ca.setVar('shared',2);assert(global.shared==2 and cn.vars.shared==2)
global.haste_cycle.targets={'changed'}
assert(ca.vars.haste_cycle.targets[1]=='me')
ca.setVar('haste_cycle',nil);assert(ca.vars.haste_cycle==nil and cb.vars.haste_cycle==nil)
ca.resetVar('haste_cycle');assert(cb.vars.haste_cycle.targets[1]=='me')
local copy=ca.getOriginalVar('haste_cycle');copy.targets[1]='bad'
assert(ca.getOriginalVar('haste_cycle.targets.1')=='me')
ca.varIncrement('haste_cycle.count');assert(cb.vars.haste_cycle.count==1)
assert(#ca.vars.haste_cycle.spells==2)
local count=0;for _ in pairs(ca.vars.haste_cycle) do count=count+1 end;assert(count==3)
local co=coroutine.create(function()
    cn.vars.haste_cycle.count=10;coroutine.yield();assert(cn.vars.haste_cycle.count==10)
end)
assert(coroutine.resume(co));ca.vars.haste_cycle.count=20;assert(coroutine.resume(co))
local fresh=scopes.build(global,values.copy(global),container._variableScopes)
assert(fresh.view(function() return a._variableScope end).haste_cycle.count==0)
assert(not pcall(scopes.prepare,{}, {with_vars={'invalid'}}))
-- Exercise the actual context wiring, including explicit global access and
-- switching the active action before evaluating its conditions.
local binding=assert(source:match('(    local globalVars = actionStateManager.vars.-)    context.skillchain_trigger_time'))
local wired={action=a}
local bind=assert(loadstring(binding))
setfenv(bind,setmetatable({context=wired,actionStateManager={vars=global,originalVars=values.copy(global),variableScopes=state},
    variableValues=values,attachVariableHelpers=attach},{__index=_G}))
bind();attach(wired)
wired.setVarGlobal('haste_cycle.count',77)
assert(global.haste_cycle.count==77 and wired.vars.haste_cycle.count==20)
assert(wired.getVarGlobal('haste_cycle.count')==77)
wired.action=nested;assert(wired.getVar('haste_cycle.count')==10)
wired.action={};assert(wired.vars==global and wired.getVar('haste_cycle.count')==77)
wired.action=a
local found=false
for key in wired.pairs(wired.vars) do if key=='haste_cycle' then found=true end end
assert(found)
print('PASS: persistent shared descendants, nested isolation, direct writes, resets, global fallback, yielding and rebuild')
