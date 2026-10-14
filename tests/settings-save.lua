local f=assert(io.open('lib/settings.lua'));local source=f:read('*a');f:close()
local helpers=assert(source:match('(local lastSavedSettings.-)local function firstSettingsPath'))
local save=assert(source:match('(function saveSettings.-)\n%-%-%-%-'))
local function copy(v)
    if type(v)~='table' then return v end
    local out={}; for k,x in pairs(v) do out[k]=copy(x) end; return out
end
local writes=0
local env=setmetatable({
    json={stringify=copy,parse=copy},
    windower={ffxi={get_player=function() return {name='Player'} end}},
    getSettingsFileName=function() return 'main.json' end,
    settingsPaths={getLoadedNamespace=function() return nil end},
    writeJsonToFile=function(_,v) writes=writes+1; assert(v.actions==nil) end,
}, {__index=_G})
local chunk=assert(loadstring(helpers .. save .. '\nreturn function(value) lastSavedSettings=settingsSnapshot(value) end'))
setfenv(chunk,env)
local seed=chunk()
env.settings={strategy='nearest',nested={distance=5},actions={}}
seed(env.settings)
assert(env.saveSettings()==false and writes==0)
env.settings.actions.changed=true
assert(env.saveSettings()==false and writes==0)
env.settings.nested.distance=6
assert(env.saveSettings()==true and writes==1)
assert(env.saveSettings()==false and writes==1)
assert(env.saveSettings(nil,true)==true and writes==2)
print('PASS: unchanged loads do not save, nested changes save once, explicit force saves')
