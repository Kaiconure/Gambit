local handlers = {}

-------------------------------------------------------------------------------
-- show
handlers['show'] = function (args)
    writeMessage('All scalar settings: ')
    for name, value in pairs(settings) do
        local message = makeDisplayValue(name, value, true)
        if message then
            writeMessage(message)
        end
    end
end

-------------------------------------------------------------------------------
-- strategy
handlers['strategy'] = function (args)
    local strategy = (args[1] or ''):lower()

    if strategy == '' then
        writeMessage('Current strategy: ' .. text_green(settings.strategy))
        return
    end
    if TargetStrategy[strategy] == nil then
        writeMessage('Err: Invalid target strategy: ' .. strategy)
        return
    end

    settings.strategy = strategy
    saveSettings()

    writeMessage('Target strategy has been set to: ' .. text_green(strategy))
end
handlers['strat'] = handlers['strategy']

handlers['status'] = function(args)
    writeMessage(text_gray('Gambit status:'))
    writeMessage('  Current gambit is %s':format(settings and settings.actionInfo and text_green(settings.actionInfo.name) or text_red('n/a')))
    writeMessage('  Automation is %s':format(globals.enabled and text_green('enabled') or text_red('disabled')))
    writeMessage('  Targeting strategy is %s':format(text_green(settings.strategy)))
    
end

-------------------------------------------------------------------------------
-- disable
handlers['disable'] = function (args)
    local quiet = arrayIndexOfStrI(args, '-quiet')

    if globals.enabled then
        globals.enabled = false

        -- Clear the mob after we disable
        resetCurrentMob(nil, true)

        writeMessage('  Status: Automation has been %s.':format(text_red('disabled')))
    else
        -- Quiet mode means we won't message when there's no actual status change
        if not quiet then
            writeMessage('  Status: Automation is %s.':format(text_red('disabled')))
        end
    end

    smartMove:cancelJob()
end

-------------------------------------------------------------------------------
-- enable
handlers['enable'] = function (args)
    local quiet = arrayIndexOfStrI(args, '-quiet')
    local changed = false

    if not globals.enabled then
        -- Clear the mob before we enable
        resetCurrentMob(nil, true)
        actionStateManager:resetActionTime()

        globals.enabled = true
        changed = true
        writeMessage('  Status: Automation has been %s with the %s strategy!':format(
            text_green('enabled'),
            text_action(settings.strategy)
        ))
    else
        -- Quiet mode means we won't message when there's no actual status change
        if not quiet then
            writeMessage('  Status: Automation is %s with the [%s] strategy.':format(
                text_green('enabled'),
                text_action(settings.strategy)
            ))
        end
    end

    -- Display the action state
    if not quiet or changed then
        sendSelfCommand('actions')
    end

    smartMove:cancelJob()
end

handlers['varget'] = function(args)
    local context = actionStateManager:getContext()
    if not context then
        writeMessage('No valid context is available to set a variable.')
        return
    end

    local name = trimString(args[1])
    if type(name) ~= 'string' then
        writeMessage('A variable name must be specified.')
        return
    end

    local value = context.getVar(name)
    writeMessage(text_gray('Variable %s value:':format(text_yellow(type(value), Colors.gray))))

    if type(value) == 'boolean' then
        writeMessage('  %s: %s':format(
            text_blue(name),
            value and text_green('true') or text_red('false')
        ))
    elseif type(value) == 'string' then
        writeMessage('  %s: %s':format(
            text_blue(name),
            text_yellow('"%s"':format(value))
        ))
    elseif type(value) == 'number' then
        writeMessage('  %s: %s':format(
            text_blue(name),
            text_number(tostring(value))
        ))
    elseif type(value) == 'nil' then
        writeMessage('  %s: %s':format(
            text_blue(name),
            text_gray('nil')
        ))
    elseif type(value) == 'table' and #value > 0 then
        writeMessage('  %s %s:':format(
            text_blue(name),
            text_yellow('array')
        ))

        for i, v in ipairs(value) do
            writeMessage('    %s: %s':format(
                text_number(i),
                    (type(v) == 'number' and text_number(v)) or
                    (type(v) == 'string' and text_yellow('"%s"':format(v))) or
                    (type(v) == 'boolean' and (v and text_green('true') or text_red('false'))) or
                    (type(v) == 'nil' and text_gray('nil')) or
                    text_gray(tostring(v))
            ))
        end
    else
        writeMessage('  %s %s:':format(
            text_blue(name),
            text_yellow('table')
        ))

        for key, v in pairs(value) do
            writeMessage('    %s: %s':format(
                text_yellow(key),
                    (type(v) == 'number' and text_number(v)) or
                    (type(v) == 'string' and text_yellow('"%s"':format(v))) or
                    (type(v) == 'boolean' and (v and text_green('true') or text_red('false'))) or
                    (type(v) == 'nil' and text_gray('nil')) or
                    text_gray(tostring(v))
            ))
        end
    end
end

handlers['varset'] = function(args)
    local context = actionStateManager:getContext()
    if not context then
        writeMessage('No valid context is available to set a variable.')
        return
    end

    local name = args[1]
    if type(name) ~= 'string' then
        writeMessage('A variable name must be specified.')
        return
    end
    
    local value = args[2]

    if value == nil then
        writeMessage('A variable value must be specified.')
    end

    local value_lower = string.lower(value)

    if value_lower == 'true' then
        -- Boolean true
        value = true
    elseif value_lower == 'false' then
        -- Boolean false
        value = false
    elseif value_lower == 'nil' then
        -- Nil
        value = nil
    else
        local num_value = tonumber(value)
        if num_value then
            value = num_value
        end
    end

    context.setVar(name, value)

    handlers['varget']({name})
end

-------------------------------------------------------------------------------
-- toggle
handlers['toggle'] = function (args)
    sendSelfCommand(globals.enabled and 'disable' or 'enable')
end

-------------------------------------------------------------------------------
-- follow
handlers['follow'] = function (args)
    local target = arrayIndexOfStrI(args, '-target') or arrayIndexOfStrI(args, '-t')
    local distance = tonumber(arrayIndexOfStrI(args, '-distance') or arrayIndexOfStrI(args, '-d') or 0)
    local cancel = arrayIndexOfStrI(args, '-cancel') or arrayIndexOfStrI(args, '-c')
    local toggle = arrayIndexOfStrI(args, '-toggle')

    distance = distance > 0 and tonumber(args[distance + 1]) or settings.followCommandDistance

    if toggle then
        -- If not following, initiate follow in the current target at the specified distance
        -- If following, cancel
        local jobInfo = smartMove:getJobInfo()
        if jobInfo then
            sendSelfCommand('follow -c')
        else
            sendSelfCommand('follow -t -d %.1f':format(distance))
        end
    elseif cancel then
        local jobInfo = smartMove:getJobInfo()
        local jobId = smartMove:cancelJob()
        if jobId then
            writeMessage(text_cornsilk('Follow job %s was cancelled.':format(text_number(jobId, Colors.cornsilk))))
        end
    elseif target then
        local target = windower.ffxi.get_mob_by_target('t')
        if 
            target and
            target.valid_target and
            target.hpp > 0 and
            target.id ~= globals.me_id
        then
            local job = smartMove:followIndex(target.index, distance)
            if job then
                writeMessage(text_cornsilk('Following %s with a distance of %s. Use Ctrl+F to cancel.':format(
                    text_mob(target.name, Colors.cornsilk),
                    text_number('%.1f':format(distance), Colors.cornsilk)
                )))
            else
                writeMessage('Unable to follow %s.':format(
                    text_mob(target.name)
                ))
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Start moving
handlers['run'] = function(args)
    local start = arrayIndexOfStrI(args, '-start')
    local stop = arrayIndexOfStrI(args, '-stop')

    if start then
        windower.ffxi.run(true)
    elseif stop then
        windower.ffxi.run(false)
    end
end

handlers['move'] = function (args)
    local x = arrayIndexOfStrI(args, '-x')
    local y = arrayIndexOfStrI(args, '-y')

    if type(x) == 'number' then x = tonumber(args[x + 1]) end
    if type(y) == 'number' then y = tonumber(args[y + 1]) end

    local me = windower.ffxi.get_mob_by_target('me')
    if type(x) == 'number' and type(y) ~= 'number' then y = me.y end
    if type(y) == 'number' and type(x) ~= 'number' then x = me.x end

    if type(x) ~= 'number' or type(y) ~= 'number' then
        writeMessage('A valid coordinate could not be found. Movement skipped.')
        return
    end

    local job = smartMove:moveTo(x, y)
    if job then
        writeMessage(text_cornsilk('Moving to %s. Use Ctrl+F to cancel.':format(
            text_number('(%.3f, %.3f)':format(x, y), Colors.cornsilk)
        )))
    else
        writeMessage('Unable to move to %s.':format(
            text_number('(%.2f, %.2f)':format(x, y))
        ))
    end

end
handlers['face'] = function(args)
    writeMessage('Not implemented: face')  
end

-------------------------------------------------------------------------------
-- reload
handlers['reload'] = function (args)
    -- The settings only flag causes us to bypass the reloading of actions, and to just load
    -- settings changes. This allows us to configure verbosity and whatnot without losing
    -- the current action state.
    local bypassActions = arrayIndexOfStrI(args, '-settings-only') or arrayIndexOfStrI(args, '-so')
    local actionsName = arrayIndexOfStrI(args, '-actions') or arrayIndexOfStrI(args, '-a')
    local reload = arrayIndexOfStrI(args, '-reload') or arrayIndexOfStrI(args, '-r')

    if reload and settings.actionInfo and type(settings.actionInfo.name) == 'string' then
        writeMessage('Attempting to reload: %s':format(text_action(settings.actionInfo.name)))
        actionsName = settings.actionInfo.name
    else
        actionsName = actionsName and (args[actionsName + 1]) or nil
    end

    reloadSettings(actionsName, bypassActions ~= nil)
end
handlers['r'] = handlers['reload']

local VerbosityNames = {
    [0] = 'normal',     -- Minimal level
    [1] = 'verbose',    -- More information
    [2] = 'comment',    -- Lots more information
    [3] = 'debug',      -- Debug spew
    [4] = 'trace'       -- Very detailed debug spew
}
-------------------------------------------------------------------------------
-- verbosity
handlers['verbosity'] = function (args)
    local level = arrayIndexOfStrI(args, '-level')
    local verbosity = type(level) == 'number' and (args[level + 1] or ''):lower()
    local verbositySet = false

    if verbosity == '' then verbosity = nil end

    if verbosity == 'normal' or verbosity == '0' then
        settings.verbosity = VERBOSITY_NORMAL
        verbositySet = true
    elseif verbosity == 'verbose' or verbosity == '1' then
        settings.verbosity = VERBOSITY_VERBOSE
        verbositySet = true
    elseif verbosity == 'comment' or verbosity == '2' then
        settings.verbosity = VERBOSITY_COMMENT
        verbositySet = true
    elseif verbosity == 'debug' or verbosity == '3' then
        settings.verbosity = VERBOSITY_DEBUG
        verbositySet = true
    elseif verbosity == 'trace' or verbosity == '4' then
        settings.verbosity = VERBOSITY_TRACE
        verbositySet = true
    end

    local verbosityName = VerbosityNames[settings.verbosity]

    if verbositySet then
        logging_settings.verbosity = settings.verbosity

        writeMessage('Verbosity changed to: %s':format(text_green(verbosityName)))
        saveSettings()
    else
        if verbosityName ~= nil then
            writeMessage('Verbosity is set to: %s':format(text_green(
                verbosityName
            )))
        end
    end
end

handlers['sendkey'] = function(args)
    -- This short sleep before the first key press ensures that we can use this command on ourselves, 
    -- even when manually typing out the command.
    coroutine.sleep(0.5)

    if #args > 0 then
        local all_keys = table.concat(args, ' ')
        writeMessage('Preparing to send key sequence: %s':format(text_yellow(all_keys)))
        for i, key in ipairs(args) do
            local command = 'setkey %s down; wait 0.1; setkey %s up; wait 0.1;':format(key, key)
            windower.send_command(command)
            coroutine.sleep(0.25)
        end
    end
end
handlers['sk'] = handlers['sendkey']

handlers['iteminfo'] = function(args)
    local bag_info = windower.ffxi.get_bag_info()
    local inventory = bag_info and bag_info.inventory or bag_info
    local verbose = hasArg(args, '-verbose') or hasArg(args, '-v')

    writeMessage(text_green('Item Information'))

    if inventory and inventory.enabled then
        writeMessage('  %s: %s / %s':format(
            text_yellow('Inventory'),
            text_number(inventory.count or '--'),
            text_number(inventory.max or '--')
        ))
    end

    writeMessage(text_green('Currencies'))

    local gil = windower.ffxi.get_items('gil')
    if gil then
        writeMessage('  %s: %s':format(
            text_yellow('Gil'),
            text_number(format_number(gil))
        ))
    end

    if verbose then
        local conquest = actionStateManager:getConquestInfo()
        local conquest_points = conquest and tonumber(conquest.conquestPoints)
        local imperial_standing = conquest and tonumber(conquest.imperialStanding)

        if conquest_points then
            writeMessage('  %s: %s':format(
                text_yellow('Conquest Points'),
                text_number(format_number(conquest_points))
            ))
        end

        if imperial_standing then
            writeMessage('  %s: %s':format(
                text_yellow('Imperial Standing'),
                text_number(format_number(imperial_standing))
            ))
        end

        local sack = bag_info.sack and bag_info.sack.enabled and bag_info.sack
        local case = bag_info.case and bag_info.case.enabled and bag_info.case
        local satchel = bag_info.satchel and bag_info.satchel.enabled and bag_info.satchel

        if sack or case or satchel then
            writeMessage('%s':format(text_green("Field-Accessible Storage")))

            if case then
                writeMessage('  %s: %s / %s':format(
                    text_yellow('Case'),
                    text_number(case.count or '--'),
                    text_number(case.max or '--')
                ))
            end

            if sack then
                writeMessage('  %s: %s / %s':format(
                    text_yellow('Mog Sack'),
                    text_number(sack.count or '--'),
                    text_number(sack.max or '--')
                ))
            end

            if satchel then
                writeMessage('  %s: %s / %s':format(
                    text_yellow('Satchel'),
                    text_number(satchel.count or '--'),
                    text_number(satchel.max or '--')
                ))
            end
        end

        --writeJsonToFile('./data/%.03f.get_bag_info.json':format(os.clock()), bag_info)

        local safe = bag_info.safe and bag_info.safe.max and bag_info.safe.max > 0 and bag_info.safe
        local safe2 = bag_info.safe2 and bag_info.safe2.max and bag_info.safe2.max > 0 and bag_info.safe2
        local locker = bag_info.locker and bag_info.locker.max and bag_info.locker.max > 0 and bag_info.locker
        local storage = bag_info.storage and bag_info.storage.max and bag_info.storage.max > 0 and bag_info.storage

        if safe or safe2 or locker or storage then
            writeMessage('%s':format(text_green("Other Storage")))

            if safe then
                writeMessage('  %s: %s / %s':format(
                    text_yellow('Safe'),
                    text_number(safe.count or '--'),
                    text_number(safe.max or '--')
                ))
            end

            if safe2 then
                writeMessage('  %s: %s / %s':format(
                    text_yellow('Safe2'),
                    text_number(safe2.count or '--'),
                    text_number(safe2.max or '--')
                ))
            end

            if locker then
                writeMessage('  %s: %s / %s':format(
                    text_yellow('Locker'),
                    text_number(locker.count or '--'),
                    text_number(locker.max or '--')
                ))
            end

            if storage then
                writeMessage('  %s: %s / %s':format(
                    text_yellow('Storage'),
                    text_number(storage.count or '--'),
                    text_number(storage.max or '--')
                ))
            end
        end

        writeMessage('%s':format(text_green("Wardrobes")))
        for i = 1, 8 do
            local wname = 'wardrobe'
            if i > 1 then
                wname = wname .. i
            end

            local wardrobe = bag_info[wname]
            if wardrobe and wardrobe.enabled then
                writeMessage('  %s: %s / %s':format(
                    text_yellow(wname),
                    text_number(wardrobe.count or '--'),
                    text_number(wardrobe.max or '--')
                ))
            end
        end
    end
end
handlers['ii'] = handlers['iteminfo']

handlers['jobinfo'] = function(args)

    local send = hasArg(args, '-send')
    if send then
        writeMessage('Sending job info to other alts...')
        sendJobInfoIpc()
        return
    end

    local name = makePlayerName(getArgValue(args, '-name') or getArgValue(args, '-n'))

    local main_job = nil
    local main_job_level = nil
    local sub_job = nil    
    local sub_job_level = nil

    if name == nil or name == globals.me_name then
        local player = windower.ffxi.get_player()
        if player then
            name = player.name
            main_job = player.main_job
            main_job_level = player.main_job_level or 0
            sub_job = player.sub_job
            sub_job_level = player.sub_job_level or 0
        end
    elseif globals.ipc_job_info[name] then
        local jobInfo = globals.ipc_job_info[name]
        main_job = jobInfo.main_job
        main_job_level = jobInfo.main_job_level or 0
        sub_job = jobInfo.sub_job
        sub_job_level = jobInfo.sub_job_level or 0
    end

    if name and main_job then
        if sub_job then
            writeMessage('Job Info: %s is %s':format(
                text_player(name),
                text_cornsilk('%s%d/%s%d':format(
                    main_job,
                    main_job_level,
                    sub_job,
                    sub_job_level))
            ))
        else
            writeMessage('Job Info: %s is %s':format(
                text_player(name),
                text_cornsilk('%s%d':format(
                    main_job,
                    main_job_level))
            ))
        end
    else
        writeMessage('No job information is available for %s.':format(
            text_player(name or globals.me_name)
        ))
    end
end
handlers['ji'] = handlers['jobinfo']

-------------------------------------------------------------------------------
-- distance
handlers['config'] = function(args)
    local distance = tonumber(arrayIndexOfStrI(args, '-distance') or arrayIndexOfStrI(args, '-d') or 0)
    local distancez = tonumber(arrayIndexOfStrI(args, '-distancez') or arrayIndexOfStrI(args, '-z') or 0)
    local strat = tonumber(arrayIndexOfStrI(args, '-strategy') or arrayIndexOfStrI(args, '-strat') or 0)
    local fcd = tonumber(arrayIndexOfStrI(args, '-followd') or arrayIndexOfStrI(args, '-fd') or 0)
    local h_offset = tonumber(arrayIndexOfStrI(args, '-follow-offset') or arrayIndexOfStrI(args, '-foff') or 0)
    local ct = tonumber(arrayIndexOfStrI(args, '-chasetime') or arrayIndexOfStrI(args, '-ct') or 0)
    local scd = tonumber(arrayIndexOfStrI(args, '-skillchaindelay') or arrayIndexOfStrI(args, '-scdelay') or arrayIndexOfStrI(args, '-scd') or 0)
    local tabs = tonumber(arrayIndexOfStrI(args, '-tabs') or 0)
    local targetingDuration = tonumber(arrayIndexOfStrI(args, '-targetingduration') or arrayIndexOfStrI(args, '-td') or 0)
    local useRawDistance = tonumber(arrayIndexOfStrI(args, '-rawdistance') or arrayIndexOfStrI(args, '-rd') or 0)
    local partyTarget = tonumber(arrayIndexOfStrI(args, '-partytarget') or arrayIndexOfStrI(args, '-pt') or 0)
    local debugging = tonumber(arrayIndexOfStrI(args, '-debugging') or 0)
    local slowTargetTransitions = tonumber(arrayIndexOfStrI(args, '-stt') or 0)
    local skipPacketTargeting = tonumber(arrayIndexOfStrI(args, '-spt') or 0)
    local preTargeting = tonumber(arrayIndexOfStrI(args, '-pretarget') or 0)

    local cp = tonumber(arrayIndexOfStrI(args, '-cloudpanel') or arrayIndexOfStrI(args, '-cp') or 0)
    
    local hasChanges = false

    if distance > 0 then
        distance = tonumber(args[distance + 1])
        if distance and distance > 0 then
            distance = math.clamp(distance, 3, 50)
            settings.maxDistance = distance
            hasChanges = true
        end

        writeMessage('Max targeting distance: %s':format(text_number('%.1f':format(settings.maxDistance))))
    end

    if distancez > 0 then
        distancez = tonumber(args[distancez + 1])
        if distancez and distancez >= 0 then
            distancez = math.clamp(distancez, 1, 50)
            settings.maxDistanceZ = distancez
            hasChanges = true
        end

        writeMessage('Max Z targeting distance: %s':format(text_number('%.1f':format(settings.maxDistanceZ))))
    end

    if fcd > 0 then
        fcd = tonumber(args[fcd + 1])
        if fcd and fcd > 0 then
            fcd = math.clamp(fcd, 0.25, 10.0)
            settings.followCommandDistance = fcd
            hasChanges = true
        end

        writeMessage('Follow command distance: %s':format(text_number('%.1f':format(settings.followCommandDistance))))
    end

    if h_offset > 0 then
        h_offset = tonumber(args[h_offset + 1])
        if h_offset and h_offset >= 0 then
            h_offset = math.max(h_offset, 0)
            settings.followOffset = h_offset
            hasChanges = true

            smartMove:applySettings(settings)
        end

        writeMessage('Horizontal follow offset: %s':format(
            settings.followOffset and text_number('%.2f':format(settings.followOffset)) or text_magenta('n/a')
        ))
    end

    -- NOTE: This is not actually used for anything at this point
    if partyTarget > 0 then
        partyTarget = string.lower(tostring(args[partyTarget + 1]))
        if partyTarget then
            if partyTarget == 'true' or partyTarget == 'on' or partyTarget == 'enable' or partyTarget == 'enabled' then
                settings.partyTargeting = true
                hasChanges = true
            elseif partyTarget == 'false' or partyTarget == 'off' or partyTarget == 'disable' or partyTarget == 'disabled' then
                settings.partyTargeting = false
                hasChanges = true
            end
        end

        writeMessage('Party targeting: %s':format(
            settings.partyTargeting and text_green('on') or text_red('off')
        ))
    end

    if strat > 0 then
        strat = tostring(args[strat + 1] or ''):lower()
        if TargetStrategy[strat] ~= nil then
            settings.strategy = TargetStrategy[strat]
            hasChanges = true
        end

        writeMessage('Targeting strategy: %s':format(text_green(settings.strategy)))
    end

    if ct > 0 then
        ct = tonumber(args[ct + 1])
        if ct and ct > 0 then
            ct = math.clamp(ct, 5.0, 60.0)
            settings.maxChaseTime = ct
            hasChanges = true
        end

        writeMessage('Max chase time: %s':format(
            pluralize('%.1f':format(settings.maxChaseTime), 'second', 'seconds')
        ))
    end

    if scd > 0 then
        scd = tonumber(args[scd + 1])
        if scd and scd > 0 then
            scd = math.clamp(scd, 0.0, MAX_SKILLCHAIN_TIME)
            settings.skillchainDelay = scd
            hasChanges = true
        end

        writeMessage('Skillchain delay: %s':format(
            pluralize('%.1f':format(settings.skillchainDelay), 'second', 'seconds')
        ))
    end

    if tabs > 0 then
        -- tabs = tonumber(args[tabs + 1])
        -- if tabs and tabs >= 0 then
        --     tabs = math.floor(math.clamp(tabs, 0.0, 20))
        --     settings.maxTabs = tabs
        --     hasChanges = true
        -- end

        -- writeMessage('Targeting tab presses: %s':format(
        --     text_number(settings.maxTabs)
        -- ))
        writeWarning('The tabs setting is no longer used and has been deprecated.')
    end

    if useRawDistance > 0 then
        useRawDistance = string.lower(args[useRawDistance + 1] or '')

        if useRawDistance == 'on' then
            settings.useRawDistances = true
        elseif useRawDistance == 'off' then
            settings.useRawDistances = nil
        end

        writeMessage('Raw distances? %s':format(
            settings.useRawDistances and text_green('on') or text_red('off')
        ))
    end

    if debugging > 0 then
        debugging = args[debugging + 1]
        if debugging == 'on' then
            settings.debugging = true
            hasChanges = true
        elseif debugging == 'off' then
            settings.debugging = false
            hasChanges = true
        end

        writeMessage('Additional debugging details: %s':format(
            settings.debugging and text_green('on') or text_red('off')
        ))
    end

    if cp > 0 then
        local hasCpChanges = false

        cp = args[cp + 1]
        settings.cloudPanel = settings.cloudPanel or {}

        if cp == 'on' then
            settings.cloudPanel.enabled = true
            hasChanges = true
            hasCpChanges = true
        elseif cp == 'off' then
            settings.cloudPanel.enabled = false
            hasChanges = true
            hasCpChanges = true 
        end

        if hasCpChanges then
            if globals.cloud_panel then
                globals.cloud_panel:configure(settings.cloudPanel)
            end
        end

        writeMessage('Cloud panel display: %s':format(
            settings.cloudPanel.enabled and text_green('on') or text_red('off')
        ))
    end

    if slowTargetTransitions > 0 then
        slowTargetTransitions = args[slowTargetTransitions + 1]
        if slowTargetTransitions == 'on' then
            settings.slowTargetTransitions = true
            hasChanges = true
        elseif slowTargetTransitions == 'off' then
            settings.slowTargetTransitions = false
            hasChanges = true
        end

        writeMessage('Use slower target transitions: %s':format(
            settings.slowTargetTransitions and text_green('on') or text_red('off')
        ))
    end

    if skipPacketTargeting > 0 then
        skipPacketTargeting = args[skipPacketTargeting + 1]
        if skipPacketTargeting == 'on' then
            settings.skipPacketTargeting = true
            hasChanges = true
        elseif skipPacketTargeting == 'off' then
            settings.skipPacketTargeting = false
            hasChanges = true
        end

        writeMessage('Skip packet targeting: %s':format(
            settings.skipPacketTargeting and text_green('on') or text_red('off')
        ))
    end

    if preTargeting > 0 then
        preTargeting = args[preTargeting + 1]
        if preTargeting == 'on' then
            settings.preTargeting = true
            hasChanges = true
        elseif preTargeting == 'off' then
            settings.preTargeting = false
            hasChanges = true
        end

        writeMessage('Pre-targeting: %s':format(
            settings.preTargeting and text_green('on') or text_red('off')
        ))
    end

    if targetingDuration > 0 then
        targetingDuration = tonumber(args[targetingDuration + 1])
        if targetingDuration and targetingDuration > 0 then
            targetingDuration = math.clamp(targetingDuration, 1, 20)
            settings.targetingDuration = targetingDuration
            hasChanges = true
        end

        writeMessage('Max targeting duration: %s':format(
            pluralize('%.1f':format(settings.targetingDuration), 'second', 'seconds')
        ))
    end

    if hasChanges then
        saveSettings()
    end
end

handlers['function'] = function(args)
    local name = getArgValue(args, '-name') or getArgValue(args, '-n')
    local list = arrayIndexOfStrI(args, '-list') or arrayIndexOfStrI(args, '-l')
    local silent = arrayIndexOfStrI(args, '-silent')
    local max_iterations = arrayIndexOfStrI(args, '-max')

    local send = arrayIndexOfStrI(args, '-send')
    if send then
        local target = string.lower(args[send + 1])
        if send then
            -- Remove the -send and its value from the arguments list
            table.remove(args, send)
            table.remove(args, send)

            local command = 'send %s gbt function %s':format(
                target,
                trimString(replaceTokens(table.concat(args, ' ')))
            )

            --print('Sending: [%s]':format(command))
            windower.send_command(command)
        else
            writeWarning('Invalid function send target specified.')
        end

        return
    end

    --print('Running: [gbt function %s]':format(trimString(table.concat(args, ' '))))

    local max_iterations = getArgValue(args, '-max')
    if list or not name then
        local count = 0
        writeMessage('Registered function list:')

        local keys = {}
        for key, _ in pairs(actionStateManager.functions) do
            keys[#keys + 1] = key
        end
        table.sort(keys, function (a, b) return a < b end)
        for i, key in ipairs(keys) do
            local val = actionStateManager.functions[key]
            writeMessage('%s':format(text_green(key)))
            if type(val.description) == 'string' then
                writeMessage('%s':format(text_gray(val.description)))
            end
        end

        writeMessage('You have %s configured!':format(pluralize(#keys, 'function', 'functions')))

        return
    end

    if not name then
        writeMessage('A function name must be specified.')
        return
    end

    local settings_counter = settings.settings_counter

    local action = actionStateManager.functions[name]
    if action then
        -- Allow the function to configure some of its own settings
        max_iterations = max_iterations or action.max_iterations or math.huge
        silent = silent or action.silent
        
        -- Functions have a maximum frequency of 0.5 seconds, but they can override themselves to higher than that
        local fn_frequency = math.max(0.5, action.frequency or 0)

        -- for i = 1, #args do
        --     print(' %d: [%s]':format(i, args[i]))
        -- end

        --------------------------------------------------------------------
        -- Handle stop commands
        if
            hasArg(args, '-stop') or
            hasArg(args, '-cancel') or
            hasArg(args, '-exit')
        then
            if not action._running then
                writeMessage('  %s: The function is not running, so cannot be stopped.':format(text_green(action.name)))
            else
                action._fn_exiting = true
            end
            return
        end

        -- If this function is already running and it allows re-entry, we will give it
        -- a certain amount of time to exit before we proceed and try to retart it.
        if action._running and action.allow_reentry then
            action._fn_exiting = true
            local reentry_time = tonumber(action.reentry_time) or 2
            if reentry_time > 0 then
                local t0 = os.clock()
                coroutine.sleep(math.min(reentry_time, 0.5))
                while (os.clock() - t0) <= reentry_time do
                    coroutine.sleep(0.5)
                end
            end
        end

        if not action._running then
            if not silent then
                writeMessage('  %s: Beginning execution.':format(text_green(action.name)))
            end

            action._running = true
            action._fn_exiting = false
            action._fn_iteration = 0

            local start = os.clock()
            local done = false

            local arg_params = {}
            for i = 1, #args do
                local arg = args[i]
                local split = arg and
                    arg[1] ~= '-' and
                    string.find(arg, ':')

                if split then
                    local name = replaceTokens(trimString(string.sub(arg, 1, split - 1)))
                    local value = replaceTokens(trimString(string.sub(arg, split + 1)))

                    if name ~= '' and value ~= '' then
                        local lower_value = string.lower(value)
                        if lower_value == 'true' then 
                            value = true
                        elseif lower_value == 'false' then
                            value = false
                        else
                            value = tonumber(value) or value 
                        end

                        arg_params[name] = value
                    end
                end
            end

            while
                not done and
                globals.logged_in and
                not globals.shutting_down 
            do
                if action._fn_iteration >= max_iterations then
                    if not silent then
                        writeMessage('  %s: The maximum iteration count of %s has been reached!':format(text_green(action.name), text_number(action._fn_iteration)))
                    end
                    done = true
                end

                if settings.settings_counter ~= settings_counter then
                    -- We will log this scenario even when silent, because it is an external indicator
                    writeMessage('  %s: Settings have been reloaded, functions will exit.':format(text_green(action.name)))
                    done = true
                end

                if not done then

                    action._fn_iteration = action._fn_iteration + 1

                    local context = ActionContext.create(
                        'function',                 -- Action type
                        os.clock() - start,         -- Current time
                        globals.target:mob(),       -- Target mob
                        0,                          -- Amount of time engaged with target mob. Not valid for functions.
                        -1,                         -- Battle scope. Not valid for functions.
                        windower.ffxi.get_party()   -- The current party
                    )

                    -- Pull enumerator data into the new context
                    if context then
                        context.results = {}

                        if 
                            action.enumerators and
                            action.enumerators.array
                        then
                            for name, enumerator in pairs(action.enumerators.array) do
                                if enumerator.data and enumerator.at then
                                    context.results[name] = enumerator.data[enumerator.at]
                                end
                            end

                            if action.enumerators.array_name then
                                context.result = context.results[action.enumerators.array_name]
                            end
                        end
                    end

                    if context then
                        context.action = action
                        context.params = arg_params
                        context.params._iter = action._fn_iteration
                        context.params._runtime = context.time
                        context.params._fn = name

                        setfenv(action._whenFn, context)
                        if not action._fn_exiting and action._whenFn() then
                            for i, command in ipairs(action.commands) do
                                setfenv(command._commandFn, context)
                                command._commandFn()
                            end
                        else
                            if not silent then
                                writeMessage('  %s: Execution completed!':format(text_green(action.name)))
                            end
                            done = true
                        end
                    else
                        writeMessage('  %s: Context is unavailable, exiting.':format(text_green(action.name)))
                        done = true
                    end
                end

                if not done then
                    coroutine.sleep(fn_frequency)
                end
            end

            action._running = false
            action._fn_exiting = false

            if 
                not globals.logged_in or
                globals.shutting_down 
            then
                print('Gambit: Function [%s] is exiting due to logout or addon unload.':format(name))
            else
                if action.on_exit then
                    local command = 'wait 1; gbtfn %s;':format(action.on_exit)
                    windower.send_command(command)
                end
            end
        else
            writeMessage('  %s: The function is already running.':format(text_green(action.name)))
        end
    else
        writeMessage('  %s: No valid function was found.':format(text_green(name)))
    end
end

handlers['func'] = handlers['function']
handlers['fn'] = handlers['function']

-------------------------------------------------------------------------------
-- targetinfo
handlers['targetinfo'] = function (args)
    local targetArg = tonumber(arrayIndexOfStrI(args, '-target') or arrayIndexOfStrI(args, '-t'))
    if targetArg then
        targetArg = args[targetArg + 1]
    end

    targetArg = targetArg or 't'

    local target = targetArg == 'player' and windower.ffxi.get_player() or
        windower.ffxi.get_mob_by_target(targetArg)
    local game_info = windower.ffxi.get_info()
    local zone = game_info and game_info.zone and resources.zones[game_info.zone]

    if target ~= nil then
        writeMessage(
            "\n" ..

            string.format('Target: %s\n', text_mob(target.name)) ..

            string.format('  Zone: %s / %s (%s)\n':format(
                text_green(zone and zone.name or '--'),
                text_green(zone and zone.search or '--'),
                text_number(tostring(zone and zone.id or 0)
            )) ..

            string.format('  Id: %s\n', text_number(tostring(target.id))) ..
            string.format('  Index: %s/%s\n',
                text_number(tostring(target.index)),
                text_hex('%03X':format(target.index or 0))
            ) ..
            
            string.format('  Target\'s target index: %s/%s\n',
                text_number(tostring(target.target_index or 0)),
                text_hex('%03X':format(target.target_index or 0))
            ) ..
            
            string.format('  Spawn type: %s\n', text_number(tostring(target.spawn_type))) ..
            string.format('  Status: %s\n', text_number(tostring(target.status))) ..
            string.format('  Claim id: %s\n', text_number(tostring(target.claim_id or 0))) ..
            string.format('  Model size: %s x%s\n',
                text_number('%.2f':format(target.model_size or -1337)),
                text_number('%.2f':format(target.model_scale or -1337))
            ) ..
            
            string.format('  Pos: %s  %s  %s\n',
                text_number('%.2f':format(target.x or -1337)),
                text_number('%.2f':format(target.y or -1337)),
                text_number('%.2f':format(target.z or -1337))
            ) ..
            
            string.format('  Hdg: %s\n', text_number('%.2f degrees':format(target.heading and (target.heading * 180 / math.pi) or -1337))) ..
            
            string.format('  Speed: %s\n', text_number('%.2f':format(target.movement_speed or -1337)))
        ))

        if arrayIndexOfStrI(args, '-save') then
            local filename = string.format('.\\data\\targets\\%s-%d.target.json', target.name, target.index)
            writeMessage('Saving target info to file: ' .. filename)
            writeJsonToFile(filename, target)

            local party = windower.ffxi.get_party()
            local partyMember = party[targetArg]
            if partyMember then
                writeJsonToFile(string.format('.\\data\\%s-%d.party.json', partyMember.name, partyMember.mob.index), partyMember)
            end
        end
    end
end
handlers['ti'] = handlers['targetinfo']

handlers['rollinfo'] = function (args)
    local latestRoll = actionStateManager:getLatestRoll()
    local hasRolls = false
    local rolls = actionStateManager:getRolls(true)
    
    for id, value in pairs(rolls) do
        hasRolls = true
        writeMessage('  %s %s%s':format(
            text_buff(value.name),
            text_number(value.count),
            latestRoll and latestRoll.id == value.id and '*' or ''))
    end

    if not hasRolls then
        writeMessage('  No active rolls were found.')
    end
end
handlers['ri'] = handlers['rollinfo']

-------------------------------------------------------------------------------
-- ignore-list
handlers['ignore-list'] = function (args)
    local show = arrayIndexOfStrI(args, '-show') ~= nil

    local downgrade = (arrayIndexOfStrI(args, '-downgrade') or arrayIndexOfStrI(args, '-down'))
    if downgrade then
        downgrade = tonumber(args[downgrade + 1])
    end

    local remove = arrayIndexOfStrI(args, '-remove')
    if remove then
        remove = tonumber(args[remove + 1])
    end

    if show then
        local message = makeDisplayValue('Current Ignore List', settings.ignoreList)
        writeMessage(message)
    elseif remove then
        table.remove(settings.ignoreList, remove)
        writeMessage(string.format('Successfully removed item %d from the ignore list!', remove))
        saveSettings()
    elseif downgrade then
        local item = settings.ignoreList[downgrade]
        if item then
            item.downgrade = (not item.downgrade) or nil
            writeMessage(string.format('Ignore list item %d has been set with downgrade=%s', downgrade, item.downgrade and 'true' or 'false'))
            saveSettings()
        else
            writeMessage(string.format('No ignore list item was found at index %d', downgrade))
        end
    end
end
handlers['il'] = handlers['ignore-list']

-------------------------------------------------------------------------------
-- ignore
handlers['ignore'] = function (args)
    local always = arrayIndexOfStrI(args, '-always') ~= nil
    local withZone = arrayIndexOfStrI(args, '-zone') ~= nil
    local downgrade = arrayIndexOfStrI(args, '-downgrade') ~= nil or arrayIndexOfStrI(args, '-dg') ~= nil
    
    local note = arrayIndexOfStrI(args, '-note')
    if note then
        note = args[note + 1]
    end

    local name = arrayIndexOfStrI(args, '-name')

    if arrayIndexOfStrI(args, '-target') or arrayIndexOfStrI(args, '-t') or not name then
        local target = windower.ffxi.get_mob_by_target('t')
        if target ~= nil and target.spawn_type == 16 then
            
            -- If a name argument was specified, grab the name from the target and use that
            if name then
                sendSelfCommand(string.format(
                        'ignore -name "%s"%s%s%s%s',
                        target.name,
                        note and string.format(' -note "%s"', note) or '',
                        withZone and ' -zone' or '',
                        always and ' -always' or '',
                        downgrade and ' -downgrade' or ''
                    )
                )
                return
            end

            settings.ignoreList[#settings.ignoreList + 1] = {
                index = target.index,
                zone = globals.currentZone.id,
                ignoreAlways = always or nil,
                name = nil,
                downgrade = downgrade or nil,
                _note = note,
                _refName = target.name,
                _refZone = globals.currentZone.name,
            }

            saveSettings()
            writeMessage(string.format('Successfully added %s [Index=%03X] to the ignore list!', target.name, target.index))
        else
            writeMessage('There is not a valid target.')
        end
    elseif name then
        name = args[name + 1]
        if name then
            settings.ignoreList[#settings.ignoreList + 1] = {
                name = name,
                zone = withZone and globals.currentZone.id or nil,
                downgrade = downgrade or nil,
                ignoreAlways = always or nil,
                _note = note,
                _refZone = withZone and globals.currentZone.name or nil,
            }

            saveSettings()
            writeMessage(string.format('Successfully added [%s] with zone=[%s] to the ignore list!', name, withZone and globals.currentZone.name or '*'))
        else
            writeMessage('A valid name was not provided.')
        end
    end
end

handlers['target'] = function(args)
    local id = arrayIndexOfStrI(args, '-id')
    local index = arrayIndexOfStrI(args, '-index')
    local name = arrayIndexOfStrI(args, '-name') or arrayIndexOfStrI(args, '-n')

    -- If none of the known arguments were provided, we'll just treat the entire
    -- argument list as if it were a mob name
    if not id and not index and not name then
        if args and #args > 0 then
            name = table.concat(args, ' ')
        end
    else
        id = id and tonumber(args[id + 1]) or 0
        index = index and tonumber(args[index + 1]) or 0
        name = name and args[name + 1] and tostring(args[name + 1])
    end

    local mob = nil
    if id and id > 0 then
        mob = windower.ffxi.get_mob_by_id(id)
    elseif index and index > 0 then
        mob = windower.ffxi.get_mob_by_index(index)
    elseif name then
        local context = actionStateManager and actionStateManager:getContext()
        mob = context and context.findByName(name)
    end

    if mob then
        local player = windower.ffxi.get_player()
        lockTarget(player, mob)
    else
        writeMessage(text_gray(
            'The specified mob [%s] could not be found.':format(
                text_yellow(id or index or name or '<unknown>', Colors.gray)
            )
        ))
    end
end
handlers['ta'] = handlers['target']

handlers['touch'] = function(args)
    local name = arrayIndexOfStrI(args, '-name') or arrayIndexOfStrI(args, '-n')
    local id = arrayIndexOfStrI(args, '-id')
    local t = arrayIndexOfStrI(args, '-t')
    local all = arrayIndexOfStrI(args, '-all')

    local context = actionStateManager and actionStateManager:getContext()
    local mob = nil

    -- Using current target
    if mob == nil and type(t) == 'number' then
        mob = windower.ffxi.get_mob_by_target('t')
    end

    -- Using mob id
    if mob == nil and type(id) == 'number' then
        id = args[id + 1]
        mob = windower.ffxi.get_mob_by_id(id)
    end

    -- Using mob name
    if mob == nil and type(name) == 'number' and context then
        name = args[name + 1]
        if name then
            mob = context.findByName(name)
        end
    end

    if mob then
        --print('all=' .. (all and 'yes' or 'no') .. ' / mob: id=' .. mob.id .. ', name=' .. mob.name)
        if type(all) == 'number' then
            local command = 'send @all //gbt touch -id %d':format(mob.id)
            windower.send_command(command)
        else
            local enabled = globals.enabled
            globals.enabled = false

            writeMessage('Attempting to %s target: %s':format(
                text_green('touch'),
                text_mob(mob.name)
            ))

            local followJob = smartMove:cancelJob()

            context.touch(mob)

            if followJob then
                smartMove:reschedule(followJob)
            end

            if enabled then
                globals.enabled = true
            end
        end
    end
end

handlers['tap'] = function(args)
    local name = arrayIndexOfStrI(args, '-name')
    local id = arrayIndexOfStrI(args, '-id')
    local t = arrayIndexOfStrI(args, '-t')
    local all = arrayIndexOfStrI(args, '-all')

    local context = actionStateManager and actionStateManager:getContext()
    local mob = nil

    -- Using current target
    if mob == nil and type(t) == 'number' then
        mob = windower.ffxi.get_mob_by_target('t')
    end

    -- Using mob id
    if mob == nil and type(id) == 'number' then
        id = args[id + 1]
        mob = windower.ffxi.get_mob_by_id(id)
    end

    -- Using mob name
    if mob == nil and type(name) == 'number' and context then
        name = args[name + 1]
        if name then
            mob = context.findByName(name)
        end
    end

    if mob then
        --print('all=' .. (all and 'yes' or 'no') .. ' / mob: id=' .. mob.id .. ', name=' .. mob.name)
        if type(all) == 'number' then
            local command = 'send @all //gbt tap -id %d':format(mob.id)
            windower.send_command(command)
        else
            local enabled = globals.enabled
            globals.enabled = false

            writeMessage('Attempting to %s target: %s':format(
                text_green('tap'),
                text_mob(mob.name)
            ))

            local followJob = smartMove:cancelJob()

            context.tap(mob)

            if followJob then
                smartMove:reschedule(followJob)
            end

            if enabled then
                globals.enabled = true
            end
        end
    end
end

handlers['actions'] = function(args)
    local on = arrayIndexOfStrI(args, '-on') or arrayIndexOfStrI(args, '-enable')
    local off = arrayIndexOfStrI(args, '-off') arrayIndexOfStrI(args, '-disable')
    local toggle = arrayIndexOfStrI(args, '-toggle')

    local load = tonumber(arrayIndexOfStrI(args, '-load') or 0)

    if load > 0 then
        local actionsName = args[load + 1]
        if actionsName then
            local actions, fileName = loadActions(windower.ffxi.get_player().name, actionsName)
            if type(actions) == 'table' then
                
                settings.actionInfo = settings.actionInfo or {}
                settings.actionInfo.name = actionsName
                settings.actionInfo.fileName = fileName
                settings.actions = actions

                recompileActions()
                saveSettings()
            end
        end

        return
    end
    
    local saveDefault = tonumber(arrayIndexOfStrI(args, '-save-default') or 0)
    local force = tonumber(arrayIndexOfStrI(args, '-force') or 0)
    if saveDefault > 0 then
        if saveDefaultActions(windower.ffxi.get_player(), force > 0) then
            writeMessage('Default actions were saved.')
        else
            writeMessage('Defaults could not be saved. Run with -force to overwrite existing actions.')
        end

        return
    end

    local saveLocal = tonumber(arrayIndexOfStrI(args, '-save-local') or 0)
    local saveLocalActions = saveLocal > 0 and args[saveLocal + 1]
    if saveLocal > 0 then
        if saveLocalActions or (settings and settings.actionInfo and type(settings.actionInfo.name) == 'string') then
            local success, message = saveActions(windower.ffxi.get_player(), force > 0, saveLocalActions or settings.actionInfo.name)
            if not success then
                writeMessage(message)
            end
        end
        return
    end

    if load <= 0 and saveDefault <= 0 then
        if on then
            globals.actionsEnabled = true
        elseif off then
            globals.actionsEnabled = false
        elseif toggle then
            globals.actionsEnabled = not globals.actionsEnabled
        end
        
        writeMessage(string.format(
            '  Action execution is [%s]',
            globals.actionsEnabled and text_green('on') or text_red('off')
        ))
    end
end

handlers['align'] = function(args)
    local target = arrayIndexOfStrI(args, '-target') or arrayIndexOfStrI(args, '-t')
    local distance = arrayIndexOfStrI(args, '-distance') or arrayIndexOfStrI(args, '-d')
    local angle = arrayIndexOfStrI(args, '-angle') or arrayIndexOfStrI(args, '-a')
    local wait = arrayIndexOfStrI(args, '-wait') or arrayIndexOfStrI(args, '-w')
    local cancel = arrayIndexOfStrI(args, '-cancel') or arrayIndexOfStrI(args, '-c')

    distance = tonumber(tonumber(distance) and args[tonumber(distance) + 1]) or 1
    angle = tonumber(tonumber(angle) and args[tonumber(angle) + 1])
    wait = tonumber(tonumber(wait) and args[tonumber(wait) + 1]) or 10

    if cancel then
        local jobInfo = smartMove:getJobInfo()
        local jobId = smartMove:cancelJob()
        if jobId then
            writeMessage('Follow cancelled!')
        else
            writeMessage('There was no follow to cancel.')
        end
    else
        if target then
            target = windower.ffxi.get_mob_by_name(args[target + 1])
        else
            target = windower.ffxi.get_mob_by_target('t')
        end

        if target and target.valid_target then
            local context = actionStateManager:getContext()

            if context then
                if angle then
                    writeMessage('Aligning within %s of the %s position of %s...':format(
                        text_number('%03d degree':format(angle)),
                        text_number('%.1f':format(distance)),
                        text_mob(target.name)
                    ))
                else
                    writeMessage('Aligning within %s of %s...':format(
                        text_number('%.1f':format(distance)),
                        text_mob(target.name)
                    ))
                end

                local success = context.align(target, angle, distance, wait)

                writeMessage('Alginment with %s was %s!':format(
                    text_mob(target.name),
                    success and text_green('successful') or text_red('unsuccessful')
                ))

                return
            end

            writeMessage('Unable to align with %s!':format(
                text_mob(target.name)
            ))
        else
            writeMessage('A valid alignment target was not specified!')
        end
    end
end

handlers['showfollow'] = function(args)
    writeMessage('Not implemented: showfollow')
end

handlers['walkmode'] = function (args)
    local on = arrayIndexOfStrI(args, '-on')
    local off = arrayIndexOfStrI(args, '-off')

    if on then
        windower.ffxi.toggle_walk(true)
    elseif off then
        windower.ffxi.toggle_walk(false)
    else
        windower.ffxi.toggle_walk()
    end
end

handlers['buffs'] = function(args)
    local player = windower.ffxi.get_player()
    local buffs = player and player.buffs

    if type(buffs) == 'table' and #buffs > 0 then
        local message = '\n' .. text_cornsilk('\nMy Active Buffs\n')

        for i, id in ipairs(buffs) do
            local buff = resources.buffs[id]
            if buff then
                message = message .. ' %s (%s)\n':format(
                    text_buff(buff.name),
                    text_number(id)
                )
            end

            if message:len() > 450 then
                writeMessage(message)
                message = '\n'
            end
        end

        if message:len() > 1 then
            writeMessage(message)
        end
    else
        writeMessage('No active buffs were found.')
    end

end

handlers['mobbuffs'] = function(args)
    local mobs = actionStateManager:getBuffedMobs()
    local limit = arrayIndexOfStrI(args, '-limit') or arrayIndexOfStrI(args, '-l')
    if limit then
        limit = args[limit + 1]
        if type(limit) == 'string' then
            limit = string.lower(limit)
        end
    end

    if #mobs > 0 then
        local message = '\n' .. text_cornsilk('\nTracked Mob Buffs\n')

        for i, id in ipairs(mobs) do
            local data = actionStateManager:getBuffInfoForMob(id)
            if 
                data and
                data.details and
                data.mob
            then
                local mob = data.mob
                local mobcol = mob.spawn_type == SPAWN_TYPE_MOB and text_magenta or text_green
                local type = 
                    (isMobPlayer(mob) and 'Player') or
                    ((mob.spawn_type == SPAWN_TYPE_TRUST) and 'Trust')
                    or 'Mob'
                local t = windower.ffxi.get_mob_by_target('bt') or windower.ffxi.get_mob_by_target('t')
                local is_my_bt = t and t.id == mob.id

                if
                    not limit or (
                        (is_my_bt or limit ~= 'bt') and
                        (mob.spawn_type == SPAWN_TYPE_TRUST or limit ~= 'trust') and
                        (mob.spawn_type == SPAWN_TYPE_MOB or limit ~= 'mob')
                    )
                then

                    -- Mob header
                    message = message .. 
                        '  %s%s / %s (%s)\n':format(
                            mobcol(mob.name),
                            is_my_bt and '**' or '',
                            text_number('%03X':format(mob.index)),
                            type
                        )

                    -- Mob buffs list
                    for buffId, info in pairs(data.details) do
                        local buff = resources.buffs[buffId]
                        local actor = info.actor
                        local actorcol = (actor and (isMobPlayer(actor) or actor.spawn_type == SPAWN_TYPE_TRUST or actor.spawn_type == SPAWN_TYPE_PET)) and text_green or text_magenta
                        local actortype = '???'
                        if info.byMe then
                            actortype = 'Me'
                        elseif actor then
                            if isMobPlayer(actor) then actortype = 'Player'
                            elseif actor.spawn_type == SPAWN_TYPE_PET then actortype = 'Pet'
                            elseif actor.spawn_type == SPAWN_TYPE_TRUST then actortype = 'Trust'
                            elseif actor.spawn_type == SPAWN_TYPE_MOB then actortype = 'Mob'
                            end
                        end

                        message = message ..
                            '    %s applied by %s (%s): %s\n':format(
                                text_buff(buff.name),
                                actorcol(actor and actor.name or '???'),
                                actortype,
                                info.timer and info.timer > 0 and pluralize('%d':format(info.timer), 'second', 'seconds') or text_cornsilk('--')
                            )
                    end

                    if message:len() > 450 then
                        writeMessage(message)
                        message = '\n'
                    end
                end
            end
        end

        if message:len() > 1 then
            writeMessage(message)
        end
    else
        writeMessage('No actively tracked mob buffs were found.')
    end
end
handlers['mb'] = handlers['mobbuffs']

handlers['equipment'] = function(args)
    local slot = arrayIndexOfStrI(args, '-slot') or arrayIndexOfStrI(args, '-s')
    slot = type(slot) == 'number' and args[slot + 1] or nil

    local verbose = arrayIndexOfStrI(args, '-verbose') or arrayIndexOfStrI(args, '-v')

    if slot then
        local equipment = inventory.find_equipment_in_slot(slot)
        if equipment then
            writeMessage('Found %s equipped in %s with %s!':format(
                text_item(equipment.name),
                text_gearslot(equipment.slot),
                pluralize(equipment.augments and #equipment.augments or 0, 'augment', 'augments')
            ))

            if equipment.augments and #equipment.augments > 0 then
                writeMessage('    Augments:')
                for i, augment in ipairs(equipment.augments) do
                    writeMessage('      %s. %s':format(text_number(i), text_item(augment)))
                end
            end

            if verbose then
                writeMessage('    Details:')
                writeMessage('      Name: %s':format(text_item(equipment.name)))
                writeMessage('      Bag: %s / %s':format(text_item(equipment.bagName), text_number(equipment.bagId)))
                writeMessage('      Item id: %s':format(text_number(equipment.id)))
                writeMessage('      Local id: %s':format(text_number(equipment.localId)))
            end
        end
    end
end

handlers['cancelbuff'] = function(args)
    local index = 
        arrayIndexOfStrI(args, '-name') or
        arrayIndexOfStrI(args, '-names') or
        arrayIndexOfStrI(args, '-buff') or
        arrayIndexOfStrI(args, '-buffs') or
        arrayIndexOfStrI(args, '-n') or
        arrayIndexOfStrI(args, '-b')
    
    local names = table.unpack(args, index + 1, #args)

    if #names > 0 then
        local context = actionStateManager:getContext()
        local num_queued = context.cancelBuff(names)

        if num_queued then
            writeMessage('Successfully queued %s for cancellation!':format(pluralize(num_queued, 'buff', 'buffs')))
            return
        end
    end

    writeWarning('No buffs were queued for cancellation.')
end
handlers['cb'] = handlers['cancelbuff']

local BagsById = 
{
    [0] = { field = "inventory" },
    [8] = { field = "wardrobe" },
    [10] = { field = "wardrobe2" },
    [11] = { field = "wardrobe3" },
    [12] = { field = "wardrobe4" },
    [13] = { field = "wardrobe5" },
    [14] = { field = "wardrobe6" },
    [15] = { field = "wardrobe7" },
    [16] = { field = "wardrobe8" },
}

handlers['exp'] = function (args)
    -- local player = windower.ffxi.get_player()
    -- local buffs = player.buffs

    -- local commitment = tableFirst(resources.buffs:en('Commitment'))
    -- if commitment then
    --     local index = arrayIndexOf(buffs, commitment.id)
    --     if index == nil then
    --         local items = windower.ffxi.get_items()

    --         local ring1lid = items.equipment['ring1']
    --         local ring1bag = items.equipment['ring1_bag']

    --         local ring2lid = items.equipment['ring2']
    --         local ring2bag = items.equipment['ring2_bag']

    --     end
    -- end

    writeMessage('lang: ' .. (globals.language or ''))

    local spellName = 'Refresh'

    spellName = string.lower(spellName)

    local refresh = tableFirst(resources.spells, function (s) return string.lower(s.en) == spellName end)
    if refresh then
        writeMessage('Refresh found with id: ' .. refresh.id)
    else
        writeMessage('Refresh not found!')
    end
end

handlers['colortest'] = function (args)
    local color = tonumber(args[1])
    if color then
        writeMessage(colorize(color, string.format('Color %03d', color), Colors.default))
    end

    local maxColor = 252
    local line = ''
    for color = 1, maxColor do
        line = line .. colorize(color, string.format('%03d ', color), Colors.default)
        if (color % 12) == 0 or color == maxColor then
            writeMessage(line)
            line = ''
        end
    end
end


commands = {}

commands.process = function (command, args)
    command = (command or ''):lower()

    handler = handlers[command]
    if type(handler) == 'function' then
        handler(args)
    else
        writeMessage(string.format('Unknown command: %s', text_error(command)))
    end
end