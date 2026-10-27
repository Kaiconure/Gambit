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
assert(actions._availableSlots.emergency.battle and actions._availableSlots.emergency.idle)
assert(actions._availableSlots['battle-setup'].battle)
assert(actions._availableSlots['mounted-fallback'].mounted)
assert(actions._availableSlots['battle-setup'].battle < actions._availableSlots.emergency.battle)
assert(actions._availableSlots.emergency.battle < actions._availableSlots['battle-fallback'].battle)
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
local executableTypes={'loading','battle','idle_battle','pull','idle','resting','event','dead','mounted'}
local automatic={contributions={}}
for _, kind in ipairs(executableTypes) do
    automatic[kind]={{commands={'normal()'}}}
    for _, suffix in ipairs({'setup','priority','fallback'}) do
        automatic.contributions[kind .. '-' .. suffix]={{commands={suffix .. '()'}}}
    end
end
load('Tester',automatic,player,'entry')
for _, kind in ipairs(executableTypes) do
    assert(#automatic[kind]==4)
    assert(automatic[kind][1].commands[1]=='setup()')
    assert(automatic[kind][2].commands[1]=='priority()')
    assert(automatic[kind][3].commands[1]=='normal()')
    assert(automatic[kind][4].commands[1]=='fallback()')
end
assert(#automatic.imports==0 and #automatic.functions==0)
documents.nativeHooks={actions={{commands={'imported()'}}}}
local explicit={battle={{import='nativeHooks'},{slot='battle-priority',precondition='guard()'}},
    contributions={['battle-priority']={{commands={'priority()'}}},
        ['battle-setup']={{commands={'setup()'}}},['battle-fallback']={{commands={'fallback()'}}}}}
load('Tester',explicit,player,'entry')
assert(#explicit.battle==4 and explicit.battle[1].commands[1]=='setup()')
assert(explicit.battle[2].commands[1]=='imported()' and explicit.battle[3].commands[1]=='priority()')
assert(preconditions.collect(explicit.battle[3])[1].expression=='guard()')
local absent={contributions={['battle-setup']={{commands={'absent-section()'}}}}}
load('Tester',absent,player,'entry')
assert(#absent.battle==1 and absent.battle[1].commands[1]=='absent-section()')
local placeholders={battle={{slots={'battle-setup',{'battle-priority','alternative'}}}},imports={},functions={}}
slots.addAutomatic(placeholders,{'battle','imports','functions'})
slots.addAutomatic(placeholders,{'battle','imports','functions'})
assert(#placeholders.battle==2 and placeholders.battle[2].slot=='battle-fallback')
assert(#placeholders.imports==0 and #placeholders.functions==0)
print('PASS: automatic hooks in every executable section, missing sections, explicit placement, imports and idempotence')
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
local function optionalTest(definitions, expectedWarnings, expectedActions)
    local container={battle={{slot='present'}}}
    local notices={}
    local instance=slots.new(container,function() return 1 end,function(message) notices[#notices+1]=message end,
        function(required) return require('./lib/target-selectors').matchesPlayer({name='Tester',main_job='BLM'},required) end)
    for index, definition in ipairs(definitions) do instance.collect({contributions=definition},tostring(index)) end
    instance.expand({'battle'})
    assert(#notices==expectedWarnings)
    assert(#container.battle==(expectedActions or 0))
end
optionalTest({{['present,missing']={optional=true,actions=command('optional')}}},0,1)
optionalTest({{missing={optional=true,actions={}}}},0)
optionalTest({{missing={actions={}}}},1)
optionalTest({{missing={optional=false,actions={}}}},1)
optionalTest({{missing={}}},1)
optionalTest({{missing={optional=true,actions={}}},{missing={}}},1)
optionalTest({{['^missing']={}},{missing={optional=true,actions={}}}},0)
optionalTest({{['!missing']={optional=true,actions={}}},{missing={}}},0)
for _, invalid in ipairs({{optional=true},{optional='true',actions={}},
    {optional=true,actions='bad'},{optional=true,actions={},silent=true},
    {optional=true,actions={named='bad'}}}) do
    assert(not pcall(optionalTest,{{missing=invalid}},0))
end
print('PASS: optional contribution objects, aliases, mixed warnings, replacements, fallbacks and invalid objects')
optionalTest({{missing={required_for={'BLM','GEO'},actions={}}}},1)
optionalTest({{missing={required_for={'WAR'},actions={}}}},0)
optionalTest({{missing={optional=true,required_for={'mages'},actions={}}}},1)
optionalTest({{missing={required_for={'*','~BLM'},actions={}}}},0)
optionalTest({{['present,missing']={required_for={'BLM'},actions=command('required')}}},0,1)
optionalTest({{['absent,missing']={required_for={'BLM'},actions={}}}},2)
for _, required in ipairs({'BLM', {true}, {named='BLM'}, {''}}) do
    assert(not pcall(optionalTest,{{missing={required_for=required,actions={}}}},0))
end
print('PASS: required_for job/group selectors, exclusions, optional override and shared-slot satisfaction')
-- Use actual generated common-file ordering with the real import/variable loader.
for path in pairs(documents) do documents[path]=nil end
local paths=dofile('lib/settings-paths.lua')
local selectors=require('./lib/target-selectors')
env.settingsPaths.commonFiles=function(name,job)
    return paths.commonFiles(name,job,selectors.entryPointGroups(job))
end
documents['./actions/lib/common/common.json']={vars={choice='default',inverse_default='default'}}
documents['./actions/lib/common/(~mages).json']={vars={choice='inverse',positive='inverse',inverse_default='inverse',['!explicit']='inverse'}}
documents['./actions/lib/common/(melee).json']={vars={choice='positive',positive='positive',explicit='positive'}}
documents['./actions/lib/common/PLD.json']={vars={choice='job',explicit='job'}}
local layered={}
load('Tester',layered,{name='Tester',main_job='PLD',main_job_level=99},'entry')
assert(layered.vars.choice=='job')
assert(layered.vars.positive=='positive')
assert(layered.vars.inverse_default=='inverse')
assert(layered.vars.explicit=='inverse')
documents['./actions/lib/common/(~mages).json'].vars.layer='global-inverse'
documents['./actions/lib/common/PLD.json'].vars.layer='global-job'
documents['./settings/Tester/actions/lib/common/(~mages).json']={vars={layer='character-inverse'}}
local scoped={}
load('Tester',scoped,{name='Tester',main_job='PLD',main_job_level=99},'entry')
assert(scoped.vars.layer=='character-inverse')
print('PASS: common imports layer job over positive over inverse over defaults, preserve explicit priorities and character scope')
env.settingsPaths.commonFiles=function() return {} end
documents['ordered-block']={actions={{commands={'block-first()'}},{commands={'block-second()'}}}}
local prioritized={battle={{commands={'before-slot()'}},{slot='ordered'},{commands={'after-slot()'}}},
    contributions={ordered={
        {commands={'normal-first()'}},
        {priority='low',commands={'low()'}},
        {priority='high',import='ordered-block'},
        {priority=0,commands={'normal-second()'}},
        {priority=-100,commands={'high-tie()'}},
        {priority=-2000,commands={'numeric-first()'}},
    }}}
load('Tester',prioritized,player,'entry')
local expected={'before-slot()','numeric-first()','block-first()','block-second()',
    'high-tie()','normal-first()','normal-second()','low()','after-slot()'}
assert(#prioritized.battle==#expected)
for i, command in ipairs(expected) do
    assert(prioritized.battle[i].commands[1]==command, 'Priority ordering failed at '..i)
    assert(prioritized.battle[i].priority==nil)
end
assert(prioritized._availableSlots.ordered.battle)
for _, invalid in ipairs({'urgent','100',true,math.huge,-math.huge,0/0}) do
    local invalidActions={battle={{slot='ordered'}},contributions={ordered={{priority=invalid,commands={'bad()'}}}}}
    assert(not pcall(load,'Tester',invalidActions,player,'entry'))
end
local replacement= {battle={{slot='ordered'}},contributions={['!ordered']={{commands={'retained()'}}}}}
documents['discarded-priority']={contributions={ordered={{priority='highest',commands={'discarded()'}}}}}
replacement.imports={{import='discarded-priority'}}
load('Tester',replacement,player,'entry')
assert(#replacement.battle==1 and replacement.battle[1].commands[1]=='retained()')
print('PASS: stable numeric/alias priorities, contiguous imported blocks, slot boundaries, replacement selection and validation')
