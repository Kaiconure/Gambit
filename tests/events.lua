local Config=require('./lib/events/config')
local Runtime=require('./lib/events/runtime')
local Service=require('./lib/events/init')
local Paths=require('./lib/settings-paths')
local copy=require('./lib/variable-values').copy
local documents={
    global={vars={minimum=25,nested={a=1},list={'old','extra'}},job_abilities={pre={
        {id='replace',commands={"mark('old')"}},
        {commands={"mark('general')"}},
        {id='disable',commands={"mark('disabled')"}},
    }}},
    character={vars={minimum=30,nested={b=2},list={'new'}},job_abilities={pre={
        {id='replace',commands={"mark('specific')"}},
        {id='disable',disabled=true},
    }}},
}
local config=Config.load({'missing','character','global'},function(p) return documents[p] end)
assert(not pcall(Config.load,{'invalid'},function() return {weapon_skill={}} end))
for _,kind in ipairs(Config.kinds) do
    local enabled=Config.load({'test'},function() return {[kind]={use_equipment_snapshot=true}} end)
    assert(enabled.rules[kind].use_equipment_snapshot==true)
    assert(not pcall(Config.load,{'invalid'},function() return {[kind]={use_equipment_snapshot='true'}} end))
end
assert(config.vars.minimum==30 and config.vars.nested.a==nil and config.vars.nested.b==2)
assert(#config.vars.list==1 and config.vars.list[1]=='new')
assert(#config.rules.job_abilities.pre==1 and config.rules.job_abilities.pre[1].id=='replace')
assert(config.path=='character' and #config.files==1)
assert(config.rules.job_abilities.pre[1].source:find('character',1,true))
local empty=Config.load({'empty','fallback'},function(path)
    if path=='empty' then return {} end
    error('must not read a fallback after selecting a file')
end)
assert(empty.path=='empty' and #empty.rules.spells.pre==0)
assert(not pcall(Config.load,{'invalid','fallback'},function() return {invalid=true} end))
assert(not pcall(Config.load,{'bad'},function() return {imports={}} end))
assert(not pcall(Config.load,{'bad'},function() return {spells={pre={{commands={'broken('}}}}} end))
assert(not pcall(Config.load,{'bad'},function() return {spells={pre={bad={}}}} end))
local commented=Config.load({'comments'},function() return {spells={pre={
    {comment='Section heading: this is prose, not Lua.'},
    {comment={'First line','Second line'}},
    {comment='Stop for a matching spell',when={'true'},stop=true},
}}} end)
assert(#commented.rules.spells.pre==1 and commented.rules.spells.pre[1].stop)
assert(commented.rules.spells.pre[1].source=='comments:spells.pre[3]')
local commentsOnly=Config.load({'comments'},function() return {spells={pre={{comment='Notes only'}}}} end)
assert(#commentsOnly.rules.spells.pre==0)
for _,comment in ipairs({false,42,{'valid',false},{text='not an array'}}) do
    local accepted=Config.load({'comments'},function() return {spells={pre={
        {comment=comment}, {comment=comment,commands={"mark('works')"}},
    }}} end)
    assert(#accepted.rules.spells.pre==1 and accepted.rules.spells.pre[1].comment==nil)
end
Paths.setLoadedNamespace('child',{'child','parent'})
local paths=Paths.eventFiles('Tester','RDM')
assert(paths[1]=='./settings/_ns/child/players/Tester/events/rdm.json' and paths[4]=='./settings/_ns/child/events/common.json')
assert(paths[5]=='./settings/_ns/parent/players/Tester/events/rdm.json')
assert(paths[9]=='./settings/Tester/events/rdm.json')
local available={
    ['./settings/_ns/child/events/common.json']={},
    ['./settings/Tester/events/rdm.json']={vars={wrong_scope=true}},
}
local function selected() return Config.load(paths,function(path) return available[path] end) end
assert(selected().path=='./settings/_ns/child/events/common.json')
available['./settings/_ns/child/players/Tester/events/common.json']={}
available['./settings/_ns/child/events/rdm.json']={}
assert(selected().path=='./settings/_ns/child/players/Tester/events/common.json')
available['./settings/_ns/child/players/Tester/events/rdm.json']={}
assert(selected().path=='./settings/_ns/child/players/Tester/events/rdm.json')
assert(not Paths.validateNamespace('child/events/test'))
Paths.setLoadedNamespace(nil)
local selectors=require('./lib/target-selectors')
local groupPaths=Paths.eventFiles('Tester','RDM',selectors.entryPointGroups('RDM',true))
local positions={}
for index,path in ipairs(groupPaths) do positions[path]=index end
local root='./settings/events/'
assert(positions[root..'(~melee).json'] and not positions[root..'(melee).json'])
assert(positions[root..'(mages).json'] and positions[root..'(leader).json'])
assert(positions[root..'common.json']>positions[root..'(~melee).json'])
assert(positions[root..'(~melee).json']>positions[root..'(mages).json'])
assert(positions[root..'(mages).json']>positions[root..'rdm.json'])
assert(positions['./settings/Tester/events/(mages).json'])

local now,queue,trace,errors=0,{},{},{}
local savedCancel
local function context(_,state)
    assert(state.vars~=documents.global.vars)
    return {vars=state.vars,me={hpp=20},
        mark=function(value) trace[#trace+1]=value end,
        capture=function(fn) savedCancel=fn end,
        yieldNow=function() coroutine.yield('wait') end,
        explode=function() error('rule failure') end}
end
local deps={context=context,clock=function() return now end,
    equipmentSession=function() return {inventory={snapshot_equipment=function() return {} end},discard=function() end,commit=function() end} end,
    report=function(e) errors[#errors+1]=e end,
    schedule=function(fn) queue[#queue+1]=fn end}
local function flush()
    local current=queue; queue={}
    for _,fn in ipairs(current) do fn() end
end
local function load(doc)
    return Config.load({'test'},function() return doc end)
end
local function event(kind,id,target)
    return {kind=kind or 'spell',id=id or 10,name='Test',target={id=target or 200}}
end
local runtime=Runtime.new(config,deps)
local sent=0
assert(runtime:submit(event('job_ability'),function() sent=sent+1 end)==true)
assert(table.concat(trace,',')=='specific' and sent==0)
flush(); assert(sent==1)
runtime:complete('job_ability',10,200,'completed'); assert(#runtime.pending==0)
assert(runtime:submit(event('spell'),function() error('no rules') end)==nil)

config=load({vars={counter=0},spells={pre={
    {when={'me.hpp < 25'},commands={"vars.counter=vars.counter+1", "cancelEvent('low HP')",'capture(cancelEvent)'}},
    {when={'event.cancelled'},commands={"mark('cancel seen')"}},
},post={{commands={"mark(event.outcome)","mark(vars.counter)"}}}}})
runtime=Runtime.new(config,deps); trace={}
runtime:submit(event(),function() error('cancelled dispatch') end)
assert(table.concat(trace,',')=='cancel seen,cancelled,1' and #runtime.pending==0)
assert(config.vars.counter==0 and not pcall(savedCancel))
flush()

-- Dynamic stop finishes the current rule, skips later rules, and resets each phase.
for _,shouldStop in ipairs({false,true}) do
    config=load({vars={should_stop=shouldStop},spells={
        pre={{commands={'vars.should_stop and stopEvent()',"mark('pre tail')",'capture(stopEvent)'}},
            {commands={"mark('later pre')"}}},
        mid={{commands={'stopEvent(false)',"mark('mid tail')"}},{commands={"mark('later mid')"}}},
        post={{commands={'stopEvent()',"mark('post tail')"}},{commands={"mark('later post')"}}},
    }})
    runtime=Runtime.new(config,deps); trace={}
    runtime:submit(event(),function() end)
    assert(not pcall(savedCancel)) -- Captured stop cannot affect a finished phase.
    flush(); runtime:complete('spell',10,nil,'completed')
    local expected=shouldStop and 'pre tail,mid tail,post tail' or 'pre tail,later pre,mid tail,post tail'
    assert(table.concat(trace,',')==expected)
end
config=load({spells={pre={{commands={'stopEvent(true)',"mark('cancel tail')"}},
    {commands={"mark('later pre')"}}},post={{commands={'mark(event.outcome)'}}}}})
runtime=Runtime.new(config,deps); trace={}
runtime:submit(event(),function() error('stopped cancellation dispatched') end)
assert(table.concat(trace,',')=='cancel tail,cancelled' and #runtime.pending==0)
for _,phase in ipairs({'mid','post'}) do
    config=load({spells={[phase]={{commands={'stopEvent(true)'}}}}})
    runtime=Runtime.new(config,deps)
    runtime:submit(event(),function() end); flush()
    runtime:complete('spell',10,nil,'completed')
    assert(errors[#errors]:find('only valid',1,true))
end

config=load({spells={pre={{commands={"vars.test='kept'"}}},
    mid={{commands={"mark(event.phase)"}}},post={{commands={'mark(event.outcome)','mark(vars.test)'}}}}})
runtime=Runtime.new(config,deps); trace={}
runtime:submit(event(),function() sent=sent+1 end); flush()
assert(trace[1]=='mid' and #runtime.pending==1)
assert(not runtime:complete('spell',11,200,'completed'))
assert(not runtime:complete('spell',10,201,'completed'))
assert(runtime:complete('spell',10,200,'interrupted'))
assert(table.concat(trace,',')=='mid,interrupted,kept')
assert(not runtime:complete('spell',10,200,'completed'))
runtime:submit(event(),function() sent=sent+1 end)
runtime:clear('reloaded'); local before=sent; flush(); assert(sent==before)
runtime:submit(event(),function() return false end); flush(); assert(#runtime.pending==0)
runtime:submit(event(),function() end); flush(); now=121; runtime:tick(); assert(#runtime.pending==0)

config=load({spells={pre={{commands={'yieldNow()'}}},post={{commands={'mark(event.outcome)'}}}}})
runtime=Runtime.new(config,deps); trace={}
runtime:submit(event(),function() error('must not dispatch') end)
assert(trace[1]=='cancelled' and errors[#errors]:find('cannot yield',1,true))
runtime:submit(event(),function() error('quarantined pre rule must not dispatch') end)
assert(#runtime.pending==0)
config=load({spells={post={{commands={'cancelEvent()'}}}}})
runtime=Runtime.new(config,deps)
runtime:submit(event(),function() end); flush(); runtime:complete('spell',10,nil,'completed')
assert(errors[#errors]:find('only valid',1,true))

-- Outcome flags are consistent in post and absent before completion.
for _,outcome in ipairs({'completed','interrupted','failed','timeout','cancelled',
    'reloaded','zoned','logout','unloaded'}) do
    config=load({spells={pre={{commands={'mark(event)'}}},
        mid={{commands={'mark(event)'}}},post={{commands={'mark(event)'}}}}})
    runtime=Runtime.new(config,deps); trace={}
    runtime:submit(event(),function() end); flush()
    local request=runtime.pending[1]
    runtime:finish(request,outcome)
    assert(#trace==3)
    for _,value in ipairs({trace[1],trace[2]}) do
        assert(value.completed==nil and value.interrupted==nil and value.failed==nil and value.timed_out==nil)
        assert(value.cancelled==false)
    end
    local value=trace[3]
    assert(value.outcome==outcome and value.completed==(outcome=='completed'))
    assert(value.interrupted==(outcome=='interrupted') and value.failed==(outcome=='failed'))
    assert(value.timed_out==(outcome=='timeout') and value.cancelled==(outcome=='cancelled'))
    runtime:finish(request,'completed'); assert(#trace==3)
end
config=load({spells={pre={{commands={'cancelEvent()', 'mark(event)'}}},
    post={{commands={'mark(event)'}}}}})
runtime=Runtime.new(config,deps); trace={}
runtime:submit(event(),function() error('cancelled action dispatched') end)
assert(trace[1].cancelled==true and trace[1].completed==nil)
assert(trace[2].cancelled==true and trace[2].completed==false and trace[2].interrupted==false)

-- Adapter: actual listener callbacks, including manual and Gambit injection paths.
local listeners,removed={},{}
local player={id=100,name='Tester',main_job='RDM'}
local resources={spells={[10]={id=10,name='ケアル',en='Cure',ja='ケアル',type='WhiteMagic',element=6}},
    job_abilities={[11]={id=11,name='コンバート',en='Convert',ja='コンバート',type='JobAbility',element=0}},
    weapon_skills={[12]={id=12,name='サベッジブレード',en='Savage Blade',ja='サベッジブレード'}},
    elements={[0]={en='Fire',name='localized fire'},[6]={en='Light',name='localized light'}},
    skills={[33]={en='Healing Magic',name='localized healing'}}}
resources.spells[10].skill=33
local packet
local service
local injected=0
local announcements={}
local delayedEcho=false
local echoes={}
local function buildPacket(p)
    return 'HEAD'..table.concat({p.Category,p.Param,p.Target,p['Target Index']},':')
end
local adapterDeps={context=context,clock=deps.clock,schedule=deps.schedule,report=deps.report,resources=resources,
    equipmentSession=deps.equipmentSession,
    announce=function(message) announcements[#announcements+1]=message end,
    formatPath=function(path) return '<file>'..path..'</file>' end,
    windower={ffxi={get_player=function() return player end,get_party=function() return {party1_leader=100} end,
        get_mob_by_id=function(id) return {id=id,index=20,name='Target',valid_target=true} end},
        register_event=function(name,fn) listeners[name]=fn; return name end,
        unregister_event=function(id) removed[id]=true end},
    packets={parse=function() return copy(packet) end,build=buildPacket,
        inject=function(p)
            injected=injected+1
            local raw=buildPacket(p)
            if delayedEcho then echoes[#echoes+1]={raw=raw,packet=copy(p)}
            else assert(not listeners['outgoing chunk'](0x01A,raw,raw,true,false)) end
        end}}
service=Service.new(adapterDeps)
config=load({spells={pre={{commands={"mark(event.name)"}}},post={{commands={'mark(event.outcome)'}}}},
    job_abilities={post={{commands={'mark(event.outcome)'}}}},weapon_skills={post={{commands={'mark(event.outcome)'}}}}})
service.runtime=Runtime.new(config,deps)
packet={Category=3,Param=10,Target=200,['Target Index']=20}
assert(not listeners['outgoing chunk'](0x01A,'raw','raw',false,true))
assert(listeners['outgoing chunk'](0x01A,'raw','raw',false,false)==true)
local metadata=service.runtime.pending[1].event
assert(metadata.type=='WhiteMagic' and metadata.element==6 and metadata.element_name=='Light')
assert(metadata.name=='Cure' and metadata.en==nil and metadata.ja==nil)
assert(metadata.skill==33 and metadata.skill_name=='Healing Magic')
assert(metadata.healing==true and metadata.enfeebling==false and metadata.singing==false)
assert(metadata.curing==true)
flush(); assert(injected==1)
listeners.action({actor_id=200,category=4,param=10}); assert(#service.runtime.pending==1)
listeners.action({actor_id=100,category=4,param=10}); assert(#service.runtime.pending==0)
service:send(packet); flush(); assert(injected==2)
listeners.action({actor_id=100,category=8,param=28787}); assert(#service.runtime.pending==0)
packet={Category=9,Param=11,Target=100,['Target Index']=1}
service:send(packet); flush()
metadata=service.runtime.pending[1].event
assert(metadata.type=='JobAbility' and metadata.element==0 and metadata.element_name=='Fire')
assert(metadata.name=='Convert' and metadata.en==nil and metadata.ja==nil)
assert(metadata.skill==nil and metadata.skill_name==nil and metadata.healing==nil)
assert(metadata.curing==nil)
listeners.action({actor_id=100,category=14,param=11}); assert(#service.runtime.pending==0)
packet={Category=7,Param=12,Target=200,['Target Index']=20}
service:send(packet); flush()
metadata=service.runtime.pending[1].event
assert(metadata.type==nil and metadata.element==nil and metadata.element_name==nil)
assert(metadata.name=='Savage Blade' and metadata.en==nil and metadata.ja==nil)
assert(metadata.healing==nil and metadata.enfeebling==nil)
listeners.action({actor_id=100,category=3,param=12}); assert(#service.runtime.pending==0)
service:send(packet); flush()
packet={Actor=100,Message=17}
listeners['incoming chunk'](0x029,'raw','raw',false,false); assert(#service.runtime.pending==0)
-- Regression: Windower can echo an injected request after inject() returns.
-- Both normal interception and explicit dispatch must produce one lifecycle.
delayedEcho=true
local pushes,pops=0,0
local rollDeps={clock=deps.clock,schedule=deps.schedule,report=deps.report,context=function(_,state)
    return {equipPush=function() pushes=pushes+1; state.vars.pushed=true end,
        equipPop=function() assert(state.vars.pushed); pops=pops+1 end}
end}
rollDeps.equipmentSession=deps.equipmentSession
local rollConfig=load({job_abilities={pre={{commands={'equipPush()'}}},post={{commands={'equipPop()'}}}}})
service.runtime=Runtime.new(rollConfig,rollDeps)
-- Double-Up completes with the original roll's ID rather than ability 123.
resources.job_abilities[123]={id=123,name='Double-Up',en='Double-Up',type='CorsairShot'}
resources.job_abilities[98]={id=98,name="Corsair's Roll",type='CorsairRoll'}
local doubleUp={kind='job_ability',id=123,target={id=100}}
service.runtime:submit(doubleUp,function() end)
listeners.action({actor_id=100,category=6,param=98})
assert(#service.runtime.pending==1 and pops==0) -- Not dispatched yet.
flush()
listeners.action({actor_id=200,category=6,param=98})
listeners.action({actor_id=100,category=6,param=11})
assert(#service.runtime.pending==1 and pops==0) -- Other actors/non-rolls cannot complete it.
listeners.action({actor_id=100,category=6,param=98})
assert(#service.runtime.pending==0 and pushes==1 and pops==1)
listeners.action({actor_id=100,category=6,param=98})
assert(pops==1) -- Duplicate result must not pop twice.
-- An exact roll lifecycle takes priority over the Double-Up exception.
service.runtime:submit({kind='job_ability',id=98,target={id=100}},function() end)
service.runtime:submit(doubleUp,function() end); flush()
listeners.action({actor_id=100,category=14,param=98})
assert(#service.runtime.pending==1 and service.runtime.pending[1].event.id==123)
listeners.action({actor_id=100,category=14,param=98})
assert(#service.runtime.pending==0 and pushes==3 and pops==3)
pushes,pops=0,0
local timers={[1]=60}
resources.job_abilities[11].recast_id=1
adapterDeps.abilityReady=function(_,resource) return timers[resource.recast_id]<=0 end
packet={Category=9,Param=11,Target=100,['Target Index']=20}
assert(service:send(packet))
flush(); assert(pushes==0 and #service.runtime.pending==0)
timers[1]=0
local function echoAll()
    local pending=echoes; echoes={}
    for _,echo in ipairs(pending) do
        packet=echo.packet
        -- Header changes must not affect matching.
        assert(not listeners['outgoing chunk'](0x01A,'NEXT'..echo.raw:sub(5),'NEXT'..echo.raw:sub(5),true,false))
    end
end
packet={Category=9,Param=11,Target=100,['Target Index']=20}
before=injected
assert(listeners['outgoing chunk'](0x01A,buildPacket(packet),buildPacket(packet),false,false))
flush(); echoAll(); flush()
assert(injected==before+1 and pushes==1 and #service.runtime.pending==1)
listeners.action({actor_id=100,category=6,param=11}); assert(pops==1)
service:send(packet); flush(); echoAll(); flush()
assert(injected==before+2 and pushes==2)
service:send(packet); flush()
assert(injected==before+2 and pushes==2) -- Pending retry does not swap twice.
packet={Actor=100,Message=429+32768}
listeners['incoming chunk'](0x029,'raw','raw',false,true)
assert(pops==2 and #service.runtime.pending==0)
-- An unrelated injected request must still be offered to pre rules.
packet={Category=9,Param=11,Target=200,['Target Index']=20}
assert(listeners['outgoing chunk'](0x01A,buildPacket(packet),buildPacket(packet),true,false))
assert(pushes==3)
flush(); echoAll(); listeners.action({actor_id=100,category=6,param=11})
assert(pops==3)
packet={Category=9,Param=11,Target=100,['Target Index']=20}
service:send(packet); flush(); echoAll()
assert(pushes==4)
packet={Actor=100,Message=94+32768}
listeners['incoming chunk'](0x029,'raw','raw',false,false)
assert(pops==4 and #service.runtime.pending==0)
packet={Category=9,Param=11,Target=100,['Target Index']=20}
service:send(packet); flush(); echoAll()
listeners.action({actor_id=100,category=6,param=0,targets={{actions={{message=429+32768}}}}})
assert(pops==5 and #service.runtime.pending==0)
-- Duplicate rejection notifications cannot run post a second time.
packet={Actor=100,Message=429}
listeners['incoming chunk'](0x029,'raw','raw',false,false)
assert(pops==5)
adapterDeps.abilityReady=nil
-- Spell recast rejection also happens before any pre work or pending state.
service.runtime=Runtime.new(config,deps)
resources.spells[10].recast_id=2
adapterDeps.windower.ffxi.get_spell_recasts=function() return {[2]=100} end
packet={Category=3,Param=10,Target=200,['Target Index']=20}
local beforeRecast=injected
assert(service:send(packet)); flush()
assert(injected==beforeRecast and #service.runtime.pending==0)
adapterDeps.windower.ffxi.get_spell_recasts=nil
delayedEcho=false
service.runtime=Runtime.new(config,deps)
-- Reload commits only after validation, finishes old requests once, and makes
-- queued callbacks inert. A failed reload leaves the previous engine intact.
packet={Category=3,Param=10,Target=200,['Target Index']=20}
service:send(packet)
local beforeReload=injected
adapterDeps.read=function(path)
    if path=='./settings/events/common.json' then return {spells={post={{commands={'mark(event.outcome)'}}}}} end
    if path=='./settings/events/(mages).json' then return {vars={group_loaded=true}} end
    if path=='./settings/Tester/events/(leader).json' then return {vars={leader_loaded=true}} end
end
local loaded=service:reload()
assert(#loaded.files==1 and loaded.path=='./settings/Tester/events/(leader).json')
assert(loaded.vars.group_loaded==nil and loaded.vars.leader_loaded)
assert(announcements[#announcements]=='Active event file: <file>'..loaded.path..'</file>')
flush(); assert(injected==beforeReload)
local retainedRuntime=service.runtime
adapterDeps.read=function() return {spells={pre={{commands={'bad('}}}}} end
assert(not pcall(service.reload,service) and service.runtime==retainedRuntime)
assert(announcements[#announcements]=='Active event file: <file>'..loaded.path..'</file>')
packet={Category=3,Param=10,Target=200,['Target Index']=20}
service:send(packet); flush()
listeners['zone change'](); assert(#service.runtime.pending==0)
service:send(packet)
beforeReload=injected
listeners.logout(); flush()
assert(service.runtime==nil and injected==beforeReload)
adapterDeps.read=function() return nil end
local absent=service:reload()
assert(absent.path==nil and #absent.files==0)
assert(announcements[#announcements]=='No active event file (no matching file found).')
-- Every flag uses the same skill IDs as the action helpers, independent of locale.
service.runtime=Runtime.new(config,deps)
for flag,id in pairs(require('./meta/magic-skills')) do
    resources.spells[10].skill=id
    resources.skills[id]={en='English '..flag,name='localized '..flag}
    packet={Category=3,Param=10,Target=200,['Target Index']=20}
    service:send(packet)
    local value=service.runtime.pending[1].event
    assert(value.skill==id and value.skill_name=='English '..flag)
    assert(value.curing==(id==33))
    for other,otherId in pairs(require('./meta/magic-skills')) do
        assert(value[other]==(id==otherId))
    end
    flush(); listeners.action({actor_id=100,category=4,param=10})
end
service:destroy(); assert(removed['outgoing chunk'] and removed.action and removed.logout)
-- Stock Lua needs parentheses around Windower's string-literal method syntax.
for _,path in ipairs({'Gambit.lua','lib/action-context.lua','lib/events/config.lua',
    'lib/events/runner.lua','lib/events/runtime.lua','lib/events/init.lua'}) do
    local file=assert(io.open(path)); local source=file:read('*a'); file:close()
    source=source:gsub("\\'",'\1'):gsub('\\"','\2')
        :gsub("('[^'\r\n]*'):format",'(%1):format'):gsub('("[^"\r\n]*"):format','(%1):format')
        :gsub('\1',"\\'"):gsub('\2','\\"')
    assert(loadstring(source,'@'..path))
end
print('PASS: single event file selection, path reporting, schema, variables, ordering, cancellation, outcomes and packet adapter')
