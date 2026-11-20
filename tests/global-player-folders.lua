local directories={}
windower={addon_path='',dir_exists=function(path) return directories[path] or false end}
local paths=dofile('lib/settings-paths.lua')

assert(paths.globalPlayerRoot('Tester')=='./settings/Tester')
assert(paths.writePath('Tester','main.json')=='./settings/Tester/main.json')
assert(paths.candidates('Tester','actions/war.json')[1]=='./settings/Tester/actions/war.json')

directories['settings/players/Tester']=true
assert(paths.globalPlayerParent('Tester')=='./settings/players')
assert(paths.globalPlayerRoot('Tester')=='./settings/players/Tester')
assert(paths.writePath('Tester','main.json')=='./settings/players/Tester/main.json')
assert(paths.candidates('Tester','actions/war.json')[1]=='./settings/players/Tester/actions/war.json')
assert(paths.entryPointLayers('Tester','actions')[1]=='./settings/players/Tester/actions')
local events=paths.eventFiles('Tester','WAR',{})
assert(events[1]=='./settings/players/Tester/events/war.json')
local common=paths.commonFiles('Tester','WAR',{})
assert(common[7]=='./settings/players/Tester/actions/lib/common/common.json')
local imports=paths.importCandidates('Tester','$(PlayerLib)/buff')
assert(imports[1]=='./settings/players/Tester/actions/lib/buff.json')

-- A different character without an organized directory still uses the legacy tree.
assert(paths.globalPlayerRoot('Legacy')=='./settings/Legacy')

print('PASS: organized global player folders take precedence with legacy fallback')
