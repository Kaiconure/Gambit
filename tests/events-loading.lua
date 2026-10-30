local Config=require('./lib/events/config')
local Runtime=require('./lib/events/runtime')
local Service=require('./lib/events/init')
local traces,errors,commits={},{},0
local document={vars={count=0,sets={['csv(A,B)']={head='Hat'}}},loading={actions={
    {comment={anything=true}},
    {when={'vars.count==0'},commands={"setVar('count', vars.count+1)","setVar('ready', true)",
        "setVar('selected', vars.sets.A)","equip('loading gear')",'stopEvent()'}},
    {commands={"setVar('must_not_run',true)"}},
}},spells={pre={{commands={'record(vars.count)',"setVar('count',99)"}}}}}
local deps={clock=function() return 1 end,report=function(err) errors[#errors+1]=err end,
    context=function(_,state) return {vars=state.vars,
        setVar=function(name,value) state.vars[name]=value end,
        record=function(value) traces[#traces+1]=value end,
        equip=function() state.equipment.changed=true end} end,
    equipmentSession=function()
        local s={inventory={snapshot_equipment=function() return {} end}}
        function s:commit() if self.changed then commits=commits+1 end end
        function s:discard() end
        return s
    end,
    schedule=function(fn) fn() end}
local function config() return Config.load({'selected'},function() return document end) end
local c=config()
local runtime=Runtime.new(c,deps)
runtime:loading(); runtime:loading()
assert(c.vars.count==1 and c.vars.ready and not c.vars.must_not_run and c.vars._==nil and commits==1)
assert(c.vars.selected.head=='Hat' and c.vars.sets.B.head=='Hat')
runtime:submit({kind='spell',id=1,target={id=1}},function() end)
runtime:complete('spell',1,nil,'completed')
runtime:submit({kind='spell',id=2,target={id=1}},function() end)
assert(traces[1]==1 and traces[2]==1 and c.vars.count==1) -- Per-lifecycle isolation remains.
-- Every real reload compiles fresh vars and executes loading exactly once.
deps.resources={}
deps.windower={ffxi={get_player=function() return {id=1,name='Tester',main_job='GEO'} end},
    register_event=function(name) return name end,unregister_event=function() end}
deps.read=function(path) if path=='./settings/events/geo.json' then return document end end
local service=Service.new(deps)
service:reload(); service:reload()
assert(commits==3 and service.runtime.config.vars.count==1)
local previous=service.runtime
deps.read=function() return {loading={actions={{commands={'broken('}}}}} end
assert(not pcall(service.reload,service) and service.runtime==previous and commits==3)
-- Failed loading never publishes partial vars or commits equipment.
document={vars={count=0},loading={actions={{commands={"setVar('count',5)","equip('bad')",'cancelEvent()'}}}}}
c=config(); runtime=Runtime.new(c,deps); runtime:loading()
assert(c.vars.count==0 and commits==3 and #errors==1)
assert(not pcall(Config.load,{'bad'},function() return {loading={pre={}}} end))
assert(not pcall(Config.load,{'bad'},function() return {loading={use_equipment_snapshot=true}} end))
service:destroy()
print('PASS: loading order/stop, initialized defaults, persistent gear, reload once, validation/error handling and retained lifecycle isolation')
