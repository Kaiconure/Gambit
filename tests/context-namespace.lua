local file=assert(io.open('lib/action-context.lua'))
local source=file:read('*a'); file:close()
local fields=assert(source:match('gambit = ({.-\n        }),'))
local current='boss/vagary'
local env={globals={},settings={},settingsPaths={getLoadedNamespace=function() return current end}}
local context=assert(loadstring('return '..fields)); setfenv(context,env)
local Config=require('./lib/ux/status-config')
local entry=Config.defaults.tracking.sets.default[2]
assert(entry.name=='Namespace')
local display=assert(loadstring('return '..entry.expression[1]))
setfenv(display,{gambit=context()})
assert(display()=='boss/vagary')
current=nil
setfenv(display,{gambit=context()})
assert(display()=='(base settings)')
print('PASS: loaded namespace context and default tracking fallback')
