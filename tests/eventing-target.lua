local file=assert(io.open('lib/eventing.lua'))
local source=file:read('*a'); file:close()
local helper=assert(source:match('(local function isMyBattleTarget%(%s*id%s*%).-\nend)'))
local targets={}
local environment=setmetatable({SPAWN_TYPE_MOB=16,windower={ffxi={
    get_mob_by_target=function(name) return targets[name] end,
}}},{__index=_G})
local chunk=assert(loadstring(helper..'\nreturn isMyBattleTarget'))
setfenv(chunk,environment)
local matches=chunk()
assert(not matches(10))
targets.t={id=10,spawn_type=16}
assert(matches(10))
targets.bt={id=20,spawn_type=16}
assert(matches(20))
assert(not matches(30))
targets.t={id=10,spawn_type=1}
assert(not matches(10))
assert(matches(20))
print('PASS: skillchain target helper remains local and handles cursor/battle targets and missing targets')
