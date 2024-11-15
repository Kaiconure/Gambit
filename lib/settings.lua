----------------------------------------------------------------------------------------
-- Supported targeting strategies
TargetStrategy = {
    nearest         = 'nearest',    -- Find the nearest aggroing mob
    maxhp           = 'maxhp',      -- Find the aggroing mob with the most HP
    minhp           = 'minhp',      -- Find aggroing mob with the least HP
    aggressor       = 'aggressor',  -- Behaves like nearest, but initiates battle rather than finding the nearest aggroing mob
    leader          = 'leader',     -- The party leader target, or the nearest aggro if none
    camp            = 'camp'        -- Camps on a spot and waits for puller to bring mobs close [NOT IMPLEMENTED]
}

-- We will use the 'nearest' strategy if no other has been set.
TargetStrategy.default = TargetStrategy.nearest

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
    { name = 'Bounding Chapuli', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Chilblain Snoll', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Crabapple Treant', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Floodplain Spider', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Furfluff Lapinion', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Indomitable Spurned', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Larkish Opo-opo', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Lavender Twitherym', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Lightfoot Lapinion', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Oregorger Worm', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Ruby Raptor', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Skittish Matamata', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Sloshmouth Snapweed', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Soiled Funguar', ignoreAlways = true, _note = 'Reive guard' },
    { name = 'Twitherym Windstorm', ignoreAlways = true, _note = 'Reive guard' }
}

--
-- Mobs who we will always avoid trying to stand behind. These will typically be reive obstacles,
-- where we have no reliable way of approaching from the rear.
local DefaultNoRearList = {
    'Amaranth Barrier',
    'Bedrock Crag',
    'Gnarled Rampart',
    'Heliotrope Barrier',
    'Icy Palisade',
    'Knotted Root',
    'Monolithic Boulder'
}

local defaultSettings = {
    maxDistance = 50,
    maxDistanceZ = 5,
    retargetDelay = 0.0,
    strategy = TargetStrategy.default,
    verbosity = VERBOSITY_VERBOSE,
    schemaVersion = 2,
    ignoreList = DefaultIgnoreList,
    noRearList = DefaultNoRearList,
    maxChaseTime = nil
}

----------------------------------------------------------------------------------------
-- Determine the settings file name for this player
local function getSettingsFileName(playerName)
    return string.format('.\\settings\\%s\\main.json', playerName)
end

local function getActionsFileName(playerName, actionsName)
    return string.format('.\\settings\\%s\\actions\\%s.json', playerName, actionsName)
end

local function getActionsJobFileName(player)
    local actionsName = player.main_job
    if player.sub_job then
        actionsName = actionsName .. '-' .. player.sub_job
    end

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
                        -- For straight up arrays, we'll actually just take the new value
                        original[key] = val
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
local function _loadActionImportsInternal(playerName, baseActions, actionType)
    local imported = false

    local actions = baseActions and baseActions[actionType]
    if actions then
        if baseActions.vars == nil then
            baseActions.vars = {}
        end

        for i = #actions, 1, -1 do
            local action = actions[i]

            -- Import any items that have an import reference and which aren't marked as disabled
            if type(action.import) == 'string' and not action.disabled then
                -- First, try the user's actions/.libs folder
                local fileName = './settings/%s/actions/.lib/%s.json':format(playerName, action.import)
                local file = files.new(fileName)

                -- If the import doesn't exist there, use the standard settings .lib folder
                if not file:exists() then
                    fileName = './settings/.lib/%s.json':format(action.import)
                    file = files.new(fileName)
                end

                if file:exists() then
                    import = json.parse(file:read())

                    if import then
                        --
                        -- Pull in any variables defined in this import. Existing values are not overwritten.
                        if import.vars then
                            -- for name, val in pairs(import.vars) do
                            --     if baseActions.vars[name] == nil then
                            --         baseActions.vars[name] = val
                            --     end
                            -- end
                            loadVars(baseActions.vars, import.vars)
                        end

                        -- Remove the import reference from the calling action
                        table.remove(actions, i)

                        -- Now, if the import has its own actions we will insert them in place
                        -- of the original import reference
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

----------------------------------------------------------------------------------------
--
local function loadActionImports(playerName, actions)
    -- Keep importing actions until there are no more to pull in. This is to ensure that
    -- imports which have their own imports will work.
    if actions then
        local MAX_PASSES = 10
        local types = {'battle', 'pull', 'idle', 'resting', 'dead'}

        for i = 1, #types do
            local actionType = types[i]
            local passes = 0

            -- Prevent runaway, infinite imports. Most likely caused if an include references 
            -- itself. Let's not crash the game because of a mistake or typo.
            while passes <= MAX_PASSES and _loadActionImportsInternal(playerName, actions, actionType) do
                passes = passes + 1
            end

            if passes > MAX_PASSES then
                writeMessage('Warning: The maximum number of %s import passes (%s) was exceeded.':format(
                    text_action(actionType),
                    text_number(passes)
                ))
            end
        end
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

        if type(actions.vars) == 'table' then

        end
    end

    return actions
end

----------------------------------------------------------------------------------------
--
local function loadDefaultActions(player, save)
    local fileName = '.\\settings\\.defaults\\default-actions.json'
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
    tempSettings.maxDistance = math.max(5, math.min(tempSettings.maxDistance or 0, 60))

    -- The maximum vertical search radius to use when acquiring targets. Can be used to prevent
    -- acquiring targets on unreachable platforms, or to avoid walking down stairs or ramps.
    -- Must be a number greater than or equal to 1.
    tempSettings.maxDistanceZ = math.max(tempSettings.maxDistanceZ or 0, 1)

    -- The maximum amount of time to wait (in seconds) before assuming an unengaged target
    -- is unreachable. This prevents you from getting into infinite wall-running ruts.
    tempSettings.maxChaseTime = tonumber(tempSettings.maxChaseTime)
    if tempSettings.maxChaseTime and tempSettings.maxChaseTime > 0 then
        -- Clamp the give up period to between 5-30 seconds
        tempSettings.maxChaseTime = math.max(5, math.min(30, tempSettings.maxChaseTime))
    else
        -- If no chase time was configured, calculate it based on the max distance.
        -- This will end up with a value between 5-20 seconds.
        tempSettings.maxChaseTime = math.max(15, tempSettings.maxDistance) / 3
    end

    local jobActionsName = nil
    local actions = nil

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

        actionsName = '%s%s':format(
            mainJob,
            subJob and '-%s':format(subJob) or ''
        ):lower()

        jobActionsName = actionsName
        actions = loadActions(player.name, actionsName)

        -- if actions then
        --     writeMessage('Actions were loaded for %s/%s!':format(player.main_job, player.sub_job))
        -- end

        --
        -- If there were no actions for this job, we can try reloading the last explicitly loaded action set
        --
        -- if actions == nil then
        --     if tempSettings.actionInfo and tempSettings.actionInfo.name then
        --         actionsName = tempSettings.actionInfo.name:lower()
        --         actions = loadActions(player.name, actionsName)
        --     end
        -- end

        -- Load the default actions if nothing else has worked
        if actions == nil then
            actions = loadDefaultActions(player, true)

            if actions then
                actionsName = jobActionsName
                writeMessage('No actions were found for your current job. The defaults were loaded instead.')
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
        writeJsonToFile('.\\settings\\%s\\.output\\%s.actions.processed.json':format(player.name, (actionsName or player.name)), actions)

        if actionsName then
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
    return loadActionsFromFile(playerName, fileName)
end

----------------------------------------------------------------------------------------
-- The settings global
settings = nil