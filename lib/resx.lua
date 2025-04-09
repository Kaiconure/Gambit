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
    local lower = string.lower(resource.en)
    local lowerl = type(resource.enl) == 'string' and string.lower(resource.enl) or nil

    return resource and (
        (lower == enNameLowerCase or
            "\"%s\"":format(lower) == enNameLowerCase) or
        (lowerl and 
            (lowerl == enNameLowerCase or "\"%s\"":format(lowerl) == enNameLowerCase))
    )
end

--------------------------------------------------------------------------------------
-- 
local function matchResourceByNameJP(resource, jpName)
    return resource and resource.jp == jpName
end

--------------------------------------------------------------------------------------
-- Given the specified resource table, find the first match with 
-- the provided name
function findResourceByName(res, name, language)
    if type(res) ~= 'table' then return end
    --if type(name) == 'table' and name.name then name = name.name end

    -- If it's a table, convert to its id or name
    if type(name) == 'table' then
        if type(name.id) == 'number' then
            name = name.id
        elseif type(name.name) == 'string' then
            name = name.name
        end
    end

    -- Allow numeric id's in
    if type(name) == 'number' then
        return res[name]
    end    

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
function findKeyItem(name)
    return findResourceByName(resources.key_items, name)
end

--------------------------------------------------------------------------------------
--
function findBuff(name)
    return name and findResourceByName(resources.buffs, name)
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
-- Gets an item resource from an id or name
local function getItemResource(item)
    if type(item) == 'number' then item = resources.items[spell] end
    if type(item) == 'string' then item = findItem(item) end

    if type(item) ~= 'table' or type(item.id) ~= 'number' or item.id < 1 then
        return nil
    end

    return item
end

--------------------------------------------------------------------------------------
-- Gets a spell resource from an id or name
local function getSpellResource(spell)
    if type(spell) == 'number' then spell = resources.spells[spell] end
    if type(spell) == 'string' then spell = findSpell(spell) end

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

function hasBuffInArray(buffs, buff, strict)
    -- Nothing to do if we don't have a buffs array to search
    if type(buffs) ~= 'table' or #buffs < 1 then return end

    local check_list = { }

    if type(buff) == 'string' then
        check_list = meta.buffs:get_ids_by_name(buff)
    elseif type(buff) == 'number' then
        if strict then 
            check_list = { buff } 
        else
            check_list = meta.buffs:get_with_shared_name_by_id(buff)
        end
    elseif type(buff) == 'table' and type(buff.id) == 'number' then
        if strict then
            check_list = { buff.id }
        else
            check_list = meta.buffs:get_with_shared_name_by_id(buff.id)
        end
    end

    -- Now find if any buffs in the check list are present. If the check list is not a table, it
    -- means that the buff didn't correspond to something we know about (invalid name, etc)
    if type(check_list) == 'table' then
        for i, id in pairs(check_list) do
            if arrayIndexOf(buffs, id) then
                return resources.buffs[id]
            end
        end
    end
end

--------------------------------------------------------------------------------------
-- Check if the player has the specified buff. If strict, no duplication matching
-- is performed at only the exact match is evaluated. This is only valid when
-- and id or an actual buff table entry is provided.
function hasBuff(player, buff, strict)
    player = player or windower.ffxi.get_player()
    return player and hasBuffInArray(player.buffs, buff, strict)
end

--------------------------------------------------------------------------------------
-- Check if the player has the specified buff
function hasBuffOrig(player, buff, skiprecursion)
    player = player or windower.ffxi.get_player()

    -- Sleep is special. There are two separate status effects with the same name, so we will
    -- force ourselves to check both of them if we encounter a sleep check.
    if skiprecursion ~= true then
        if 
            --(type(buff) == 'string' and buff:lower() == 'silence') or
            (type(buff) == 'number' and (buff == BUFF_SLEEP1 or buff == BUFF_SLEEP2)) or
            (type(buff) == 'table' and (buff.id == BUFF_SLEEP1 or buff.id == BUFF_SLEEP2))
        then
            return hasBuff(player, BUFF_SLEEP1, true) or hasBuff(player, BUFF_SLEEP2, true)
        end
    end

    if type(buff) == 'number' then buff = resources.buffs[buff] end
    if type(buff) == 'string' then buff = findBuff(buff) end

    if type(buff) ~= 'table' or type(buff.id) ~= 'number' or not resources.buffs[buff.id] then
        return nil
    end

    if arrayIndexOf(player.buffs, buff.id) ~= nil then
        return buff
    end
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
function canUseSpell(player, spell, recasts, spellsLearned)
    player = player or windower.ffxi.get_player()

    spell = getSpellResource(spell)

    if spell == nil then
        return
    end

    -- Bail if we don't have enough MP
    if spell.mp_cost and player.vitals.mp < spell.mp_cost then
        return
    end
    
    -- Bail if we're silenced or asleep
    if 
        hasBuff(player, BUFF_SILENCE) or
        hasBuff(player, BUFF_SLEEP1) or
        hasBuff(player, BUFF_SLEEP2) or
        hasBuff(player, BUFF_STUN) or
        hasBuff(player, BUFF_PETRIFIED) or
        hasBuff(player, BUFF_TERROR)
    then
        return
    end

    -- Bail if we haven't learned this spell at all
    spellsLearned = spellsLearned or windower.ffxi.get_spells()
    if 
        not spellsLearned or
        not spellsLearned[spell.id] 
    then
        return
    end

    -- Bail if our current main/sub job cannot use the spell
    if not canJobUseSpell(player, spell) then
        return
    end

    -- Bail if it's a blue magic spell and it is not assigned
    if spell.type == 'BlueMagic' and not hasBluSpellAssigned(player, spell) then
        return
    end

    -- Don't allow trusts in non-trust zones
    if spell.type == 'Trust' then
        if globals.currentZone then
            if 
                globals.currentZone.can_pet ~= true or
                globals.currentZone.id == 80 -- South San d'Oria [S] seems to be inappropriately tagged
            then
                return
            end
        end
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

    recasts = recasts or windower.ffxi.get_spell_recasts()
    if not recasts then return end

    local recast = recasts[spell.recast_id or spell.id]
    if not recast then return end

    -- Recast will be a number in ticks, which is seconds * 60
    return recast <= 0, (recast / 60)
end

--------------------------------------------------------------------------------------
--
function canUseAbility(player, ability, recasts)
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

    -- Bail if the ability is a Corsair double-up, without the double-up buff active
    if
        ability.id == 123 and       -- Double-up
        not hasBuff(player, 308)    -- Double-up chance
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

    -- Bail if we have a status effect that prevents use of job abilities.
    -- Note: This also affects pet commands
    if
        hasBuff(player, BUFF_SLEEP1) or
        hasBuff(player, BUFF_SLEEP2) or
        hasBuff(player, BUFF_STUN) or
        hasBuff(player, BUFF_PETRIFIED) or
        hasBuff(player, BUFF_AMNESIA) or
        hasBuff(player, BUFF_TERROR) or
        (ability.type == 'Waltz' and hasBuff(player, BUFF_SABER_DANCE)) or
        (ability.type == 'Samba' and hasBuff(player, BUFF_FAN_DANCE))
    then
        return false
    end

    -- NOTE: We should return false here if the ability is a pet command and there is no pet

    if 
        ability and
        ability.recast_id
    then
        recasts = recasts or windower.ffxi.get_ability_recasts()

        if 
            ability.recast_id == 231 and    -- Strategems
            getMaxStratagems(player) > 0
        then
            if getAvailableStratagems(player, recasts) > 0 then
                return 0
            end
        end

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
            local recast = recasts and recasts[ability.recast_id]
            if type(recast) == 'number' then
                -- Recast will be a number in ticks, which is seconds * 60
                recast = recast / 60
                return recast <= 0, recast
            end
        end
    end

    return false
end

--------------------------------------------------------------------------------------
--
function canUseWeaponSkill(player, weaponSkill, abilities)
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
        hasBuff(player, BUFF_SLEEP1) or
        hasBuff(player, BUFF_SLEEP2) or
        hasBuff(player, BUFF_STUN) or
        hasBuff(player, BUFF_PETRIFIED) or
        hasBuff(player, BUFF_AMNESIA) or
        hasBuff(player, BUFF_TERROR)
    then
        return false
    end

    abilities = abilities or windower.ffxi.get_abilities() or {}
    local knownWeaponSkills = abilities.weapon_skills or {}

    -- Only return true if the weapon skill we're checking is in the collection of available weapon skills
    for i, knownWeaponSkillId in pairs(knownWeaponSkills) do
        if knownWeaponSkillId == weaponSkill.id then
            return true
        end
    end

    return false
end

--------------------------------------------------------------------------------------
-- Determine if a weapon skill is usable
function isUsableWeaponSkill(weaponSkill, abilities)
    weaponSkill = getWeaponSkillResource(weaponSkill)
    if weaponSkill == nil then
        return false
    end

    abilities = abilities or windower.ffxi.get_abilities() or {}
    local knownWeaponSkills = abilities.weapon_skills or {}

    for i, knownWeaponSkillId in pairs(knownWeaponSkills) do
        if knownWeaponSkillId == weaponSkill.id then
            return true
        end
    end
end

local FINISHING_MOVES_COUNT = 
{
    381,    -- 1 finishing move
    382,    -- 2 finishing moves
    383,    -- 3 finishing moves
    384,    -- 4 finishing moves
    385,    -- 5 finishing moves
    588     -- 6 or more finishing moves
}

function getFinishingMoves(player)
    player = player or windower.ffxi.get_player()

    for i = #FINISHING_MOVES_COUNT, 1, -1 do
        if arrayIndexOf(player.buffs, FINISHING_MOVES_COUNT[i]) then
            return i
        end
    end

    return 0
end


local stratagem_charge_time = {
    [1] = 240,
    [2] = 120,
    [3] = 80,
    [4] = 60,
    [5] = 48
}
function getMaxStratagems(player)
    --
    -- The following was obtained from the StrategemCounter addon:
    --  https://github.com/lorand-ffxi/addons/blob/master/StratagemCounter/StratagemCounter.lua
    --
    player = player or windower.ffxi.get_player()
	if S{player.main_job, player.sub_job}:contains('SCH') then
		local lvl = (player.main_job == 'SCH') and player.main_job_level or player.sub_job_level
		return math.floor(((lvl  - 10) / 20) + 1)
	else
		return 0
	end
end
function getAvailableStratagems(player, recasts)
    --
    -- The following was obtained from the StrategemCounter addon:
    --  https://github.com/lorand-ffxi/addons/blob/master/StratagemCounter/StratagemCounter.lua
    --
    player = player or windower.ffxi.get_player()

	local recastTime = (recasts or windower.ffxi.get_ability_recasts())[231] or 0
	local maxStrats = getMaxStratagems()
	if (maxStrats == 0) then return 0 end
	local stratsUsed = (recastTime / stratagem_charge_time[maxStrats]):ceil()
	return maxStrats - stratsUsed
end

-------------------------------------------------------------------------------
-- Key items related to being able to summon trusts
local TrustKeyItems = 
{
    PermitWindurst      = 2497,   -- KI to call 3 trusts (Windurst)
    PermitBastok        = 2499,   -- KI to call 3 trusts (Bastok)
    PermitSandoria      = 2501,   -- KI to call 3 trusts (San d'Oria)
    RhapsodyInWhite     = 2884,   -- KI to call 4 trusts
    RhapsodyInCrimson   = 2887,   -- KI to call 5 trusts
    
}

-------------------------------------------------------------------------------
-- Get the maximum number of trusts the player can call
function getMaxTrusts(player)
    local myKeyItems = windower.ffxi.get_key_items()
    if myKeyItems then
        if arrayIndexOf(myKeyItems, TrustKeyItems.RhapsodyInCrimson) then
            return 5
        elseif arrayIndexOf(myKeyItems, TrustKeyItems.RhapsodyInWhite) then
            return 4
        elseif
            arrayIndexOf(myKeyItems, TrustKeyItems.PermitWindurst) or
            arrayIndexOf(myKeyItems, TrustKeyItems.PermitBastok) or
            arrayIndexOf(myKeyItems, TrustKeyItems.PermitSandoria)
        then
            return 3
        end
    end

    return 0
end

-------------------------------------------------------------------------------
-- Get the spell used to call the trust with the specified name within a party.
-- If more than one match is found (i.e. Shantotto / Shantotto II), then 
-- disambiguation will be done based on the like-named trust already in your
-- party. If none is in your party, it will find the first one you can use.
-- If that fails, it will simply return the first one it finds.
TrustSearchModes = { 
    best = 'best',      -- The single best usable match
    usable = 'usable',  -- All usable matches
    all = 'all'         -- All matches
}
function getTrustSpellMeta(partyName, mode, player, party)
    if type(partyName) ~= 'string' then return end

    local matches = {}

    mode = TrustSearchModes[string.lower(mode or TrustSearchModes.best)]
    if mode == nil then return end

    -- A flag that indicates whether the requested mode should be limited 
    -- to usable trust spells only
    local onlyUsable = mode == TrustSearchModes.best or mode == TrustSearchModes.usable

    partyName = string.lower(partyName)

    if onlyUsable then
        player = player or windower.ffxi.get_player()
    end

    -- Iterate over the trust metadata. Store any entries that match the mode requirements.
    for id, metadata in pairs(meta.trusts) do
        if 
            string.lower(metadata.party_name) == partyName and
            (not onlyUsable or canUseSpell(player, metadata.id))
        then
            matches[#matches + 1] = metadata
        end
    end

    -- If we're getting all results or all usable results, we're done here. Modes
    -- that can result in multiple hits will always return an empty array rather
    -- than nil when there are no results.
    if 
        mode == TrustSearchModes.all or
        mode == TrustSearchModes.usable 
    then
        return matches
    end

    -- If we get here, we're looking for the single best match for the player.
    -- Everything we have at this point is usable by the player.

    if #matches > 1 then
        party = party or windower.ffxi.get_party()
        if party then
            for i = 0, 5 do 
                local p = party['p' .. i]
                if 
                    p and
                    p.mob and
                    p.mob.spawn_type == SPAWN_TYPE_TRUST 
                then
                    for j, metadata in ipairs(matches) do
                        if p.mob.models and (p.mob.models[1] == metadata.model) then
                            if string.lower(metadata.party_name) == string.lower(p.name) then
                                return metadata
                            end
                        end
                    end
                end
            end
        end
    end

    -- If we've made it here, we'll just return the first match we've found. Note
    -- that if we found no matches, this will just return nil as expected.
    return matches[1]
end