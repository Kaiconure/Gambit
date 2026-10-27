local selectors = require('./lib/target-selectors')
local requiredPlayer={name='Tester',main_job='GEO'}
assert(selectors.matchesPlayer(requiredPlayer,{'BLM','GEO'}))
assert(selectors.matchesPlayer(requiredPlayer,{'mages'}))
assert(not selectors.matchesPlayer(requiredPlayer,{'WAR'}))
assert(not selectors.matchesPlayer(requiredPlayer,{'*','~GEO'}))
assert(not selectors.matchesPlayer(requiredPlayer,{'^mages'}))
assert(selectors.matchesPlayer(requiredPlayer,{'leader'},true))
assert(not selectors.matchesPlayer(requiredPlayer,{'leader'},false))
local leaderParty = {
    me={id=1},
    p0={id=1,name='Self',is_party_leader=true,is_participant=true},
    p1={id=2,name='Other',is_participant=true},
}
assert(table.concat(selectors.resolve(leaderParty,'LeAdEr'),',')=='Self')
assert(#selectors.resolve(leaderParty,'^LEADER')==0)
assert(selectors.partyHasJob(leaderParty,'leader'))
assert(not selectors.partyHasJob(leaderParty,'^leader'))
leaderParty.p0.is_party_leader=false
leaderParty.p1.is_party_leader=true
assert(table.concat(selectors.resolve(leaderParty,{'^leader','Other'}),',')=='Other')
assert(selectors.partyHasJob(leaderParty,'^leader'))
leaderParty.p1.is_participant=false
assert(not selectors.partyHasJob(leaderParty,'leader'))
assert(#selectors.resolve(leaderParty,'leader')==1)
leaderParty.p1=nil
assert(#selectors.resolve(leaderParty,'leader')==0)
assert(not selectors.partyHasJob(leaderParty,'leader'))
local me, first, last = {id=1}, {id=2}, {id=3}
local members = {first, me, last}
assert(selectors.selfFirst({me={id=1}}, members) == members)
assert(members[1] == me and members[2] == first and members[3] == last)
selectors.selfFirst({me=me}, members)
assert(members[1] == me and members[2] == first and members[3] == last)
local absent = {first, last}
selectors.selfFirst({me=me}, absent)
assert(#absent == 2 and absent[1] == first and absent[2] == last)
assert(#selectors.selfFirst({me=me}, {}) == 0)
local context = {
    p0={name='Steris',main_job='RDM'},
    p1={mob={name='Carbonite'},main_job='pld'},
    p2={name='Trust',main_job='RDM'},
    p3={name='Unknown'},
    a10={name='AllianceRdm',main_job='RDM'},
}
assert(table.concat(selectors.resolve(context, {'rDm','PLD','steris','me'}), ',') == 'Steris,Trust,Carbonite,me')
assert(#selectors.resolve(context, 'BLM') == 0)
assert(table.concat(selectors.resolve(context, {'Unknown','ME','*'}), ',') == 'Unknown,ME,*')
context.p0.main_job='WHM'
context.p0.is_participant=true
local sentinel = {}
context.member = sentinel
context.action = {enumerators={member=sentinel}}
assert(selectors.partyHasJob(context, {'whm', 'SCH'}) == true)
assert(selectors.partyHasJob(context, {'HeAlErS'}) == true)
assert(selectors.partyHasJob(context, {'BLM', 'SCH'}) == false)
assert(selectors.partyHasJob(context, {'Steris', 'me', '*', 'unknown'}) == false)
assert(selectors.partyHasJob(context, {}) == false)
assert(selectors.partyHasJob({a10={main_job='WHM'}}, 'WHM') == false)
assert(context.member == sentinel and context.action.enumerators.member == sentinel)
context.p0.is_participant=false
assert(not selectors.partyHasJob(context, 'WHM'))
context.p0.is_participant=nil
assert(not selectors.partyHasJob(context, 'WHM'))
context.p4={main_job='SCH',is_participant=true}
assert(selectors.partyHasJob(context, {'WHM','SCH'}))
assert(selectors.partyHasJob(context, 'healers'))
context.p4=nil
context.p0.is_participant=true
assert(selectors.partyHasJob(context, 'WHM'))
assert(table.concat(selectors.resolve(context, 'RDM'), ',') == 'Trust')
assert(table.concat(selectors.resolve(context, {'HeAlEr','mage','RDM','Steris'}), ',') == 'Steris,Trust')
assert(table.concat(selectors.resolve(context, 'tank'), ',') == 'Carbonite')
assert(#selectors.resolve(context, 'ranged') == 0)
for _, singular in ipairs({'mage', 'healer', 'nuker', 'tank'}) do
    assert(table.concat(selectors.resolve(context, singular), ',') ==
        table.concat(selectors.resolve(context, singular:upper() .. 'S'), ','))
end
assert(table.concat(selectors.resolve(context, {'MaGeS','healers','NUKERS','Steris'}), ',') == 'Steris,Trust')
local groupCases = {
    melee={'BLU', 'WHM'}, ranged={'COR', 'BLM'}, mage={'BRD', 'COR'},
    healer={'SCH', 'DNC'}, nuker={'BLM', 'SMN'}, support={'SMN', 'PLD'}, tank={'RUN', 'WAR'},
}
for group, jobs in pairs(groupCases) do
    local party = {p0={name='Match',main_job=jobs[1]:lower()}, p1={name='Other',main_job=jobs[2]}}
    assert(table.concat(selectors.resolve(party, group:upper()), ',') == 'Match', group)
end
-- Exercise the actual expression builder, including the no-match/empty distinction.
local excluding = {
    me={id=10},
    p0={id=10,name='Self',main_job='WHM',is_participant=true},
    p1={id=11,name='Other',main_job='SCH',is_participant=true},
}
assert(#selectors.resolve(excluding, '^whm') == 0)
assert(table.concat(selectors.resolve(excluding, '^HeAlErS'), ',') == 'Other')
assert(table.concat(selectors.resolve(excluding, {'me','^mages'}), ',') == 'me,Other')
assert(table.concat(selectors.resolve(excluding, {'^mages','WHM','healers'}), ',') == 'Other,Self')
assert(not selectors.partyHasJob(excluding, '^WHM'))
assert(selectors.partyHasJob(excluding, '^healers'))
excluding.p1.is_participant=false
assert(not selectors.partyHasJob(excluding, '^healers'))
assert(selectors.partyHasJob(excluding, {'^healers','whm'}))
excluding.me=nil
excluding.p0.is_me=true
assert(#selectors.resolve(excluding, '^WHM') == 0)
local file=assert(io.open('lib/action-context.lua'))
local source=file:read('*all');file:close()
source=source:gsub("('[^'\r\n]*'):format", '(%1):format')
    :gsub('("[^"\r\n]*"):format', '(%1):format')
assert(loadstring(source))
local setupSource = assert(source:match('(local function setPartyEnumerators.-)local function setArrayEnumerators'))
local setup = assert(loadstring(setupSource .. '\nreturn setPartyEnumerators'))()
for _, name in ipairs({'partyByName', 'alliesByName'}) do
    local state = {member=me, members={me}, member_count=1,
        action={enumerators={member={data={me,first},at=1}}}}
    setup(state)
    assert(state[name]({}) == nil)
    assert(state.member == nil and #state.members == 0 and state.member_count == 0)
    assert(state.action.enumerators.member == nil)
end
local body=assert(source:match('(local function createMemberNamesExpression.-)local function setPartyEnumerators'))
local build=assert(loadstring('local targetSelectors = require("./lib/target-selectors")\n' .. body .. '\nreturn createMemberNamesExpression'))()
assert(build(context, {'BLM'}) == 'false')
assert(build(excluding, {'^WHM'}) == 'false')
assert(build(context, {'ranged'}) == 'false')
assert(build(context, {}) == 'true')
assert(build(context, {'BLM','*'}) == 'true')
assert(build(context, {'rDm'}):find('isNameMatch("trust")',1,true))
print('PASS: case-insensitive jobs, multiple matches, deduplication, passthrough, current party, no-match safety, context syntax')
local party={
    p0={id=1,name='Self',main_job='BLU',symbol='p0',symbol2='me',is_participant=true},
    p1={id=2,name='Warrior',main_job='WAR',symbol='p1',is_participant=true,is_party_leader=true},
    p2={id=3,name='Bard',main_job='BRD',symbol='p2',is_participant=true},
}
party.me=party.p0
local function selected(list, member)
    local fn=assert(loadstring('return ' .. build(party,list)))
    setfenv(fn,{isNameMatch=function(name)
        return name==member.name:lower() or name==member.symbol or name==member.symbol2
    end})
    return fn()
end
for _, list in ipairs({{'melee','~mages','Self'},{'~MAGES','Self','melee'}}) do
    assert(not selected(list,party.p0) and selected(list,party.p1))
end
assert(not selected({'~support'},party.p1))
assert(not selected({'*','~me'},party.p0))
assert(selected({'*','~me'},party.p1))
assert(not selected({'*','~leader'},party.p1))
assert(not selected({'*','~Warrior'},party.p1))
assert(not selected({'*','~p1'},party.p1))
assert(selected({'melee','~^mages'},party.p0))
assert(not selected({'*','~*'},party.p0))
assert(selectors.partyHasJob(party,{'melee','~mages'}))
assert(not selectors.partyHasJob(party,{'melee','~mages','~leader'}))
assert(not selectors.partyHasJob(party,{'~mages'}))
assert(not selected({'ranged','~mages'},party.p1))
print('PASS: final exclusions, order independence, wildcard, names, symbols, caret and presence checks')

-- Stable movement anchors use fresh selector results, not the cycling enumerator.
local candidates = {}
local anchorEnv = setmetatable({
    targetSelectors = selectors,
    createMemberNamesExpression = build,
    enumerateContextByExpression = function(_, _, expression)
        if expression == 'false' then return {} end
        return candidates
    end,
}, {__index=_G})
setfenv(setup, anchorEnv)
local anchorContext = {me={id=1}, action={}, p1={name='First',main_job='WHM'}}
setup(anchorContext)
local a = {id=2,name='Alpha',valid_target=true,distance=10,isNameMatch=function() return false end}
local b = {id=3,name='Beta',valid_target=true,distance=12,isNameMatch=function() return false end}
candidates = {a,b}
assert(anchorContext.partyAnchorByName({'WHM'}) == a)
candidates = {b,a}
assert(anchorContext.partyAnchorByName({'WHM'}) == a)
a.is_dead = true
assert(anchorContext.partyAnchorByName({'WHM'}) == b)
b.distance = 31
assert(anchorContext.partyAnchorByName({'WHM'}) == nil)
assert(anchorContext.action._memberAnchorId == nil)
a.is_dead = false
b.distance = 12
assert(anchorContext.partyAnchorByName({'WHM'}) == a)
candidates = {b}
b.distance = 30
assert(anchorContext.partyAnchorByName({'WHM'}) == b)
assert(anchorContext.partyAnchorByName({'WHM'}, 20) == nil)
assert(anchorContext.partyAnchorByName({}) == nil)
assert(anchorContext.partyAnchorByName(nil) == nil)
assert(anchorContext.partyAnchorByName({'RNG'}) == nil)
candidates = {{id=1,name='A',valid_target=true,distance=0,isNameMatch=function() return false end}, {id=4,name='D',valid_target=false,distance=1,isNameMatch=function() return false end}}
assert(anchorContext.partyAnchorByName({'WHM'}) == candidates[1])
assert(anchorContext.partyAnchorByName({'WHM'}, 30, true) == nil)
candidates = {candidates[1], a}
assert(anchorContext.partyAnchorByName({'WHM'}) == candidates[1])
assert(anchorContext.partyAnchorByName({'WHM'}, 30, true) == a)
assert(anchorContext.partyAnchorByName({'WHM'}, 30, false) == candidates[1])
print('PASS: stable member anchors, reselection, range, death, optional self exclusion and empty targets')

local function named(id, name, job)
    return {id=id,name=name,main_job=job,isNameMatch=function(value)
        return value == name:lower()
    end}
end
local alpha, zulu, scholar = named(10,'Alpha','WHM'), named(20,'Zulu','WHM'), named(30,'Beta','SCH')
for _, roster in ipairs({{p0=zulu,p1=scholar,p2=alpha}, {p0=alpha,p1=zulu,p2=scholar}}) do
    assert(table.concat(selectors.resolve(roster, {'WHM','SCH'}), ',') == 'Alpha,Zulu,Beta')
    local ordered = selectors.order(roster, {scholar,zulu,alpha}, {'Zulu','healers'})
    assert(ordered[1] == zulu and ordered[2] == alpha and ordered[3] == scholar)
    ordered = selectors.order(roster, {zulu,alpha,scholar}, {'WHM','SCH'})
    assert(ordered[1] == alpha and ordered[2] == zulu and ordered[3] == scholar)
    ordered = selectors.order(roster, {zulu,alpha,scholar}, {'*'})
    assert(ordered[1] == alpha and ordered[2] == scholar and ordered[3] == zulu)
end
local enumSource = assert(source:match('(local function enumerateContextByExpression.-)local function getNextMemberEnumerator'))
local enum = assert(loadstring('local targetSelectors = require("./lib/target-selectors")\n' .. enumSource .. '\nreturn enumerateContextByExpression'))()
local results = enum({p0=zulu,p1=alpha,p2=scholar}, {'p0','p1','p2'}, 'true')
assert(results[1] == alpha and results[2] == scholar and results[3] == zulu)
print('PASS: roster-independent ordering, explicit precedence, group expansion and alphabetical expression selection')

local calls = 0
local originalRandom = math.random
math.random = function(n) calls = calls + 1; return 1 end
local nextSource = assert(source:match('(local function getNextMemberEnumerator.-)local function createMemberNamesExpression'))
local nextFn = assert(loadstring(nextSource .. '\nreturn getNextMemberEnumerator'))()
setfenv(nextFn, setmetatable({windower={ffxi={get_mob_by_index=function() return {valid_target=true} end}}}, {__index=_G}))
setfenv(setup, setmetatable({
    targetSelectors=selectors, createMemberNamesExpression=build,
    enumerateContextByExpression=enum, getNextMemberEnumerator=nextFn,
    PARTY_MEMBER_FIELD_NAMES={'p0','p1','p2'}, ALL_MEMBER_FIELD_NAMES={'p0','p1','p2'},
    varargs=function(args) return type(args[1]) == 'table' and args[1] or args end,
}, {__index=_G}))
for _, method in ipairs({'partyByName','alliesByName'}) do
    local ctx={p0=zulu,p1=alpha,p2=scholar,me=zulu,action={enumerators={}}}
    setup(ctx)
    calls=0
    assert(ctx[method]({'WHM','SCH'}) == alpha)
    assert(calls == 0)
    ctx.action.enumerators={}
    assert(ctx[method]('WHM','SCH',{self_first=true}) == zulu)
    assert(calls == 0)
    ctx.action.enumerators={}
    assert(ctx[method]({'WHM','SCH'},{randomize=true,self_first=true}) == zulu)
    assert(calls == 2)
    assert(ctx[method]({'WHM','SCH'},{randomize=true,self_first=true}) == scholar)
    assert(calls == 2) -- continuing the cycle does not reshuffle
    assert(ctx[method]({}, {randomize=true}) == nil)
    assert(ctx.action.enumerators.member == nil)
end
math.random=originalRandom
print('PASS: optional shuffle/self-first, vararg and array syntax, cycle stability and empty selections')
