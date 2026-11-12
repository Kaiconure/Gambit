windower={addon_path='',dir_exists=function(path) return path=='settings/namespaces' end}
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
    profiling=require('./lib/load-profile'),
    variableScopes=scopes, actionPreconditions=preconditions, actionSlots=slots,
    variableLoader=require('./lib/variable-loader'),
    settingsPaths={
        getLoadedPrecedence=function() return {'child','base'} end,
        commonFiles=function() return {'./settings/namespaces/base/common.json','./settings/namespaces/child/common.json'} end,
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
    useArray=function(value) return type(value)=='table' and value or {value} end,
    arrayIndexOf=function(array,value) for index,item in ipairs(array) do if item==value then return index end end end,
    _processMacros=function() end,
}, {__index=_G})
local chunk = assert(loadstring(internal .. loader .. '\nreturn loadActionImports'))
setfenv(chunk, env)
local load = chunk()
local player = {name='Tester',main_job='RDM',main_job_level=99}
documents['./settings/namespaces/base/common.json'] = {contributions={emergency={{commands={'base()'}}}}}
documents['./settings/namespaces/child/common.json'] = {contributions={
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
local nested={battle={{slot='other'},{slot='emergency'}}}
load('Tester',nested,player,'entry')
assert(nested.battle[1].commands[1]=='bad()') -- Definitions reach an earlier slot.
documents['./settings/namespaces/child/common.json']=nil
documents['./settings/namespaces/base/common.json']=nil
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
assert(pcall(load,'Tester',{
    battle={{slots='test'}},contributions={test={{import='nested'}}},
},player,'entry'))
assert(not pcall(load,'Tester',{
    battle={{slots='test'}},contributions={test={{slots={'test'}}}},
},player,'entry'))
print('PASS: slot aliases, ordered arrays, repeated scopes, empty arrays, validation and nested-slot recursion rejection')
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
documents['./settings/namespaces/base/common.json']={contributions={['geo/burst']={{commands={'parent()'}}}}}
documents['./settings/namespaces/child/common.json']={contributions={['geo/burst']={}}}
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
    {'./settings/namespaces/base/actions/lib/common/geo.json',{['!burst']=command('base')}},
    {'./settings/namespaces/child/actions/lib/common/common.json',{['!burst']=command('child')}},
    {'./settings/namespaces/child/actions/lib/common/geo.json',{burst=command('job')}},
},'job,child')
replacementTest({
    {'./settings/namespaces/base/actions/lib/common/common.json',{burst=command('general')}},
    {'./settings/namespaces/base/actions/lib/common/(mages).json',{burst=command('role')}},
    {'./settings/namespaces/base/actions/lib/common/geo.json',{['!burst, !nuke']={}}},
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
local near='./settings/namespaces/child/actions/lib/common/geo.json'
local far='./settings/namespaces/base/actions/lib/common/common.json'
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
optionalTest({{{slot='missing',['for']={'BLM'},actions={}}}},1)
optionalTest({{{slot='missing',['for']={'WAR'},actions={}}}},0)
optionalTest({{{slot='missing',['for']={'BLM'},optional=true,actions={}}}},1)
optionalTest({{{slot='missing',['for']={'BLM','GEO'},required_for={'GEO'},actions={}}}},0)
optionalTest({{{slot='missing',['for']={'BLM'},required_for={'WAR'},actions={}}}},0)
optionalTest({{{slot='missing',['for']={'WAR'},required_for={'BLM'},actions={}}}},0)
for _, required in ipairs({'BLM', {true}, {named='BLM'}, {''}}) do
    assert(not pcall(optionalTest,{{missing={required_for=required,actions={}}}},0))
end
print('PASS: implicit/explicit required_for selectors, filtering intersection, exclusions, optional override and shared-slot satisfaction')
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

documents['library-parent']={
    imports={{imports={'library-child'}}},
    actions={{commands={'in_place()'}}},
}
documents['library-child']={
    imports={{import='library-grandchild'}},
    vars={library_value=42},macros={library_macro={'macro()'}},
    functions={{name='library_function',commands={'function_body()'}}},
    loading={{commands={'load_body()'}}},
    actions={{commands={'must_not_enter_battle()'}}},
}
documents['library-grandchild']={functions={{name='nested_library_function',commands={'nested_body()'}}}}
for _,area in ipairs({'battle','functions'}) do
    local subject={[area]={{import='library-parent',with_vars={library_scope={value=7}},precondition='library_gate()'}}}
    load('Tester',subject,player,'entry')
    assert(subject.vars.library_value==42 and subject.macros.library_macro[1]=='macro()')
    local found={}
    for _,fn in ipairs(subject.functions) do if fn.name then found[fn.name]=fn end end
    assert(found.library_function and found.nested_library_function)
    assert(found.library_function._variableScope and found.nested_library_function._variableScope)
    local inherited=preconditions.collect(found.nested_library_function)
    assert(inherited[1].expression=='library_gate()')
    for _,action in ipairs(subject.battle) do
        assert(action.commands[1]~='must_not_enter_battle()')
    end
    if area=='battle' then assert(#subject.battle==1 and subject.battle[1].commands[1]=='in_place()') end
    assert(#subject.loading==1 and subject.loading[1].commands[1]=='load_body()')
end
documents['library-loop']={imports={{import='library-loop'}}}
assert(not pcall(load,'Tester',{imports={{import='library-loop'}}},player,'entry'))
print('PASS: library top-level imports remain non-executable, recurse across late sections, inherit scopes/preconditions, and bound cycles')

documents['short-library']={imports={'short-child',{import='library-grandchild'}},
    functions={{name='short_parent',commands={'parent()'}}}}
documents['short-child']={vars={short_value=123},functions={{name='short_child',commands={'child()'}}}}
local function shortResult(imports)
    local subject={imports=imports}
    load('Tester',subject,player,'entry')
    assert(subject.vars.short_value==123 and #subject.battle==0)
    local names={}
    for _,fn in ipairs(subject.functions) do if fn.name then names[#names+1]=fn.name end end
    return table.concat(names,',')
end
assert(shortResult({'short-library',{import='library-grandchild'}})==
    shortResult({{import='short-library'},{imports={'library-grandchild'}}}))
local scopedShort={battle={{import='short-library',with_vars={short_scope={enabled=true}},precondition='short_gate()'}}}
load('Tester',scopedShort,player,'entry')
local matched=false
for _,fn in ipairs(scopedShort.functions) do
    if fn.name=='short_child' then
        assert(fn._variableScope and preconditions.collect(fn)[1].expression=='short_gate()')
        matched=true
    end
end
assert(matched)
print('PASS: direct-string and mixed top-level imports match object ordering and preserve nested dependency scopes')

documents['inline-body']={actions={{commands={'inline_cast()'}}}}
documents['inline-library']={actions={{slot='inline-hook',actions={{import='inline-body'}}}}}
local inline={battle={{import='inline-library',precondition='inline_gate()',with_vars={inline_scope={enabled=true}}}}}
load('Tester',inline,player,'entry')
assert(#inline.battle==1 and inline.battle[1].commands[1]=='inline_cast()')
assert(inline.battle[1]._variableScope and preconditions.collect(inline.battle[1])[1].expression=='inline_gate()')
local repeatedInline={battle={{import='inline-library'},{import='inline-library'}}}
load('Tester',repeatedInline,player,'entry')
assert(#repeatedInline.battle==2) -- Same source contribution is not registered twice.
print('PASS: inline slot imports, inherited preconditions/scopes and repeated-library contribution deduplication')

-- Reproduce a role-common file's nested setup import arriving after ancestor
-- job-common vars. Proximity must win without moving the vars or using !.
env.settingsPaths.commonFiles=function()return {
 './settings/namespaces/base/actions/lib/common/whm.json',
 './settings/namespaces/child/actions/lib/common/(mages).json'}end
documents['./settings/namespaces/base/actions/lib/common/whm.json']={vars={frontline_engagement={distance=12}}}
documents['./settings/namespaces/child/actions/lib/common/(mages).json']={imports={
 './settings/namespaces/child/actions/lib/setup/use-spacing.json'}}
documents['./settings/namespaces/child/actions/lib/setup/use-spacing.json']={vars={frontline_engagement={distance=17}}}
local nestedPrecedence={}
load('Tester',nestedPrecedence,player,'./settings/namespaces/child/actions/whm.json')
assert(nestedPrecedence.vars.frontline_engagement.distance==17)
print('PASS: real import loader gives late child setup vars precedence over ancestor common vars')

env.settingsPaths.commonFiles=function()return {}end
documents['nested-provider']={vars={nested_default=17},imports={'nested-metadata'},
 actions={{commands={'provider_action()'}}},
 contributions={earlier={{import='nested-child',with_vars={nested_value=42},precondition='nested_gate()'}}}}
documents['nested-metadata']={contributions={['battle-setup']={{commands={'metadata_setup()'}}}}}
documents['nested-child']={contributions={last={{commands={'last_action()'}}}},actions={{commands={'child_action()'}}}}
local chain={battle={{slot='last'},{slot='earlier'},{slot='entry'}},pull={{slot='entry'}},
 contributions={entry={{import='nested-provider',precondition='provider_gate()'}}}}
load('Tester',chain,player,'entry')
assert(chain.vars.nested_default==17)
local counts={}
for _,a in ipairs(chain.battle)do counts[a.commands[1]]=(counts[a.commands[1]] or 0)+1 end
assert(counts['metadata_setup()']==1 and counts['last_action()']==1 and counts['child_action()']==1 and counts['provider_action()']==1)
local last
for _,a in ipairs(chain.battle)do if a.commands[1]=='last_action()' then last=a end end
local nestedState=scopes.build({}, {}, chain._variableScopes)
assert(nestedState.view(function()return last._variableScope end).nested_value==42)
local gates=preconditions.collect(last)
assert(gates[1].expression=='provider_gate()' and gates[2].expression=='nested_gate()')
assert(#chain.pull==1 and chain.pull[1].commands[1]=='provider_action()')

local function rejected(provider,definitions,extra)
 documents['cycle-provider']=provider
 local config={battle={{slot='a'},{slot='b'},{slot='c'}},contributions=definitions or {a={{import='cycle-provider'}}}}
 if extra then extra(config)end
 local ok,err=pcall(load,'Tester',config,player,'entry')
 assert(not ok and tostring(err):find('Recursive contribution'),tostring(err))
end
rejected({contributions={a={}}})
documents['cycle-child']={contributions={a={{commands={'cycle()'}}}}}
rejected({contributions={b={{import='cycle-child'}}}})
rejected({imports={'cycle-provider'}})
-- Shared providers must not hide a cycle through deduplicated definitions.
documents['cycle-shared']={contributions={b={{import='cycle-child'}}}}
documents['cycle-child']={contributions={c={{import='cycle-shared'}}}}
rejected({imports={'cycle-shared'}})
-- Cleared and unselected contributions are not traversed.
documents['cycle-provider']={contributions={a={}}}
local cleared={battle={{slot='a'}},contributions={a={{import='cycle-provider'}}},imports={{import='./settings/namespaces/child/actions/clear-a.json'}}}
documents['./settings/namespaces/child/actions/clear-a.json']={contributions={['!a']={}}}
load('Tester',cleared,player,'entry');assert(#cleared.battle==0)
local filtered={battle={{slot='a'}},contributions={a={{import='cycle-provider',disabled=true}}}}
load('Tester',filtered,player,'entry');assert(#filtered.battle==0)
print('PASS: nested contribution discovery, earlier/automatic slots, repeated imports, conditions/scopes, direct/indirect/shared/import cycles and cleared/disabled branches')
local tankFile=assert(io.open('settings/_namespaces/_base/actions/lib/tank-alignment.json'))
documents['real-tank-alignment']=require('./lib/jsonlua').parse(tankFile:read('*a'));tankFile:close()
documents['test-dynamic']={actions={{commands={'position()'}}}}
local tankSlots={battle={{slot='normal-engagement',actions={{imports={'real-tank-alignment','test-dynamic'}}}}},
 pull={{slot='normal-engagement'}}}
load('Tester',tankSlots,player,'entry')
for _,kind in ipairs({'battle','pull'})do
 assert(#tankSlots[kind]==3)
 assert(tankSlots[kind][1].commands[1]:find('Gained tank status',1,true))
 assert(tankSlots[kind][2].commands[1]:find('Lost tank status',1,true))
 assert(tankSlots[kind][3].commands[1]=='position()')
end
print('PASS: real tank-alignment contributions imported inline in engagement populate earlier setup slots exactly once')
documents['slot-scoped-provider']={contributions={destination={{commands={'scoped_destination()'}}}}}
local fromScope={battle={{slot='destination'},{slot='origin',precondition='origin_gate()',with_vars={origin_value=99}}},
 contributions={origin={{import='slot-scoped-provider'}}}}
load('Tester',fromScope,player,'entry')
assert(#fromScope.battle==1)
assert(preconditions.collect(fromScope.battle[1])[1].expression=='origin_gate()')
local originState=scopes.build({}, {}, fromScope._variableScopes)
assert(originState.view(function()return fromScope.battle[1]._variableScope end).origin_value==99)
print('PASS: nested contributions inherit the originating slot condition and variable scope')
-- Base common files own setup and movement definitions, not the entry points.
local function diskDocument(path)
 local f=assert(io.open(path));local doc=require('./lib/jsonlua').parse(f:read('*a'));f:close();return doc
end
local baseCommon=diskDocument('settings/_namespaces/_base/actions/lib/common/common.json')
documents['shared-engagement-common']={contributions={}}
for _,entry in ipairs(baseCommon.contributions) do
 if entry.slot=='normal-engagement' then table.insert(documents['shared-engagement-common'].contributions,entry) end
end
documents['shared-melee-common']=diskDocument('settings/_namespaces/_base/actions/lib/common/(melee).json')
documents['tank-alignment']=documents['real-tank-alignment']
documents['dynamic-engagement']={actions={{commands={'shared_position()'}}}}
local realSelectors=require('./lib/target-selectors')
env.settingsPaths.commonFiles=function(_,job)
 local result={'shared-engagement-common'}
 for _,group in ipairs(realSelectors.entryPointGroups(job,false))do
  if group=='melee' then result[#result+1]='shared-melee-common' end
 end
 return result
end
for _,job in ipairs({'PLD','WAR','SAM','BLM','COR','GEO','RDM','WHM'})do
 for _,clear in ipairs({false,true})do
  local selectedPlayer={name='Tester',main_job=job,main_job_level=99}
  local layout={pull={{slot='normal-engagement'}},battle={{slot='normal-engagement'}},idle={}}
  if clear then layout.contributions={['!normal-engagement']={}} end
  load('Tester',layout,selectedPlayer,'./settings/namespaces/child/actions/'..job:lower()..'.json')
  local tank=job=='PLD' or job=='WAR' or job=='SAM'
  for _,kind in ipairs({'pull','battle','idle'})do
   local setup,movement=0,0
   for _,a in ipairs(layout[kind])do
    if a.commands[1]:find('tank status',1,true) then setup=setup+1 end
    if a.commands[1]=='shared_position()' then movement=movement+1 end
   end
   assert(setup==(tank and 2 or 0),job..'/'..kind)
   assert(movement==((not clear and kind~='idle') and 1 or 0),job..'/'..kind)
  end
 end
end
print('PASS: shared melee setup is registered once per phase, shared engagement reaches pull/battle, child clears retain setup and caster jobs do not load tank setup')

-- Nested hooks expand in place, using the same global contribution selection.
env.settingsPaths.commonFiles=function() return {} end
documents['nested-ws']={actions={
 {commands={'before_ws()'}},
 {slot='ws-inner',precondition='inner_gate()',with_vars={inner_value=7}},
 {slot='inline-inner',actions={{commands={'inline_ws()'}}}},
 {commands={'after_ws()'}},
}}
documents['nested-ws-provider']={
 contributions={earlier_ws={{commands={'earlier_ws()'}}}},
 actions={{commands={'selected_ws()'}}},
}
local function nestedLayout()
 return {battle={{slot='earlier_ws'},{slot='ws-main',actions={{import='nested-ws',precondition='import_gate()'}},
  precondition='outer_gate()',with_vars={outer_value=42}},
  {slot='ws-main',precondition='second_gate()',with_vars={outer_value=99}}},
  contributions={['ws-inner']={{import='nested-ws-provider'}}}}
end
local nestedWS=nestedLayout()
warnings={}
load('Tester',nestedWS,player,'entry')
assert(#nestedWS.battle==10, 'Nested action count: '..#nestedWS.battle) -- Earlier provider registered separately for each outer scope.
local selectedWS={}
for _,action in ipairs(nestedWS.battle) do
 assert(not action.slot and not action.slots and not action.import and #(action.imports or {})==0)
 if action.commands[1]=='selected_ws()' then selectedWS[#selectedWS+1]=action end
end
assert(#selectedWS==2 and selectedWS[1].discriminator~=selectedWS[2].discriminator)
local state=scopes.build({}, {}, nestedWS._variableScopes)
for index,action in ipairs(selectedWS) do
 local view=state.view(function()return action._variableScope end)
 assert(view.outer_value==(index==1 and 42 or 99) and view.inner_value==7)
 local gates=preconditions.collect(action)
 assert(#gates==3 and gates[1].expression==(index==1 and 'outer_gate()' or 'second_gate()'))
 assert(gates[2].expression=='import_gate()' and gates[3].expression=='inner_gate()')
end
assert(nestedWS._availableSlots['ws-inner'].battle and #warnings==0)
-- A parent replacement removes nested hooks and imports (including metadata).
documents['./settings/namespaces/child/actions/clear-ws.json']={contributions={['!ws-main']={}}}
local clearWS=nestedLayout();clearWS.imports={{import='./settings/namespaces/child/actions/clear-ws.json'}}
load('Tester',clearWS,player,'entry')
assert(#clearWS.battle==0 and clearWS._availableSlots['ws-inner']==nil)
-- Inner replacement and fallback selection leave siblings intact.
documents['./settings/namespaces/child/actions/clear-ws.json']={contributions={['!ws-inner']={{commands={'replacement_ws()'}}},['!inline-inner']={}}}
local replacedWS=nestedLayout();replacedWS.imports={{import='./settings/namespaces/child/actions/clear-ws.json'}}
load('Tester',replacedWS,player,'entry')
assert(#replacedWS.battle==6)
for i=1,6,3 do
 assert(replacedWS.battle[i].commands[1]=='before_ws()')
 assert(replacedWS.battle[i+1].commands[1]=='replacement_ws()')
 assert(replacedWS.battle[i+2].commands[1]=='after_ws()')
end
for _,definitions in ipairs({
 {a={{slot='a'}}},
 {a={{slot='b'}},b={{slot='a'}}},
 {a={{import='recursive-ws'}}},
}) do
 documents['recursive-ws']={actions={{slot='a'}}}
 local ok,err=pcall(load,'Tester',{battle={{slot='a'}},contributions=definitions},player,'entry')
 assert(not ok and tostring(err):find('Recursive contribution'),tostring(err))
end
-- Keep a nested-library fixture independent of the production WS layout.
documents['melee-ws']={actions={{slot='finisher'},{slot='ws-priority'},
 {import='ws/ws-finisher'},{import='ws/all-out-melee'},{slot='sc-priority'}}}
documents['ws/ws-finisher']={actions={{commands={'finisher_ws()'}}}}
documents['ws/all-out-melee']={actions={{commands={'all_out_ws()'}}}}
local realWS={battle={{slot='ws-main',actions={{import='melee-ws'}}}},contributions={
 finisher={{commands={'finisher_slot()'}}},['ws-priority']={{commands={'priority_slot()'}}},
 ['sc-priority']={{commands={'sc_slot()'}}}}}
load('Tester',realWS,player,'entry')
for index,command in ipairs({'finisher_slot()','priority_slot()','finisher_ws()','all_out_ws()','sc_slot()'}) do
 assert(realWS.battle[index].commands[1]==command)
end
print('PASS: nested WS hooks, inline definitions, earlier providers, repeated scopes/conditions, parent/inner replacements and cycles')

documents['nested-destinations']={
 actions={{slot='branch-action',actions={{commands={'branch_action()'}}}}},
 loading={{slot='branch-loading',actions={{commands={'branch_loading()'}}}}},
 functions={{slot='branch-function',actions={{name='branch_function',commands={'branch_function()'}}}}},
}
local destinations={battle={{slot='outer'}},contributions={outer={{import='nested-destinations'}}}}
load('Tester',destinations,player,'entry')
assert(#destinations.battle==1 and destinations.battle[1].commands[1]=='branch_action()')
assert(#destinations.loading==1 and destinations.loading[1].commands[1]=='branch_loading()')
assert(#destinations.functions==1 and destinations.functions[1].name=='branch_function')
local alternatives={battle={{slot='outer'}},contributions={outer={
 {slots={{'absent','choice'},'tail'}},
 {slot='disabled-branch',disabled=true,actions={{import='recursive-ws'}}},
 {slot='filtered-branch',filter={main_jobs={'PLD'}},actions={{import='recursive-ws'}}},
},['^choice']={{commands={'fallback_choice()'}}},tail={{commands={'tail()'}}}}}
load('Tester',alternatives,player,'entry')
assert(#alternatives.battle==2 and alternatives.battle[1].commands[1]=='fallback_choice()')
assert(alternatives.battle[2].commands[1]=='tail()')
print('PASS: nested slots preserve loading/function destinations, fallback aliases and disabled/job-filtered branches')

-- Exercise production WS policies through the import loader. Other libraries
-- are irrelevant here; WS leaf imports are markers so ordering is observable.
documents['melee-ws']=diskDocument('settings/_namespaces/_base/actions/lib/melee-ws.json')
for _,name in ipairs({'ws/mp-recovery','ws/staged/four-part-light','ws/two-part-light','ws/three-part-light'}) do
 documents[name]={actions={{commands={name}}}}
end
local magePath='./settings/namespaces/base/actions/lib/common/(mages).json'
env.targetSelectors=realSelectors
local policyPath='./settings/namespaces/child/actions/lib/common/common.json'
documents[magePath]=diskDocument('settings/_namespaces/_base/actions/lib/common/(mages).json')
for _,policy in ipairs({'_base','_boss/_normal','xp','sortie/_a','sortie/_b','sortie/_ghatjot','sortie/_leshonn','clear-offense'}) do
 local policyDoc=policy=='_base' and {} or policy=='clear-offense' and {contributions={['!ws-main']={}}}
  or diskDocument('settings/_namespaces/'..policy..'/actions/lib/common/common.json')
 documents[policyPath]={contributions={}}
 for _,entry in ipairs(require('./lib/contribution-entries').read(policyDoc.contributions)) do
  local key=entry.slot
  if key=='ws-main' or key=='!ws-main' or key=='!ws-mp-recovery' then table.insert(documents[policyPath].contributions,entry) end
 end
 for _,job in ipairs({'WAR','PLD','COR','BLU','SAM','BLM','GEO','WHM','RDM'}) do
  local selectedPlayer={name='Tester',main_job=job,main_job_level=99}
  local isMage=realSelectors.matchesPlayer(selectedPlayer,{'mages'})
  local isMelee=realSelectors.matchesPlayer(selectedPlayer,{'melee','ranged'})
  env.settingsPaths.commonFiles=function() return isMage and {magePath,policyPath} or {policyPath} end
  local entryName=(job=='SAM' or job=='BLU') and '(melee)' or job:lower()
  local layout=diskDocument('settings/_namespaces/_base/actions/'..entryName..'.json')
  for index,action in ipairs(layout.battle) do
   if action.slot=='ws-main' then assert(layout.battle[index-1].slot=='ws-mp-recovery') end
  end
  load('Tester',layout,selectedPlayer,'./settings/namespaces/base/actions/'..entryName..'.json')
  local actual={}
  for _,action in ipairs(layout.battle) do
   local command=action.commands and action.commands[1]
   if command and (command:match('^ws/') or command=='finisher_ws()' or command=='all_out_ws()') then
    local eligible=true
    for _,gate in ipairs(preconditions.collect(action)) do
     if gate.expression:find('selfMatches',1,true) or gate.expression:find('me.main_job',1,true) then
      local fn=assert(loadstring('return '..gate.expression))
      setfenv(fn,{me=selectedPlayer,selfMatches=function(...)return realSelectors.matchesPlayer(selectedPlayer,{...})end})
      if not fn() then eligible=false end
     end
    end
    if eligible then actual[#actual+1]=command end
   end
  end
  local expected={}
  local suppressMP=policy=='sortie/_ghatjot' or policy=='sortie/_leshonn'
  if isMage and not suppressMP then expected[#expected+1]='ws/mp-recovery' end
  if policy=='sortie/_ghatjot' and (job=='WAR' or job=='PLD') then expected[#expected+1]='ws/three-part-light' end
  if isMelee and policy~='clear-offense' then expected[#expected+1]='finisher_ws()';expected[#expected+1]='all_out_ws()' end
  if isMelee and (policy=='_boss/_normal' or policy=='xp') then expected[#expected+1]='ws/staged/four-part-light' end
  if policy=='sortie/_a' and (job=='WAR' or job=='PLD') then expected[#expected+1]='ws/two-part-light' end
  assert(table.concat(actual,',')==table.concat(expected,','),policy..'/'..job..': '..table.concat(actual,','))
 end
end
print('PASS: WS ordering, separate MP recovery and offensive clearing across eight policies and nine jobs, including BLU and RDM')

env.settingsPaths.commonFiles=function() return {} end
documents['filtered-cycle']={vars={must_not_load=true},actions={{slot='ordered'}},
 contributions={{slot='missing',actions={{commands={'unreachable()'}}}}}}
documents['ordered-provider']={vars={provider_loaded=true},actions={{slot='inner-ordered'}},contributions={
 {slot='inner-ordered',['for']={'RDM'},actions={{commands={'inner()'}}}},
 {slot='earlier-ordered',['for']={'RDM'},actions={{commands={'early()'}}}},
 {slot='ordered',['for']={'fighter'},actions={{import='filtered-cycle'}}},
}}
local ordered={battle={{slot='earlier-ordered'},{slot='ordered'}},contributions={
 {slot='ordered',['for']={'fighter'},actions={{import='filtered-cycle'}}},
 {slot='ordered',['for']={'RDM'},actions={{commands={'first()'}}}},
 {slot='ordered',['for']={'mages','~BLM'},actions={{import='ordered-provider'}}},
 {slot='ordered',actions={{commands={'last()'}}}},
 {slot='missing',['for']={},actions={}},
}}
warnings={}
load('Tester',ordered,player,'entry')
assert(#warnings==0 and ordered.vars.provider_loaded and not ordered.vars.must_not_load)
for index,command in ipairs({'early()','first()','inner()','last()'}) do assert(ordered.battle[index].commands[1]==command) end
-- A matching replacement retains sibling entries from the same ordered file.
local function orderedReplacement(job)
 local config={battle={{slot='ordered'}},contributions={
  {slot='ordered',actions={{commands={'before()'}}}},
  {slot='!ordered',['for']={'RDM'},actions={{commands={'replace()'}}}},
  {slot='ordered',actions={{commands={'after()'}}}},
 },imports={{import='ordered-base'}}}
 documents['ordered-base']={contributions={{slot='ordered',actions={{commands={'base()'}}}}}}
 load('Tester',config,{name='Tester',main_job=job,main_job_level=99},'./settings/namespaces/child/actions/rdm.json')
 return config
end
local replaced=orderedReplacement('RDM')
assert(#replaced.battle==3 and replaced.battle[3].commands[1]=='after()')
local unmatched=orderedReplacement('WAR')
assert(#unmatched.battle==3 and unmatched.battle[3].commands[1]=='base()')
for _,entry in ipairs({{slot='a'},{slot='a',actions=false},{slot='a',actions={},['for']='RDM'},
 {slot='a',actions={},['for']={false}},{slot='a',actions={},unexpected=true}}) do
 assert(not pcall(load,'Tester',{battle={{slot='a'}},contributions={entry}},player,'entry'))
end
local cyclic={battle={{slot='a'}},contributions={{slot='a',['for']={'RDM'},actions={{slot='a'}}}}}
assert(not pcall(load,'Tester',cyclic,player,'entry'))
local defaults={battle={{slot='default'}},contributions={
 {slot='^default',actions={{commands={'fallback first()'}}}},
 {slot='^default',actions={{commands={'fallback second()'}}}},
 {slot='!default',['for']={'WAR'},actions={}},
}}
load('Tester',defaults,player,'entry')
assert(#defaults.battle==2 and defaults.battle[2].commands[1]=='fallback second()')
print('PASS: ordered contributions, repeated slots, load-time selector filtering, filtered cycles/vars/warnings, sibling replacements and validation')
