local session=require('./lib/session-variables')

session.reset()
assert(session.set('nyzul.floor',4)==4)
assert(session.get('nyzul.floor')==4)
local reference=session.values()

-- Action-style reloads do not replace the module-owned table.
local managerSource=assert(io.open('lib/action-state-manager.lua')):read('*a')
assert(managerSource:find('self.vars = { }',1,true))
assert(session.values()==reference and session.get('nyzul.floor')==4)

session.set('nyzul.objective','Lamps')
session.reset('nyzul')
assert(session.get('nyzul')==nil and session.values()==reference)
session.set('other.value',true)
session.reset()
assert(next(reference)==nil)

local contextSource=assert(io.open('lib/action-context.lua')):read('*a')
assert(contextSource:find('context.session=sessionVariables.values()',1,true))
assert(contextSource:find('context.setSessionVar=sessionVariables.set',1,true))
assert(contextSource:find('context.resetSessionVar=sessionVariables.reset',1,true))

print('PASS: reload-stable in-memory session variables and branch reset')
