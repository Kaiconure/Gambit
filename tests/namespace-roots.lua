local dirs={}
windower={addon_path='',dir_exists=function(p) return dirs[p] or false end}
local paths=dofile('lib/settings-paths.lua')
assert(paths.namespaceRoot()=='./settings/namespaces')
assert(paths.namespaceSettingsRoot()=='./settings/namespace-settings')
assert(paths.bundledNamespaceRoot()=='./namespaces')
paths.setLoadedNamespace('example')
assert(paths.writePath('Tester','main.json')=='./settings/namespace-settings/example/players/Tester/main.json')
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
assert(paths.namespaceRoot()=='./settings/namespaces')
assert(paths.bundledNamespaceRoot()=='./namespaces')
assert(paths.namespaceSettingsRoot()=='./settings/namespace-settings')
assert(paths.namespaceExists('plain-only')) -- Plain roots win when both forms exist.
dirs['settings/namespaces']=nil
dirs['namespaces']=nil
dirs['settings/namespace-settings']=nil
assert(paths.namespaceRoot()=='./settings/_namespaces')
assert(paths.bundledNamespaceRoot()=='./_namespaces')
assert(paths.namespaceSettingsRoot()=='./settings/_namespace-settings')
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
local index = './settings/_namespaces/index.json'
local indexContents = '{"aliases":{"xp":"battle","xp/di":"battle/di","di":"battle/di","chain":"di"}}'
local newFile = files.new
files.new=function(path)
    if path==index then
        return {exists=function() return true end,read=function() return indexContents end}
    end
    return newFile(path)
end
dirs['settings/_namespaces/battle']=true
dirs['settings/_namespaces/battle/di']=true
assert(paths.namespacePath('xp')=='./settings/_namespaces/battle')
assert(paths.namespacePlayerRoot('xp/di')=='./settings/_namespace-settings/battle/di/players')
assert(not paths.namespaceExists('xp/cleave') and not paths.namespaceExists('chain'))
assert(not paths.namespaceExists('gambit:xp'))
local configs={di={inherits_from='xp'},battle={}}
local chain=paths.resolveInheritance('di',function(name) return configs[name] end,paths.namespaceExists)
assert(#chain==2 and chain[2]=='battle')
dirs['_namespaces/xp']=true
assert(paths.namespacePath('xp')=='./_namespaces/xp')
dirs['settings/_namespaces/xp']=true
assert(paths.namespacePath('xp')=='./settings/_namespaces/xp')
paths.withDirectoryCache(function()
    assert(paths.namespaceExists('di'))
    indexContents='{}'
    assert(paths.namespaceExists('di'))
end)
assert(not paths.namespaceExists('di'))
print('PASS: namespace index aliases, exact and bundled precedence, inheritance, personal paths and reload scope')
print('PASS: plain organizational defaults, underscore fallback, root conflicts, bundled selection and path metadata')
