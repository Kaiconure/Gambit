local Service=require('./lib/events/init')
local copy=require('./lib/variable-values').copy
local callbacks,trace,errors={}, {}, {}
local player={id=100,name='Tester',main_job='SMN'}
local pet={id=200,index=20,name='Carbuncle',valid_target=true}
local target={id=300,index=30,name='Enemy',valid_target=true,spawn_type=16,status=1}
local packet,now,sent,ready= nil,0,0,true
local held
local resources={job_abilities={
    [512]={id=512,en='Healing Ruby',prefix='/pet',type='BloodPactWard'},
    [513]={id=513,en='Poison Nails',prefix='/pet',type='BloodPactRage'},
    [681]={id=681,en='Razor Fang',prefix='/pet',type='Monster'},
    [70]={id=70,en='Heel',prefix='/pet',type='PetCommand'},
    [11]={id=11,en='Normal JA',prefix='/ja',type='JobAbility'}},
    monster_abilities={[906]={id=906,en='Healing Ruby'},[907]={id=907,en='Poison Nails'},[271]={id=271,en='Razor Fang'}},
    action_messages={[43]={en='readies ${weapon_skill}'},[326]={en='readies ${ability}'}}}
local deps={resources=resources,clock=function() return now end,
    report=function(err) errors[#errors+1]=err end,
    read=function(path) if path=='./events/smn.json' then return {
        pet_abilities={pre={{commands={'record(event)','push()'}}},mid={{commands={'record(event)'}}},
            post={{commands={'record(event)','pop()'}}}},job_abilities={post={{commands={'record(event)'}}}}
    } end end,
    context=function(_,state) return {
        record=function(event) trace[#trace+1]=copy(event) end,
        push=function() state.vars.pushed=true end,
        pop=function() assert(state.vars.pushed); state.vars.pushed=false end,
    } end,
    equipmentSession=function() return {inventory={snapshot_equipment=function() return {} end},
        discard=function() end,commit=function() end} end,
    barrier=function(fn) if held then held=fn else fn(true) end end,
    abilityReady=function() return ready end,
    windower={ffxi={get_player=function() return player end,
        get_mob_by_target=function(symbol) if symbol=='pet' then return pet end end,
        get_mob_by_id=function(id) if id==300 then return target elseif pet and id==pet.id then return pet end end},
        register_event=function(name,fn) callbacks[name]=fn; return name end,unregister_event=function() end},
    packets={parse=function() return copy(packet) end,build=function() return 'HEADpayload' end,
        inject=function() sent=sent+1 end}}
local service=Service.new(deps); service:reload()
local function submit(id)
    packet={Category=9,Param=id or 513,Target=300,['Target Index']=30}
    return service:outgoing(0x01A,'raw','raw',false,false)
end
local function action(category,id,message,actor)
    service:action({actor_id=actor or 200,category=category,param=id,
        targets={{id=300,actions={{param=id,message=message or 1}}}}})
end
assert(submit() and #trace==1 and trace[1].kind=='pet_ability' and trace[1].type=='BloodPactRage')
assert(sent==1 and #service.runtime.pending==1 and trace[1].pet.id==200)
action(7,907,43,999); assert(#trace==1)
-- A ready packet carries its ability ID inside the target action.
service:action({actor_id=200,category=7,param=24931,targets={{id=300,actions={{param=907,message=43}}}}})
assert(#trace==2 and trace[2].phase=='mid')
service:action({actor_id=200,category=7,param=24931,targets={{actions={{param=907,message=43}}}}})
assert(#trace==2)
action(13,513)
assert(#trace==3 and trace[3].completed and trace[3].phase=='post' and #service.runtime.pending==0)
action(13,513); assert(#trace==3)
-- Direct completion, rejection, and interrupted execution don't require mid.
trace={}; submit(512); action(13,512)
assert(#trace==2 and trace[2].completed and trace[1].type=='BloodPactWard')
trace={}; submit(); packet={Actor=100,Message=17}
service:incoming(0x029,'raw','raw',false,false)
assert(#trace==2 and trace[2].failed and #service.runtime.pending==0)
service:incoming(0x029,'raw','raw',false,false); assert(#trace==2)
trace={}; submit(); action(7,28787)
assert(#trace==2 and trace[2].interrupted)
trace={}; submit(); service:action({actor_id=100,category=4,param=0,
    targets={{actions={{param=513,message=328}}}}})
assert(#trace==2 and trace[2].failed)
trace={}; submit(); action(6,0,78,100)
assert(#trace==2 and trace[2].failed) -- Unidentified player failure, exactly one pending pet command.
trace={}; submit(); packet={Actor=999,Target=300,Message=6}
service:incoming(0x029,'raw','raw',false,false)
assert(#trace==2 and trace[2].failed) -- Target died before the pact executed.
-- Monster resources have different IDs; correlate their English resource names.
trace={}; submit(681)
service:action({actor_id=200,category=7,param=24931,targets={{actions={{param=271,message=43}}}}})
action(11,271)
assert(#trace==3 and trace[2].phase=='mid' and trace[3].completed)
trace={}; submit(512)
service:action({actor_id=200,category=7,param=24931,targets={{actions={{param=512,message=326}}}}})
assert(trace[2].phase=='mid'); action(13,512)
trace={}; submit(70); action(6,70,1,100)
assert(#trace==2 and trace[2].completed)
-- Recast gates precede pre; pre dispatch remains behind the equipment barrier.
trace={}; ready=false; local before=sent; submit(); assert(#trace==0 and sent==before); ready=true
held=true; submit(); assert(#trace==1 and sent==before)
action(13,513); assert(#trace==1) -- Cannot complete before dispatch.
local release=held; held=nil; release(true); assert(sent==before+1 and #trace==1)
action(13,513); assert(#trace==2)
-- Loss/replacement of the original pet triggers cleanup; timeouts remain a fallback.
trace={}; submit(); local saved=pet; pet=nil; callbacks.prerender()
assert(#trace==2 and trace[2].failed); pet=saved
trace={}; submit(); now=121; callbacks.prerender(); assert(trace[2].timed_out)
-- Ambiguous unidentified rejections cannot cancel one of several commands.
trace={}; submit(512); submit(513); packet={Actor=100,Message=17}
service:incoming(0x029,'raw','raw',false,false); assert(#service.runtime.pending==2)
service:clear('reloaded'); assert(#service.runtime.pending==0 and #errors==0)
service:destroy()
print('PASS: pet routing, pre barrier, observed mid/result, BP/monster ID mapping, failures, dedup, pet loss, timeout and ambiguity')
