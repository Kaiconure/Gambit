local resolve=require('./lib/equipment/references').resolve
local values=require('./lib/variable-values')
local vars={gear={battle={head={name='Hat',augments={'Magic Attack Bonus+10'},extra={preserved=true}}},
    candidates={'Preferred Hat',{name='Fallback Hat'}}}}
local function lookup(path) return values.get(vars,path) end
local reference={var='vars.gear.battle.head'}
local result=resolve(reference,lookup)
assert(result.name=='Hat' and result.augments[1]=='Magic Attack Bonus+10' and result.extra.preserved)
result.slot='head'; result.augments[1]='changed'
assert(vars.gear.battle.head.slot==nil and vars.gear.battle.head.augments[1]=='Magic Attack Bonus+10')
assert(reference.slot==nil)
assert(resolve({var='gear.missing.head'},lookup)==nil)
vars.gear.battle.head='Different Hat'
assert(resolve(reference,lookup)=='Different Hat')
local candidates=resolve({{var='gear.missing'}, {var='gear.candidates'},'Last Hat'},lookup)
assert(#candidates==3 and candidates[1]=='Preferred Hat' and candidates[2].name=='Fallback Hat' and candidates[3]=='Last Hat')
vars.a={var='vars.b'}; vars.b={var='a'}
assert(not pcall(resolve,vars.a,lookup))
for _,invalid in ipairs({{var=''},{var=false},{var='x',name='Hat'}}) do assert(not pcall(resolve,invalid,lookup)) end
vars.bad=false; assert(not pcall(resolve,{var='bad'},lookup))
-- The supplied scope-aware lookup controls resolution, not a global variable store.
assert(resolve(reference,function(path) assert(path=='vars.gear.battle.head'); return 'Scoped Hat' end)=='Scoped Hat')
print('PASS: equipment references preserve full values, resolve live/scoped paths, copy safely, expand candidates and reject cycles/invalid forms')
