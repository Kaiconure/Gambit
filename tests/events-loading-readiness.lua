local Events=require('./lib/events/init')
local Equipment=require('./lib/equipment/init')
local now=0
local player,mob,items=nil,nil,nil
local info={zone=0,logged_in=false}
local listeners={}
local ffxi={get_player=function() return player end,get_mob_by_target=function() return mob end,
    get_info=function() return info end,get_items=function() return items end,
    get_party=function() return {} end}
local windower={ffxi=ffxi,register_event=function(name,fn)
    listeners[name]=listeners[name] or {}; table.insert(listeners[name],fn); return fn
end,unregister_event=function() end}
local function notify(name,...)
    for _,fn in ipairs(listeners[name] or {}) do fn(...) end
end
local sends,records,contexts={},{},0
local equipment=Equipment.new({windower=windower,clock=function() return now end,
    report=function(err) error(err) end,
    inventory={get_item_from_bag=function(_,bag,index) return {id=index} end},
    packets={new=function(_,_,values) return values end,inject=function(packet)
        sends[#sends+1]={time=now,packet=packet}
    end}})
local document={vars={version='first'},loading={actions={{commands={
    'record(vars.version)',"equip('idle ring')"}}}}}
local deps={windower=windower,resources={},clock=function() return now end,
    report=function(err) error(err) end,
    zoneReady=function() return equipment:isReady() end,
    read=function(path) if path=='./settings/events/geo.json' then return document end end,
    context=function(_,state)
        contexts=contexts+1
        return {vars=state.vars,record=function(value) records[#records+1]=value end,
            equip=function() state.equipment.changed=true end}
    end,
    equipmentSession=function()
        return {inventory={},discard=function() end,commit=function(self)
            if self.changed then equipment:submit({{slot=13,item={localId=51,bagId=10,id=51}}}) end
        end}
    end}
local events=Events.new(deps)
assert(not equipment:isReady())
events:reload() -- Addon loaded at character selection: nothing to load yet.
assert(not events.runtime and contexts==0 and #sends==0)
player={id=100,name='Tester',main_job='GEO'}
info={zone=1,logged_in=true}
-- Main login reload can precede the equipment service's login listener.
events:reload()
local old=events.runtime
assert(events.loadingPending==old and not old.loaded)
notify('login')
for i=1,20 do now=now+1; notify('prerender') end
assert(contexts==0 and #records==0 and #sends==0)
-- A replacement reload must supersede the old pending run.
document.vars.version='second'
events:reload()
local current=events.runtime
assert(current~=old and events.loadingPending==current)
local validDocument=document
document={loading={actions={{commands={'broken('}}}}}
assert(not pcall(events.reload,events) and events.runtime==current and events.loadingPending==current)
document=validDocument -- Failed compilation must preserve the prior pending configuration.
mob={id=100,valid_target=false}
items={equipment={left_ring=64,left_ring_bag=10}}
notify('prerender'); assert(#records==0)
mob.valid_target=true
notify('prerender'); assert(#records==0)
now=now+1; notify('prerender')
assert(equipment:isReady() and current.loaded and not old.loaded)
assert(#records==1 and records[1]=='second' and contexts==1)
assert(#sends==1 and sends[1].time==now and sends[1].packet['Item Index']==51)
assert(equipment.queue.batches[1].ops[1].first_sent_at==now)
notify('prerender'); assert(#records==1)
-- Ordinary ready reload runs immediately, once.
events:reload(); assert(#records==2)
-- Zoning holds loading until the destination is ready, without dropping it.
notify('incoming chunk',0x00B,string.char(0,0,0,0),nil,false,false)
document.vars.version='destination'
events:reload(); local destination=events.runtime
assert(not destination.loaded)
for i=1,20 do now=now+1; notify('prerender') end
assert(#records==2)
info.zone=2; notify('zone change',2,1)
notify('prerender'); now=now+1; notify('prerender')
assert(destination.loaded and #records==3 and records[3]=='destination')
-- Logout invalidates a waiting runtime. Becoming ready afterward cannot run it.
notify('incoming chunk',0x00B,string.char(0,0,0,0),nil,false,false)
events:reload(); local abandoned=events.runtime
notify('logout')
assert(not events.runtime and not events.loadingPending)
mob.valid_target=true; now=now+10; notify('prerender'); now=now+1; notify('prerender')
assert(not abandoned.loaded and #records==3)
notify('incoming chunk',0x00B,string.char(0,0,0,0),nil,false,false)
events:reload(); local unloaded=events.runtime
assert(events.loadingPending==unloaded)
events:destroy(); equipment:destroy()
assert(not unloaded.loaded and not events.loadingPending)
print('PASS: logged-out startup, login listener order, player/equipment readiness, superseding reload, once-only loading, zone deferral and logout cancellation')
