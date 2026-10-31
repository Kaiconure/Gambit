local Config=require('./lib/events/config')
local Paths=require('./lib/settings-paths')
local selectors=require('./lib/target-selectors')
local Runtime=require('./lib/events/runtime')
Paths.setLoadedNamespace('child',{'child'})
local paths=Paths.eventFiles('Tester','GEO',selectors.entryPointGroups('GEO',false))
local root='./events/geo.json'
local personal='./settings/_ns/child/players/Tester/events/geo.vars.json'
local shared='./settings/events/common.vars.json'
local documents={
    [root]={imports={'lib/base'},spells={pre={{commands={"mark('root')"}}}},
        contributions={['^spells.pre.before']={{commands={"mark('discarded fallback')"}}}}},
    ['./events/lib/base.json']={spells={pre={{commands={"mark('base')"}},
        {slot='spells.pre.custom'},{commands={"mark('tail')"}}}},
        contributions={['spells.pre.after']={{commands={"mark('after')"}}}}},
    [shared]={vars={shared=true},contributions={['spells.pre.before']={{commands={"mark('shared before')"}}},
        ['spells.pre.custom']={{commands={"mark('discarded lower')"}}}}},
    [personal]={contributions={
        ['spells.pre.before']={{priority='high',commands={"mark('first')"}},
            {commands={"mark('personal before')"}}},
        ['!spells.pre.custom']={{commands={"mark('replacement')"}}},
        missing_optional={optional=true,actions={{commands={"mark('never')"}}}},
    }},
}
local warnings={}
local function load(job)
    warnings={}
    return Config.load(paths,function(path) return documents[path] end,
        function(message) warnings[#warnings+1]=message end,
        function(required) return selectors.matchesPlayer({name='Tester',main_job=job or 'GEO'},required,false) end)
end
local function trace(config)
    local output={}
    local runtime=Runtime.new(config,{clock=function() return 0 end,report=function(err) error(err) end,
        context=function() return {mark=function(value) output[#output+1]=value end} end})
    runtime:run({section='spells',event={},variables={vars={_={eq_stack={}}}}},'pre')
    return table.concat(output,',')
end
local config=load()
assert(trace(config)=='first,personal before,shared before,base,replacement,tail,root,after')
assert(#warnings==0 and config.available_slots['spells.pre.custom'])
assert(config.available_slots['loading.actions.before'] and config.available_slots['statuses.idle.enter.after'])
assert(config.rules.spells.pre[1].source:find(personal,1,true))
assert(config.rules.spells.pre[5].source:find('contributions',1,true))
local output=require('./lib/events/processed')(config)
assert(output._sources.slots['spells.pre.before'] and output.spells.pre[1].commands[1]=="mark('first')")
-- Prefixes, empty replacements, and fallback specificity share normal action semantics.
documents[personal].contributions['!spells.pre.after']={}
assert(not trace(load()):find('after',1,true))
documents[personal].contributions['!spells.pre.custom']=nil
documents[shared].contributions['spells.pre.custom']=nil
documents[personal].contributions['^spells.pre.custom']={{commands={"mark('closest default')"}}}
documents[shared].contributions['^spells.pre.custom']={{commands={"mark('lower default')"}}}
assert(trace(load()):find('closest default',1,true) and not trace(load()):find('lower default',1,true))
-- required_for controls diagnostics, not whether a contribution executes.
documents[personal].contributions['missing_required']={optional=true,required_for={'GEO'},actions={}}
load(); assert(#warnings==1 and warnings[1]:find('missing_required',1,true))
load('WAR'); assert(#warnings==0)
documents[personal].contributions['missing_required']=nil
documents[personal].contributions['^spells.pre.custom']=nil
documents[personal].contributions['spells.pre.custom, missing_alias']={required_for={'GEO'},actions={}}
load(); assert(#warnings==0) -- Any declared alias satisfies a required_for group.
documents[personal].contributions['spells.pre.custom, missing_alias']=nil
-- Replacement IDs apply after slot placement, across contributions and normal rules.
documents[personal].contributions['spells.pre.before']={{id='target',commands={"mark('before id')"}}}
documents[root].spells.pre={{id='target',disabled=true}}
assert(not trace(load()):find('before id',1,true))
documents[personal].contributions['!spells.pre.after']={{id='target',commands={"mark('after id')"}}}
assert(trace(load()):find('after id',1,true))
-- A stop in a before contribution stops the entire expanded phase.
documents[personal].contributions['spells.pre.before']={{commands={"mark('stop')",'stopEvent()'}}}
assert(trace(load())=='stop')
-- Slot declarations are unique, cannot redeclare built-ins, and cannot hide executable rules.
for _,bad in ipairs({{slot='spells.pre.before'},{slot='spells.pre.custom'},
    {slot='other',commands={'bad()'}}}) do
    documents[root].spells.pre={bad}
    assert(not pcall(load))
end
documents[root].spells.pre={}
for _,bad in ipairs({{actions={},optional='yes'},{actions={},required_for='GEO'},
    {actions={{priority='invalid'}}},{actions={{slot='nested'}}},
    {actions={{commands={'broken('}}}},{actions={{unknown=true}}}}) do
    documents[personal].contributions={['spells.pre.before']=bad}
    assert(not pcall(load))
end
-- Built-ins work even without an explicit phase, including loading and statuses.
local native=Config.load({'test'},function() return {contributions={
    ['loading.actions.after']={{commands={'vars.initialized=true'}}},
    ['statuses.idle.enter.after']={{commands={'record(event.kind)'}}},
    ['zones.enter.before']={{commands={'record(event.phase)'}}},
}} end)
local notifications={}
local runtime=Runtime.new(native,{clock=function() return 0 end,report=function(err) error(err) end,
    context=function(_,state) return {vars=state.vars,record=function(value) notifications[#notifications+1]=value end} end})
runtime:loading()
assert(native.vars.initialized)
runtime:observe({kind='status',category='idle'},'enter')
runtime:observe({kind='zone'},'enter')
assert(notifications[1]=='status' and notifications[2]=='enter')
Paths.setLoadedNamespace(nil)
print('PASS: event built-ins/custom slots, hierarchy ordering, priority/default/replacement semantics, requirements, IDs, stopping and validation')
