local Config=require('./lib/events/config')
local processed=require('./lib/events/processed')
local json=require('./lib/jsonlua')
local docs={['./events/geo.json']={imports={'lib/base'},vars={['csv(A,B)']={x=1}},
    spells={pre={{id='replace',when={'true'},commands={'replacement()'}}}},
    statuses={idle={enter={{commands={'idle()'}}}}}},
    ['./events/lib/base.json']={spells={use_equipment_snapshot=true,pre={
        {id='replace',commands={'old()'}},{commands={'retained()'}}}},
        loading={actions={{commands={"vars.initialized=true"}}}}}}
local config=Config.load({'./events/geo.json'},function(path) return docs[path] end)
local output=processed(config)
assert(output.spells.pre[1].commands[1]=='retained()')
assert(output.spells.pre[2].commands[1]=='replacement()' and output.spells.pre[2].when[1]=='true')
assert(output.spells.pre[2]._source=='./events/geo.json:spells.pre[1]')
assert(output.statuses.idle.enter[1].commands[1]=='idle()')
assert(output.spells.use_equipment_snapshot and output.loading.actions[1].commands[1]=='vars.initialized=true')
assert(output.vars.A.x==1 and output.vars.B.x==1 and #output._sources.files==2)
assert(output.imports==nil)
assert(json.parse(json.stringify(output)).spells.pre[2].id=='replace')
output.vars.A.x=9; assert(config.vars.A.x==1)
-- Real reload writes only when requested, before loading mutates defaults.
local Service=require('./lib/events/init')
local writes={}
local service=Service.new({windower={ffxi={get_player=function() return {id=1,name='Tester',main_job='GEO'} end},
    register_event=function(name) return name end,unregister_event=function() end},resources={},
    read=function(path) return docs[path] end,clock=function() return 0 end,
    context=function(_,state) return {vars=state.vars} end,report=function(err) error(err) end,
    writeProcessed=function(path,value) writes[#writes+1]={path=path,value=value} end})
service:reload(); assert(#writes==0)
service:reload(true)
assert(#writes==1 and writes[1].path=='./settings/Tester/.output/geo.events.processed.json')
assert(writes[1].value.vars.initialized==nil and service.runtime.config.vars.initialized==true)
service:destroy()
print('PASS: processed event ordering/source metadata, expanded vars, JSON safety, optional output and before-loading snapshot')
