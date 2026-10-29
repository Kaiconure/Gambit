local classify=require('./lib/cure-spell')
local ids=require('./meta/cure-spells')
local spells={Cure={id=1,skill=33},Curaga={id=7,skill=33},Cura={id=93,skill=33},
    ['Full Cure']={id=893,skill=33},Poisona={id=14,skill=33},Raise={id=12,skill=33},
    Regen={id=108,skill=34},['White Wind']={id=690,skill=43}}
for id in pairs(ids) do
    assert(classify({id=id,skill=33}))
    assert(not classify({id=id,skill=35}))
end
assert(not classify(nil) and not classify({}) and not classify({id=999,skill=33}))
local file=assert(io.open('lib/action-context.lua')); local source=file:read('*a'); file:close()
local body=assert(source:match('(    context.isCureSpell = function.-)\n    context.canMagicBurst ='))
local context={}
local chunk=assert(loadstring(body))
setfenv(chunk,{context=context,type=type,cureSpell=classify,findSpell=function(value)
    for name,spell in pairs(spells) do if value==name or value==spell.id then return spell end end
end})
chunk()
for _,name in ipairs({'Cure','Curaga','Cura','Full Cure'}) do
    local spell=spells[name]
    assert(context.isCureSpell(name) and context.isCureSpell(spell.id))
    assert(context.isCureSpell(spell) and context.isCureSpell({kind='spell',id=spell.id}))
    assert(not context.isCureSpell({kind='job_ability',id=spell.id}))
end
for _,name in ipairs({'Poisona','Raise','Regen','White Wind','unknown'}) do
    assert(not context.isCureSpell(name))
end
assert(not context.isCureSpell(nil) and not context.isCureSpell({}))
print('PASS: cure families, skill guard, name/ID/resource/event inputs and non-cure exclusions')
