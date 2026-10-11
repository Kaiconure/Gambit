local selectors = require('./lib/target-selectors')
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
