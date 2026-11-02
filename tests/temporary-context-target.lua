local file=assert(io.open('lib/action-context.lua'))
local source=file:read('*a'); file:close()
local body=assert(source:match('createTemporary = function%((.-)\n    end,\n    create ='))
local factory=assert(loadstring('return function('..body..'\nend'))
local mobs={me={id=1},bt={id=2,spawn_type=16},t={id=3,spawn_type=16}}
local environment=setmetatable({
    settings={},globals={},SPAWN_TYPE_MOB=16,
    windower={ffxi={get_player=function() return {id=1} end,
        get_mob_by_target=function(name) return mobs[name] end,
        get_party=function() return {} end}},
    makeActionContext=function(_,_,target) return {bt=target} end,
},{__index=_G})
setfenv(factory,environment)
local create=factory()
assert(create().bt==mobs.bt)
local selected={id=4,spawn_type=16}
environment.globals.target={mob=function() return selected end}
assert(create().bt==selected)
environment.globals.target={mob=function() return nil end}
assert(create().bt==mobs.bt)
mobs.bt=nil
assert(create().bt==nil) -- Cursor alone does not establish a battle target.
mobs.bt={id=5,spawn_type=1}
assert(create().bt==nil)
print('PASS: temporary contexts retain automation target and fall back to Windower battle target, never cursor')
