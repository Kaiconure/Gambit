local Service=require('./lib/events/init')
local Config=require('./lib/events/config')
local Runtime=require('./lib/events/runtime')
local processed=require('./lib/events/processed')
local copy=require('./lib/variable-values').copy
local listeners,events,commits,errors={},{},{},{}
local player={id=10}
local buffs={}
local deps={resources={buffs={[15]={en='doom',name='localized Doom'},
    [1001]={en='Refresh'},[1002]={en='Refresh'}}},
    clock=function() return 12 end,report=function(err) errors[#errors+1]=err end,
    windower={ffxi={get_player=function() return player end},
        register_event=function(name,fn) listeners[name]=fn; return name end,
        unregister_event=function(name) listeners[name]=nil end},
    equipmentSession=function()
        local session={planned={}}
        function session:commit() commits[#commits+1]=self.planned end
        function session:discard() end
        return session
    end,
    context=function(_,state)
        return {vars=state.vars,record=function(event) events[#events+1]=copy(event) end,
            hasBuff=function(name) return buffs[name] end,
            equipMany=function(set) state.equipment.planned[#state.equipment.planned+1]=copy(set) end}
    end}
local document={vars={ring={ring1={name="Eshmun's Ring",lock_when={"hasBuff('Doom')"}}}},
    buffs={added={
        {when={"event.matches('Doom')","hasBuff('Doom')"},commands={'equipMany(vars.ring)','record(event)'},id='doom'},
        {when={"event.matches('1002')"},commands={'record(event)'},id='specific-refresh'},
        {when={'event.matches(999)'},commands={'record(event)'},id='unknown-id'},
    },removed={{commands={'record(event)'},id='removed'}}},
    contributions={['buffs.added.after']={{when={"event.matches('Doom')"},commands={'record(event)'},id='after'}}}}
local config=Config.load({'test'},function() return document end)
assert(config.available_slots['buffs.added.before'] or #config.available_slots>0)
local service=Service.new(deps)
listeners['gain buff'](15); assert(#events==0) -- Not loaded yet; no synthetic load events.
service.runtime=Runtime.new(config,deps)
buffs.Doom=true
listeners['gain buff'](15)
assert(#events==2 and events[1].kind=='buff' and events[1].phase=='added')
assert(events[1].id==15 and events[1].name=='doom' and events[1].actor_id==10)
assert(events[1].name_lower=='doom')
assert(events[1].time==12 and events[1].cancelled==false)
assert(commits[1][1].ring1.lock_when[1]=="hasBuff('Doom')")
listeners['gain buff'](1001); assert(#events==2)
listeners['gain buff'](1002); assert(#events==3 and events[3].id==1002)
assert(events[3].name=='Refresh' and events[3].name_lower=='refresh')
buffs.Doom=nil
listeners['lose buff'](15)
assert(#events==4 and events[4].phase=='removed' and events[4].name=='doom')
listeners['gain buff'](999)
assert(events[5].id==999 and events[5].name==nil)
assert(events[5].name_lower==nil)
player=nil; listeners['lose buff'](15); assert(#events==5)
local output=processed(config)
assert(output.buffs.added[1].id=='doom' and output.buffs.removed[1].id=='removed')
for _,section in ipairs({{pre={}},{enter={}},{use_equipment_snapshot=true},{added={bad=true}}}) do
    assert(not pcall(Config.load,{'test'},function() return {buffs=section} end))
end
player={id=10}
local cancelled=Config.load({'test'},function() return {buffs={added={{commands={'cancelEvent()'}}}}} end)
service.runtime=Runtime.new(cancelled,deps)
listeners['gain buff'](15)
assert(#errors==1 and errors[1]:find('only valid',1,true))
local stopped=Config.load({'test'},function() return {buffs={added={
    {commands={'record(event)'},stop=true},{commands={'record(event)'}}}}} end)
service.runtime=Runtime.new(stopped,deps)
listeners['gain buff'](15); assert(#events==6)
service:destroy()
assert(not listeners['gain buff'] and not listeners['lose buff'])
print('PASS: self buff added/removed, English names, duplicate-name IDs, equipment batching, contributions, processed output and observational rules')
