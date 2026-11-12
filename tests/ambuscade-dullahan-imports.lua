windower={addon_path='',dir_exists=function(path) return path=='settings/_namespaces' end}
local copy = require('./lib/variable-values').copy
local scopes = require('./lib/variable-scopes')
local preconditions = require('./lib/action-preconditions')
local slots = require('./lib/action-slots')
local file = assert(io.open('lib/settings.lua'))
local source = file:read('*a'); file:close()
source = source:gsub("('[^'\r\n]*'):format", '(%1):format')
local internal = source:match('(local function _loadActionImportsInternal.-)local function _expandActionMacrosToArray')
local loader = source:match('(local function loadActionImports.-)local function _expandVariable')
local documents, warnings = {}, {}
local env = setmetatable({
    variableScopes=scopes, actionPreconditions=preconditions, actionSlots=slots,
    variableLoader=require('./lib/variable-loader'),
    settingsPaths={
        getLoadedPrecedence=function() return {'child','base'} end,
        commonFiles=function() return {'./settings/_namespaces/base/common.json','./settings/_namespaces/child/common.json'} end,
        importCandidates=function(_, name) return {name} end,
    },
    targetSelectors={entryPointGroups=function() return {} end},
    firstSettingsPath=function(paths) return paths[1] end,
    files={new=function(path) return {
        exists=function() return documents[path] ~= nil end,
        read=function() return copy(documents[path]) end,
    } end},
    json={parse=function(value) return value end},
    writeWarning=function(message) warnings[#warnings+1]=message end,
    writeMessage=function(message) warnings[#warnings+1]=message end,
    text_action=tostring, text_gold=tostring, text_number=tostring,
    _processMacros=function() end,
}, {__index=_G})
local chunk = assert(loadstring(internal .. loader .. '\nreturn loadActionImports'))
setfenv(chunk, env)
local load = chunk()
env.arrayIndexOf=function(values,value) for i,v in ipairs(values) do if v==value then return i end end end
env.useArray=function(value) if type(value)=='table' then return value end return {value} end
local root='settings/_namespaces/ambuscade/dullahan/'
local json=require('./lib/jsonlua')
local function read(path)
    local f=io.open(path); if not f then return end
    local source=f:read('*a'); f:close(); return json.parse(source)
end
env.settingsPaths.commonFiles=function() return {} end
env.settingsPaths.importCandidates=function(_,name)
    return {root..'actions/lib/'..name..'.json','actions/lib/'..name..'.json'}
end
env.firstSettingsPath=function(paths)
    for _,path in ipairs(paths) do local f=io.open(path); if f then f:close(); return path end end
end
env.files.new=function(path) return {
    exists=function() return read(path)~=nil end,read=function() return read(path) end} end
for _,job in ipairs({'PLD','WAR','GEO','COR','BRD','WHM'}) do
    local actions=read(root..'actions/(all).json')
    load('Tester',actions,{name='Tester',main_job=job,main_job_level=99,sub_job='WHM'},'entry')
    assert(actions.vars.dullahan and #actions.battle>0)
    assert(actions.vars.dullahan.song_targets[3].id=='dd')
    if job=='COR' then assert(actions.vars.use_rolls.alignment and actions.vars.use_rolls.logic and actions.vars.use_rolls.rolls[1]=='Chaos Roll') end
end
assert(#warnings==0,table.concat(warnings,'; '))
print('PASS: real action imports expand for all six jobs, including shipped COR rolls and healer buffs')