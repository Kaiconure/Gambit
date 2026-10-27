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
disk['./settings/.ns/fight/.nsconfig']={}
local player={name='Player',main_job='PLD'}
local paths=dofile('lib/settings-paths.lua')
windower={addon_path='',dir_exists=function(path) return path=='settings/.ns' or path=='settings/.ns/fight' end}
paths.ensureNamespaceFolders=function() error('Normal loads must not initialize namespaces') end
local messages={}
local abstractWarnings={}
local env=setmetatable({
    Colors={warning=1},
    writeWarning=function(message) abstractWarnings[#abstractWarnings+1]=message end,
    settingsPaths=paths, json={parse=copy,stringify=copy},
    files={new=function(path) return {
        exists=function() return disk[path]~=nil end,
        read=function() return copy(disk[path]) end,
    } end},
    windower={addon_path='',ffxi={get_player=function() return player end},
        dir_exists=function(path) return path=='settings/.ns/fight' end},
    writeJsonToFile=function(path,value) disk[path]=copy(value) end,
    writeMessage=function(message, color)
        assert(color == nil, 'Settings messages must not pass replacement counts as chat colors')
        messages[#messages+1]=message
    end,
    print=function(message) messages[#messages+1]=message end,
    text_green=function(value) return value end,
    text_gray=function(value) return value end,
    text_cornsilk=function(value) return value end,
    text_job=function(value) return value end,
    text_namespace=function(value) return value end,
    getSettingsFileName=function() return base end,
    loadSettingsInternal=function() return {distance=5} end,
}, {__index=_G})
files=env.files
local chunk=assert(loadstring(helpers..loader..saver)); setfenv(chunk,env); chunk()
env.loadSettings()
assert(paths.getNamespace()=='fight' and paths.getLoadedNamespace()=='fight')
env.reportLoadedSettings()
assert(messages[#messages] == 'Gambit: Settings loaded from namespace: fight')
local nsconfig='./settings/.ns/fight/.nsconfig'
disk[nsconfig]=nil
local missingLoaded, missingError=pcall(env.loadSettings)
assert(not missingLoaded and missingError:find('gbt ns -set fight -force',1,true))
assert(paths.getLoadedNamespace()=='fight' and disk[nsconfig]==nil)
disk[nsconfig]={}
disk[nsconfig].abstract=true
env.loadSettings()
env.reportLoadedSettings()
assert(#abstractWarnings==1 and abstractWarnings[1]:find('is abstract',1,true))
disk[nsconfig].abstract='true'
assert(not pcall(env.loadSettings))
disk[nsconfig]={}
assert(not pcall(env.loadSettings,nil,false,'missing')) -- Explicit reload override cannot create namespaces.
disk[nsconfig]={description={'Recommended jobs: BLM, WHM', 'First line\r\nSecond line'}}
env.loadSettings()
env.reportLoadedSettings()
assert(messages[#messages-2]==' Recommended jobs: BLM, WHM')
assert(messages[#messages-1]==' First line' and messages[#messages]==' Second line')
disk[nsconfig]={description='Single line'}
env.loadSettings()
env.reportLoadedSettings()
assert(messages[#messages]==' Single line')
for _, invalid in ipairs({false, 42, {'valid', false}, {text='invalid'}}) do
    disk[nsconfig]={description=invalid}
    assert(not pcall(env.loadSettings))
end
disk[nsconfig]={}
env.loadSettings()
env.reportLoadedSettings()
assert(messages[#messages]=='Gambit: Settings loaded from namespace: fight')
local originalDirExists=windower.dir_exists
windower.dir_exists=function(path)
    return originalDirExists(path) or path=='settings/.ns/parent' or path=='settings/.ns/root'
end
disk[nsconfig]={description='Child advice', inherits_from='parent'}
disk['./settings/.ns/parent/.nsconfig']={description={'Parent advice'}, inherits_from='root'}
disk['./settings/.ns/root/.nsconfig']={description='Root advice'}
env.loadSettings()
env.reportLoadedSettings()
assert(messages[#messages-5]=='Description from namespace: root' and messages[#messages-4]==' Root advice')
assert(messages[#messages-3]=='Description from namespace: parent' and messages[#messages-2]==' Parent advice')
assert(messages[#messages-1]=='Description from namespace: fight' and messages[#messages]==' Child advice')
local replayStart=#messages
env.reportNamespaceDescriptions()
assert(#messages==replayStart+6)
assert(messages[replayStart+1]=='Description from namespace: root' and messages[#messages]==' Child advice')
disk['./settings/.ns/parent/.nsconfig'].description={}
env.loadSettings()
local beforeReport=#messages
env.reportLoadedSettings()
assert(#messages==beforeReport+6) -- Load messages plus child/root blocks; empty parent skipped.
assert(messages[#messages-3]=='Description from namespace: root' and messages[#messages-2]==' Root advice')
assert(messages[#messages-1]=='Description from namespace: fight' and messages[#messages]==' Child advice')
disk['./settings/.ns/parent/.nsconfig']['!description']={'Parent override'}
env.loadSettings()
beforeReport=#messages
env.reportLoadedSettings()
assert(#messages==beforeReport+6)
assert(messages[#messages-2]==' Parent override' and messages[#messages]==' Child advice')
disk[nsconfig]['!description']='Child override'
env.loadSettings()
beforeReport=#messages
env.reportLoadedSettings()
assert(#messages==beforeReport+4 and messages[#messages]==' Child override')
disk[nsconfig]['!description']={}
env.loadSettings()
beforeReport=#messages
env.reportLoadedSettings()
assert(#messages==beforeReport+2) -- Empty override suppresses all descriptions.
disk[nsconfig]['!description']=false
assert(not pcall(env.loadSettings))
disk[nsconfig]={}
env.loadSettings()
windower.dir_exists=originalDirExists
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
disk[base].ui={other={keep=true}}
env.savePanelSettings({visible=false,tracking={current='notes',sets={notes={}}}})
assert(env.loadPanelSettings().visible==false)
assert(disk[base].ui.other.keep and disk[base].distance==6)
env.saveSettings({distance=6,ui={status_panel={visible=true}}},true)
assert(disk[base].ui.status_panel.visible==false and disk[base].ui.other.keep)

disk[base]='malformed'
assert(not pcall(env.saveDefaultNamespace,'fight'))
assert(disk[base]=='malformed')
disk[base]=nil
env.saveDefaultNamespace('fight')
assert(disk[base].default_namespace=='fight' and disk[base].distance==nil)
print('PASS: startup, job changes, missing namespace fallback, isolated persistence, clear and malformed-file protection')
