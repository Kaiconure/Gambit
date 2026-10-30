local file=assert(io.open('Gambit.lua')); local source=file:read('*a'); file:close()
local recording=assert(source:match('(%-%- Record completed self job abilities.-)\n    local actor ='))
local globals={}
local now=123.5
local env={globals=globals,packet={['Target 1 ID']=200},tonumber=tonumber,os={clock=function() return now end},
    resources={job_abilities={[10]={id=10,name='Convert'},[11]={id=11,name='Composure'}},
        spells={[10]={id=10,name='Cure'},[11]={id=11,name='Refresh'}}},
    windower={ffxi={get_player=function() return {id=100} end,
        get_mob_by_id=function(id) if id==200 then return {id=id,name='Ally',index=20} end end}}}
local function record(category,id,actor)
    env.category=category; env.actionId=id; env.actorId=actor
    local chunk=assert(loadstring(recording)); setfenv(chunk,env); chunk()
end
record(6,10,200); assert(globals.last_ability==nil)
env.packet['Target 1 Action 1 Param']=10
record(8,24931,200); assert(globals.last_spell==nil)
record(8,28787,100); assert(globals.last_spell==nil)
record(8,24931,100)
assert(globals.last_spell.name=='Cure' and globals.last_spell.status=='casting')
assert(globals.last_spell.target.name=='Ally')
now=124
record(8,28787,200); assert(globals.last_spell.status=='casting')
record(8,28787,100)
assert(globals.last_spell.status=='interrupted' and globals.last_spell.time==124)
now=125
record(8,28787,100); assert(globals.last_spell.time==124)
env.packet['Target 1 Action 1 Param']=11
record(8,24931,100)
assert(globals.last_spell.name=='Refresh' and globals.last_spell.status=='casting')
now=126
record(4,11,100)
assert(globals.last_spell.status=='completed' and globals.last_spell.time==126)
record(8,28787,100); assert(globals.last_spell.status=='completed')
now=123.5
record(4,10,100); assert(globals.last_ability==nil)
record(6,10,100)
assert(globals.last_ability.name=='Convert' and globals.last_ability.time==123.5)
assert(globals.last_ability.target.id==200 and globals.last_ability.target.name=='Ally'
    and globals.last_ability.target.index==20)
record(14,11,100); assert(globals.last_ability.id==11)
record(6,999,100); assert(globals.last_ability.id==11)
assert(globals.last_spell.name=='Cure' and globals.last_spell.time==123.5)
assert(globals.last_spell.target.id==200 and globals.last_spell.target.name=='Ally' and globals.last_spell.target.index==20)
record(4,11,200); assert(globals.last_spell.id==10)
record(8,11,100); assert(globals.last_spell.id==10) -- Unrecognized category-8 param is ignored.
record(4,11,100); assert(globals.last_spell.id==11 and globals.last_ability.id==11)
record(4,999,100); assert(globals.last_spell.id==11)
env.packet['Target 1 ID']=300
record(4,11,100)
assert(globals.last_spell.target.id==300 and globals.last_spell.target.name==nil)
record(6,11,100)
assert(globals.last_ability.target.id==300 and globals.last_ability.target.name==nil
    and globals.last_ability.target.index==nil)
env.packet['Target 1 ID']=nil
record(4,11,100); assert(globals.last_spell.target==nil)
record(14,11,100); assert(globals.last_ability.target==nil)
env.packet['Target 1 ID']=200
record(4,11,100)
record(14,11,100)
env.windower.ffxi.get_player=function() return nil end
record(4,10,100); assert(globals.last_spell.id==11)
record(6,10,100); assert(globals.last_ability.id==11)
local file=assert(io.open('lib/action-context.lua')); source=file:read('*a'); file:close()
local fields=assert(source:match('gambit = ({.-\n        }),'))
local context=assert(loadstring('return '..fields))
local contextEnv={globals=globals,settings={},time=125,settingsPaths={getLoadedNamespace=function() end},
    targetMetadata=require('./lib/target-metadata'),windower=env.windower}
setfenv(context,contextEnv)
assert(context().last_ability.age==1.5 and context().last_spell.age==1.5)
local defaults=require('./lib/ux/status-config').defaults.tracking.sets.default
for _,entry in ipairs(defaults) do
    if entry.name=='Spell' or entry.name=='Ability' then
        local display=assert(loadstring('return '..entry.expression[1]))
        contextEnv.time=129.49
        setfenv(display,{gambit=context(),format=string.format})
        assert(type(display())=='string')
        contextEnv.time=129.5
        setfenv(display,{gambit=context(),format=string.format})
        assert(display()==nil)
    end
end
local snapshot=context().last_ability
assert(snapshot.name=='Composure' and snapshot.time==123.5)
snapshot.name='Changed'; assert(globals.last_ability.name=='Composure')
assert(snapshot.target.name=='Ally' and snapshot.target.id==200 and snapshot.target.index==20)
snapshot.target.name='Changed'; assert(globals.last_ability.target.name=='Ally')
local spellSnapshot=context().last_spell
assert(spellSnapshot.status=='completed')
assert(spellSnapshot.name=='Refresh' and spellSnapshot.time==123.5)
spellSnapshot.name='Changed'; assert(globals.last_spell.name=='Refresh')
assert(spellSnapshot.target.name=='Ally')
spellSnapshot.target.name='Changed'; assert(globals.last_spell.target.name=='Ally')
env.windower.ffxi.get_mob_by_id=function() return {id=200,index=20,name='New live name',
    spawn_type=16,status=2,valid_target=true} end
assert(context().last_spell.target.is_dead and context().last_ability.target.is_mob)
assert(context().last_spell.target.name=='Ally')
env.windower.ffxi.get_mob_by_id=function() return nil end
assert(not context().last_spell.target.valid_target and context().last_spell.target.id==200)
assert(context().last_ability.target.is_mob==nil)
globals.last_spell=nil; assert(context().last_spell==nil)
globals.last_ability=nil; assert(context().last_ability==nil)
print('PASS: self completed abilities, category filtering, unknown resources, missing player and isolated context snapshot')
