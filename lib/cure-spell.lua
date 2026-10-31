local ids=require('./meta/cure-spells')
local skills=require('./meta/magic-skills')
return function(spell)
    return type(spell)=='table' and spell.skill==skills.healing and ids[spell.id]==true
end
