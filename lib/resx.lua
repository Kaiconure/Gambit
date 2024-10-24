local NumberToRoman = {
    'I',
    'II',
    'III',
    'IV',
    'V',
    'VI',
    'VII',
    'VIII',
    'IX',
    'X',
    'XI',
    'XII',
    'XIII',
    'XIV',
    'XV',
    'XVI',
    'XVII',
    'XVIII',
    'XIX',
    'XX'
}

--------------------------------------------------------------------------------------
-- Limited roman numeral -> number conversion for spell and ability tiers
function fromRomanNumeral(roman)
    -- Return the index of the specified roman numeral in the nubmer->roman numeral mapping
    return arrayIndexOfStrI(NumberToRoman, roman)
end

--------------------------------------------------------------------------------------
-- Limited number -> roman numeral conversion for spell and ability tiers
function toRomanNumeral(number)
    -- Return the value at [number] in the number->roman numeral mapping
    return NumberToRoman[number]
end

--------------------------------------------------------------------------------------
-- Find the roman numeral tier of the given spell or ability name
function romanNumeralTier(name)
    local nameLength = type(name) == 'string' and string.len(name) or 0

    if nameLength > 0 then
        name = string.upper(name)
        
        -- Find the last space
        local lastSpace = 0
        for i = nameLength, 1, -1 do
            if name[i] == ' ' then
                lastSpace = i
                break
            end
        end

        -- If there was a space, then we can grab the next character and treat that as the tier marker
        if lastSpace > 0 then
            local sub = string.sub(name, lastSpace + 1)

            if sub then
                -- Look for an item from the roman numerals list that exactly matches the potential tier marker
                for i, item in ipairs(NumberToRoman) do
                    if sub == item then
                        return i
                    end
                end
            end
        end
    end

    -- Anything without a tier marker will be treated as tier 1 (Cure, Stone, etc)
    return 1
end

--------------------------------------------------------------------------------------
--
local function matchResourceByNameEN(resource, enNameLowerCase)
    return resource and string.lower(resource.en) == enNameLowerCase
end

--------------------------------------------------------------------------------------
-- 
local function matchResourceByNameJP(resource, jpName)
    return resource and resource.jp == jpName
end

--------------------------------------------------------------------------------------
-- Given the specified resource table, find the first
-- match with the provided name
function findResourceByName(res, name, language)
    if type(res) ~= 'table' then return end
    if type(name) ~= 'string' then return end

    language = language or globals.language

    local matchFn = matchResourceByNameJP
    if language == 'English' then
        matchFn = matchResourceByNameEN
        name = string.lower(name)
    end

    return tableFirst(res, function (res) return matchFn(res, name) end)
end

--------------------------------------------------------------------------------------
--
function findWeaponSkill(name)
    return findResourceByName(resources.weapon_skills, name)
end

--------------------------------------------------------------------------------------
--
function findSpell(name)
    return findResourceByName(resources.spells, name)
end

--------------------------------------------------------------------------------------
--
function findJobAbility(name)
    return findResourceByName(resources.job_abilities, name)
end

--------------------------------------------------------------------------------------
--
function findItem(name)
    return findResourceByName(resources.items, name)
end

--------------------------------------------------------------------------------------
--
function findBuff(name)
    return findResourceByName(resources.buffs, name)
end

--------------------------------------------------------------------------------------
-- 
function findJob(symbol)
    symbol = toupper(symbol or '')
    return tableFirst(resources.jobs, function (job)
        return job.ens == symbol
    end)
end

--------------------------------------------------------------------------------------
-- Returns true if the two items have at least one set flag in common
function hasAnyFlagMatch(a, b)
    if type(a) == 'table' and type(b) == 'table' then
        for key, val in pairs(a) do
            if val == true and b[key] == true then
                return true
            end
        end
    end

    return false
end

--------------------------------------------------------------------------------------
-- Check if the resource can target a mob with the specified target flags
function hasMatchingTargetFlag(resource, targetFlags)
    if not resource or not resource.targets then return false end
    if not target or not target.targets then return false end

    for key, value in resource.targets do
        -- Return true if the resource targets and the corresponding
        -- target flags values are both set
        if value and targetFlags[key] then
            return true
        end
    end
end

--------------------------------------------------------------------------------------
-- Gets a spell resource from an id or name
local function getSpellResource(spell)
    if type(spell) == 'number' then spell = resource.spells[spell] end
    if type(spell) == 'string' then spell = findSpell(name) end

    if type(spell) ~= 'table' or type(spell.id) ~= 'number' or spell.id < 1 then
        return nil
    end

    return spell
end

--------------------------------------------------------------------------------------
-- Gets a job ability resource from an id or name
local function getJobAbilityResource(jobAbility)
    if type(jobAbility) == 'number' then jobAbility = resource.job_abilities[jobAbility] end
    if type(jobAbility) == 'string' then jobAbility = findJobAbility(jobAbility) end

    if type(jobAbility) ~= 'table' or type(jobAbility.id) ~= 'number' or jobAbility.id < 1 then
        return nil
    end

    return jobAbility
end

--------------------------------------------------------------------------------------
-- Gets a job ability resource from an id or name
local function getWeaponSkillResource(weaponSkill)
    if type(weaponSkill) == 'number' then weaponSkill = resource.weapon_skills[weaponSkill] end
    if type(weaponSkill) == 'string' then weaponSkill = findWeaponSkill(weaponSkill) end

    if type(weaponSkill) ~= 'table' or type(weaponSkill.id) ~= 'number' or weaponSkill.id < 1 then
        return nil
    end

    return weaponSkill
end

--------------------------------------------------------------------------------------
-- Check if the player has the specified buff
function hasBuff(player, buff, skiprecursion)
    player = player or windower.ffxi.get_player()

    -- Sleep is special. There are two separate status effects with the same name, so we will
    -- force ourselves to check both of them if we encounter a sleep check.
    if skiprecursion ~= true then
        if 
            (type(buff) == 'string' and buff:lower() == 'silence') or
            (type(buff) == 'number' and (buff == BUFF_SLEEP1 or buff == BUFF_SLEEP2)) or
            (type(buff) == 'table' and (buff.id == BUFF_SLEEP1 or buff.id == BUFF_SLEEP2))
        then
            return hasBuff(player, BUFF_SLEEP1, true) or hasBuff(player, BUFF_SLEEP2, true)
        end
    end

    if type(buff) == 'number' then buff = resources.buffs[buff] end
    if type(buff) == 'string' then buff = findBuff(buff) end

    if type(buff) ~= 'table' or type(buff.id) ~= 'number' or not resources.buffs[buff.id] then
        return false
    end

    return arrayIndexOf(player.buffs, buff.id) ~= nil
end

--------------------------------------------------------------------------------------
-- Check main and sub job levels against the spell requirements, and
-- determine if the specified spell could be available for use
function canJobUseSpell(player, spell)
    spell = getSpellResource(spell)

    -- Check the main job
    local jobLevel = player.main_job_level
    if jobLevel then
        local spellLevel = spell.levels[player.main_job_id]

        -- NOTE: Some spells unlocked with job points have a spell level of 100+ for those jobs. This
        -- check ensures we perform a proper job level comparison.
        if spellLevel and (spellLevel <= jobLevel or (spellLevel > 99 and jobLevel == 99)) then
            return true
        end
    end

    -- Check the sub job (if any)
    jobLevel = player.sub_job_level
    if jobLevel then
        local spellLevel = spell.levels[player.sub_job_id]
        if spellLevel and spellLevel <= jobLevel then
            return true
        end
    end    

    return false
end

--------------------------------------------------------------------------------------
--  Check if the specified blue magic spell is assigned
function hasBluSpellAssigned(player, spell)
    spell = getSpellResource(spell)

    local jobData = nil
    
    if player.main_job == 'BLU' then
        jobData = windower.ffxi.get_mjob_data()
    elseif player.sub_job == 'BLU' then
        jobData = windower.ffxi.get_sjob_data()
    end

    return jobData and tableFirst(jobData.spells, function (spellId)
        return spellId == spell.id
    end)
end

--------------------------------------------------------------------------------------
--
function canUseSpell(player, spell)
    player = player or windower.ffxi.get_player()

    spell = getSpellResource(spell)

    if spell == nil then
        return
    end

    -- Bail if we don't have enough MP
    if spell.mp_cost and player.vitals.mp < spell.mp_cost then
        return false
    end
    
    -- Bail if we're silenced or asleep
    if hasBuff(player, 'Silence') or hasBuff(player, 'Sleep') then
        return false
    end

    -- Bail if we haven't learned this spell at all
    local spellsLearned = windower.ffxi.get_spells()
    if not spellsLearned[spell.id] then
        return false
    end

    -- Bail if our current main/sub job cannot use the spell
    if not canJobUseSpell(player, spell) then
        return false
    end

    -- Bail if it's a blue magic spell and it is not assigned
    if spell.type == 'BlueMagic' and not hasBluSpellAssigned(player, spell) then
        return false
    end    

    --
    -- NOTE: At this point we know:
    --  1. The player has enough MP to cast the spell
    --  1. The player has learned this spell
    --  2. The current job (or sub job) can use this spell
    --  3. If this is blue magic, it's in the assigned list
    --
    -- Now we just need to verify that the recast is up
    --

    local recasts = windower.ffxi.get_spell_recasts()

    -- Recast will be a number in ticks, which is seconds * 60. The conversion doesn't
    -- matter if we're just checking for readiness.
    return recasts and recasts[spell.recast_id or spell.id] <= 0
end

--------------------------------------------------------------------------------------
--
function canUseAbility(player, ability)
    player = player or windower.ffxi.get_player()

    ability = getJobAbilityResource(ability)
    if not ability then
        return
    end

    -- Bail if the ability requires TP, and we don't have enough
    if 
        ability.tp_cost and 
        player.vitals.tp < ability.tp_cost 
    then
        return false
    end

    -- Bail if the ability requires MP, and we don't have enough. Note 
    -- that "Monster" abilities have an MP cost but it's our pet rather than ourselves.
    -- TODO: Research pet MP requirements and filtering.
    if 
        ability.mp_cost and
        ability.type ~= "Monster" and
        player.vitals.mp < ability.mp_cost 
    then
        return false
    end

    -- Bail if we have a debuff that prevents use of job abilities.
    -- Note: This also affects pet commands
    if
        hasBuff(player, 'Sleep') or
        hasBuff(player, 'Amnesia')
    then
        return false
    end

    -- NOTE: We should return false here if the ability is a pet command and there is no pet

    if 
        ability and
        ability.recast_id
    then
        local abilities = windower.ffxi.get_abilities()
        local jobAbilities = abilities and abilities.job_abilities or {}
        local petCommands = abilities and abilities.pet_commands or {}

        local foundJobAbility = arrayIndexOf(jobAbilities, ability.id)
        local foundPetCommand = arrayIndexOf(petCommands, ability.id)

        -- Look up recast timers if we found the job ability, or if we found the pet ability and we have a pet
        if  
            foundJobAbility or
            (foundPetCommand and windower.ffxi.get_mob_by_target('pet')) 
        then
            local recasts = windower.ffxi.get_ability_recasts()

            local recast = recasts and recasts[ability.recast_id]
            if type(recast) == 'number' and recast <= 0 then
                -- Recast will be a number in ticks, which is seconds * 60. The conversion doesn't
                -- matter if we're just checking for readiness, though.
                return true
            end
        end
    end

    return false
end

--------------------------------------------------------------------------------------
--
function canUseWeaponSkill(player, weaponSkill)
    player = player or windower.ffxi.get_player()

    weaponSkill = getWeaponSkillResource(weaponSkill)
    if weaponSkill == nil then
        return false
    end

    -- Bail if we don't have enough TP
    if player.vitals.tp < 1000 then
        return false
    end

    -- Bail if we have a debuff that prevents use of weapon skills
    if
        hasBuff(player, 'Sleep') or
        hasBuff(player, 'Amnesia')
    then
        return false
    end

    local abilities = windower.ffxi.get_abilities() or {}
    local knownWeaponSkills = abilities.weapon_skills or {}

    -- Only return true if the weapon skill we're checking is in the collection of available weapon skills
    for i, knownWeaponSkillId in pairs(knownWeaponSkills) do
        if knownWeaponSkillId == weaponSkill.id then
            return true
        end
    end

    return false
end