local Discovery=require('./lib/events/discovery')
local Service=require('./lib/events/init')
local now=0
local player={id=100,name='Tester'}
local target={id=200,index=2,name='Test NM',spawn_type=16,hpp=100}
local listeners={}
local saved,path
local deps={clock=function() return now end,resources={spells={},job_abilities={},weapon_skills={},monster_abilities={}},
    windower={ffxi={get_player=function() return player end,get_info=function() return {zone=15} end,
        get_mob_by_target=function() return target end,get_mob_by_id=function() return target end},
        register_event=function(name,fn) listeners[name]=fn; return name end,unregister_event=function() end},
    packets={parse=function(_,raw) assert(raw=='test'); return {Message=123,['Param 1']=2} end},
    writeProcessed=function(p,result) path=p; saved=result end,
    report=function(message) error(message) end}
local service=Service.new(deps)
assert(not Discovery.active())
assert(service:discovery('start'):find('started',1,true))
assert(service:discovery('start'):find('already exists',1,true))
now=1
listeners['incoming chunk'](0x02A,'test',nil,false,true)
listeners['incoming text']('weakness hint','modified',148)
local action={actor_id=100,category=3,param=46,targets={{id=200,actions={{message=185,param=100}}}}}
service:action(action)
action.param=99
now=2
assert(service:discovery('stop'):find('saved',1,true))
assert(path:find('discovery-',1,true) and saved.metadata.player.name=='Tester' and saved.metadata.zone==15)
assert(#saved.entries==3 and saved.entries[1].fields.Message==123)
assert(saved.entries[1].hex=='74657374' and saved.entries[1].blocked)
assert(saved.entries[2].original=='weakness hint' and saved.entries[3].action.param==46)
assert(not Discovery.active())
deps.packets.parse=function() return {} end -- Weakness observer remains active without recording.
listeners['incoming chunk'](0x02A,'test',nil,false,false)
assert(service:discovery('stop')=='No discovery recording is active.')
assert(Discovery.start(deps.clock,{}))
for i=1,8200 do Discovery.record('test',{n=i}) end
assert(not Discovery.active())
local result=Discovery.stop()
assert(result.truncated and #result.entries==8192)
assert(service:discovery('start'):find('started',1,true))
deps.writeProcessed=function() error('disk unavailable') end
assert(not pcall(service.discovery,service,'stop'))
assert(service.discoveryResult,'failed export must retain recording')
deps.writeProcessed=function(_,data) saved=data end
assert(service:discovery('stop'):find('saved',1,true) and not service.discoveryResult)
service:destroy()
print('PASS: discovery hooks, immutable evidence, bounded capture, disabled fast path, export and failed-write recovery')
