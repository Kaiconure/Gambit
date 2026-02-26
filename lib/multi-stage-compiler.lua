-----------------------------------------------------------------------------------------
-- Converts an array of strings into a map, where the lower-case equivalent of
-- each entry maps to its original location. Essentially this reverses the
-- mapping of index->field to field->index instead.
local function string_array_to_map(array)
    local map = {}
    if array then
        for i, val in ipairs(array) do
            if val then
                map[string.lower(tostring(val))] = i
            end
        end
    end

    return map
end

-----------------------------------------------------------------------------------------
-- Performs an in-place conversion of a string array to its lower-case equivalent
local function string_array_to_lower(string_array)
    if type(string_array) == 'table' then
        for i = 1, #string_array do
            if type(string_array[i]) == 'string' then
                string_array[i] = string.lower(string_array[i])
            end
        end
    end

    return string_array
end

-----------------------------------------------------------------------------------------
-- Given an exclusion rule set, a list of participants, and the current stage number,
-- return the properly pruned participant list.
local function process_multi_stage_exclusions(exclusions, participants, current)
    if participants and #participants > 0 and exclusions then
        participants = {unpack(participants)}

        -- Promote single value exclusions into a table format for ease of use
        if type(exclusions) ~= 'table' then
            exclusions = {exclusions}
        end
        
        for player, player_exclusions in pairs(exclusions) do
            if arrayIndexOf(player_exclusions, current) then
                local player_location = arrayIndexOfStrI(participants, player)
                if player_location then
                    table.remove(participants, player_location)
                end
            end
        end
    end

    return participants
end

local function shuffle_multi_stage_participants(stage_number, strategy, participants)
    if participants and #participants > 1 then
        participants = {unpack(participants)}
        if strategy == 'rotate' or strategy == 'rotate-right' then
            
            -- Rotate Right: Moves the last element to the front
            local max_moves = (stage_number % #participants) - 1
            for i = 1, max_moves do
                local removed = table.remove(participants, #participants)
                table.insert(participants, 1, removed)
            end
        elseif strategy == 'rotate-left' then
            -- Rotate Left: Moves the first element to the end
            local max_moves = (stage_number % #participants) - 1
            for i = 1, max_moves do
                local removed = table.remove(participants, 1)
                table.insert(participants, removed)
            end
            
        end
    end

    return participants
end

-----------------------------------------------------------------------------------------
--
local function setup_multi_stage_openers(multi_stage, known_weapon_skills)
    local stage_meta = multi_stage and multi_stage.stages or {}

    if stage_meta then
        if known_weapon_skills then
            if stage_meta[1] then
                local stage1 = stage_meta[1]
                local player_name = globals.player and globals.player.name

                -- If this opener uses "open_for" rather than specifif weapon skills
                if type(stage1.open_for) == 'string' then
                    local opening_sc = stage1.open_for

                    -- When "open_for" is used, we own the weapon skills to use for opening
                    stage1.use = {}

                    -- We will fully take over stage 2 at this point. We may need to insert it, which we'll do if the
                    -- second entry looks like a skillchain-related entry rather than a weapon skill related one.
                    if 
                        not stage_meta[2] or
                            (stage_meta[2].continue_from or stage_meta[2].continue_to)
                    then
                        table.insert(stage_meta, 2, {})
                    end

                    local sequences = skillchain_helper.find_skillchain_openings(opening_sc)
                    local openers = skillchain_helper.filter_weapon_skills(sequences.all_openers, 
                        known_weapon_skills,
                        multi_stage.preferred_weapon_skills,
                        multi_stage.blocked_weapon_skills)
                    if openers then
                        stage1.use = openers
                    else
                        stage1.use = {'-'}

                        local participants = stage1.participants or multi_stage.participants
                        if arrayIndexOfStrI(participants, globals.player and globals.player.name) then 
                            writeWarning('**Unable to %s the initial multi-stage sequence for: %s':format(
                                text_green('open', Colors.warning),
                                text_weapon_skill(opening_sc, Colors.warning)
                            ))
                        end
                    end

                    local stage2 = stage_meta[2]

                    stage2.on_ws = {}
                    stage2.on_sc = nil
                    stage2.use = nil
                    stage2.exclusions = stage2.exclusions or {}
                    stage2.generated = true

                    for group_i, group in ipairs(sequences.groupings) do

                        local sub_stage = '2.%d':format(group_i)
                        local participants = nil

                        -- If automatic participant shuffling is enabled and an explicit participant list for this stage hasn't 
                        -- been defined, then perform the desired shuffle now.
                        if 
                            not multi_stage.stage_participants['2'] and 
                            not multi_stage.stage_participants[sub_stage] and
                            not stage2.participants and
                            multi_stage.participants and 
                            multi_stage.participant_shuffle 
                        then
                            participants = shuffle_multi_stage_participants(2, multi_stage.participant_shuffle, multi_stage.participants)
                        end

                        if not participants then
                            participants = multi_stage.stage_participants[sub_stage] or multi_stage.stage_participants['2'] or stage2.participants or multi_stage.participants
                        end
                        
                        participants = process_multi_stage_exclusions(stage2.exclusions, participants, group_i)
                        participants = process_multi_stage_exclusions(multi_stage.exclusions, participants, 2)
                        participants = process_multi_stage_exclusions(multi_stage.exclusions, participants, tonumber(sub_stage))

                        local party_using = skillchain_helper.filter_weapon_skills(group.open_with)
                        if party_using then
                            local use = skillchain_helper.filter_weapon_skills(group.close_with, 
                                known_weapon_skills,
                                multi_stage.preferred_weapon_skills,
                                multi_stage.blocked_weapon_skills)

                            table.insert(stage2.on_ws, {
                                party_using = party_using,
                                use = use or {'--'},
                                participants = participants,
                                threshold = stage2.threshold or multi_stage.threshold
                            })
                            
                            if not use then
                                if arrayIndexOfStrI(participants, player_name) then
                                    local list = {unpack(party_using, 1, 5)}
                                    local using_string = table.concat(list, ', ')
                                    local more_string = #party_using > #list and '+%s more':format(#party_using - #list) or ''
                                
                                    writeWarning('**Unable to %s multi-stage opening step %s for %s if started with: %s %s':format(
                                        text_green('close', Colors.warning),
                                        text_number('#%d.%d':format(2, group_i), Colors.warning),
                                        text_weapon_skill(opening_sc, Colors.warning),
                                        text_weapon_skill(using_string, Colors.warning),
                                        text_gray(more_string, Colors.warning)
                                    ))
                                end
                            end
                        end                        
                    end

                    if #stage2.on_ws == 0 then
                        -- Stage 2 has two exclusion lists in effect -- its own, as well as the main stage-level. 
                        local participants = process_multi_stage_exclusions(stage2.exclusions, stage2.participants or multi_stage.participants, 1)
                        participants = process_multi_stage_exclusions(multi_stage.exclusions, participants, 2)
                        participants = process_multi_stage_exclusions(multi_stage.exclusions, participants, 2.1)

                        table.insert(stage2.on_ws, {
                            party_using = {'--'},
                            use = {'--'},
                            participants = participants,
                            threshold = stage2.threshold or multi_stage.threshold
                        })

                        if arrayIndexOfStrI(participants, player_name) then
                            writeWarning('**Unable to %s the initial multi-stage sequence for: %s':format(
                                text_green('close', Colors.warning),
                                text_weapon_skill(opening_sc, Colors.warning)
                            ))
                        end
                    end

                    stage2.participants = nil
                    stage2.threshold = nil
                    stage2.party_using = nil
                    stage2.use = nil
                else
                    stage1.use = skillchain_helper.filter_weapon_skills(string_array_to_lower(stage1.use),
                        known_weapon_skills,
                        multi_stage.preferred_weapon_skills,
                        multi_stage.blocked_weapon_skills)

                    if not stage1.use then
                        local participants = stage1.participants or multi_stage.participants
                        if arrayIndexOfStrI(participants, globals.player and globals.player.name) then 
                            stage1.use = {'-'}

                            writeWarning('**Unable to %s the initial multi-stage sequence.':format(
                                text_green('open', Colors.warning)
                            ))
                        end
                    end
                end
            end
        end
    end
end

local function expand_skillchain_continuation(multi_stage, stage_number, known_weapon_skills)
    local stage_meta = multi_stage and multi_stage.stages or {}

    if stage_meta then
        local stage = stage_meta[stage_number]
        if stage then
            if type(stage.continue_from) == 'string' and type(stage.continue_to) == 'string' then
                local continuation_weapon_skills = skillchain_helper.filter_weapon_skills(
                    skillchain_helper.get_skillchain_continuation(stage.continue_from, stage.continue_to),
                    known_weapon_skills, 
                    multi_stage.preferred_weapon_skills,
                    multi_stage.blocked_weapon_skills
                )

                if continuation_weapon_skills then
                    stage.on_sc = { stage.continue_from }
                    stage.use = continuation_weapon_skills

                    if not stage.participants then
                        stage.participants = multi_stage.participants
                    end
                    if not stage.threshold then
                        stage.threshold = multi_stage.threshold
                    end

                    stage.continuation = 'Auto-configured to see [%s] and attempt to make [%s].':format(stage.continue_from, stage.continue_to)
                    stage.continue_from = nil
                    stage.continue_to = nil

                    return true
                else
                    local participants = stage.participants or multi_stage.stage_participants or multi_stage.participants
                    if arrayIndexOfStrI(participants, globals.player and globals.player.name) then
                        writeWarning('**Unable to participate in stage %s to make: %s %s %s':format(
                            text_number('#%d':format(stage_number), Colors.warning),
                            text_weapon_skill(stage.continue_from, Colors.warning),
                            CHAR_RIGHT_ARROW,
                            text_weapon_skill(stage.continue_to, Colors.warning)
                        ))
                    end

                    stage.on_sc = {'--'}
                    stage.use = {'--'}
                end
            else
                stage.use = skillchain_helper.filter_weapon_skills(
                    string_array_to_lower(stage.use),
                    known_weapon_skills, 
                    multi_stage.preferred_weapon_skills,
                    multi_stage.blocked_weapon_skills
                )

                if not stage.use then
                    local participants = stage.participants or multi_stage.stage_participants or multi_stage.participants
                    if arrayIndexOfStrI(participants, globals.player and globals.player.name) then
                        writeWarning('**Unable to participate in stage %s in response to: %s':format(
                            text_number('#%d':format(stage_number), Colors.warning),
                            text_weapon_skill(
                                (stage.on_sc and #stage.on_sc > 0 and table.concat(stage.on_sc, ',')) or '--',
                                Colors.warning
                            )
                        ))
                    end

                    stage.on_sc = {'--'}
                    stage.use = '--'
                end
            end
        end
    end
end

function compile_multi_stage(multi_stage)
    local stage_meta = multi_stage and multi_stage.stages or {}

    local abilities = windower.ffxi.get_abilities()
    local known_weapon_skills = abilities and abilities.weapon_skills or {}

    multi_stage.stage_participants = multi_stage.stage_participants or {}

    -- Preferred or blocked weapon skills. These are ONLY used when auto-generating weapon skills. Anything
    -- explicitly set in the configuration file will be used as-is.
    multi_stage.preferred_weapon_skills = multi_stage.preferred_weapon_skills or {}
    multi_stage.blocked_weapon_skills = multi_stage.blocked_weapon_skills or {}

    setup_multi_stage_openers(multi_stage, known_weapon_skills)

    for i = #stage_meta, 1, -1 do
        local stage = stage_meta[i]

        if type(stage) ~= 'table' then
            -- We will strip out any invalid stage entries
            table.remove(stage_meta, i)

            writeMessage('Removed invalid stage %s from multi-stage configuration due to invalid value.':format(text_number(i)))
        else
            -- If automatic participant shuffling is enabled and an explicit participant list for this stage hasn't 
            -- been defined, then perform the desired shuffle now.
            if 
                not stage.participants and 
                not multi_stage.stage_participants[i] and 
                multi_stage.participants and 
                multi_stage.participant_shuffle 
            then
                stage.participants = shuffle_multi_stage_participants(i, multi_stage.participant_shuffle, multi_stage.participants)
            end

            -- Threshold must always be a number between 0 and 1000
            stage.threshold = math.clamp(tonumber(stage.threshold) or tonumber(multi_stage.threshold) or 800, 0, 1000)
            stage.participants = process_multi_stage_exclusions(multi_stage.exclusions, 
                stage.participants or multi_stage.stage_participants[tostring(i)] or multi_stage.participants or {}, 
                i
            )

            -- Normalize the weapon skill lists for this entry
            if stage.party_using then stage.party_using = string_array_to_lower(stage.party_using) end
            if stage.use then stage.use = string_array_to_lower(stage.use) end

            -- Promote single use entry to on_ws array if needed (one-time setup)
            if i == 2 and not stage.on_ws and stage.use then
                stage.on_ws = {
                    party_using = stage.party_using,
                    use = stage.use,
                    threshold = stage.threshold
                }

                stage.use = nil
                stage.party_using = nil
                stage.threshold = nil
            end

            -- Promote stage-level threshold/participants to each on_ws entry if they aren't already defined (one-time setup)
            if i == 2 then
                stage.on_ws = type(stage.on_ws) == 'table' and stage.on_ws or {}
                for entry_i, entry in ipairs(stage.on_ws) do
                    -- Threshold must always be a number between 0 and 1000
                    entry.threshold = math.clamp(tonumber(entry.threshold) or stage.threshold, 0, 1000)

                    -- Inherit the include_self flag if not defined at the entry level. This determines whether your own TP
                    -- is taken into account when determining if a skillchain can be started.
                    if entry.include_self == nil then
                        entry.include_self = stage.include_self
                    end

                    -- For manually entered entries, we'll validate that the current character can participate if included
                    if not stage.generated then
                        entry.party_using = string_array_to_lower(entry.party_using)
                        entry.use = skillchain_helper.filter_weapon_skills(string_array_to_lower(entry.use), known_weapon_skills, multi_stage.preferred_weapon_skills, multi_stage.blocked_weapon_skills)

                        entry.participants = entry.participants or stage.participants or multi_stage.participants or {}
                        entry.participants = process_multi_stage_exclusions(stage.exclusions, entry.participants, entry_i)                                  -- Stage 2's own exclusion list
                        entry.participants = process_multi_stage_exclusions(multi_stage.exclusions, entry.participants, tonumber('2.%d':format(entry_i)))   -- The overall exclusion list for this exact phase of stage 2
                        entry.participants = process_multi_stage_exclusions(multi_stage.exclusions, entry.participants, 2)                                  -- The overall exclusion list for stage 2 as a whole

                        if not entry.use then
                            if arrayIndexOfStrI(entry.participants, globals.player and globals.player.name) then
                                entry.use = {'--'}

                                local using_list = entry.party_using or {'any'}

                                local list = {unpack(using_list or {'any'}, 1, 5)}
                                local using_string = table.concat(list, ', ')
                                local more_string = #using_list > #list and '+%s more':format(#using_list - #list) or ''

                            
                                writeWarning('**Unable to %s multi-stage opening step %s if started with: %s %s':format(
                                    text_green('close', Colors.warning),
                                    text_number('#%d.%d':format(2, entry_i), Colors.warning),
                                    text_weapon_skill(using_string, Colors.warning),
                                    text_gray(more_string, Colors.warning)
                                ))
                            end
                        end
                    end

                    -- We'll convert the party_using array into a keyed table for faster lookups. With automated
                    -- weapon skill generation, these lists can get quite large.
                    if entry.party_using and #entry.party_using > 0 then
                        local temp = {}
                        for using_i, using in ipairs(entry.party_using) do
                            temp[string.lower(using)] = true
                        end

                        entry.party_using = temp
                    else
                        entry.party_using = {['*'] = true}
                    end

                    -- We need each participant to have a normalized player name, so we can compare more easily later.
                    if entry.participants then
                        for j = 1, #entry.participants do
                            entry.participants[j] = makePlayerName(entry.participants[j])
                        end
                    end
                end

                stage.threshold = nil
                stage.participants = nil
                stage.include_self = nil
            elseif i == 1 then

            elseif i > 2 then
                expand_skillchain_continuation(multi_stage, i, known_weapon_skills)
            end

            -- We need each participant to have a normalized player name, so we can compare more easily later.
            if stage.participants then
                for j = 1, #stage.participants do
                    stage.participants[j] = makePlayerName(stage.participants[j])
                end
            end
        end
    end

    multi_stage._compiled = true

    local player = windower.ffxi.get_player()
    multi_stage._compiled_for = player and player.name

    writeJsonToFile('./.data/%s/multi-stage/compiled/%s.json':format(
            player and player.name or 'unknown-player',
            (player and player.main_job) and (player.sub_job and '%s-%s':format(player.main_job, player.sub_job) or player.main_job) or 'UNK'
        ), 
        multi_stage
    )

    writeVerbose('Multi-stage skillchain sequence compiled with: %s':format(
        pluralize(multi_stage and multi_stage.stages and #multi_stage.stages or 0, 'stage', 'stages')
    ))
end