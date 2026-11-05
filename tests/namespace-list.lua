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
    directories['addon/settings/namespaces/'..relative]=true
    children['addon/settings/namespaces/'..relative..'/']=entries or {}
    if configured then configs['./settings/namespaces/'..relative..'/.nsconfig']=true end
end
directories['addon/settings/namespaces']=true
children['addon/settings/namespaces/']={'Zeta','sortie','_base','group','actions','players','.git','foo','_foo','readme.txt'}
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
configs['./settings/namespaces/_base/.nsconfig']={abstract=true}
configs['./settings/namespaces/sortie/.nsconfig']={abstract=false}
local names, abstract=paths.listNamespaces()
assert(abstract.base and not abstract.sortie and not abstract['sortie/a'])
assert(table.concat(names,',')=='_foo,base,foo,group/child,sortie,sortie/a,sortie/ghatjot,Zeta')
assert(not visits['addon/settings/namespaces/actions/'] and not visits['addon/settings/namespaces/players/'])
assert(not visits['addon/settings/namespaces/.git/'])
for _, name in ipairs(names) do assert(paths.namespaceExists(name)) end
directories['addon/settings/namespaces']=nil
for _, oldRoot in ipairs({'ns','_ns','.ns'}) do
    directories['addon/settings/'..oldRoot]=true
    children['addon/settings/'..oldRoot..'/']={'legacy'}
    directories['addon/settings/'..oldRoot..'/legacy']=true
    configs['./settings/'..oldRoot..'/legacy/.nsconfig']=true
end
assert(#paths.listNamespaces()==0)
print('PASS: namespace discovery, aliases, collisions, reserved folders and removed roots')