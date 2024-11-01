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

    if TargetStrategy[strategy] == nil then
        writeMessage('Err: Invalid target strategy: ' .. strategy)
        return
    end

    settings.strategy = strategy
    saveSettings()

    writeMessage('Target strategy has been set to: ' .. strategy)
end
handlers['strat'] = handlers['strategy']

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
end

-------------------------------------------------------------------------------
-- enable
handlers['enable'] = function (args)
    local quiet = arrayIndexOfStrI(args, '-quiet')
    local changed = false

    if not globals.enabled then
        -- Clear the mob before we enable
        resetCurrentMob(nil)

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
end

-------------------------------------------------------------------------------
-- toggle
handlers['toggle'] = function (args)
    sendSelfCommand(globals.enabled and 'disable' or 'enable')
end

-------------------------------------------------------------------------------
-- follow
handlers['follow'] = function (args)
    local id = arrayIndexOfStrI(args, '-id')
    local index = arrayIndexOfStrI(args, '-index')

    id = id and tonumber(args[id + 1]) or 0
    index = index and tonumber(args[index + 1]) or 0
    
    local hasFollow = id > 0 or index > 0
    local noOverwrite = arrayIndexOfStrI(args, '-no-overwrite')

    -- Figure out if we should skip this command; that is, if the -no-overwrite flag
    -- was specified and the target has changed. This flag is used to resume follow
    -- after a longer action, where the mob could have been killed the bt changed.
    local skip = false
    if noOverwrite then
        local player = windower.ffxi.get_player()
        local followIndex = player.follow_index

        -- if followIndex and not globals.autoFollowIndex then
        --     -- We have a follow index but no global follow index, we'll proceed as if we have nothing
        --     followIndex = nil
        -- elseif not followIndex and globals.autoFollowIndex then
        --     -- We have no follow index but the global follow index is set; proceed as if we have nothing
        --     -- and clear the global
        --     globals.autoFollowIndex = nil
        -- end

        if followIndex then
            writeDebug('Follow index: %d (%03X)':format(followIndex, followIndex))
            writeJsonToFile('.\\data\\player.json', player)
            -- Skip if we're following a valid target
            local followed = windower.ffxi.get_mob_by_index(followIndex)
            if followed and followed.valid_target then
                skip = true
            end
        end

        if not skip then
            current = globals.target:mob()
            
            if hasFollow and not current then
                -- Skip if we're being asked to follow but there's no current target
                skip = true
            elseif hasFollow and current then
                -- Skip if our current id/index doesn't match the current target's id/index
                skip = (id ~= 0 and current.id ~= id) or
                    (index ~= 0 and current.index ~= index)
            elseif not hasFollow and current then
                -- Skip if this is a cancel and a target has been set
                skip = true
            end
        end
    end

    local _mobToFollow = nil

    if not skip then
        if id > 0 then
            local mob = windower.ffxi.get_mob_by_id(id)
            if mob and mob.valid_target and mob.hpp > 0 then
                _mobToFollow = mob
            end
        elseif index > 0 then
            local mob = windower.ffxi.get_mob_by_index(index)
            if mob and mob.valid_target and mob.hpp > 0 then
                _mobToFollow = mob
            end
        end
    end

    if skip then
        writeTrace('Follow skipped because another target was already set.')
    elseif _mobToFollow then
        globals.autoFollowIndex = _mobToFollow.index
        windower.ffxi.follow(_mobToFollow.index)        
        
        writeTrace(string.format('Following %s at distance %.1f with index=%d (%03X)',
            text_mob(_mobToFollow.name, Colors.trace),
            math.sqrt(_mobToFollow.distance),
            _mobToFollow.index,
            _mobToFollow.index))
    else
        windower.ffxi.run(false)

        -- SUPER SUPER important to use -1, rather than no param at all like the docs say. If you pass nothing,
        -- the player object's follow index is not modified and it becomes incorrect.
        --
        -- UPDATE: There are still bugs, so we're going to have to use our own tracking. Hence, globals.autoFollowIndex :(
        globals.autoFollowIndex = nil
        windower.ffxi.follow(-1)
        
        writeTrace('Follow cancelled.')
    end
end

handlers['run'] = function(args)
    local start = arrayIndexOfStrI(args, '-start')
    local stop = arrayIndexOfStrI(args, '-stop')

    if start then
        windower.ffxi.run(true)
    elseif stop then
        windower.ffxi.run(false)
    end
end

handlers['walk'] = function (args)

    local stop = arrayIndexOfStrI(args, '-stop')
    if stop then
        windower.ffxi.run(false)
        return
    end

    local direction = tonumber(arrayIndexOfStrI(args, '-direction'))
    local time = tonumber(arrayIndexOfStrI(args, '-time'))

    direction = direction and args[direction + 1]
    time = time and tonumber(args[time + 1] or 0)

    local radians = nil
    local degrees = tonumber(direction)
    if type(direction) == 'string' then
        radians = directionality.directionToRadians(direction)
    elseif type(degrees) == 'number' then
        radians = directionality.degToRad(degrees)
    end

    -- If we have an angle, face toward it
    windower.ffxi.follow(-1)
    if radians ~= nil then
        windower.ffxi.run(radians)
    else
        windower.ffxi.run()
    end

    local directionMessage = radians ~= nil and 
        ' with heading %s degrees':format(text_number('%03d':format(directionality.radToDeg(radians)))) or ''

    -- Set up the run end, if one was specified
    if type(time) == 'number' and time > 0 then
        
        writeMessage('Initiating walk for %s%s.':
            format(pluralize(time, 'second', 'seconds'),
            directionMessage
        ))

        local stopCommand = string.format('wait %d; %s',
            time,
            makeSelfCommand('follow -no-overwrite')
        )
        windower.send_command(stopCommand)
    else
        writeMessage('Initiating walk%s.':format(directionMessage))
    end
end

handlers['face'] = function(args)
    local id = arrayIndexOfStrI(args, '-id')
    local index = arrayIndexOfStrI(args, '-index')
    local target = arrayIndexOfStrI(args, '-target') or arrayIndexOfStrI(args, '-t')
    local direction = arrayIndexOfStrI(args, '-direction')
    local skipFacing = false

    id = id and tonumber(args[id + 1])
    index = index and tonumber(args[index + 1])
    target = target and 't'
    direction = direction and tonumber(args[direction + 1])

    local radians = nil

    if direction ~= nil then
        if type(direction) == 'number' then
            -- The param was a numeric degree value
            radians = directionality.degToRad(direction)
        else
            -- The param was a named directional value
            radians = directionality.directionToRadians(direction)
        end
    else
        local target = (id and windower.ffxi.get_mob_by_id(id)) or
            (index and windower.ffxi.get_mob_by_index(index)) or
            (target and windower.ffxi.get_mob_by_target(target))
        radians = directionality.faceTarget(target, true)

        local radians = directionality.faceTarget(target)
        skipFacing = true
    end

    if type(radians) == 'number' then
        writeMessage('Adjusting current heading to %s!':format(
            text_number('%03d degrees':format(
                directionality.radToDeg(radians)
            ))
        ))

        if not skipFacing then
            directionality.faceDirection(radians)
        end
    end    
end

-------------------------------------------------------------------------------
-- reload
handlers['reload'] = function (args)
    -- The settings only flag causes us to bypass the reloading of actions, and to just load
    -- settings changes. This allows us to configure verbosity and whatnot without losing
    -- the current action state.
    local bypassActions = arrayIndexOfStrI(args, '-settings-only') or arrayIndexOfStrI(args, '-so')
    local actionsName = arrayIndexOfStrI(args, '-actions') or arrayIndexOfStrI(args, '-a')

    actionsName = actionsName and (args[actionsName + 1]) or nil

    reloadSettings(actionsName, bypassActions ~= nil)
end
handlers['r'] = handlers['reload']

-------------------------------------------------------------------------------
-- verbosity
handlers['verbosity'] = function (args)
    local level = arrayIndexOfStrI('-level')
    local verbosity = type(level) == 'number' and (args[level + 1] or ''):lower()
    local verbositySet = false

    if verbosity == 'normal' or verbosity == '0' then
        settings.verbosity = VERBOSITY_NORMAL
        verbositySet = true
    elseif verbosity == 'verbose' or verbosity == '1' then
        settings.verbosity = VERBOSITY_VERBOSE
        verbositySet = true
    elseif verbosity == 'debug' or verbosity == '2' then
        settings.verbosity = VERBOSITY_DEBUG
        verbositySet = true
    elseif verbosity == 'trace' or verbosity == '3' then
        settings.verbosity = VERBOSITY_TRACE
        verbositySet = true
    end

    if verbositySet then
        logging_settings.verbosity = settings.verbosity

        writeMessage(string.format('Verbosity set to: %s', verbosity))
        saveSettings()
    else
        writeMessage(string.format('Invalid verbosity setting: %s', verbosity))
    end
end

-------------------------------------------------------------------------------
-- targetinfo
handlers['targetinfo'] = function (args)
    local targetArg = tonumber(arrayIndexOfStrI(args, '-target') or arrayIndexOfStrI(args, '-t') or 0)
    if targetArg then
        targetArg = args[targetArg + 1]
    end

    targetArg = targetArg or 't'

    local target = targetArg == 'player' and windower.ffxi.get_player() or
        windower.ffxi.get_mob_by_target(targetArg)
    if target ~= nil then
        writeMessage(
            "\n" ..
            string.format('Target: %s\n', target.name) ..
            string.format('Id: %s\n', tostring(target.id)) ..
            string.format('Index: %d (Hex=%03X)\n', target.index, target.index) ..
            string.format('Spawn type: %s\n', tostring(target.spawn_type)) ..
            string.format('Status: %s\n', tostring(target.status)) ..
            string.format('Claim id: %s\n', tostring(target.claim_id or 0)) ..
            string.format('Pos: (%.2f, %.2f, %.2f)\n', target.x or -1337, target.y or -1337, target.z or -1337) ..
            string.format('Speed: %.2f\n', target.movement_speed or -1337)
        )

        if arrayIndexOfStrI(args, '-save') ~= nil then
            writeJsonToFile(string.format('.\\data\\%s-%d.target.json', target.name, target.index), target)

            local party = windower.ffxi.get_party()
            local partyMember = party[targetArg]
            if partyMember then
                writeJsonToFile(string.format('.\\data\\%s-%d.party.json', partyMember.name, partyMember.mob.index), partyMember)
            end

            -- local player = windower.ffxi.get_player()
            -- player = windower.ffxi.get_mob_by_id(player.id)
            -- writeJsonToFile(string.format('.\\data\\%s-%d.self.json', player.name, player.index), player)
        end
    end
end
handlers['ti'] = handlers['targetinfo']

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

    id = id and tonumber(args[id + 1]) or 0
    index = index and tonumber(args[index + 1]) or 0

    local _mob = nil
    if id > 0 then
        mob = windower.ffxi.get_mob_by_id(id)
    elseif index > 0 then
        mob = windower.ffxi.get_mob_by_index(index)
    end

    if mob then
        local player = windower.ffxi.get_player()
        lockTarget(player, mob)
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
            local actions = loadActions(windower.ffxi.get_player().name, actionsName)
            if type(actions) == 'table' then
                
                settings.actionInfo = settings.actionInfo or {}
                settings.actionInfo.name = actionsName
                settings.actions = actions

                recompileActions()
                saveSettings()
            end
        end
    else
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
    local id = arrayIndexOfStrI(args, '-id')
    local index = arrayIndexOfStrI(args, '-index')
    local t = arrayIndexOfStrI(args, '-t')
    local duration = arrayIndexOfStrI(args, '-duration')

    id = id and tonumber(args[id + 1]) or 0
    index = index and tonumber(args[index + 1]) or 0

    duration = duration and args[duration + 1]
    duration = duration and math.max(tonumber(duration), 0) or 10

    local _mob = nil
    if t then
        _mob = windower.ffxi.get_mob_by_target('t')
    elseif id > 0 then
        _mob = windower.ffxi.get_mob_by_id(id)
    elseif index > 0 then
        _mob = windower.ffxi.get_mob_by_index(index)
    end

    if _mob then
        result = directionality.walkToMobRear(_mob, 1.5, 5)

        -- local aligned = directionality.isAtMobRear(mob, 2) and context.facingEnemy()
        -- if aligned then
        --     writeVerbose('Already aligned, exiting.')
        --     return
        -- end

        -- writeVerbose('Walking to rear of %s...':format(text_mob(mob.name, Colors.verbose)))

        -- local tries = 0
        -- local result = false
        -- while tries < 10 and not directionality.isAtMobRear(mob, 2) do
        --     result = directionality.walkToMobRear(mob, 2, 1)
        --     tries = tries + 1
        -- end
        -- writeVerbose('  ..walk completed (%s in %d tries)':format(result and 'success' or 'exited', tries))
    end
end

handlers['showfollow'] = function(args)
    local player = windower.ffxi.get_player()
    if player and player.follow_index then
        local mob = windower.ffxi.get_mob_by_index(player.follow_index)
        if mob and mob.valid_target then
            writeMessage('Following %s (%s / %s)':format(text_mob(mob.name), text_number(mob.index), text_number('%03X':format(mob.index))))
        end
    end

    writeMessage('No follow target was found.')
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

local commitmentRings = {
    "Endorsement Ring",
    "Trizek Ring",
    "Capacity Ring"
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