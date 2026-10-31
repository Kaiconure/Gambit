local skills=require('./meta/magic-skills')
local file=assert(io.open('lib/action-context.lua')); local source=file:read('*a'); file:close()
local body=assert(source:match('(    context.spellHasSkill = function.-)\n    context.skillchaining ='))
local spells={Dispel={id=260,skill=35},Cure={id=1,skill=33},Drain={id=245,skill=37}}
local context={}
local chunk=assert(loadstring(body))
setfenv(chunk,{context=context,type=type,pairs=pairs,magicSkills=skills,findSpell=function(value)
    for name,spell in pairs(spells) do if value==name or value==spell.id then return spell end end
end})
chunk()
assert(context.isEnfeeblingSpell('Dispel'))
assert(context.isEnfeeblingSpell(260))
assert(context.isEnfeeblingSpell(spells.Dispel))
assert(context.isEnfeeblingSpell({kind='spell',id=260}))
assert(context.isEnfeeblingSpell({name='Dispel'}))
assert(not context.isEnfeeblingSpell({kind='job_ability',id=260}))
assert(not context.isEnfeeblingSpell('Cure'))
assert(not context.isEnfeeblingSpell('Drain'))
assert(not context.isEnfeeblingSpell('unknown'))
assert(not context.isEnfeeblingSpell(nil))
assert(not context.isEnfeeblingSpell({}))
assert(context.isHealingSpell('Cure') and not context.isDarkSpell('Cure'))
assert(context.isDarkSpell('Drain') and not context.isElementalSpell('Drain'))
assert(context.spellHasSkill('Dispel',35))
assert(context.spellHasSkill('Dispel','enfeebling'))
assert(not context.spellHasSkill('Dispel','unknown'))
assert(not context.spellHasSkill('Dispel',nil))
for helper,skill in pairs({isDivineSpell='divine',isHealingSpell='healing',
    isEnhancingSpell='enhancing',isEnfeeblingSpell='enfeebling',
    isElementalSpell='elemental',isDarkSpell='dark',isSummoningSpell='summoning',
    isNinjutsuSpell='ninjutsu',isSingingSpell='singing',isBlueSpell='blue',isGeomancySpell='geomancy'}) do
    spells.Probe={id=999,skill=skills[skill]}
    assert(context[helper]('Probe'),helper)
    assert(not context[helper]({kind='job_ability',id=999}),helper)
end
print('PASS: enfeebling skill classification, name/ID/resource/event inputs and invalid inputs')
