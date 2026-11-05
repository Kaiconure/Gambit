local directories={}
windower={addon_path='',dir_exists=function(path) return directories[path]==true end}
local paths=dofile('lib/settings-paths.lua')
assert(paths.namespaceRoot()=='./settings/_namespaces')
directories['settings/namespaces']=true
assert(paths.namespaceRoot()=='./settings/namespaces')
directories['settings/namespaces/_xp']=true
directories['settings/namespaces/_xp/_cleave']=true
assert(paths.namespacePath('xp/cleave')=='./settings/namespaces/_xp/_cleave')
assert(paths.namespacePath('_xp/_cleave')==paths.namespacePath('xp/cleave'))
paths.setLoadedNamespace('xp/cleave',{'xp/cleave','xp'})
assert(paths.writePath('Tester','main.json')=='./settings/_namespace-settings/_xp/_cleave/players/Tester/main.json')
assert(paths.candidates('Tester','actions/geo.json')[3]=='./settings/_namespace-settings/_xp/players/Tester/actions/geo.json')
assert(not pcall(paths.resolveInheritance,'xp',function() return {inherits_from='_xp'} end,paths.namespaceExists))
directories['settings/namespaces/xp']=true
assert(paths.namespacePath('xp/cleave')=='./settings/namespaces/xp/cleave')
directories['settings/namespaces']=true
assert(paths.namespaceRoot()=='./settings/namespaces')
directories['settings/namespaces/xp']=nil
directories['settings/namespaces/_xp']=true
assert(paths.namespacePath('xp/new')=='./settings/namespaces/_xp/new')
for _, name in ipairs({'_actions','xp/_players','__actions','_con'}) do assert(not paths.validateNamespace(name)) end
local slots=require('./lib/action-slots')
assert(slots.priority('./settings/namespaces/_xp/actions/lib/common/geo.json',{'xp'},'Tester','GEO')==11)
print('PASS: namespace root, segment aliases, exact precedence, writes, cycles and contribution priority')
