local directories={}
local configs={}
local children={}
local visits={}
windower={addon_path='addon/',dir_exists=function(path) return directories[path] or false end,
    get_dir=function(path) visits[path]=true; return children[path] or {} end}
files={new=function(path) return {exists=function() return configs[path] or false end,
    read=function() return configs[path] end} end}
json={parse=function(value) return value end}
local paths=dofile('lib/settings-paths.lua')
assert(#paths.listNamespaces()==0)
local function folder(relative, entries, configured)
    directories['addon/settings/_ns/'..relative]=true
    children['addon/settings/_ns/'..relative..'/']=entries or {}
    if configured then configs['./settings/_ns/'..relative..'/.nsconfig']=true end
end
directories['addon/settings/_ns']=true
children['addon/settings/_ns/']={'Zeta','sortie','_base','group','actions','players','.git','foo','_foo','readme.txt'}
folder('Zeta',{},true)
folder('_base',{},true)
folder('sortie',{'_ghatjot','a','actions'},true)
folder('sortie/_ghatjot',{},true)
folder('sortie/a',{},true)
folder('group',{'child'},false)
folder('group/child',{},true)
folder('foo',{},true)
folder('_foo',{},true)
folder('actions',{'hidden'},true)
folder('players',{'hidden'},true)
folder('.git',{'hidden'},true)
configs['./settings/_ns/_base/.nsconfig']={abstract=true}
configs['./settings/_ns/sortie/.nsconfig']={abstract=false}
local names, abstract=paths.listNamespaces()
assert(abstract.base and not abstract.sortie and not abstract['sortie/a'])
assert(table.concat(names,',')=='_foo,base,foo,group/child,sortie,sortie/a,sortie/ghatjot,Zeta')
assert(not visits['addon/settings/_ns/actions/'] and not visits['addon/settings/_ns/players/'])
assert(not visits['addon/settings/_ns/.git/'])
for _, name in ipairs(names) do assert(paths.namespaceExists(name)) end
directories['addon/settings/_ns']=nil
directories['addon/settings/.ns']=true
children['addon/settings/.ns/']={'legacy'}
directories['addon/settings/.ns/legacy']=true
configs['./settings/.ns/legacy/.nsconfig']=true
assert(table.concat(paths.listNamespaces(),',')=='legacy')
print('PASS: namespace discovery, sorting, aliases, collisions, unmarked parents, reserved folders, empty and legacy roots')
