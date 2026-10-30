local Config=require('./lib/events/config')
local paths={'./settings/Tester/events/pld.json','./settings/events/common.json','./events/common.json'}
local docs={
    [paths[1]]={vars={automatic=true}},
    ['./settings/Tester/events/empty.json']={},
    ['./events/empty.json']={vars={wrong=true}},
    ['./events/custom.json']={imports={'lib/shared'},vars={custom=true}},
    ['./events/lib/shared.json']={vars={imported=true}},
    ['./settings/Tester/events/pld.vars.json']={vars={personal=true}},
}
local function load(name) return Config.load(paths,function(path) return docs[path] end,nil,nil,name) end
assert(load().path==paths[1])
local empty=load('empty')
assert(empty.path=='./settings/Tester/events/empty.json' and empty.vars.personal and not empty.vars.wrong)
assert(load('empty.json').path==empty.path)
local custom=load('custom')
assert(custom.path=='./events/custom.json' and custom.vars.custom and custom.vars.imported and custom.vars.personal)
for _,name in ipairs({'missing','../empty','/empty','C:/empty','lib/../empty'}) do assert(not pcall(load,name)) end
assert(load().path==paths[1])

local Service=require('./lib/events/init')
local Paths=require('./lib/settings-paths')
Paths.setLoadedNamespace(nil,{})
local service=setmetatable({deps={
    read=function(path) return docs[path] end,
    windower={ffxi={get_player=function() return {name='Tester',id=1,main_job='PLD'} end}},
    report=function(message) error(message) end,
}}, {__index=Service})
service:reload(false,'empty'); assert(service.selectedFile=='empty' and service.runtime.config.path==empty.path)
local previous=service.runtime
assert(not pcall(service.reload,service,false,'missing') and service.runtime==previous and service.selectedFile=='empty')
service:reload() -- Full settings reload does not pass a selection.
assert(service.selectedFile==nil and service.runtime.config.path==paths[1])
print('PASS: explicit event hierarchy selection, imports/vars, validation, failed reload retention and full-reload reset')
