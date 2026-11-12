-- Classify confirmed equipment without modifying inventory or resource records.
local oneHanded = {[2]=true, [3]=true, [5]=true, [9]=true, [11]=true}
local twoHanded = {[4]=true, [6]=true, [7]=true, [8]=true, [10]=true, [12]=true}

return function(equipment, slot)
    if not equipment then return nil end
    local item = equipment.item or {}
    local skill = item.skill
    return {
        slot = slot,
        id = equipment.id,
        name = equipment.name,
        item = item,
        skill = skill,
        one_handed = oneHanded[skill] == true,
        two_handed = twoHanded[skill] == true,
        shield = type(item.shield_size) == 'number' and item.shield_size > 0,
        h2h = skill == 1,
        archery = skill == 25,
        marksmanship = skill == 26,
        throwing = skill == 27,
    }
end
