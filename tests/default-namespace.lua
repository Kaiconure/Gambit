local f=assert(io.open('lib/settings.lua')); local source=f:read('*a'); f:close()
local helpers=assert(source:match('(local lastSavedSettings.-)local function firstSettingsPath'))
local loader=assert(source:match('(function loadSettings%(.-)\nfunction saveSettings'))
local saver=assert(source:match('(function saveSettings.-)\n%-%-%-%-'))
local function copy(v)
    if type(v)~='table' then return v end
    local out={}; for k,x in pairs(v) do out[k]=copy(x) end; return out
end
local base='./settings/Player/main.json'
local disk={[base]={default_namespace='fight', distance=18, nested={keep=true}}}
local player={name='Player',main_job='PLD'}
local paths=dofile('lib/settings-paths.lua')
windower={addon_path='',dir_exists=function(path) return path=='settings/.ns' or path=='settings/.ns/fight' end}
paths.ensureNamespaceFolders=function() return true end
local messages={}
local env=setmetatable({
    settingsPaths=paths, json={parse=copy,stringify=copy},
    files={new=function(path) return {
        exists=function() return disk[path]~=nil end,
        read=function() return copy(disk[path]) end,
    } end},
    windower={addon_path='',ffxi={get_player=function() return player end},
        dir_exists=function(path) return path=='settings/.ns/fight' end},
    writeJsonToFile=function(path,value) disk[path]=copy(value) end,
    writeMessage=function(message) messages[#messages+1]=message end,
    print=function(message) messages[#messages+1]=message end,
    text_green=function(value) return value end,
    text_job=function(value) return value end,
    text_namespace=function(value) return value end,
    getSettingsFileName=function() return base end,
    loadSettingsInternal=function() return {distance=5} end,
}, {__index=_G})
local chunk=assert(loadstring(helpers..loader..saver)); setfenv(chunk,env); chunk()
env.loadSettings()
assert(paths.getNamespace()=='fight' and paths.getLoadedNamespace()=='fight')
env.reportLoadedSettings()
assert(messages[#messages] == 'Gambit: Settings loaded from namespace: fight')
disk[base].default_namespace='missing'
player.main_job='DRG'
env.loadSettings()
assert(paths.getLoadedNamespace()=='fight') -- Job change does not reread preference.
env.resetNamespaceStartup()
env.loadSettings()
assert(paths.getNamespace()==nil and paths.getLoadedNamespace()==nil)
assert(disk[base].default_namespace=='missing')
env.saveDefaultNamespace('fight')
assert(disk[base].distance==18 and disk[base].nested.keep)
env.saveSettings({distance=6},true)
assert(disk[base].default_namespace=='fight') -- Ordinary saves preserve preference.
env.saveDefaultNamespace(nil)
assert(disk[base].default_namespace==nil and disk[base].distance==6)
disk[base]='malformed'
assert(not pcall(env.saveDefaultNamespace,'fight'))
assert(disk[base]=='malformed')
disk[base]=nil
env.saveDefaultNamespace('fight')
assert(disk[base].default_namespace=='fight' and disk[base].distance==nil)
print('PASS: startup, job changes, missing namespace fallback, isolated persistence, clear and malformed-file protection')
