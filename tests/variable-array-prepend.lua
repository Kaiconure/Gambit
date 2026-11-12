local Loader=require('./lib/variable-loader')
local function state()
 local vars,warnings={},{}
 local loader=Loader.new(function(s)warnings[#warnings+1]=s end)
 return vars,function(value)loader.merge(vars,value,'layer')end,warnings
end
local vars,merge,warnings=state()
merge({['array.prepend(list)']={'B','A','B'}})
merge({list={'A','C','C'}})
assert(table.concat(vars.list,',')=='B,A,C' and #warnings==0)
merge({['array.prepend(list)']={'D'}}) -- Later-loaded parent runs first.
assert(table.concat(vars.list,',')=='B,A,D,C')
merge({unrelated=true});assert(table.concat(vars.list,',')=='B,A,D,C')
vars,merge=state()
merge({list={'A','B'},['array.append(list)']={'C','D'},
 ['array.prepend(list)']={'C','B'},['array.remove(list)']={'B'}})
assert(table.concat(vars.list,',')=='C,A,D')
for _,base in ipairs({false,42,'text',{named=true},{[1]='A',[3]='B'}})do
 vars,merge,warnings=state();merge({list=base});merge({['array.prepend(list)']={'Z'}})
 assert(type(vars.list)==type(base) and #warnings==1)
end
vars,merge,warnings=state();merge({['array.prepend(list)']={named=true}})
assert(vars.list==nil and #warnings==1)
vars,merge=state();merge({['array.prepend(list)']={}});assert(next(vars.list)==nil)
for _,marker in ipairs({'$object.null','$table.null','$array.empty','$object.empty','$table.empty'})do
 vars,merge=state();merge({list=marker});merge({['array.prepend(list)']={'Z'}})
 assert(vars.list==nil or next(vars.list)==nil)
 merge({['!array.prepend(list)']={'Z'}});assert(vars.list[1]=='Z')
end
vars,merge=state();merge({['csv(a,b)']={['array.prepend(list)']={{id=1},{id=1}}}})
assert(#vars.a.list==1 and #vars.b.list==1)
vars.a.list[1].id=2;assert(vars.b.list[1].id==1)
assert(not pcall(merge,{['array.prepend()']={}}))
assert(not pcall(merge,{['array.prepend(list']={}}))
-- Namespace precedence is independent of discovery order.
for _,order in ipairs({{'parent','child'},{'child','parent'}})do
 local loader=Loader.new(nil,function(source)return source=='child' and 0 or 1 end)
 local result={}
 local layers={parent={list={'base'},['array.prepend(list)']={'parent'}},
  child={['array.prepend(list)']={'child'}}}
 for _,name in ipairs(order)do loader.merge(result,layers[name],name)end
 assert(table.concat(result.list,',')=='child,parent,base')
end
local scopes=require('./lib/variable-scopes')
local container={}
local action={with_vars={['array.prepend(list)']={'B'},nested={['array.prepend(items)']={}},
 ['csv(a,b)']={['array.prepend(items)']={{id=1}}}}}
scopes.prepare(container,action)
local global={list={'A','B'},nested={items={'X'}}}
local scoped=scopes.build(global,global,container._variableScopes)
local view=scoped.view(function()return action._variableScope end)
assert(table.concat(view.list,',')=='B,A' and table.concat(global.list,',')=='A,B')
assert(view.nested.items[1]=='X' and view.a.items[1]~=view.b.items[1])
print('PASS: prepend order, duplicate promotion, combined operations, priority/clears, namespace order, validation, CSV and scoped arrays')
