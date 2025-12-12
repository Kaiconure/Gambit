local sc_opening = require('meta/sc-opening')
local sc_continuation = require('meta/sc-continuation')

local helper = {}

---------------------------------------------------------------------------------------------------
-- With a given skillchain active, determine which weapon skills can be used to make
-- an appropriate continuation skillchain.
helper.get_skillchain_continuation = function(with_skillchain, make_skillchain)
    with_skillchain = string.lower(with_skillchain)
    make_skillchain = string.lower(make_skillchain)

    return 
        with_skillchain and 
        make_skillchain and 
        sc_continuation[with_skillchain] and 
        sc_continuation[with_skillchain][make_skillchain]
end

---------------------------------------------------------------------------------------------------
-- Identify all possible weapon skill combinations that can be used to create an initial
-- opening skillchain sequence.
helper.find_skillchain_openings = function (skillchain)
    skillchain = string.lower(skillchain)

    return
        skillchain and
        sc_opening[skillchain]
end

---------------------------------------------------------------------------------------------------
-- Given a list of possible weapon skill names, and the result of windower.ffxi.get_abilities().weapon_skills,
-- return a copy of the possible weapon skills limited to only those usable by you. If no filter is
-- provided (nil), then filtering will not occur but transformation will be performed.
helper.filter_weapon_skills = function(possible_weapon_skills, filter_ids)
    if not possible_weapon_skills then
        return
    end

    local result = {}
    if filter_ids then
        table.sort(filter_ids)

        for i = #filter_ids, 1, -1 do
            local id = filter_ids[i]
            local ws = resources.weapon_skills[id]

            if ws then
                if table.find(possible_weapon_skills, string.lower(ws.name)) then
                    table.insert(result, ws.name)
                end
            end
        end
    else
        for id = 255, 1, -1 do
            local ws = resources.weapon_skills[id]

            if ws then
                if table.find(possible_weapon_skills, string.lower(ws.name)) then
                    table.insert(result, ws.name)
                end
            end
        end
    end

    return #result > 0 and result or nil
end

return helper