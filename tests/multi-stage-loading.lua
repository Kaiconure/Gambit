windower={addon_path='',dir_exists=function(path) return path=='settings/.ns' end}
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
        commonFiles=function() return {'./settings/.ns/base/common.json','./settings/.ns/child/common.json'} end,
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
local player = {name='Tester',main_job='RDM',main_job_level=99}
local function readJson(path)
    local f=assert(io.open(path)); local text=f:read('*a'); f:close()
    return require('./lib/jsonlua').parse(text)
end
env.settingsPaths.commonFiles=function() return {} end
documents['staged']=readJson('settings/_ns/_base/actions/lib/ws/staged/four-part-light.json')
documents['ws/multi-stage']=readJson('actions/lib/ws/multi-stage.json')
documents['ws/common']={}
documents['ws/terminal-reset']={}
documents['macros/skillchaining']={}
local actions={battle={{import='staged'}}}
load('Tester', actions, player, 'entry')
assert(actions.loading[1].name=='multi-stage-overrides')
assert(actions.loading[2].name=='multi-stage-compile')
assert(actions.vars.ws.multi_stage_settings.default.participants[1]=='melee')
print('PASS: real nested import loader preserves multi-stage preset and loading action order')
