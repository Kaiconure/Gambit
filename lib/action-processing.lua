-------------------------------------------------------------------------------
-- ACTION SCHEMA
--
--  Three action types: pull, battle, and idle. The system transitions through them
--  based on current state. Each of these is an array of actions to execute, in
--  ascending priority order. Every cycle, these will be evaluated to determine
--  the first one that's ready (the 'when' piece), and then the associated actions
--  will be performed (the 'commands' piece).
--
-- Actions:
--  - [when] - A conditional that determines if the action will be triggered. This is a string.
--  - [commands] - An array of commands to execute when the condition is met.
--  - [frequency] - If the conditions are met and executed, this action will not be evaluated
--      again until [frequency] seconds has passed.
--  - [delay] - The number of seconds to wait before executing the action. This is measured
--      from the time the current state was entered (pull, battle, idle).
--
-------------------------------------------------------------------------------

function recompileActions()
    actionStateManager.needsRecompile = true
end

function setSkillchain(name, mob)
    actionStateManager:setSkillchain(name, mob)
end

function markMobAbilityStart(mob, ability, targets)
    actionStateManager:setMobAbility(mob, ability, targets)
end

function markMobAbilityEnd(mob)
    actionStateManager:clearMobAbility(mob)
end

function setPartyWeaponSkill(actor, skill, mob)
    actionStateManager:setPartyWeaponSkill(actor, skill, mob)
end

--------------------------------------------------------------------------------------
-- Executes an action command. Spells should use sendSpellCastingCommand instead, as
-- it will take into account traits such as Fast Cast as well as spell interruption.
--
function sendActionCommand(
    command,            -- The command to execute
    context,            -- The context we're working under
    commandDuration,    -- The amount of time the command is expected to take. If greater than 0, the thread is slept for this time.
    pauseFollow,        -- Whether follows should be paused during execution
    durationType        -- Set how to handle the specified duration
)
    if durationType then
        writeDebug("Warning: Duration type value provided: " .. tostring(durationType))
    end

    -- How to handle the duration
    durationType = durationType or 0

    -- Overall sleep time
    commandDuration = math.max(tonumber(commandDuration) or 0, 0)

    -- If we're not pausing the follow, we'll at least stop the smart move component
    -- from thinking we're stuck while performing this action
    if not pauseFollow then
        smartMove:resetJitter()
    end

    local movementJob = pauseFollow and smartMove:cancelJob()
    if command and command ~= '' then
        if settings.verbosity >= VERBOSITY_TRACE then
            writeTrace(string.format('Sending %s', colorize(Colors.magenta, command, Colors.trace)))
        end
        windower.send_command(command)
    end

    if commandDuration > 0 then
        coroutine.sleep(commandDuration)        
    end

    -- Kick the movement job back on, if any
    if movementJob then
        smartMove:reschedule(movementJob)
    elseif not pauseFollow then
        -- We'll reset jitter again once the command is done
        smartMove:resetJitter()
    end

    -- TODO: Maybe see if there's a better way to figure this out dynamically?
    local complete = true

    if context and context.action then
        complete = true
        context.action.complete = true
        context.action.incomplete = false
    end

    return complete
end

function sendRangedAttackCommand(target, context, waitFor)
    if 
        target == nil
    then
        return
    end

    local followJob = smartMove:cancelJob()

    -- Construct the actual spell casting command
    local command = 'input /ra <%s>;':format(
        target.symbol or target
    )

    local startTime = os.clock()

    -- Send the ranged attack command. It will wait 1 second before returning (the third parameter)
    sendActionCommand(command, context, 1)
    
    -- Wait until the RA is done or it expires
    local continue = true
    while continue do 
        local ra = actionStateManager:getRangedAttack()
        if ra == nil or ra.time == 0 then
            continue = false
        else
            coroutine.sleep(0.5)
        end
    end

    local complete = actionStateManager:getRangedAttackSuccessful()

    -- Sleep a bit more to space things out
    if type(waitFor) == 'number' and waitFor > 0 then
        coroutine.sleep(waitFor)
    end

    if followJob then
        smartMove:reschedule(followJob)
    end

    local endTime = os.clock()

    if context and context.action then
        context.action.complete = complete
        context.action.incomplete = not complete
    end

    writeDebug('Ranged attack observer has completed with %s after %s!':format(
        complete and text_green('success') or text_red('interruption'),
        pluralize('%.1f':format(endTime - startTime), 'second', 'seconds')
    ))

    return complete
end

--------------------------------------------------------------------------------------
-- Executes a spell casting action command.This is similar to sendActionCommand, but
-- it will take into account traits such as Fast Cast as well as spell interruption
-- to ensure that the operation completes as early as possible.
function sendSpellCastingCommand(spell, target, context, ignoreIncomplete)
    if 
        spell == nil or
        target == nil
    then
        return
    end

    local followJob = smartMove:cancelJob()

    -- Calculate the maximum amount of time we will wait for spell casting to complete. It's
    -- safer for this to err on the slightly longer side, as we will exit early as soon as we
    -- detect that casting has completed.
    local endTime = os.clock() + (math.max(spell.cast_time, 1) * 1.5) + 1

    -- Construct the actual spell casting command
    local command = 'input %s "%s" <%s>':format(
        spell.prefix,
        spell.name,
        target
    )

    local castingStartedAt = os.clock()
    local interrupted   = false     -- Set if the spell completes with interruption
    local missed        = false     -- Set if the spell completed but missed (not yet implemented)
    local isFirstCycle  = true

    -- Send the casting command. It will wait 1 second before returning (the third parameter)
    sendActionCommand(command, context, 1)

    -- We will now continue looping until either casting completes, or the max end time has been reached.
    -- Note that if the spell has not begun casting after the 1 second delay used above, exit early.
    local continue = true
    while continue do
        local currentSpell = actionStateManager.currentSpell

        if
            os.clock() >= endTime or
            currentSpell.spell ~= spell
        then
            continue = false
            interrupted = currentSpell.interrupted
        else
            isFirstCycle = false
            coroutine.sleep(0.25)
        end
    end

    local castingEndedAt = os.clock()

    -- We need to pad the casting time a bit, because spell casting fires its completion event before
    -- it's actually fully done casting.
    local paddingTime = 2.0

    coroutine.sleep(paddingTime)

    if followJob then
        smartMove:reschedule(followJob)
    end

    local wokeAt = os.clock()

    local castingTime = castingEndedAt - castingStartedAt
    local totalTime = wokeAt - castingStartedAt

    local complete = not interrupted

    -- If the spell was interrupted, we'll adjust scheduling to allow it to be tried again
    if
        interrupted and
        context and
        context.action and
        ignoreIncomplete ~= true
    then
        context.action.complete = false
        context.action.incomplete = true
    elseif 
        not interrupted and
        context and 
        context.action 
    then
        context.action.complete = true
        context.action.incomplete = false
    end

    -- In trace mode, let's log that we've finished our work here
    if settings.verbosity >= VERBOSITY_TRACE then
        writeTrace('%s: Cast time %s / Observer time %s':format(
            text_spell(spell.name, Colors.trace),
            pluralize('%.1f':format(castingTime), 'second', 'seconds', Colors.trace),
            pluralize('%.1f':format(totalTime), 'second', 'seconds', Colors.trace)        
        ))
    end

    return complete
end

function string_trim(s)
    if type(s) == 'string' then
        return string:match('^()%s*$') and '' or s:match('^%s*(.*%S)')
    end

    return ''
 end

 --------------------------------------------------------------------------------------
-- Recompiles the specified action type
local function compileActions(actionType, parent, rawActions)
    --writeMessage(string.format('Recompiling [%s] actions...', actionType))

    if isArray(rawActions) then
        local actions = json.parse(json.stringify(rawActions)) -- force deep copy
        local _temp = {}
        for i, action in ipairs(actions) do
            local shouldAdd = false

            -- If the "when" clause was broken into an array, we'll combine it all into
            -- a single parenthesised AND'ed expression here.
            if type(action.when) == 'table' then
                local and_count = 0
                local combined = ''
                local expression = ''
                local expression_count = 0
                local has_multiline = false
                for i, _when in ipairs(action.when) do
                    if type(_when) == 'string' then
                        _when = trimString(_when)
                        if _when ~= '' then
                            local len = #_when
                            if _when[len] == '\\' then
                                expression = expression .. (expression_count > 0 and ' ' or '') .. string.sub(_when, 1, len - 1) 
                                expression_count = expression_count + 1
                                has_multiline = true                                
                            else
                                combined = combined .. 
                                    (and_count > 0 and ' and ' or '') .. 
                                    '(' .. ((expression_count > 0 and (expression .. ' ') or '') .. _when) .. ')'

                                and_count = and_count + 1
                                expression = ''
                                expression_count = 0
                            end
                        end
                    end
                end

                if expression ~= '' then
                    if combined == '' then
                        combined = '(' .. expression .. ')'
                    else
                        combined = combined .. ' and (' .. expression .. ')'
                    end
                end

                -- if has_multiline then
                --     writeMessage('multiline: ' .. combined)
                -- end

                action.when = combined
            end

            -- If no when was provided, we'll always evaluate to true but will force a frequency of at least 1 second.
            -- Otherwise, this action (which always evaluates to true) would prevent anything further down from ever running.
            if action.when == nil or trimString(action.when) == '' then 
                action.when = 'true' 
                action.frequency = math.max(tonumber(action.frequency) or 0, 1)
            end

            if action.when and action.commands and not action.disabled then
                if type(action.commands) == 'string' then
                    action.commands = { action.commands }
                end

                if isArray(action.commands) then
                    -- Compute the 'when' function
                    action._whenFn = loadstring(string.format('return %s', action.when))

                    if action.frequency == 'inf' or action.frequency == 'infinity' then
                        -- We'll allow an infinity string to represent actions that should not normally be rescheduled.
                        -- This should typically be used in conjunction with a 'scope' value.
                        action.frequency = math.huge
                    else
                        -- Force frequency to a non-negative number
                        action.frequency = math.max(tonumber(action.frequency or 0), 0)
                    end
                    action.availableAt = 0
                    action.enumerators = { }
                    
                    if type(action.scope) == 'string' then
                        action.scope = string.lower(action.scope)
                    end

                    -- Certain action types will have a built in default delay
                    if actionType == 'battle' then
                        -- Battle actions will default to a delay of 2 unless otherwise specified
                        if tonumber(action.delay) == nil then
                            action.delay = 2
                        end
                    elseif actionType ~= 'idle' then
                        -- Other non-idle actions will default to a delay of 1 unless otherwise specified
                        if tonumber(action.delay) == nil then
                            action.delay = 1
                        end
                    end

                    -- Clamp the delay to (0, inf)
                    action.delay = math.max(tonumber(action.delay) or 0, 0)
                    
                    local hasErrors = type(action._whenFn) ~= 'function'
                    if not hasErrors then
                        for j = 0, #action.commands do
                            if not hasErrors then
                                if type(action.commands[j]) == 'string' then

                                    -- Promote the command to an object, with its value and execution function
                                    action.commands[j] = {
                                        command = action.commands[j],
                                        _commandFn = loadstring(string.format('return %s', action.commands[j]))
                                    }

                                    if type(action.commands[j]._commandFn) ~= 'function' then
                                        hasErrors = true
                                    end
                                end
                            end
                        end
                    end

                    if not hasErrors then
                        shouldAdd = true
                    end
                end
            end

            if shouldAdd then
                _temp[#_temp + 1] = action
            end
        end

        actionStateManager.actions[actionType] = _temp
    else
        actionStateManager.actions[actionType] = {}
    end

    local actionCount = #actionStateManager.actions[actionType]
    if actionCount > 0 then
        writeMessage('Compilation of %s has completed.':format(
            pluralize(actionCount,
                text_action(actionType .. ' action'),
                text_action(actionType .. ' actions'))
        ))
    else
        writeMessage('No %s were compiled.':format(
            text_action(actionType .. ' actions')
        ))
    end
end

--------------------------------------------------------------------------------------
-- Recompiles all action types
local function compileAllActions()
    local settingsCopy = json.parse(json.stringify(settings))

    actionStateManager:reset()

    local actions = settingsCopy.actions

    compileActions('battle',    actions, actions and actions.battle or {})
    compileActions('pull',      actions, actions and actions.pull or {})
    compileActions('idle',      actions, actions and actions.idle or {})
    compileActions('resting',   actions, actions and actions.resting or {})
    compileActions('dead',      actions, actions and actions.dead or {})
    compileActions('mounted',   actions, actions and actions.mounted or {})

    actionStateManager.vars = actions and actions.vars or {}

    actionStateManager.needsRecompile = false
end

--------------------------------------------------------------------------------------
-- Determine which action should be performed next
local function getNextBattleAction(context)
    -- We will never execute actions while snoozing
    if actionStateManager:isActionSnoozing() then
        --return nil
        -- TODO: Nothing for now, let's just log
        if settings.verbosity >= VERBOSITY_TRACE then
            writeTrace('WARNING: actionStateManager:isActionSnoozing() returned true (NO-OP for now)')
        end
    end

    actionStateManager:setActionType(context.actionType)

    -- Do not proceed further if actions are not enabled
    if not globals.actionsEnabled then
        return nil
    end

    local actions = actionStateManager.actions[context.actionType]
    local delayReference = actionStateManager:elapsedTimeInType()
    -- local delayReference = context.mobTime
    -- if context.actionType == 'battle' then
    --     -- For battle actions, we'll trigger based on the delay since entering
    --     -- battle rather than from begining to target the mob.
    --     delayReference = actionStateManager:elapsedTimeInType()
    -- end

    if actions then
        for i, action in ipairs(actions) do
            -- If this action is scoped to a battle -AND- it either has no scope yet or its scope does not
            -- match that of the current battle scope, then it is immediately reschedulable.
            if 
                action.scope == 'battle' and
                (action.lastBattleScope == nil or action.lastBattleScope ~= context.battleScope)
            then
                action.availableAt = 0

                -- If the action uses the scoped_enumerators setting, then its enumerators
                -- will also be cleared when a scope change is detected.
                if action.scoped_enumerators == true then
                    action.enumerators = { }
                end
            end

            if 
                context.time >= action.availableAt and
                delayReference >= action.delay
            then 
                -- When we evaluate a new action, we need to clear the state left behind by any previous actions
                context.spell                   = nil   -- Current spell
                context.spell_recast            = nil   -- Recast (in seconds) of the current spell
                context.ability                 = nil   -- Current ability
                context.ability_recast          = nil   -- Recast (in seconds) of the current ability
                context.ability_face_away       = nil   -- The currently triggered ability face away
                context.spell_face_away         = nil   -- The currently triggered spell face away
                context.ability_face_away_start = nil   -- The currently triggered bracketed ability face away starter
                context.ability_face_away_end   = nil   -- The currently triggered bracketed ability face away closer
                context.item                    = nil   -- Current item info [Item resource is at context.item.item]
                context.ranged                  = nil   -- Current ranged attack equipment and ammo info
                context.effect                  = nil   -- Current buff/effect
                context.member                  = nil   -- The result of a targeting enumerator
                context.mob                     = nil   -- The result of a mob search iterator
                context.point                   = nil   -- The result of a position lookup
                context.result                  = nil   -- The result of the latest arrayiterator operation
                context.player_result           = nil   -- The result of the latest find player operation
                context.find_result             = nil   -- The result of a general find by name operation
                context.nearest_result          = nil   -- The result of a nearest operation
                context.farthest_result         = nil   -- The result of a farthest/furthest operation
                context.furthest_result         = nil   -- The (alternate) result of a farthest/furthest operation
                context.results                 = { }   -- The results of all current array iterator operations
                context.is_new_result           = nil   -- An indicator that the latest array iterator value is new this cycle
                context.enemy_ability           = nil   -- The current mob ability
                context.enemy_spell             = nil   -- The current mob spell
                context.enemy_spell_target      = nil   -- The current mob spell's target
                context.weapon_skill            = nil   -- The weapon skill you're trying to use
                context.skillchain_trigger_time = 0     -- The time at which the latest skillchain occurred
                context.skillchain_age          = math.huge -- The time at which the latest skillchain occurred
                
                -- Reload the enumerator data
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

                -- Store the current action to the context
                context.action = action

                -- Make the context visible to the action function
                setfenv(action._whenFn, context)

                if action._whenFn() then
                    --writeMessage('action scope: %s, context scope: %s':format(action.lastBattleScope or 'n/a', context.battleScope or 'n/a'))

                    -- If this action will get run, we'll need to schedule the next run time. We'll actually
                    -- update this later, after the actions are executed, based on the time they complete.
                    action.availableAt = math.max(os.clock() + action.frequency, action.availableAt)

                    -- Save the scope that was present when this action was triggered.
                    action.lastBattleScope = context.battleScope

                    if settings.verbosity >= VERBOSITY_DEBUG then
                        writeDebug('Condition met %s %s [scope: %s]':format(
                            text_action(context.actionType .. '.' .. i, Colors.debug),
                            text_green(action.when, Colors.debug),
                            text_gray(tostring(action.lastBattleScope), Colors.debug)
                        ))
                    end

                    --print(action.when)

                    return action
                end
            end
        end
    end

    return nil
end

--------------------------------------------------------------------------------------
-- Execute the specified action
local function executeBattleAction(context, action)
    if action then
        -- Force a refresh of the player. This COULD actually lead to inconsistency between
        -- the code and the actions, but let's see how this goes...state changes so fast.
        context.player = windower.ffxi.get_player()
        context.action = action

        for i, command in ipairs(action.commands) do
            -- Make the context visible to the command function, and execute it
            setfenv(command._commandFn, context)
            command._commandFn()
        end

        -- At this point, we'll set the next schedule time based on the later of either its
        -- configured frequency or its own current schedulable time.
        action.availableAt = math.max(os.clock() + action.frequency, action.availableAt)

        -- If the action was flagged as incomplete, we'll allow it to be rescheduled again. In this
        -- case, we'll clear the scope and set it to the earlier of its current schedulable time
        -- or a small amount of time in the future. Don't forget to clear the incomplete flag!
        if action.incomplete then
            writeDebug('Action was flagged as incomplete, allowing rapid reschedule.')

            action.lastBattleScope = nil
            action.availableAt = math.min(os.clock() + 1, action.availableAt)

            action.incomplete = nil
        end
    end

    return action
end

function processNextAction(context)
    -- Don't proceed if automation was disabled
    if not globals.enabled then return end

    local action = getNextBattleAction(context)
    
    -- Don't proceed if automation was disabled    
    if not globals.enabled then return end

    return executeBattleAction(context, action)
end

local function doNextActionCycle(time, player, party)
    local playerStatus = player.status

    local mob = globals.target:mob()
    local mobTime = globals.target:runtime()
    local mobDistance = mob and math.sqrt(mob.distance) or 0
    local battleScope = actionStateManager.actionTransitionCounter --globals.target:scopeId()
    local actionsExecuted = false
    local restingActionsExecuted = false
    local idleActionsExecuted = false
    local battleActionsExecuted = false
    local pullActionsExecuted = false

    -- Status flags
    local hasPullableMob = mob ~= nil
    
    -- We''l start by assuming that we're idle if there's no mob, or the mob isn't engaged.
    -- Note that if mobs are aggroing, we'll always get those back first.
    local isIdle = player.status ~= STATUS_ENGAGED and (mob == nil or mob.status ~= STATUS_ENGAGED)
    
    -- Determine if we're in an idling state (forced idle until a given time unless aggro'd). See the above
    -- initialization of isIdle to see the situations that would force us out of idling.
    local isTimedIdling = isIdle and actionStateManager:isIdleSnoozing()

    -- Resting: Execute any actions, and bail
    local isResting = playerStatus == STATUS_RESTING
    if isResting then
        local context = ActionContext.create('resting', time, mob, mobTime, battleScope, party)
        local action = processNextAction(context)
        return
    end

    local isMounted = playerStatus == 85 or playerStatus == 5
    if isMounted then
        local context = ActionContext.create('mounted', time, mob, mobTime, battleScope, party)
        local action = processNextAction(context)
        return
    end

    -- Death: Execute any actions, and bail
    local isDead = player.vitals.hp <= 0
    if isDead then
        local context = ActionContext.create('dead', time, nil, mobTime, battleScope, party)
        local action = processNextAction(context);
        return
    end

    -- Idle
    ----------------------------------------------------------------------------------------------------
    -- Executed when we are disengaged and no mobs are aggroing us
    if isIdle then        
        local context = ActionContext.create('idle', time, mob, mobTime, battleScope, party)

        -- We'll ensure that we're facing the target mob at this point
        -- if mob and not context.facingEnemy() then
        --     context.faceEnemy()
        -- end

        local action = processNextAction(context);

        actionsExecuted = action ~= nil
        idleActionsExecuted = actionsExecuted

        -- writeDebug('Is timed idle? ' .. (isTimedIdling and 'true' or 'false')
        --     .. ' Actions executed? ' .. (actionsExecuted and 'true' or 'false'))
    end

    -- Battle
    ----------------------------------------------------------------------------------------------------
    -- Executed when:
    --  1. We have a target AND
    --  2. We are engaged AND
    --  3. The mob is engaged
    local isBattle = false
    if not isTimedIdling then
        if not actionsExecuted then
            if playerStatus == STATUS_ENGAGED and hasPullableMob then
                --local mob = windower.ffxi.get_mob_by_target('bt') or windower.ffxi.get_mob_by_target('bt')

                -- Determine if the target mob is engaged
                local isMobEngaged = 
                    mob and 
                    mob.status == STATUS_ENGAGED and
                    (mob.claim_id > 0 and (hasBuff(player, BUFF_ELVORSEAL) or hasBuff(player, BUFF_BATTLEFIELD) or isPartyId(mob.claim_id)))

                -- If the target mob is already engaged, it's not pullable (no need to pull)
                hasPullableMob = not isMobEngaged

                -- TODO: Multi-party mobs switch between idle/pull and battle because of the party claim check. Think about this.

                if isMobEngaged then
                    local context = ActionContext.create('battle', time, mob, mobTime, battleScope, party)
                    local action = processNextAction(context);

                    isBattle = true
                    actionsExecuted = action ~= nil
                    battleActionsExecuted = actionsExecuted
                end
            end
        end

        -- Pull
        ----------------------------------------------------------------------------------------------------
        -- Executed when:
        --  1. We have a target that's not yet engaged AND
        --  2. There are no idle actions remaining to run.
        --  3. We're not in a forced/timed idle state.
        if not actionsExecuted and not isTimedIdling then
            if hasPullableMob and not isBattle then
                local command = ''
                local commandDelay = 0
                local hasCommand = false

                -- Lock on if necessary
                if player.target_index ~= mob.index then
                    command = command .. makeSelfCommand(string.format('target -index %d; wait 0.5', mob.index))
                    hasCommand = true
                end

                -- Engage if necessary
                if mobDistance < 22 and player.status ~= STATUS_ENGAGED then
                    command = command .. string.format('input /attack <t>; ')
                    hasCommand = true
                end

                if hasCommand then
                    sendActionCommand(command, nil, 0.25)
                end

                -- Give some time for us to establish and engage with a new target before jumping straight to the pull
                if mobTime > 1 then
                    local context = ActionContext.create('pull', time, mob, mobTime, battleScope, party)

                    -- We'll ensure that we're facing the target mob at this point
                    -- if not context.facingEnemy() then
                    --     context.faceEnemy()
                    -- end

                    local action = processNextAction(context)

                    actionsExecuted = action ~= nil
                    pullActionsExecuted = actionsExecuted
                end
            end
        end
    end
end

--------------------------------------------------------------------------------------
-- Processes battle actions in the background
function cr_actionProcessor()
    local GARBAGE_COLLECTION_INTERVAL = 30

    local startTime = 0 --os.clock()
    local latestGarbageCollection = os.clock()

    while true do
        local sleepTimeSeconds = 0.5

        if actionStateManager.needsRecompile then
            compileAllActions()
        end

        local now = os.clock()
        local time = now - startTime
        local party = windower.ffxi.get_party()
        local player = windower.ffxi.get_player()

        -- Perform background garbage collection operations. These will only occur when we are
        -- not in combat, to ensure that there's no interference with time-sensitive gambits.
        local garbageCollectionAge = now - latestGarbageCollection
        if 
            garbageCollectionAge > GARBAGE_COLLECTION_INTERVAL and
            (player == nil or player.in_combat)
        then
            actionStateManager:clearOthersSpells(true)
            actionStateManager:purgeStaleMobAbilities()
            actionStateManager:purgeWeaponSkills()
            actionStateManager:purgeSkillchains()
            latestGarbageCollection = os.clock()
        end

        if globals.enabled then
            local me = windower.ffxi.get_mob_by_target('me')

            if 
                player and  -- There are conditions where these could be nil and crash the addon.
                me          -- These conditions include things like zoning or logging out.
            then
                local playerStatus = player.status
                local isMounted = (playerStatus == 85 or playerStatus == 5)     -- 85 is mount, 5 is chocobo
                local isResting = (playerStatus == STATUS_RESTING)              -- Resting
                local isDead = player.vitals.hp <= 0                            -- Dead

                if 1 == 1 then
                    actionStateManager:tick(time)

                    -- As long as we're not dead or resting, we can process targeting info
                    if 
                        not isDead
                    then
                        processTargeting(player, party)
                    end

                    doNextActionCycle(time, player, party)
                else
                    sleepTimeSeconds = 2
                end
            else
                sleepTimeSeconds = 2
            end

            -- If automation was disabled during this iteration, forcibly stop following. Note that
            -- this could inadvertently stop a manual follow, but there's not a good way around
            -- that as we don't really know how it started. This will ensure that we don't keep
            -- trying to run to a mob after being disabled (dangerous for mobs that aggro).
            if not globals.enabled then
                local existingJobId = smartMove:getJobId()
                if existingJobId then
                    smartMove:cancelJob()
                end
            end
        else
            -- We will create a context when disabled. This simply ensures that we have context-based
            -- state changes available and up to date once we re-enable.
            local context = ActionContext.create('idle', 
                time,
                nil,
                0,
                -1,
                party)

            -- Wake from idle if we're disabled
            actionStateManager.idleWakeTime = 0
            sleepTimeSeconds = 2
        end
        
        coroutine.sleep(sleepTimeSeconds)
    end
end