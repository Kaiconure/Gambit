local directories={}
windower={addon_path='',dir_exists=function(path) return directories[path]==true end}
local paths=dofile('lib/settings-paths.lua')
assert(paths.namespaceRoot()=='./settings/_ns')
directories['settings/.ns']=true
assert(paths.namespaceRoot()=='./settings/.ns')
directories['settings/.ns/_xp']=true
directories['settings/.ns/_xp/_cleave']=true
assert(paths.namespacePath('xp/cleave')=='./settings/.ns/_xp/_cleave')
assert(paths.namespacePath('_xp/_cleave')==paths.namespacePath('xp/cleave'))
paths.setLoadedNamespace('xp/cleave',{'xp/cleave','xp'})
assert(paths.writePath('Tester','main.json')=='./settings/.ns/_xp/_cleave/players/Tester/main.json')
assert(paths.candidates('Tester','actions/geo.json')[3]=='./settings/.ns/_xp/players/Tester/actions/geo.json')
assert(not pcall(paths.resolveInheritance,'xp',function() return {inherits_from='_xp'} end,paths.namespaceExists))
directories['settings/.ns/xp']=true
assert(paths.namespacePath('xp/cleave')=='./settings/.ns/xp/cleave')
directories['settings/_ns']=true
assert(paths.namespaceRoot()=='./settings/_ns')
assert(not paths.namespaceExists('xp')) -- Roots never merge.
directories['settings/_ns/_xp']=true
assert(paths.namespacePath('xp/new')=='./settings/_ns/_xp/new')
for _, name in ipairs({'_actions','xp/_players','__actions','_con'}) do assert(not paths.validateNamespace(name)) end
local slots=require('./lib/action-slots')
assert(slots.priority('./settings/_ns/_xp/actions/lib/common/geo.json',{'xp'},'Tester','GEO')==11)
print('PASS: root preference, legacy fallback, segment aliases, exact precedence, writes, cycles and contribution priority')
