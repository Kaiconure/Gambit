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

function setSkillchain(name)
    actionStateManager:setSkillchain(name)
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

    local movementJob = pauseFollow and smartMove:cancelJob()
    if command and command ~= '' then
        writeTrace(string.format('Sending %s', colorize(Colors.magenta, command, Colors.trace)))
        windower.send_command(command)
    end

    if commandDuration > 0 then
        coroutine.sleep(commandDuration)

        -- Kick the movement job back on, if any
        if movementJob then
            smartMove:reschedule(movementJob)
        end
    end
end

function sendRangedAttackCommand(target, context)
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

    -- Sleep a bit more to space things out
    coroutine.sleep(0.5)

    if followJob then
        smartMove:reschedule(followJob)
    end

    local endTime = os.clock()

    writeDebug('Ranged attack observer has completed after %s!':format(
        pluralize('%.1f':format(endTime - startTime), 'second', 'seconds')
    ))
end

--------------------------------------------------------------------------------------
-- Executes a spell casting action command.This is similar to sendActionCommand, but
-- it will take into account traits such as Fast Cast as well as spell interruption
-- to ensure that the operation completes as early as possible.
function sendSpellCastingCommand(spell, target, context)
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
    local interrupted = false
    local isFirstCycle = true

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
    -- it's actually fully done casting. We'll reduce the pading time if casting was interrupted, or
    -- if casting completed after the first cycle (first cycle completion means it either never went off,
    -- or it was an extremely short casting time so it needs less padding).
    local paddingTime = 1.75
    if isFirstCycle or interrupted then
        paddingTime = 1.75
    end
    coroutine.sleep(paddingTime)

    if followJob then
        smartMove:reschedule(followJob)
    end

    local wokeAt = os.clock()

    local castingTime = castingEndedAt - castingStartedAt
    local totalTime = wokeAt - castingStartedAt

    -- In debug mode, let's log that we've finished our work here
    writeDebug('%s: Cast time %s / Observer time %s':format(
        text_spell(spell.name, Colors.debug),
        pluralize('%.1f':format(castingTime), 'second', 'seconds', Colors.debug),
        pluralize('%.1f':format(totalTime), 'second', 'seconds', Colors.debug)
        
    ))
end

--------------------------------------------------------------------------------------
-- Recompiles the specified action type
local function compileActions(actionType, rawActions)
    --writeMessage(string.format('Recompiling [%s] actions...', actionType))

    if isArray(rawActions) then
        local actions = json.parse(json.stringify(rawActions)) -- force deep copy
        local _temp = {}
        for i, action in ipairs(actions) do
            local shouldAdd = false

            -- If no when was provided, we'll always evaluate to true but will force a frequency of at least 1 second
            if action.when == nil or action.when == '' then 
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
                    
                    -- Force frequency to a non-negative number
                    action.frequency = math.max(tonumber(action.frequency or 0), 0)
                    action.availableAt = 0
                    action.delay = tonumber(action.delay or 0)
                    action.enumerators = { }

                    -- Force a non-zero minimum delay for certain action type states. Delay is how long
                    -- we must be in a given state before actions can be executed.
                    if actionType == 'battle' then
                        -- Battle actions will always wait at least 2 seconds before firing. This ensures
                        -- we have a chance to take a swing at the enemy first (get trusts engaged, etc).
                        action.delay = math.max(action.delay, 2)
                    elseif actionType == 'pull' then
                        -- Pull actions will always wait at least 1 second before firing. This ensures 
                        -- that idle actions have a chance to run first.
                        action.delay = math.max(action.delay, 1)
                    end
                    
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

    compileActions('battle',    actions and actions.battle or {})
    compileActions('pull',      actions and actions.pull or {})
    compileActions('idle',      actions and actions.idle or {})
    compileActions('resting',   actions and actions.resting or {})
    compileActions('dead',      actions and actions.dead or {})

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
        writeTrace('WARNING: actionStateManager:isActionSnoozing() returned true (NO-OP for now)')
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

            if 
                context.time >= action.availableAt and
                delayReference >= action.delay
            then 
                -- When we evaluate a new action, we need to clear the state left behind by any previous actions
                context.spell                   = nil   -- Current spell
                context.ability                 = nil   -- Current ability
                context.item                    = nil   -- Current item info [Item resource is at context.item.item]
                context.effect                  = nil   -- Current buff/effect
                context.result                  = nil   -- The result of a targeting enumerator
                context.enemy_ability           = nil   -- The current mob ability
                context.weapon_skill            = nil   -- The weapon skill you're trying to use
                context.skillchain_trigger_time = 0     -- The time at which the latest skillchain occurred

                -- Store the current action to the context
                context.action = action

                -- Make the context visible to the action function
                setfenv(action._whenFn, context)

                if action._whenFn() then
                    -- If this action will get run, we'll need to schedule the next run time. We'll actually
                    -- update this later, after the actions are executed, based on the time they complete.
                    action.availableAt = math.max(context.time + action.frequency, action.availableAt)

                    writeDebug('Condition met %s %s':format(
                        text_action(context.actionType .. '.' .. i, Colors.debug),
                        --action.when
                        text_green(action.when, Colors.debug)
                    ))

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

        -- We'll actually bump the next schedulable time based on when this action ended,
        -- rater than when it started...does this make sense?
        action.availableAt = math.max(context.time + action.frequency, action.availableAt)
    end

    return action
end

function processNextAction(context)
    local action = getNextBattleAction(context)
    
    -- TODO: Anything to do here wrt logging, state management, etc?
    
    return executeBattleAction(context, action)
end

local function doNextActionCycle(time, player)
    local playerStatus = player.status

    local mob = globals.target:mob()
    local mobTime = globals.target:runtime()
    local mobDistance = mob and math.sqrt(mob.distance) or 0
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
        local context = ActionContext.create('resting', time, nil, 0)
        local action = processNextAction(context);
        return
    end

    -- Death: Execute any actions, and bail
    local isDead = player.vitals.hp <= 0
    if isDead then
        local context = ActionContext.create('dead', time, nil, 0)
        local action = processNextAction(context);
        return
    end

    -- Idle
    ----------------------------------------------------------------------------------------------------
    -- Executed when we are disengaged and no mobs are aggroing us
    if isIdle then        
        local context = ActionContext.create('idle', time, mob, mobTime)

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
    if not isTimedIdling then
        if not actionsExecuted then
            if playerStatus == STATUS_ENGAGED and hasPullableMob then
                --local mob = windower.ffxi.get_mob_by_target('bt') or windower.ffxi.get_mob_by_target('bt')

                -- Determine if the target mob is engaged
                local isMobEngaged = mob and (mob.claim_id > 0 and mob.status == STATUS_ENGAGED)

                -- If the target mob is already engaged, it's not pullable (no need to pull)
                hasPullableMob = not isMobEngaged

                if isMobEngaged then
                    local context = ActionContext.create('battle', time, mob, mobTime)

                    -- if player.target_locked then
                    --     sendActionCommand('input /lockon', context, 1)
                    -- end

                    local action = processNextAction(context);

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
        if not actionsExecuted then
            if hasPullableMob then
                local command = ''
                local commandDelay = 0

                -- Lock on if necessary
                if player.target_index ~= mob.index then
                    command = command .. makeSelfCommand(string.format('target -index %d; wait 0.5', mob.index))
                    commandDelay = commandDelay + 0.5
                end

                -- Engage if necessary
                if mobDistance < 22 and player.status ~= STATUS_ENGAGED then
                    command = command .. string.format('input /attack <t>; ')
                    commandDelay = commandDelay + 1
                end

                if commandDelay > 0 then
                    sendActionCommand(command, nil, commandDelay)
                end

                -- Give some time for us to establish and engage with a new target before jumping straight to the pull
                if mobTime > 1 then
                    local context = ActionContext.create('pull', time, mob, mobTime)

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
    local startTime = os.clock()

    while true do
        local sleepTimeSeconds = 0.5

        if actionStateManager.needsRecompile then
            compileAllActions()
        end

        if globals.enabled then
            local time = os.clock() - startTime
            local player = windower.ffxi.get_player()

            local playerStatus = player.status
            local isMounted = (playerStatus == 85 or playerStatus == 5)     -- 85 is mount, 5 is chocobo
            local isResting = (playerStatus == STATUS_RESTING)              -- Resting
            local isDead = player.vitals.hp <= 0                            -- Dead

            if
                not isMounted
            then
                actionStateManager:tick(time)

                -- As long as we're not dead or resting, we can process targeting info
                if 
                    not isResting and
                    not isDead
                then
                    processTargeting()
                end

                doNextActionCycle(time, player)
            else
                sleepTimeSeconds = 2
            end
        else
            sleepTimeSeconds = 2
        end
        
        coroutine.sleep(sleepTimeSeconds)
    end
end