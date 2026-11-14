local dirs={
    ['settings/_namespaces']=true,['_namespaces']=true,
    ['settings/_namespaces/example']=true,['_namespaces/example']=true,['_namespaces/base']=true,
}
windower={addon_path='',dir_exists=function(path) return dirs[path] or false end}
local Paths=dofile('lib/settings-paths.lua')
assert(Paths.namespacePath('example')=='./settings/_namespaces/example')
assert(Paths.namespacePath('gambit:example')=='./_namespaces/example')
assert(Paths.validateNamespace('gambit:example'))
assert(not Paths.validateNamespace('gambit:'))
assert(Paths.namespacePlayerRoot('gambit:example')=='./settings/_namespace-settings/example/players')
local configs={
    ['./settings/_namespaces/example']={inherits_from='gambit:example'},
    ['./_namespaces/example']={inherits_from='base'},
    ['./_namespaces/base']={},
}
local chain=Paths.resolveInheritance('example',function(name) return configs[Paths.namespacePath(name)] end,
    function(name) return configs[Paths.namespacePath(name)]~=nil end)
assert(table.concat(chain,',')=='example,gambit:example,gambit:base')
Paths.setLoadedNamespace('example',chain)
local candidates=Paths.candidates('Tester','actions/war.json')
local personal=0
for _,path in ipairs(candidates) do
    if path:find('_namespace%-settings/example/players/Tester',1) then personal=personal+1 end
end
assert(personal==1)
local layers=Paths.entryPointLayers('Tester','actions')
assert(type(layers[1])=='table' and layers[2]=='./_namespaces/example/actions'
    and layers[3]=='./_namespaces/base/actions')
local imports=Paths.importCandidates('Tester','gambit:checklists/nyzul')
assert(#imports==1 and imports[1]=='./actions/lib/checklists/nyzul.json')

local Config=require('./lib/events/config')
local candidates={'./settings/events/(all).json','./events/(all).json'}
local docs={
    ['./settings/events/(all).json']={imports={'gambit:lib/content/test'}},
    ['./settings/events/common.vars.json']={imports={'gambit:lib/content/test'}},
    ['./settings/events/lib/content/test.json']={contributions={{slot='texts.received.after',actions={{id='wrong'}}}}},
    ['./events/lib/content/test.json']={contributions={{slot='texts.received.after',actions={{id='stock'}}}}},
}
local config=Config.load(candidates,function(path)return docs[path]end)
assert(#config.rules.texts.received==1 and config.rules.texts.received[1].id=='stock')
local stockFiles=0
for _,path in ipairs(config.files) do if path=='./events/lib/content/test.json' then stockFiles=stockFiles+1 end end
assert(stockFiles==1)

local selected=Config.load(candidates,function(path)return docs[path]end,nil,nil,'gambit:lib/content/test')
assert(selected.path=='./events/lib/content/test.json')

-- A qualified action module keeps stock-only resolution for its nested imports.
do
    local source=assert(io.open('lib/settings.lua')):read('*a')
    source=source:gsub("('[^'\r\n]*'):format",'(%1):format')
    local internal=assert(source:match('(local function _loadActionImportsInternal.-)local function _expandActionMacrosToArray'))
    local loader=assert(source:match('(local function loadActionImports.-)local function _expandVariable'))
    local actionDocs={
        ['./actions/lib/outer.json']={actions={{import='inner'}}},
        ['./actions/lib/inner.json']={actions={{commands={'stock()'}}}},
        ['./settings/actions/lib/inner.json']={actions={{commands={'wrong()'}}}},
    }
    local requests={}
    local actionPaths={
        getLoadedPrecedence=function()return {}end,commonFiles=function()return {}end,
        gambitReference=Paths.gambitReference,
        importCandidates=function(_,name)
            requests[#requests+1]=name
            local stock,relative=Paths.gambitReference(name)
            return {stock and ('./actions/lib/'..relative..'.json') or ('./settings/actions/lib/'..relative..'.json')}
        end,
    }
    local copy=require('./lib/variable-values').copy
    local env=setmetatable({profiling=require('./lib/load-profile'),settingsPaths=actionPaths,
        variableScopes=require('./lib/variable-scopes'),actionPreconditions=require('./lib/action-preconditions'),
        actionSlots=require('./lib/action-slots'),variableLoader=require('./lib/variable-loader'),
        targetSelectors={entryPointGroups=function()return {}end},
        firstSettingsPath=function(values)return values[1]end,
        files={new=function(path)return {exists=function()return actionDocs[path]~=nil end,
            read=function()return copy(actionDocs[path])end}end},json={parse=function(value)return value end},
        writeWarning=function()end,writeMessage=function()end,text_action=tostring,text_gold=tostring,
        text_number=tostring,useArray=function(v)return type(v)=='table' and v or {v}end,
        arrayIndexOf=function()end,_processMacros=function()end}, {__index=_G})
    local chunk=assert(loadstring(internal..loader..'\nreturn loadActionImports'));setfenv(chunk,env)
    local actions={battle={{import='gambit:outer'}}}
    chunk()('Tester',actions,{name='Tester',main_job='WAR',main_job_level=99},'entry')
    assert(actions.battle[1].commands[1]=='stock()')
    assert(requests[1]=='gambit:outer' and requests[2]=='gambit:inner')
end
print('PASS: gambit source qualification for namespaces, inheritance, actions, event imports and event selection')
