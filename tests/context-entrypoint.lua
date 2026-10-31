local file=assert(io.open('lib/action-context.lua')); local source=file:read('*a'); file:close()
local fields=assert(source:match('(            entrypoint = .-),\n            last_ability'))
local factory=assert(loadstring('return function() return { '..fields..' } end'))
local settings={}
local env={settings=settings,settingsPaths=require('./lib/settings-paths')}
setfenv(factory,env)
local context=factory()
assert(context().entrypoint==nil and context().entrypoint_name==nil)
settings.actionInfo={name='pld',fileName='.\\settings\\Carbonite\\actions\\pld.json'}
local result=context()
assert(result.entrypoint=='pld')
assert(result.entrypoint_path==settings.actionInfo.fileName)
assert(result.entrypoint_name=='./settings/Carbonite/actions/pld')
assert(result.entrypoint_relative=='settings/Carbonite/actions/pld.json')
settings.actionInfo={name='pld',fileName='./settings/_ns/boss/_vagary/players/Carbonite/actions/pld.json'}
assert(context().entrypoint_relative=='players/Carbonite/actions/pld.json')
settings.actionInfo.fileName='./settings/.ns/_base/actions/pld.json'
assert(context().entrypoint_relative=='actions/pld.json')
settings.actionInfo={name='other',fileName='./actions/other.JSON'}
assert(context().entrypoint_name=='./actions/other')
assert(context().events==nil and context().events_relative==nil)
env.eventPath='./settings/_ns/boss/_vagary/events/(mages).json'
result=context()
assert(result.events=='(mages)')
assert(result.events_path==env.eventPath)
assert(result.events_name=='./settings/_ns/boss/_vagary/events/(mages)')
assert(result.events_relative=='events/(mages).json')
assert(result.event_namespace=='boss/_vagary')
env.eventPath='.\\settings\\_ns\\xp\\players\\Carbonite\\events\\pld.json'
assert(context().events_relative=='players/Carbonite/events/pld.json')
assert(context().event_namespace=='xp')
env.eventPath='./events/common.json'
assert(context().events=='common' and context().events_relative=='events/common.json')
assert(context().event_namespace==nil)
print('PASS: entry-point context names, original paths, normalized extensionless paths and absent settings')
