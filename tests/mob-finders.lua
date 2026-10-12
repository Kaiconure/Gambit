local f = assert(io.open('lib/action-context.lua')); local source = f:read('*all'); f:close()
source = source:gsub("('[^'\r\n]*'):format", '(%1):format'):gsub('("[^"\r\n]*"):format', '(%1):format')
local body = assert(source:match('(local function matchesMobIdentifier.-)\n    %-%-%-%-'))
body = body .. '\n' .. assert(source:match('(context%.findMobs = function.-)\n    %-%-%-%-'))
local context = {}
local claims = {}
local partyInfo = dofile('lib/party-info.lua')
partyInfo.p_by_id[10] = {}
partyInfo.a1_by_id[11] = {}
local sharedClaim = false
setfenv(partyInfo.canShareClaim, setmetatable({hasBuff=function() return sharedClaim end}, {__index=_G}))
local function mobs()
    return {
        {id=100,index=1,name='Alpha',distance=100,spawn_type=16,valid_target=true,hpp=100,status=1},
        {id=200,index=2,name='Beta',distance=25,spawn_type=16,valid_target=true,hpp=100,status=0,claim_id=claims[200]},
        {id=300,index=3,name='Alpha',distance=900,spawn_type=16,valid_target=true,hpp=100,status=1},
    }
end
local env = setmetatable({context=context, SPAWN_TYPE_MOB=16, STATUS_ENGAGED=1,
    partyInfo=partyInfo,
    executionFactory=dofile('lib/execution-factory.lua'),
    windower={ffxi={get_mob_array=mobs}}, settings={verbosity=0}, VERBOSITY_DEBUG=9,
    actionStateManager={getBuffsForMob=function() return {} end},
    varargs=function(args) if #args==1 and type(args[1])=='table' then return args[1] end return args end,
    arrayAppend=function(t,v) t[#t+1]=v end,
}, {__index=_G})
local chunk=assert(loadstring(body));setfenv(chunk,env);chunk()
assert(context.findMob(100,20).id==100)
assert(context.findMob(1,20)==nil) -- Index is no longer an ID selector.
assert(context.findMob({'ALPHA',200},20).id==200)
assert(context.findMob({'Alpha',200},20,true).id==100)
assert(context.findMob({},20)==nil)
assert(context.findMob(300,20)==nil)
assert(context.findMob('alpha',20).distance==10)
assert(#context.findMobs(20,{'ALPHA',200})==2)
assert(#context.findMobs(20,100,'beta')==2)
assert(context.findMobs(20,1)==nil)
assert(#context.findMobs('ALPHA')==2)
assert(#context.findMobs()==3)
assert(#context.findMobs({20,100,'Beta'})==2)
context.hasEffectOf = function(mob, effect)
    assert(type(mob.buffs)=='table' and effect=='Silence')
    return mob.id==200
end
context.limit = 15
assert(context.findMobWhere({'Alpha','Beta'}, "not hasEffectOf(mob, 'Silence') and distance < limit",20).id==100)
assert(context.mob.id==100)
assert(context.findMobWhere({'Alpha','Beta'}, 'mob.id == 200',20).id==200)
assert(context.findMobWhere({'Alpha','Beta'}, 'mob.id == 200',20,true)==nil)
assert(context.findMobWhere('Alpha', 'false',50)==nil)
assert(context.findMobWhere({}, 'true',50)==nil)
assert(not pcall(context.findMobWhere, 'Alpha', 'missing.field',20))
assert(not pcall(context.findMobWhere, 'Alpha', 'invalid +',20))
assert(not pcall(context.findMobWhere, 'Alpha', '',20))
assert(not pcall(context.findMobWhere, 'Alpha', nil,20))
print('PASS: predicate context, buffs, distance units, nearest accepted candidate, errors and empty results')
context.bt = {id=100}
assert(context.findMob('BT',20).id==100)
assert(context.findMob({'bt',200},20).id==200)
assert(context.findMobWhere({'bt',200}, "not hasEffectOf(mob, 'Silence')",20).id==100)
assert(context.findMobWhere('bt','false',20)==nil)
assert(#context.findMobs(20,{'bt','Alpha'})==1) -- No duplicate result.
context.bt = {id=200}
assert(context.findMob('bt',20).id==200) -- Resolve current target each call.
assert(context.findMob('bt',20,true)==nil)
context.bt = {id=300}
assert(context.findMob('bt',20)==nil)
context.bt = nil
assert(context.findMob('bt',20)==nil)
assert(context.findMob({'bt','Beta'},20).id==200)
assert(context.findMobs(20,'bt')==nil)
context.bt = {}
assert(context.findMob('bt',20)==nil)
print('PASS: battle-target selector, mixed lists, dynamic resolution, filters and missing target')
claims[200] = 999
assert(context.findMob({'Alpha','Beta'},20).id==100)
assert(context.findMobWhere({'Alpha','Beta'},'true',20).id==100)
assert(context.findMobWhere('Beta','missing.field',20)==nil) -- Excluded before predicate.
assert(#context.findMobs(20,{'Alpha','Beta'})==1)
context.bt={id=200}
assert(context.findMob('bt',20)==nil)
for _, claim in ipairs({0,10,11}) do
    claims[200]=claim
    assert(context.findMob('Beta',20).id==200)
    assert(context.findMobWhere('Beta','true',20).id==200)
    assert(#context.findMobs(20,'Beta')==1)
end
claims[200]=999
sharedClaim=true
assert(context.findMob('Beta',20).id==200)
assert(#context.findMobs(20,'Beta')==1)
print('PASS: outsider claims excluded, party/alliance/unclaimed and shared-claim exceptions accepted')
print('PASS: nearest mixed names/IDs, radius, engaged filter, index rejection, findMobs calling conventions')
