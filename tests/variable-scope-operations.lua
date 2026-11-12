local scopes=require('./lib/variable-scopes')
local values=require('./lib/variable-values')
local container={}
local parent={with_vars={
 use_dispel={['array.append(buffs)']={'Howl','Howl'},['array.remove(buffs)']={'Protect'}},
 ['csv(one, two)']={['array.append(items)']={{id=2},{id=2}}},
 ['array.append(targets)']={'GEO'},
 ['array.remove(missing)']={},
 empty={},cleared='$object.null',tableCleared='$table.null',
}}
scopes.prepare(container,parent)
local child={with_vars={use_dispel={['array.append(buffs)']={'Shell'},['array.remove(buffs)']={'Howl'}}}}
scopes.inherit(parent,child);scopes.prepare(container,child)
local sibling={with_vars={use_dispel={['array.remove(buffs)']={'Shell'}}}}
scopes.prepare(container,sibling)
local invalid={with_vars={['array.append(scalar)']={'bad'},['array.remove(object)']={'bad'}}}
scopes.prepare(container,invalid)
local emptyOps={with_vars={['array.append(newList)']={},['array.remove(targets)']={}}}
scopes.prepare(container,emptyOps)
local global={use_dispel={buffs={'Protect','Shell'},keep=true},one={items={{id=1}}},two={items={{id=3}}},
 targets={'PLD'},empty={old=true},cleared=42,tableCleared={old=true},scalar=7,object={named=true}}
local baseline=values.copy(global)
local warnings={}
local state=scopes.build(global,baseline,container._variableScopes,function(s)warnings[#warnings+1]=s end)
local function view(action,original)return state.view(function()return action._variableScope end,original)end
local p,c,s=view(parent),view(child),view(sibling)
assert(table.concat(p.use_dispel.buffs,',')=='Shell,Howl' and p.use_dispel.keep)
assert(table.concat(c.use_dispel.buffs,',')=='Shell')
assert(table.concat(s.use_dispel.buffs,',')=='Protect')
assert(table.concat(global.use_dispel.buffs,',')=='Protect,Shell')
assert(p.one.items[1].id==1 and p.one.items[2].id==2)
assert(p.two.items[1].id==3 and p.two.items[2].id==2)
assert(p.one.items[2]~=p.two.items[2])
assert(table.concat(p.targets,',')=='PLD,GEO' and #global.targets==1)
assert(next(p.empty)==nil and p.cleared==nil and p.tableCleared==nil)
assert(view(invalid).scalar==7 and view(invalid).object.named and #warnings==2)
assert(next(view(emptyOps).newList)==nil and view(emptyOps).targets[1]=='PLD')
p.use_dispel.buffs[1]='changed'
assert(c.use_dispel.buffs[1]=='Shell' and global.use_dispel.buffs[2]=='Shell')
assert(view(parent,true).use_dispel.buffs[1]=='Shell')
assert(not p.use_dispel['array.append(buffs)'] and not p['csv(one, two)'])
print('PASS: with_vars CSV and array operations, nested/sibling isolation, snapshots, top-level ownership, empty/clear behavior and warnings')
