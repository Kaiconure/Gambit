local Config=require('./lib/events/config')
local Runtime=require('./lib/events/runtime')
local Service=require('./lib/events/init')
local copy=require('./lib/variable-values').copy
local listeners,seen,errors,commits={},{},{},{}
local mobs={
    [100]={id=100,index=1,name='Self',spawn_type=1,valid_target=true},
    [200]={id=200,index=2,name='Enemy',spawn_type=16,valid_target=true,status=1},
    [300]={id=300,index=3,name='Other Enemy',spawn_type=16,valid_target=true,status=1},
    [400]={id=400,index=4,name='Trust',spawn_type=14,valid_target=true},
}
local deps={resources={spells={[10]={id=10,en='Fire',element=0,skill=36}},
    monster_abilities={[20]={id=20,en='Gaze',element=7}},elements={[0]={en='Fire'},[7]={en='Dark'}},
    skills={[36]={en='Elemental Magic'}},job_abilities={}},
    windower={ffxi={get_player=function() return {id=100} end,
        get_mob_by_id=function(id) return mobs[id] end},
        register_event=function(name,fn) listeners[name]=fn; return name end,
        unregister_event=function(name) listeners[name]=nil end},
    clock=function() return 5 end,report=function(err) errors[#errors+1]=err end,
    context=function(_,state) return {vars=state.vars,record=function(event)
        assert(event.matches(event.id or 'unidentified')==(event.id~=nil))
        seen[#seen+1]=copy(event)
    end,equip=function(name) state.equipment.planned[#state.equipment.planned+1]=name end} end,
    equipmentSession=function()
        local session={planned={}}
        function session:commit() commits[#commits+1]=self.planned end
        function session:discard() end
        return session
    end}
local rules={}
for _,section in ipairs({'enemy_spells','enemy_abilities'}) do
    rules[section]={pre={{commands={'record(event)',"equip('pre')"}}},post={{commands={'record(event)'}}}}
end
local config=Config.load({'test'},function() return rules end)
local service=Service.new(deps); service.runtime=Runtime.new(config,deps)
local function emit(category,param,id,actor,message)
    listeners.action({actor_id=actor or 200,category=category,param=param,
        targets={{id=100,actions={{param=id,message=message or 0}}},{id=400,actions={{message=0}}}}})
end
emit(8,24931,10)
assert(#seen==1 and seen[1].kind=='enemy_spell' and seen[1].phase=='pre')
assert(seen[1].name=='Fire' and seen[1].elemental and seen[1].element_name=='Fire')
assert(seen[1].actor.id==200 and seen[1].actor.is_mob and seen[1].target.is_me)
assert(#seen[1].targets==2 and seen[1].targets[2].is_trust)
assert(commits[1][1]=='pre' and #service.runtime.pending==0)
emit(4,10,nil)
assert(#seen==2 and seen[2].completed and seen[2].outcome=='completed')
emit(11,20,nil,300) -- Post without any pre, from an enemy other than bt.
assert(#seen==3 and seen[3].actor.id==300 and seen[3].name=='Gaze' and seen[3].completed)
emit(7,24931,20)
assert(#seen==4 and seen[4].kind=='enemy_ability' and seen[4].phase=='pre')
emit(7,28787,0)
assert(#seen==5 and seen[5].interrupted and seen[5].id==nil and seen[5].name==nil)
emit(8,28787,10)
assert(#seen==6 and seen[6].interrupted and seen[6].name=='Fire')
emit(4,10,nil,200,88)
assert(#seen==7 and seen[7].failed and not seen[7].completed)
emit(4,999,nil)
assert(#seen==8 and seen[8].id==999 and seen[8].name==nil)
emit(8,12345,10); emit(1,10,nil); emit(4,10,nil,400); emit(4,10,nil,999)
assert(#seen==8 and #errors==0)
local bad=Config.load({'test'},function() return {enemy_spells={pre={{commands={'cancelEvent()'}}}}} end)
service.runtime=Runtime.new(bad,deps)
emit(8,24931,10)
assert(#errors==1 and errors[1]:find('only valid',1,true))
for _,section in ipairs({'enemy_spells','enemy_abilities'}) do
    assert(not pcall(Config.load,{'test'},function() return {[section]={mid={}}} end))
    assert(not pcall(Config.load,{'test'},function() return {[section]={use_equipment_snapshot=true}} end))
end
service:destroy()
print('PASS: independent enemy observations, spell/ability metadata, targets, post-only results, interruptions, failures and non-cancellation')
