local dirs={}
windower={addon_path='',dir_exists=function(p) return dirs[p] or false end}
local paths=dofile('lib/settings-paths.lua')
assert(paths.namespaceRoot()=='./settings/_namespaces')
assert(paths.namespaceSettingsRoot()=='./settings/_namespace-settings')
assert(paths.bundledNamespaceRoot()=='./_namespaces')
paths.setLoadedNamespace('example')
assert(paths.writePath('Tester','main.json')=='./settings/_namespace-settings/example/players/Tester/main.json')
for _,parent in ipairs({'settings/',''}) do
    dirs[parent..'namespaces']=true
end
dirs['settings/namespace-settings']=true
assert(paths.namespaceRoot()=='./settings/namespaces')
assert(paths.bundledNamespaceRoot()=='./namespaces')
assert(paths.namespaceSettingsRoot()=='./settings/namespace-settings')
assert(paths.writePath('Tester','main.json')=='./settings/namespace-settings/example/players/Tester/main.json')
dirs['settings/namespaces/plain-only']=true
dirs['namespaces/plain-only']=true
for _,parent in ipairs({'settings/',''}) do dirs[parent..'_namespaces']=true end
dirs['settings/_namespace-settings']=true
assert(paths.namespaceRoot()=='./settings/_namespaces')
assert(paths.bundledNamespaceRoot()=='./_namespaces')
assert(paths.namespaceSettingsRoot()=='./settings/_namespace-settings')
assert(not paths.namespaceExists('plain-only')) -- Organizational roots never merge.
dirs['_namespaces/example']=true
assert(paths.namespacePath('example')=='./_namespaces/example')
files={new=function(p) return {exists=function() return p=='./_namespaces/example/.nsconfig' end,
    read=function() return '{}' end,write=function() error('bundled write') end} end,
    create_path=function() error('bundled create') end}
json=require('./lib/jsonlua')
assert(paths.ensureNamespaceFolders('Tester','example'))
assert(paths.writePath('Tester','main.json')=='./settings/_namespace-settings/example/players/Tester/main.json')
for _,prefix in ipairs({'settings/namespaces','settings/_namespaces','namespaces','_namespaces'}) do
    assert(paths.fileNamespace('./'..prefix..'/example/events/(all).json')=='example')
    assert(paths.namespaceRelativeFile('./'..prefix..'/example/actions/war.json')=='actions/war.json')
end
for _,prefix in ipairs({'namespace-settings','_namespace-settings'}) do
    local p='./settings/'..prefix..'/example/players/Tester/events/war.json'
    assert(paths.fileNamespace(p)=='example')
    assert(paths.namespaceRelativeFile(p)=='players/Tester/events/war.json')
end
print('PASS: underscore organizational defaults, plain fallback, root conflicts, bundled selection and path metadata')