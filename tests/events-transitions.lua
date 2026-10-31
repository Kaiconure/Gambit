local Service=require('./lib/events/init')
local Config=require('./lib/events/config')
local Runtime=require('./lib/events/runtime')
local copy=require('./lib/variable-values').copy
local listeners,trace,errors,commits={},{},{},{}
local info={zone=1,logged_in=true}
local player={id=100,name='Tester',main_job='GEO'}
local mob={id=100,valid_target=true}
local deps={clock=function() return 10 end,report=function(err) errors[#errors+1]=err end,
    resources={zones={[1]={en='Old Zone',name='localized',search='OldZone'},
        [2]={en='New Zone',search='NewZone'},[3]={en='Third Zone',search='Third'}}},
    windower={ffxi={get_player=function() return player end,get_info=function() return info end,
        get_mob_by_target=function() return mob end},
        register_event=function(name,fn) assert(not listeners[name]); listeners[name]=fn; return name end,
        unregister_event=function() end},
    equipmentSession=function()
        local session={inventory={},planned={}}
        function session:commit() if #self.planned>0 then commits[#commits+1]=self.planned end end
        function session:discard() self.planned={} end
        return session
    end,
    context=function(_,state) return {vars=state.vars,
        record=function(event) trace[#trace+1]=copy(event) end,
        equip=function(name) state.equipment.planned[#state.equipment.planned+1]=name end}
    end}
local config=Config.load({'test'},function() return {vars={counter=0},
    statuses={battle={enter={{commands={'vars.counter=vars.counter+1','record(event)',"equip('battle')",'stopEvent()'}},
        {commands={"equip('must not run')"}}},
        leave={{commands={'record(event)',"equip('idle')"}}}}},
    zones={leave={{commands={'record(event)'}}},enter={{commands={'record(event)',"equip('arrival')"}}}}
} end)
local service=Service.new(deps)
service.runtime=Runtime.new(config,deps)
listeners['status change'](1,0)
assert(#trace==1 and trace[1].kind=='status' and trace[1].category=='battle' and trace[1].phase=='enter')
assert(trace[1].status==1 and trace[1].old_status==0 and trace[1].new_status==nil)
assert(#commits==1 and #commits[1]==1 and commits[1][1]=='battle')
listeners['status change'](1,1); listeners['status change'](0,5)
assert(#trace==1)
listeners['status change'](2,1)
assert(trace[2].phase=='leave' and trace[2].status==2 and trace[2].old_status==1)
assert(commits[2][1]=='idle' and config.vars.counter==0)
-- Departure emits once, with destination unknown; arrival waits for live state.
listeners['incoming chunk'](0x00B,'raw','raw',true,false); assert(#trace==2)
listeners['incoming chunk'](0x00B,'raw','raw',false,true); assert(#trace==2)
listeners['incoming chunk'](0x00B,'raw','raw',false,false)
assert(#trace==3 and trace[3].phase=='leave' and trace[3].old_zone==1 and trace[3].zone==nil)
assert(trace[3].old_zone_name=='Old Zone' and trace[3].old_zone_search=='OldZone')
listeners['incoming chunk'](0x00B,'raw','raw',false,false)
listeners['status change'](0,1); assert(#trace==3) -- Zoning status changes aren't battle events.
listeners['zone change'](2,1); listeners['zone change'](2,1)
listeners.prerender(); assert(#trace==3) -- Still observing old zone.
info.zone=2; mob=nil; listeners.prerender(); assert(#trace==3)
mob={id=100,valid_target=false}; listeners.prerender(); assert(#trace==3)
mob.valid_target=true; listeners.prerender()
assert(#trace==4 and trace[4].phase=='enter' and trace[4].zone==2 and trace[4].old_zone==1)
assert(trace[4].zone_name=='New Zone' and trace[4].zone_search=='NewZone')
assert(commits[3][1]=='arrival')
listeners.prerender(); listeners['zone change'](2,1); listeners.prerender(); assert(#trace==4)
-- Fallback when no departure packet was observed: destination is already known.
listeners['zone change'](3,2)
assert(#trace==5 and trace[5].zone==3 and trace[5].old_zone==2 and trace[5].phase=='leave')
listeners.logout(); info.zone=3; listeners.prerender(); assert(#trace==5 and service.runtime==nil)
-- Schema rejects action phases/automatic restoration on observational sections.
for _,section in ipairs({'zones','statuses.battle','statuses.idle','statuses.death'}) do
    local function document(value)
        if section=='zones' then return {zones=value} end
        return {statuses={[section:match('%.(.+)$')]=value}}
    end
    assert(not pcall(Config.load,{'bad'},function() return document({pre={}}) end))
    assert(not pcall(Config.load,{'bad'},function() return document({use_equipment_snapshot=true}) end))
end
for _,document in ipairs({{battle={}},{zone={}},{statuses={unknown={}}},{statuses=false}}) do
    assert(not pcall(Config.load,{'bad'},function() return document end))
end
-- Cancellation isn't allowed; stop-only remains valid and equipment errors roll back.
local bad=Config.load({'test'},function() return {statuses={battle={enter={
    {commands={"equip('discarded')",'stopEvent(true)'}}}}}} end)
service.runtime=Runtime.new(bad,deps)
local before=#commits
service.runtime:observe({kind='status',category='battle',status=1,old_status=0},'enter')
assert(#errors==1 and errors[1]:find('only valid',1,true) and #commits==before)
-- Category changes notify leave before enter; 2/3 share one death category.
local all={statuses={}}
for _,category in ipairs({'battle','idle','death'}) do
    all.statuses[category]={enter={{commands={'record(event)',"equip(event.category .. ' enter')"}}},
        leave={{commands={'record(event)',"equip(event.category .. ' leave')",'stopEvent()'}}}}
end
service.runtime=Runtime.new(Config.load({'test'},function() return all end),deps)
trace={}; commits={}
listeners['status change'](1,0)
assert(#trace==2 and trace[1].category=='idle' and trace[1].phase=='leave')
assert(trace[2].category=='battle' and trace[2].phase=='enter')
assert(commits[1][1]=='idle leave' and commits[2][1]=='battle enter')
listeners['status change'](2,1)
assert(trace[3].category=='battle' and trace[3].phase=='leave')
assert(trace[4].category=='death' and trace[4].phase=='enter')
listeners['status change'](3,2); assert(#trace==4)
listeners['status change'](0,3)
assert(trace[5].category=='death' and trace[6].category=='idle')
assert(trace[5].status==0 and trace[5].old_status==3)
listeners['status change'](5,0)
assert(#trace==7 and trace[7].category=='idle' and trace[7].phase=='leave')
listeners['status change'](85,5); assert(#trace==7)
listeners['status change'](0,85)
assert(#trace==8 and trace[8].category=='idle' and trace[8].phase=='enter')
service:destroy()
print('PASS: status category transitions/order, phase batching, non-cancellation, zone departure/dedup/readiness and metadata')
