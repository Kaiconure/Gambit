local directories={['settings/namespaces']=true,['namespaces']=true,
    ['namespaces/abyssea']=true,['settings/namespaces/custom']=true}
local disk={['./namespaces/abyssea/.nsconfig']='{}',
    ['./settings/namespaces/custom/.nsconfig']='{"inherits_from":"abyssea"}'}
local children={['namespaces/']={'abyssea'},['settings/namespaces/']={'custom'}}
windower={addon_path='',dir_exists=function(p) return directories[p] or false end,
    get_dir=function(p) return children[p] or {} end}
json=dofile('lib/jsonlua.lua')
files={new=function(p) return {exists=function() return disk[p]~=nil end,
    read=function() return disk[p] end,write=function() error('bundled write') end} end,
    create_path=function() error('bundled create') end}
local paths=dofile('lib/settings-paths.lua')
assert(paths.namespacePath('abyssea')=='./namespaces/abyssea')
assert(paths.ensureNamespaceFolders('Tester','abyssea'))
local names,_,bundled=paths.listNamespaces()
assert(table.concat(names,',')=='abyssea,custom' and bundled.abyssea and not bundled.custom)
local chain=paths.resolveInheritance('custom',function(n)
    return json.parse(disk[paths.namespacePath(n)..'/.nsconfig'])
end,paths.namespaceExists)
assert(table.concat(chain,',')=='custom,abyssea')
paths.setLoadedNamespace('custom',chain)
local candidates=paths.candidates('Tester','main.json')
assert(candidates[1]=='./settings/_namespace-settings/custom/players/Tester/main.json')
assert(candidates[4]=='./namespaces/abyssea/main.json')
paths.setLoadedNamespace('abyssea')
local saved=paths.writePath('Tester','main.json')
assert(saved=='./settings/_namespace-settings/abyssea/players/Tester/main.json')
local slots=require('./lib/action-slots')
assert(slots.priority(saved,{'abyssea'},'Tester','WAR')==0)
assert(slots.priority('./namespaces/abyssea/actions/war.json',{'abyssea'},'Tester','WAR')==10)
assert(paths.fileNamespace(saved)=='abyssea')
assert(paths.namespaceRelativeFile('./namespaces/abyssea/events/(all).json')=='events/(all).json')
directories['settings/namespaces/abyssea']=true
assert(paths.namespacePath('abyssea')=='./settings/namespaces/abyssea')
assert(not paths.isNamespaceInitialized('abyssea')) -- No fallback to shipped config.
assert(paths.writePath('Tester','main.json')==saved)
candidates=paths.candidates('Tester','main.json')
for _,p in ipairs(candidates) do
    assert(not p:find('^%./namespaces/'))
    assert(not p:find('^%./settings/namespaces/abyssea/players/'))
end
children['settings/namespaces/']={'custom','abyssea'}
names=paths.listNamespaces()
assert(table.concat(names,',')=='custom') -- Uninitialized user copy shadows bundled listing.
disk['./settings/namespaces/abyssea/.nsconfig']='{}'
names,_,bundled=paths.listNamespaces()
assert(table.concat(names,',')=='abyssea,custom' and not bundled.abyssea)
print('PASS: bundled lookup/listing, explicit inheritance, read-only selection, whole namespace shadowing and stable personal writes')
