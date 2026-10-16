windower={addon_path='',dir_exists=function(path) return path=='settings/.ns' end}
local copy = require('./lib/variable-values').copy
local scopes = require('./lib/variable-scopes')
local preconditions = require('./lib/action-preconditions')
local slots = require('./lib/action-slots')
local file = assert(io.open('lib/settings.lua'))
local source = file:read('*a'); file:close()
source = source:gsub("('[^'\r\n]*'):format", '(%1):format')
local internal = source:match('(local function _loadActionImportsInternal.-)local function _expandActionMacrosToArray')
local loader = source:match('(local function loadActionImports.-)local function _expandVariable')
local documents, warnings = {}, {}
local env = setmetatable({
    variableScopes=scopes, actionPreconditions=preconditions, actionSlots=slots,
    variableLoader=require('./lib/variable-loader'),
    settingsPaths={
        getLoadedPrecedence=function() return {'child','base'} end,
        commonFiles=function() return {'./settings/.ns/base/common.json','./settings/.ns/child/common.json'} end,
        importCandidates=function(_, name) return {name} end,
    },
    targetSelectors={entryPointGroups=function() return {} end},
    firstSettingsPath=function(paths) return paths[1] end,
    files={new=function(path) return {
        exists=function() return documents[path] ~= nil end,
        read=function() return copy(documents[path]) end,
    } end},
    json={parse=function(value) return value end},
    writeWarning=function(message) warnings[#warnings+1]=message end,
    writeMessage=function(message) warnings[#warnings+1]=message end,
    text_action=tostring, text_gold=tostring, text_number=tostring,
    _processMacros=function() end,
}, {__index=_G})
local chunk = assert(loadstring(internal .. loader .. '\nreturn loadActionImports'))
setfenv(chunk, env)
local load = chunk()
local player = {name='Tester',main_job='RDM',main_job_level=99}
documents['./settings/.ns/base/common.json'] = {contributions={emergency={{commands={'base()'}}}}}
documents['./settings/.ns/child/common.json'] = {contributions={
    emergency={{import='reaction', with_vars={targets={'me'}}, precondition='child()'}},
    unused={{commands={'unused()'}}},
}}
documents.reaction = {actions={{commands={'cast()'}}}}
local actions = {
    battle={{commands={'before()'}},{slot='emergency',precondition='slot()'}, {commands={'after()'}}},
    idle={{slot='emergency'}},
}
load('Tester', actions, player, 'entry')
assert(#actions.battle == 4 and #actions.idle == 2)
assert(actions.battle[1].commands[1]=='before()')
assert(actions.battle[2].commands[1]=='cast()')
assert(actions.battle[3].commands[1]=='base()')
assert(actions.battle[4].commands[1]=='after()')
assert(actions.battle[2].discriminator ~= actions.idle[1].discriminator)
assert(actions.battle[2]._variableScope ~= actions.idle[1]._variableScope)
local conditions=preconditions.collect(actions.battle[2])
assert(#conditions==2 and conditions[1].expression=='slot()' and conditions[2].expression=='child()')
assert(#warnings==1 and warnings[1]:find('unused'))
assert(actions._slots==nil)
local repeated={battle={{slot='emergency'},{slot='emergency'}}}
load('Tester',repeated,player,'entry')
assert(#repeated.battle==4)
assert(repeated.battle[1].discriminator ~= repeated.battle[3].discriminator)
local state=scopes.build({}, {}, repeated._variableScopes)
local first=state.view(function() return repeated.battle[1]._variableScope end)
local second=state.view(function() return repeated.battle[3]._variableScope end)
first.targets[1]='Changed'
assert(second.targets[1]=='me')
-- A scope on the defining import is cloned for each slot occurrence as well.
documents.provider={contributions={scoped={{commands={'scope()'}}}}}
local inherited={
    imports={{import='provider',with_vars={value={number=1}},precondition='provider()'}},
    battle={{slot='scoped'},{slot='scoped'}},
}
load('Tester',inherited,player,'entry')
assert(inherited.battle[1]._variableScope ~= inherited.battle[2]._variableScope)
assert(preconditions.collect(inherited.battle[1])[1].expression=='provider()')
documents.reaction = {actions={{slot='emergency'}}}
assert(not pcall(load, 'Tester', {battle={{slot='emergency'}}},player,'entry'))
documents.reaction = {contributions={other={{commands={'bad()'}}}}}
assert(not pcall(load, 'Tester', {battle={{slot='emergency'}}},player,'entry'))
documents['./settings/.ns/child/common.json']=nil
documents['./settings/.ns/base/common.json']=nil
local empty={battle={{slot='empty'},{commands={'ok()'}}}}
load('Tester',empty,player,'entry')
assert(#empty.battle==1 and empty.battle[1].commands[1]=='ok()')
print('PASS: real import loader slot placement, namespace priority, repeated instances, scopes, conditions, warnings and recursion rejection')
for _, placeholder in ipairs({
    {slots={'burst','nuke','burst'}},
    {slot={'burst','nuke','burst'}},
    {slot='burst',slots={'nuke','burst'}},
    {slot={'burst','nuke'},slots='burst'},
}) do
    placeholder.precondition='ready()'
    local chain={battle={placeholder},contributions={
        burst={{commands={'burst()'},with_vars={value=1}}},
        nuke={{commands={'nuke()'}}},
    }}
    load('Tester',chain,player,'entry')
    assert(#chain.battle==3)
    assert(chain.battle[1].commands[1]=='burst()' and chain.battle[2].commands[1]=='nuke()')
    assert(chain.battle[3].commands[1]=='burst()')
    assert(chain.battle[1]._variableScope ~= chain.battle[3]._variableScope)
    for _, action in ipairs(chain.battle) do
        assert(preconditions.collect(action)[1].expression=='ready()')
    end
end
local emptyChain={battle={{slots={}},{commands={'ok()'}}}}
load('Tester',emptyChain,player,'entry')
assert(#emptyChain.battle==1)
for _, invalid in ipairs({false, 1, {''}, {'good',false}, {name='bad'}}) do
    assert(not pcall(load,'Tester',{battle={{slots=invalid}}},player,'entry'))
end
documents.nested={actions={{slots={'nested'}}}}
assert(not pcall(load,'Tester',{
    battle={{slots='test'}},contributions={test={{import='nested'}}},
},player,'entry'))
assert(not pcall(load,'Tester',{
    battle={{slots='test'}},contributions={test={{slots={'nested'}}}},
},player,'entry'))
print('PASS: slot aliases, ordered arrays, repeated scopes, empty arrays, validation and nested-slot rejection')
local function fallback(specific)
    local result={battle={{slots={{'geo/burst','burst'},'nuke'}}},contributions={
        ['geo/burst']=specific, burst={{commands={'generic()'}}}, nuke={{commands={'nuke()'}}},
    }}
    local count=#warnings
    load('Tester',result,player,'entry')
    assert(#warnings==count)
    return result.battle
end
local selected=fallback(nil)
assert(#selected==2 and selected[1].commands[1]=='generic()')
selected=fallback({{commands={'specific()'},precondition='false'}})
assert(#selected==2 and selected[1].commands[1]=='specific()')
assert(preconditions.collect(selected[1])[1].expression=='false')
selected=fallback({})
assert(#selected==1 and selected[1].commands[1]=='nuke()')
selected=fallback({{commands={'disabled()'},disabled=true}})
assert(#selected==1 and selected[1].commands[1]=='nuke()')
local missing={battle={{slot={{'missing','absent'},{}},slots='last'}},
    contributions={last={{commands={'last()'}}}}}
load('Tester',missing,player,'entry')
assert(#missing.battle==1 and missing.battle[1].commands[1]=='last()')
for _, invalid in ipairs({{{'good',false}}, {{' '}}, {{{'too-deep'}}}, {{name='bad'}}}) do
    assert(not pcall(load,'Tester',{battle={{slots=invalid}}},player,'entry'))
end
documents['./settings/.ns/base/common.json']={contributions={['geo/burst']={{commands={'parent()'}}}}}
documents['./settings/.ns/child/common.json']={contributions={['geo/burst']={}}}
selected=fallback(nil)
assert(#selected==2 and selected[1].commands[1]=='parent()')
print('PASS: ordered fallback selection, empty declarations, false preconditions, disabled actions, missing alternatives and inherited accumulation')
local function replacementTest(definitions, expected)
    local root={battle={{slots={'burst','nuke'}}}}
    local registry=slots.new(root,function(path) return slots.priority(path,{'child','base'},'Tester','GEO') end,function() end)
    for _, entry in ipairs(definitions) do registry.collect({contributions=entry[2]},entry[1]) end
    registry.expand({'battle'})
    local actual={}
    for _, action in ipairs(root.battle) do actual[#actual+1]=action.commands[1] end
    assert(table.concat(actual,',')==expected,table.concat(actual,','))
end
local function command(text) return {{commands={text}}} end
replacementTest({
    {'./settings/.ns/base/actions/lib/common/geo.json',{['!burst']=command('base')}},
    {'./settings/.ns/child/actions/lib/common/common.json',{['!burst']=command('child')}},
    {'./settings/.ns/child/actions/lib/common/geo.json',{burst=command('job')}},
},'job,child')
replacementTest({
    {'./settings/.ns/base/actions/lib/common/common.json',{burst=command('general')}},
    {'./settings/.ns/base/actions/lib/common/(mages).json',{burst=command('role')}},
    {'./settings/.ns/base/actions/lib/common/geo.json',{['!burst, !nuke']={}}},
},'')
replacementTest({
    {'./actions/lib/common/geo.json',{burst=command('shipped')}},
    {'./settings/actions/lib/common/geo.json',{['!burst']=command('shared')}},
    {'./settings/Tester/actions/lib/common/common.json',{burst=command('personal')}},
},'personal,shared')
replacementTest({
    {'./settings/actions/lib/first.json',{['!burst']=command('first')}},
    {'./settings/actions/lib/second.json',{['!burst']=command('second')}},
},'first')
replacementTest({{'./settings/actions/lib/test.json',{[' burst , !nuke ']=command('both')}}},'both,both')
for _, definitions in ipairs({{['burst,!burst']={}}, {burst={},['!burst']={}}, {['burst,']={}}, {['!']={}}}) do
    assert(not pcall(replacementTest,{{'test',definitions}},''))
end
local blank={battle={{slots={{'geo/burst','burst'}}}}}
local registry=slots.new(blank,function() return 1 end,function() end)
registry.collect({contributions={['!geo/burst']={},burst=command('fallback')}},'test')
registry.expand({'battle'})
assert(#blank.battle==0)
print('PASS: replacements, namespace/file specificity, non-namespace precedence, comma aliases and empty fallback suppression')
local near='./settings/.ns/child/actions/lib/common/geo.json'
local far='./settings/.ns/base/actions/lib/common/common.json'
for _, reverse in ipairs({false,true}) do
    local definitions={{near,{['^burst']=command('near')}},{far,{['^burst']=command('far')}}}
    if reverse then definitions[1],definitions[2]=definitions[2],definitions[1] end
    replacementTest(definitions,'near')
end
for _, prefix in ipairs({'','!'}) do
    replacementTest({{near,{['^burst']=command('default')}},{far,{[prefix..'burst']=command('explicit')}}},'explicit')
    replacementTest({{near,{['^burst']=command('default')}},{far,{[prefix..'burst']={}}}},'')
end
replacementTest({{near,{['^burst']={}}},{far,{['^burst']=command('far')}}},'')
replacementTest({{near,{[' ^burst , ^nuke ']=command('shared')}}},'shared,shared')
replacementTest({{'first',{['^burst']=command('first')}},{'second',{['^burst']=command('second')}}},'first')
for _, definitions in ipairs({{['^burst,burst']={}}, {['^burst']={},['!burst']={}}, {['^']={}}, {['!^burst']={}}, {['^^burst']={}}}) do
    assert(not pcall(replacementTest,{{'test',definitions}},''))
end
local fallbackBlank={battle={{slots={{'specific','generic'}}}}}
local fallbacks=slots.new(fallbackBlank,function() return 1 end,function() end)
fallbacks.collect({contributions={['^specific']={},generic=command('generic')}},'test')
fallbacks.expand({'battle'})
assert(#fallbackBlank.battle==0)
print('PASS: fallback contributions, explicit/empty suppression, closest defaults, aliases, ties and prefix validation')
