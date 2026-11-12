local file=assert(io.open('lib/action-context.lua'))
local source=file:read('*a');file:close()
local body=assert(source:match('(context%.canUseWeaponSkill = function.-)\n    %-%-+'))
local calls={abilities=0,lookup=0,ready=0}
local context={player={vitals={tp=999}},me={},bt={distance=3},vars={}}
local skill={name='Test WS',targets={},range=6}
local env=setmetatable({context=context,
    varargs=function(args)return args end,
    windower={ffxi={get_abilities=function()calls.abilities=calls.abilities+1;return {}end}},
    findWeaponSkill=function()calls.lookup=calls.lookup+1;return skill end,
    reactions={suppresses=function()return false end},
    canUseWeaponSkill=function()calls.ready=calls.ready+1;return true end,
},{__index=_G})
local chunk=assert(loadstring(body));setfenv(chunk,env);chunk()
assert(context.canUseWeaponSkill('Test WS')==nil)
assert(calls.abilities==0 and calls.lookup==0 and calls.ready==0)
context.player.vitals.tp=1000
assert(context.canUseWeaponSkill('Test WS')==1 and context.weapon_skill==skill)
assert(calls.abilities==1 and calls.lookup==1 and calls.ready==1)
print('PASS: low TP skips candidate and ability lookups; 1000 TP retains normal selection')
