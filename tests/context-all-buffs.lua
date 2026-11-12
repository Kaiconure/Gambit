local f=assert(io.open('lib/action-context.lua'))
local source=f:read('*a');f:close()
local body=assert(source:match('context.hasAllBuffs = function%(%.%.%.%)(.-)\n    end'))
local self={id=1,buffs={10,20}}
local mob={id=2,buffs={10}}
local context={me=self,bt=mob,effect='unchanged',effect_count=7}
local strictSeen
local names={protect=10,shell=20}
local env={type=type,context=context,
 isEffectTarget=function(value)return type(value)=='table' and value.buffs~=nil end,
 hasBuffInArray=function(buffs,buff,strict)
  strictSeen=strict
  local id=type(buff)=='table' and buff.id or type(buff)=='string' and names[buff:lower()] or buff
  for _,value in ipairs(buffs or {})do if value==id then return {id=id}end end
 end}
local chunk=assert(loadstring('return function(...)'..body..' end'))
setfenv(chunk,env)
local hasAll=chunk()
assert(hasAll({'Protect','Shell'}))
assert(hasAll('Protect','Shell'))
assert(not hasAll(mob,{'Protect','Shell'}))
assert(hasAll('bt',{'Protect'}))
assert(not hasAll('bt',{'Unknown'}))
assert(hasAll(self,'use-strict',{10,20}) and strictSeen)
assert(hasAll('not-strict',{10,20}) and strictSeen==false)
assert(hasAll(nil,'use-strict',10,20) and strictSeen)
assert(hasAll(self,{id=10}))
assert(hasAll(self,{id=10},{id=20}))
assert(hasAll({}) and hasAll(mob,{}) and hasAll())
assert(context.effect=='unchanged' and context.effect_count==7)
mob.buffs={};assert(not hasAll(mob,{'Protect'}))
context.me=nil;assert(not hasAll({'Protect'}))
print('PASS: hasAllBuffs self/target/symbol, arrays/varargs/resources, strictness, empty/missing buffs and effect isolation')
