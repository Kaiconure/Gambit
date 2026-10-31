local elements=require('./lib/skillchain-elements')
local magicSkills=require('./meta/magic-skills')
local burst={}

-- Eligibility now, independent of spell usability or predicted landing time.
function burst.check(value,target,context,deps)
    local object=type(value)=='table' and value or nil
    if object and object.kind and object.kind~='spell' then return false end
    local spell=deps.findSpell(object and (object.id or object.name) or value)
    if not spell then return false end
    if target==nil then target=object and object.target or context.bt end
    if type(target)=='number' then target={id=target} end
    if type(target)~='table' or type(target.id)~='number' then return false end
    local chain
    if context.bt and target.id==context.bt.id then
        chain=context.skillchain
    else
        chain=deps.getSkillchain(target)
    end
    if not chain then return false end
    local element=deps.elements[spell.element]
    if not element then return false end
    if spell.skill==magicSkills.blue then
        local ability=deps.findMonsterAbility and deps.findMonsterAbility(spell.en or spell.name)
        -- Empty strings are still physical; only an explicitly absent field qualifies.
        if not ability or ability.skillchain_a~=nil then return false end
    end
    for _,name in ipairs(elements[chain.name] or {}) do
        if element.en==name or element.name==name then return true end
    end
    return false
end
return burst
