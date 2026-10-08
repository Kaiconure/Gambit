local sc_opening = require('meta/sc-opening')
local sc_continuation = require('meta/sc-continuation')

local helper = {}

local all_non_elemental_weapon_skills = 
{
  "Dimensional Death",
  "Vulcan Shot",
  "Barbed Crescent",
  "Dancing Chains",
  "Aegis Schism",
  "Carnal Nightmare",
  "Netherspikes",
  "Grim Halo",
  "Foxfire",
  "Shackled Fists",
  "Barbed Crescent",
  "Dancing Chains",
  "Aegis Schism",
  "Carnal Nightmare",
  "Netherspikes",
  "Tartarus Torpor",
  "Myrkr",
  "Spirit Taker",
  "Dagan",
  "Mystic Boon",
  "Moonlight",
  "Starlight",
  "Sanguine Blade",
  "Spirits Within",
  "Energy Drain",
  "Energy Steal"
}

helper.apply_preferences = function(weapon_skill_names, all_preferred, all_blocked)
    if weapon_skill_names then
        if all_blocked then
            for i = #weapon_skill_names, 1, -1 do
                local weapon_skill_name = string.lower(weapon_skill_names[i])

                for j, blocked in ipairs(all_blocked) do
                    
                    if string.lower(blocked) == weapon_skill_name then
                        table.remove(weapon_skill_names, i)
                        break
                    end
                end
            end
        end

        if all_preferred then
            local found_preferred = {}
            for i = #weapon_skill_names, 1, -1 do
                local weapon_skill_name = string.lower(weapon_skill_names[i])

                for j, preferred in ipairs(all_preferred) do
                    if string.lower(preferred) == weapon_skill_name then
                        -- Remove the weapon skill from the current location, and queue it up in the preferred list
                        table.remove(weapon_skill_names, i)
                        table.insert(found_preferred, weapon_skill_name)
                        break
                    end
                end
            end

            -- For any preferences found, insert them in their original order at the front of the
            -- weapon skill names list.
            for i = #found_preferred, 1, -1 do
                local weapon_skill_name = string.lower(found_preferred[i])
                table.insert(weapon_skill_names, 1, weapon_skill_name)
            end
        end
    end
end

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
helper.filter_weapon_skills = function(possible_weapon_skills, filter_ids, all_preferred, all_blocked)
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

    -- Strips blocked weapon skills from the list, and moves preferred weapon skills to the front.
    helper.apply_preferences(result, all_preferred, all_blocked)

    return #result > 0 and result or nil
end

---------------------------------------------------------------------------------------------------
-- Similar to filter_weapon_skills, but uses all possible non-elemental weapon skills
-- as the source pool
helper.filter_non_elemental = function(filter_ids, all_preferred, all_blocked)
    return helper.filter_weapon_skills(all_non_elemental_weapon_skills, filter_ids, all_preferred, all_blocked)
end

return helper