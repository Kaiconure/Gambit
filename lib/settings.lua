----------------------------------------------------------------------------------------
-- Supported targeting strategies
TargetStrategy = {
    nearest         = 'nearest',    -- Find the nearest aggroing mob
    maxhp           = 'maxhp',      -- Find the aggroing mob with the most HP
    minhp           = 'minhp',      -- Find aggroing mob with the least HP
    aggressor       = 'aggressor',  -- Behaves like nearest, but initiates battle rather than finding the nearest aggroing mob
    leader          = 'leader',     -- The party leader target, or the nearest aggro if none
    puller          = 'puller',     -- Similar to aggressor, but tries to limit to mobs that aren't engaged with others while unclaimed
    manual          = 'manual',     -- You as the player pick the targets by engaging manually
    camp            = 'camp'        -- Camps on a spot and waits for puller to bring mobs close [NOT IMPLEMENTED]
}

-- We will use the 'leader' strategy if no other has been set
TargetStrategy.default = TargetStrategy.leader

--
-- Ignore list fields:
--  - index: The index (hex id) of the mob. Must be paired with 'zone'. The 'name' field is ignored.
--  - name: The name of the mob. Ignored if 'index' and 'zone' are set.
--  - zone: The id of the zone this entry applies to.
--  - ignoreAlways: Ignore even if aggro'd. Use very carefully.
--  - downgrade: Pushes the mob all the way to the bottom of the target list. It will only be engaged
--      if it is aggroing, or if it is the only mob within range.
local DefaultIgnoreList = {

    -- Mobs that will never attack and are generally ignorable
    { name = 'Numbing Blossom', zone = nil, index = nil, ignoreAlways = true },
    { name = 'Spinescent Protuberance', zone = nil, index = nil, ignoreAlways = true },
    { name = 'Erupting Geyser', zone = nil, index = nil, ignoreAlways = true },
    { name = 'Pungent Fungus', zone = nil, index = nil, ignoreAlways = true },
    { name = 'Steam Spout', zone = nil, index = nil, ignoreAlways = true },
    { name = 'Graupel Formation', zone = nil, index = nil, ignoreAlways = true },

    -- Mobs that guard colonization reives, which are just a waste of time to target
    -- when we could be breaking down the obstacles to eliminate them.
    { name = 'Acuex', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Alpine Rabbit', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Bounding Chapuli', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Basalt Lizard', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Cerise Wasp', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Chilblain Snoll', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Crabapple Treant', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Draftrider Bat', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Embattled Roc', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Festering Umbril', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Floodplain Spider', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Frightful Funguar', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Furfluff Lapinion', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Indomitable Spurned', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Lancing Wasp', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Larkish Opo-opo', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Lavender Twitherym', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Lightfoot Lapinion', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Matamata', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Oregorger Worm', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Preening Tulfaire', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Precipice Vulture', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Procrustean Draugar', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Pungent Ovim', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Quivering Twitherym', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Red Dropwing', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Resilient Colibri', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Ruby Raptor', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Shrubshredder Chapuli', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Skittish Matamata', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Sloshmouth Snapweed', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Soiled Funguar', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Sordid Lizard', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Stonesoftener Acuex', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Temblor Beetle', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Territorial Lucerewe', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Trogloptera', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Twitherym Windstorm', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Umberwood Tiger', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Uprooted Sapling', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Velkk Vaticinator', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Vengeful Shunned', ignoreAlways = true, _note = 'Reive guard' }
}

--
-- Mobs who we will always avoid trying to stand behind. These will typically be reive obstacles,
-- where we have no reliable way of approaching from the rear.
local DefaultNoRearList = {
    'Amaranth Barrier',
    'Bedrock Crag',
    'Broadleaf Palm',
    'Gnarled Rampart',
    'Heliotrope Barrier',
    'Icy Palisade',
    'Knotted Root',
    'Monolithic Boulder'
}

--
-- Some mobs cannot be approached using the standard melee distance. These can be called
-- out here, with the appropriate minimum distance override.
local DefaultMinDistanceList = {
    ['Bedrock Crag'] = 6
}

local defaultSettings = {
    maxDistance = 25,
    maxDistanceZ = 5,
    retargetDelay = 0.0,
    strategy = TargetStrategy.default,
    verbosity = VERBOSITY_VERBOSE,
    schemaVersion = 2,
    ignoreList = DefaultIgnoreList,
    noRearList = DefaultNoRearList,
    minDistanceList = DefaultMinDistanceList,
    maxChaseTime = nil,
    followCommandDistance = 1,
    weaponSkillDelay = nil
}

----------------------------------------------------------------------------------------
-- Determine the settings file name for this player
local function getSettingsFileName(playerName)
    return string.format('./settings/%s/main.json', playerName)
end

local function getActionsFileName(playerName, actionsName)
    if actionsName == nil then print('no actionsName provided') end
    return string.format('./settings/%s/actions/%s.json', playerName, actionsName)
end

local function getActionsAlternateFileName(playerName, actionsName)
    if actionsName == nil then print('no actionsName provided') end
    return string.format('./settings/actions/%s.json', actionsName)
end

local function getActionsJobFileName(player)
    local actionsName = player.main_job
    -- if player.sub_job then
    --     actionsName = actionsName .. '-' .. player.sub_job
    -- end

    return getActionsFileName(player.name, actionsName:lower())
end

local function loadVars(original, incoming)
    if original and incoming then
        -- Iterate over all the incoming values
        for key, val in pairs(incoming) do

            if type(val) == 'table' then
                -- For tables, we'll perform a deep copy
                if original[key] == nil then
                    original[key] = {}
                end

                -- Perform the same variable load logic on the new key. This will skip any situation
                -- where the incoming data defines a table and the original already has a non-table
                -- variable of the same name. This wouldn't be an expected situation.
                if type(original[key]) == 'table' then
                    if #original[key] > 0 and original[key][1] ~= nil then
                        -- For straight up arrays, we'll just leave the original value intact. No overwrites.

                        -- OLD: For straight up arrays, we'll actually just take the new value
                        -- OLD: original[key] = val
                    else
                        -- For non-array tables, we will merge the incoming values in
                        loadVars(original[key], val)
                    end
                end
            else
                -- For non-tables, copy the value in if it hasn't already been defined
                if original[key] == nil then
                    original[key] = val
                end
            end
        end
    end
end

----------------------------------------------------------------------------------------
-- Pulls the next round of imports into the specified actions array. Returns
-- true if new actions were imported as part of this pass.
local function _loadActionImportsInternal(playerName, baseActions, actionType, pass)
    local imported = false
    local actions = baseActions and baseActions[actionType]
    if actions then
        if baseActions.vars == nil then
            baseActions.vars = {}
        end

        -- if baseActions.importedImports == nil then
        --     baseActions.importedImports = {}
        -- end

        for i = #actions, 1, -1 do
            local action = actions[i]

            -- Import any items that have an import reference and which aren't marked as disabled
            if type(action.import) == 'string' and not action.disabled then
                -- First, try the character-level actions libs folder
                local fileName = './settings/%s/actions/lib/%s.json':format(playerName, action.import)
                local file = files.new(fileName)

                -- If the import doesn't exist there, try the user-level actions lib folder
                if not file:exists() then
                    fileName = './settings/actions/lib/%s.json':format(action.import)
                    file = files.new(fileName)
                end

                -- If the import doesn't exist there, use the standard actions lib folder
                if not file:exists() then
                    fileName = './actions/lib/%s.json':format(action.import)
                    file = files.new(fileName)
                end

                if file:exists() then
                    import = json.parse(file:read())

                    if import then
                        -- if type(import.imports) == 'table' and import.imports[1] then
                        --     for ii_index, ii_ref in ipairs(import.imports) do
                        --         local 
                        --         if not baseActions.importedImports[string.lower(ii_ref.import)] then
                        --             baseActions.importedImports[string.lower(ii_ref.import)] = { import = string.lower(ii_ref.import) }
                        --         end
                        --     end
                        -- end

                        -- Remove the import reference from the calling action
                        table.remove(actions, i)

                        --
                        -- Pull in any variables defined in this import. Existing values are not overwritten.
                        if import.vars then
                            loadVars(baseActions.vars, import.vars)
                        end

                        -- Pull in the macros
                        if type(import.macros) == 'table' then
                            local macros = type(import.macros) == 'table' and import.macros or { }

                            for name, macro in pairs(macros) do
                                if baseActions.macros[name] == nil then
                                    baseActions.macros[name] = macro
                                end
                            end
                        end                        
                        import.macros = nil

                        -- Pull in any child actions, replacing the import. If this file only defines variables or macros,
                        -- then the originating import action will simply be removed.
                        if 
                            import.actions and
                            #import.actions > 0
                        then
                            for j = #import.actions, 1, -1 do
                                local importedAction = import.actions[j]
                                if importedAction then
                                    imported = true
                                    importedAction.importedFrom = action.import

                                    table.insert(actions, i, importedAction)
                                end
                            end
                        end
                    end
                else
                    writeMessage('Warning: Referenced %s action import [%s] could not be found.':format(
                        text_action(actionType),
                        text_gold(action.import)
                    ))
                end
            end
        end
    end

    return imported
end

local function _expandActionMacrosToArray(macros, array)
    -- If we have a macro table, iterate through all entries.
    -- Note: At this point, we're guaranteed that there will be no nested macros; they
    -- have all been expaned by the settings loader. We just need to insert them.
    if type(array) == 'table' then

        -- Do array replacement macros. With $macro:<name> or $macro.<name>, we'll replace an
        -- array element with all elements from the macro.
        for i = #array, 1, -1 do
            local clause = trimString(array[i])
            if stringStartsWith(clause, '$macro:') or stringStartsWith(clause, '$macro.') then
                -- First, we will remove this entry. If it is a macro reference, it will be
                -- removed regardless of what happens next
                table.remove(array, i)

                -- Obtain the macro key itself
                local key = trimString(string.sub(clause, 8))                
                if key ~= '' and type(macros[key]) == 'table' then
                    if type(macros[key]) == 'table' then
                        for j = #macros[key], 1, -1 do
                            table.insert(array, i, macros[key][j])
                        end
                    end
                end
            else
                -- Store the trimmed version of the original string
                array[i] = clause
            end
        end

        local str_macro_types = {'$macro('}

        -- Do string-replacement macros. With $macro(<macro-name>), we'll replace directly inside of a string.
        for i = #array, 1, -1 do
            local clause = trimString(array[i])

            for j, marker in ipairs(str_macro_types) do
                local search = 1

                while search and search < #clause do
                    local start_index = string.find(clause, marker, search, true)
                    if start_index then
                        local end_index = string.find(clause, ')', start_index, true)
                        if end_index then
                            local key = trimString(string.sub(clause, start_index + #marker, end_index - 1))

                            local replacement = ''
                            if macros[key] then
                                replacement = table.concat(macros[key], ' ')
                            end

                            local newValue = 
                                string.sub(clause, 1, start_index - 1) ..
                                replacement ..
                                string.sub(clause, end_index + 1)

                            -- Store the new clause value
                            clause = newValue

                            -- We'll continue searching from exactly where we left off, because the string has been replaced.
                            -- We may have expanded a new macro reference.
                            search = start_index
                        else
                            -- No closing was found, this means there are no valid macros left
                            search = nil
                        end
                    else
                        -- No string-replacement macros were found
                        search = nil
                    end
                end
            end

            array[i] = clause
        end
    end
 end

 local function _expandActionMacros(loadedData, action)
    local macros = loadedData.macros
    if type(macros) == 'table' then
        -- Promote string actions and commands to tables to simplify macro insertion
        if type(action.when) == 'string' then
            action.when = { action.when }
        end
        if type(action.commands) == 'string' then
            action.commands = { action.commands }
        end
        
        _expandActionMacrosToArray(macros, action.when)
        _expandActionMacrosToArray(macros, action.commands)
    end
 end

 local function _processMacros(loadedData)
    local MAX_PASSES = 10

    for
        macro_set_name, macro_set in pairs(loadedData.macros) 
    do
        local passes = 0
        local num_replacements

        while passes <= MAX_PASSES and num_replacements ~= 0 do
            num_replacements = 0   
            for i = #macro_set, 1, -1 do
                local macro = trimString(macro_set[i])

                if 
                    stringStartsWith(macro, '$macro:') or
                    stringStartsWith(macro, '$macro.')
                then
                    table.remove(macro_set, i)
                    local replacement_name = string.sub(macro, 8)
                    local replacement = loadedData.macros[replacement_name]
                    if replacement then
                        for j = #replacement, 1, -1 do
                            table.insert(macro_set, i, replacement[j])
                        end
                    end

                    num_replacements = num_replacements + 1
                else
                    macro_set[i] = macro
                end
            end

            passes = passes + 1
        end

        if passes > MAX_PASSES then
            writeMessage('Warning: The maximum number of macro passes (%s) was exceeded.':format(
            text_number(passes)
        ))
        end
    end

    -- Now, expand all macros into their respective actions
    local actionTypes = {'battle', 'pull', 'idle', 'resting', 'dead', 'mounted', 'functions'}
    for i, actionType in ipairs(actionTypes) do
        local actions = loadedData and loadedData[actionType]
        if type(actions) == 'table' then
            for i, action in ipairs(actions) do
                _expandActionMacros(loadedData, action)
            end
        end
    end
 end

----------------------------------------------------------------------------------------
--
local function loadActionImports(playerName, actions)
    -- Keep importing actions until there are no more to pull in. This is to ensure that
    -- imports which have their own imports will work.
    if actions then
        local MAX_PASSES = 10
        local types = {'battle', 'pull', 'idle', 'resting', 'dead', 'mounted', 'imports', 'functions'}

        actions.macros = type(actions.macros) == 'table' and actions.macros or { }

        for i = 1, #types do
            local actionType = types[i]
            local passes = 0

            -- Prevent runaway, infinite imports. Most likely caused if an include references 
            -- itself. Let's not crash the game because of a mistake or typo.
            while passes <= MAX_PASSES and _loadActionImportsInternal(playerName, actions, actionType, passes + 1) do
                passes = passes + 1
            end

            if passes > MAX_PASSES then
                writeMessage('Warning: The maximum number of %s import passes (%s) was exceeded.':format(
                    text_action(actionType),
                    text_number(passes)
                ))
            end
        end

        _processMacros(actions)
    end
end

local function _expandVariable(name, value)
    if type(value) == 'number' then return value end
    if type(value) == 'string' then return '"%s"':format(value) end

    local result = ''
    if type(value) == 'table' then
        local first = true
        for a, b in ipairs(value) do
            local current = _expandVariable(a, b)
            if current ~= '' then
                result = result .. (first and '' or ',') .. current
                first = false
            end
        end
    end

    return result
end

local function _loadActionsWithPreprocessing(file)
    local text = file:read()

    -- local temp = json.parse(json)
    -- if temp and type(temp.vars) == 'table' then
    --     for name, value in pairs(temp.vars) do

    --     end
    -- end

    return json.parse(text)
end

----------------------------------------------------------------------------------------
local function loadActionsFromFile(playerName, fileName)
    local file = files.new(fileName)
    if not file:exists() then
        return nil
    end

    local actions = _loadActionsWithPreprocessing(file)
    if actions then
        loadActionImports(playerName, actions)
        --writeJsonToFile('.\\settings\\%s\\.output\\processed-actions.json':format(playerName), actions)

        -- if type(actions.importedImports) then
        --     local imported = true

        --     actions['imported-imports'] = {}

        --     while imported do
        --         imported = false
        --         for entry_key, entry in pairs(actions.importedImports) do
        --             if not entry.imported then
        --                 arrayAppend(actions['imported-imports'], {
        --                     import = entry_key,
        --                     imported = false
        --                 })
        --                 imported = true
        --                 entry.imported = true
        --             end
        --         end

        --         if imported then
        --             --local function _loadActionImportsInternal(playerName, baseActions, actionType, pass)
        --         end
        --     end
        -- end
    end

    return actions
end

----------------------------------------------------------------------------------------
--
local function loadDefaultActions(player, save)
    local fileName = './actions/defaults/default-actions.json'
    local defaults = loadActionsFromFile(player.name, fileName)

    if defaults and save then
        local file = files.new(fileName)
        local defaultJson = file:read()

        if save then
            local saveAsFileName = getActionsJobFileName(player)
            writeStringToFile(saveAsFileName, defaultJson)
        end
    end

    return defaults
end

----------------------------------------------------------------------------------------
--
function saveDefaultActions(player, force)
    local saveAsFileName = getActionsJobFileName(player)
    local file = files.new(saveAsFileName)

    -- Can't overwrite an existing file without the force flag
    if file:exists() and not force then
        return
    end

    return loadDefaultActions(player, true) ~= nil
end

----------------------------------------------------------------------------------------
-- Load settings
function loadSettings(actionsName, settingsOnly)
    local player = windower.ffxi.get_player()
    local fileName = getSettingsFileName(player.name)

    local file = files.new(fileName)
    if not file:exists() then
        writeMessage('No settings found for %s. Defaults will be loaded.':format(text_player(player.name)))
        tempSettings = defaultSettings
    else
        writeMessage('Loading configured settings for %s...':format(text_player(player.name)))
        tempSettings = json.parse(file:read()) or {}

        -- If any fields are missing from the loaded settings, pull the defaults for those
        for field, value in pairs(defaultSettings) do
            if tempSettings[field] == nil then
                tempSettings[field] = defaultSettings[field]
            end
        end
    end

    -- Validate the schema

    -- Clamp the verbosity to the allowed values (normal/0 to trace/3)
    tempSettings.verbosity = math.min(VERBOSITY_TRACE, math.max(VERBOSITY_NORMAL, tonumber(tempSettings.verbosity or VERBOSITY_NORMAL)))

    -- The amount of time to wait (in seconds) between finishing with one
    -- target and acquiring another. Must be a non-negative number.
    tempSettings.retargetDelay = math.max(tempSettings.retargetDelay or 0, 0)

    -- The maximum horizontal search radius to use when acquiring targets. Clamped between 5-60 units.
    tempSettings.maxDistance = math.max(3, math.min(tempSettings.maxDistance or 0, 60))

    -- The maximum vertical search radius to use when acquiring targets. Can be used to prevent
    -- acquiring targets on unreachable platforms, or to avoid walking down stairs or ramps.
    -- Must be a number greater than or equal to 1.
    tempSettings.maxDistanceZ = math.max(tempSettings.maxDistanceZ or 0, 1)

    -- The default distance that the follow command will use if none is specified
    tempSettings.followCommandDistance = math.clamp(tempSettings.followCommandDistance, 1.0, 10.0)

    -- The maximum amount of time to wait (in seconds) before assuming an unengaged target
    -- is unreachable. This prevents you from getting into infinite wall-running ruts.
    tempSettings.maxChaseTime = tonumber(tempSettings.maxChaseTime)
    if tempSettings.maxChaseTime and tempSettings.maxChaseTime > 0 then
        -- Clamp the give up period to between 5-60 seconds
        tempSettings.maxChaseTime = math.clamp(tempSettings.maxChaseTime, 5, 60)
    else
        tempSettings.maxChaseTime = 17
    end

    -- The amount of time to allow between a weapon skill/skillchain being detected, 
    -- and a skillchain being continued.
    tempSettings.skillchainDelay = math.clamp(
        tonumber(tempSettings.skillchainDelay) or SKILLCHAIN_DELAY,
        0,
        MAX_SKILLCHAIN_TIME)

    -- The maximum number of tabs to press when having trouble acquiring targets
    tempSettings.maxTabs = math.floor(math.clamp(tonumber(tempSettings.maxTabs) or 0, 0, 20))

    -- The maximum length of targeting attempts
    tempSettings.targetingDuration = math.clamp(tonumber(tempSettings.targetingDuration) or 10, 1, 20)

    local jobActionsName = nil
    local actions = nil
    local defaultsLoaded = false

    tempSettings.actions = {}

    if actionsName then
        writeMessage('Attempting to load actions from: [%s/%s]':format(player.name, actionsName))
        actions = loadActions(player.name, actionsName)
    elseif settingsOnly then
        writeMessage('All previously compiled actions will be reapplied to the current state.')

        actions = settings.actions
        actionsName = settings.actionInfo and settings.actionInfo.name
    end

    local mainJob = player.main_job
    local subJob = player.sub_job

    if actions == nil then
        -- Load main/sub job-specific actions if present
        if subJob then
            actionsName = '%s-%s':format(mainJob, subJob):lower()
            jobActionsName = actionsName
            actions = loadActions(player.name, actionsName)
        end

        -- If no actions were found, load the main job actions (default)
        if actions == nil then
            actionsName = '%s':format(mainJob):lower()
            jobActionsName = actionsName
            actions = loadActions(player.name, actionsName)
        end

        -- Load the default actions if nothing else has worked
        if actions == nil then
            actions = loadDefaultActions(player)

            if actions then
                defaultsLoaded = true
                actionsName = jobActionsName
                writeMessage(text_magenta('No existing actions were found, and temp defaults were loaded.'))
                writeMessage(text_magenta('  Run %s to save these actions.':format(
                    text_green('//' .. __shortName .. ' actions -save-default', Colors.magenta))
                ))
            else
                writeMessage('No actions were found for your current job, and the defaults could not be loaded.')
            end
        end
    end

    if actions then
        tempSettings.actions = actions
        tempSettings.actionInfo = tempSettings.actionInfo or {}
        tempSettings.actionInfo.name = actionsName

        -- Save the post-processed actions
        writeJsonToFile('./settings/%s/.output/%s.actions.processed.json':format(player.name, (actionsName or player.name)), actions)

        if actionsName and not defaultsLoaded then
            writeMessage('Successfully loaded %s actions: %s':format(
                text_player(player.name),
                text_action(actionsName)
            ))
        end
    end

    return tempSettings
end

----------------------------------------------------------------------------------------
-- Save settings
function saveSettings(settingsToSave)
    local player = windower.ffxi.get_player()
    local fileName = getSettingsFileName(player.name)

    settingsToSave = settingsToSave or settings

    -- Make a deep copy
    settingsToSave = json.parse(json.stringify(settingsToSave))

    -- Strip out the actions
    settingsToSave.actions = nil

    -- Save the result
    writeJsonToFile(fileName, settingsToSave)
end

----------------------------------------------------------------------------------------
-- Load actions by player and action set name
function loadActions(playerName, actionsName)
    local fileName = getActionsFileName(playerName, actionsName)
    local actions = loadActionsFromFile(playerName, fileName)
    if actions == nil then
        fileName = getActionsAlternateFileName(playerName, actionsName)
        actions = loadActionsFromFile(playerName, fileName)
    end

    return actions
end

----------------------------------------------------------------------------------------
-- The settings global
settings = nil