MAX_SKILLCHAIN_TIME = 5

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

_actionProcessorState = {
    needsRecompile = true,

    currentTime = 0,
    cycles = 0,

    skillchain = {
        time = 0
    },
    
    idleWakeTime = 0,
    isIdleSnoozing = function (self)
        return self.currentTime < self.idleWakeTime
    end,

    actionWakeTime = 0,
    extendActionWakeTime = function(self, duration)
        duration = math.max(duration or 0, 0)
        if self.actionWakeTime < self.currentTime then
            -- If we're not already snoozing, the wake time is now + duration
            self.actionWakeTime = self.currentTime + duration
        else
            -- If we are already snoozing, the wake time is the current wake time + duration
            self.actionWakeTime = self.actionWakeTime + duration
        end
        
        -- NOTE: This sleep is how we've prevented commands from stepping on each other. It's been wrapped
        -- in this "extend" method so we have the option to change how this works later.
        coroutine.sleep(duration)
    end,
    isActionSnoozing = function(self)
        return self.currentTime < self.actionWakeTime
    end,
    
    actionType = nil,
    actionTypeStartTime = os.clock(),

    -- Sets the action type being executed, used to track how long we're in a type
    setActionType = function (self, newType)
        
        -- If we're running actions, it's time to wake up from action snooze
        self.actionWakeTime = 0

        -- If we're running non-idle actions,it's time to wake up from idling
        if newType ~= 'idle' then
            self.idleWakeTime = 0
        end
        
        if self.actionType ~= newType and newType ~= nil then
            local isIdlePull = (self.actionType == 'idle' or self.actionType == 'pull')
            local isIdlePullTarget = (newType == 'idle' or newType == 'pull')

            -- Only reset time if we're transitioning between idle/pull and battle
            if isIdlePull ~= isIdlePullTarget then
                writeDebug(string.format(
                    'Transitioning from %s to %s after %s',
                    text_red(self.actionType ~= nil and (isIdlePull and 'idle/pull' or self.actionType) or 'init', Colors.debug),
                    text_red(isIdlePullTarget and 'idle/pull' or newType, Colors.debug),
                    pluralize(string.format('%.1f', self:elapsedTimeInType()), 'second', 'seconds', Colors.debug)
                ))

                self.actionTypeStartTime = os.clock()
                self.cycles = 0
            end

            self.actionType = newType
        end
    end,
    -- Return how long we've been in the current action type
    elapsedTimeInType = function (self)
        return os.clock() - (self.actionTypeStartTime or 0)
    end,

    -- How many cycles have been processed in the current action type
    cyclesInType = function(self)
        return self.cycles
    end,

    -- Marks the start of a new cycle
    tick = function(self, currentTime)
        self.currentTime = currentTime
        self.cycles = self.cycles + 1
    end,

    setSkillchain = function(self, name)
        self.skillchain = {
            name = name,
            time = self.currentTime
        }
    end,

    getSkillchain = function(self)
        if (self.currentTime - self.skillchain.time) > MAX_SKILLCHAIN_TIME then
            self:setSkillchain(nil)
        end

        return self.skillchain
    end,

    currentSpell = {
        time = 0,
        castTime = 0,
        spell = nil
    },

    setSpellStart = function(self, spell)
        self.currentSpell = {
            time = self.currentTime,
            spell = spell,
            interrupted = false
        }
        return self.currentTime
    end,

    setSpellCompleted = function(self, interrupted)
        self.currentSpell = {
            time = self.currentTime,
            spell = nil,
            interrupted = interrupted
        }
    end,

    reset = function (self)
        self.currentTime = 0
        self.cycles = 0
        self.idleWakeTime = 0
        self.actionWakeTime = 0
        self.actionType = nil
        self.skillchain = { time = 0 }
        self.currentSpell = { time = 0 }
        self.actionTypeStartTime = os.clock()
        self.actions = { }
        self.vars = { }
    end,

    actions = { }
}

CommandDurationTypes = 
{
    Sleep = 0,
    Immediate = 1,
    Scheduled = 2
}

function recompileActions()
    _actionProcessorState.needsRecompile = true
end

function setSkillchain(name)
    _actionProcessorState:setSkillchain(name)
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

    if pauseFollow then
        local player = context and context.player or windower.ffxi.get_player() -- TODO: Maybe just load the live player here, instead of refreshing in the action executor proc?
        local followIndex = tonumber(player.follow_index) or 0

        local followCommand = makeSelfCommand('follow')

        if followIndex > 0 then
            followCommand = followCommand ..
                string.format(' wait %.1f; ', commandDuration) ..
                makeSelfCommand(string.format('follow -index %d -no-overwrite', followIndex))
        end

        sendActionCommand(followCommand, context, 0.5)
    end

    if command and command ~= '' then
        writeTrace(string.format('Sending %s', colorize(Colors.magenta, command, Colors.trace)))
        windower.send_command(command)
    end

    if commandDuration > 0 then
        if durationType == CommandDurationTypes.Immediate then
            -- Nothing to do, execute and immediately return
        elseif durationType == CommandDurationTypes.Scheduled then
            --_actionProcessorState:extendActionWakeTime(commandDuration)
            coroutine.sleep(commandDuration)
        else
            coroutine.sleep(commandDuration)
        end
    end
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

    local player = windower.ffxi.get_player()
    local followIndex = tonumber(player.follow_index) or 0

    if followIndex then
        sendActionCommand(makeSelfCommand('follow'), context, 0.5)
    end

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
        local currentSpell = _actionProcessorState.currentSpell

        if
            os.clock() >= endTime or
            currentSpell.spell ~= spell
        then
            continue = false
            interrupted = currentSpell.interrupted
        else
            isFirstCycle = false
            coroutine.sleep(0.5)
        end
    end

    local castingEndedAt = os.clock()

    if followIndex > 0 then
        sendActionCommand(makeSelfCommand('follow -index %d -no-overwrite':format(followIndex)), context)
    end

    -- We need to pad the casting time a bit, because spell casting fires its completion event before
    -- it's actually fully done casting. We'll reduce the pading time if casting was interrupted, or
    -- if casting completed after the first cycle (first cycle completion means it either never went off,
    -- or it was an extremely short casting time so it needs less padding).
    local paddingTime = 1.75
    if isFirstCycle or interrupted then
        paddingTime = 1.75
    end
    coroutine.sleep(paddingTime)

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

                    -- Force a minimum delay for each action state. This is the amount of time
                    -- that must elapse within that state before its actions start happening.
                    if actionType == 'battle' then
                        action.delay = math.max(action.delay, 2)
                    elseif actionType == 'pull' then
                        action.delay = math.max(action.delay, 1)
                    elseif actionType == 'idle' then
                        action.delay = math.max(action.delay, 0)
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

        _actionProcessorState.actions[actionType] = _temp
    else
        _actionProcessorState.actions[actionType] = {}
    end

    local actionCount = #_actionProcessorState.actions[actionType]
    if actionCount > 0 then
        writeMessage(string.format('Compilation of %s has completed.', pluralize(actionCount,
            actionType .. ' action',
            actionType .. ' actions')
        ))
    else
        writeMessage(string.format('No valid %s actions were compiled.', actionType))
    end
end

--------------------------------------------------------------------------------------
-- Recompiles all action types
local function compileAllActions()
    local settingsCopy = json.parse(json.stringify(settings))

    _actionProcessorState:reset()

    local actions = settingsCopy.actions

    compileActions('battle',    actions and actions.battle or {})
    compileActions('pull',      actions and actions.pull or {})
    compileActions('idle',      actions and actions.idle or {})

    _actionProcessorState.vars = actions and actions.vars or {}

    _actionProcessorState.needsRecompile = false
end

--------------------------------------------------------------------------------------
-- Determine which action should be performed next
local function getNextBattleAction(context)
    -- We will never execute actions while snoozing
    if _actionProcessorState:isActionSnoozing() then
        --return nil
        -- TODO: Nothing for now, let's just log
        writeTrace('WARNING: _actionProcessorState:isActionSnoozing() returned true (NO-OP for now)')
    end

    _actionProcessorState:setActionType(context.actionType)

    -- Do not proceed further if actions are not enabled
    if not globals.actionsEnabled then
        return nil
    end

    local actions = _actionProcessorState.actions[context.actionType]
    local delayReference = _actionProcessorState:elapsedTimeInType()
    -- local delayReference = context.mobTime
    -- if context.actionType == 'battle' then
    --     -- For battle actions, we'll trigger based on the delay since entering
    --     -- battle rather than from begining to target the mob.
    --     delayReference = _actionProcessorState:elapsedTimeInType()
    -- end

    if actions then
        for i, action in ipairs(actions) do

            if 
                context.time >= action.availableAt and
                delayReference >= action.delay
            then 
                -- When we evaluate a new action, we need to clear the state left behind by any previous actions
                context.spell       = nil   -- Current spell
                context.ability     = nil   -- Current ability
                context.item        = nil   -- Current item info [Item resource is at context.item.item]
                context.result      = nil   -- The result of a targeting enumerator

                -- Store the current action to the context
                context.action = action

                -- Make the context visible to the action function
                setfenv(action._whenFn, context)

                if action._whenFn() then
                    -- If this action will get run, we'll need to schedule the next run time
                    action.availableAt = math.max(context.time + action.frequency, action.availableAt)

                    writeDebug('Condition met %s %s':format(
                        text_action(context.actionType .. '.' .. i, Colors.debug),
                        colorize(Colors.green, action.when, Colors.debug)
                    ))

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
    local isTimedIdling = isIdle and _actionProcessorState:isIdleSnoozing()

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

                -- Follow if necessary
                if player.follow_index == nil or player.follow_index ~= mob.index then
                    -- if mobDistance < 2 then
                    --     -- Cancel follow for a bit if we're very close. Follow has been known to cause an inability to engage.
                    --     -- The faceEnemy call further below will ensure we're pointed in the right direction.
                    --     command = command .. 
                    --         makeSelfCommand('follow; wait 0.5') ..
                    --         makeSelfCommand('face -index %d; wait 0.5':format(mob.index))
                    --     commandDelay = commandDelay + 1

                    --     writeDebug('Temporarily removing follow for alignment on pull.')
                    -- end

                    -- command = command .. makeSelfCommand(string.format('follow -index %d; wait 0.5', mob.index))
                    -- commandDelay = commandDelay + 0.5
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

        if _actionProcessorState.needsRecompile then
            compileAllActions()
        end

        if globals.enabled then
            local time = os.clock() - startTime
            local player = windower.ffxi.get_player()

            local playerStatus = player.status
            local isMounted = (playerStatus == 85 or playerStatus == 5)     -- 85 is mount, 5 is chocobo
            local isResting = (playerStatus == 33)                          -- 33 is taking a knee
            local isDead = player.vitals.hp <= 0                            -- Dead

            if
                not isMounted and
                not isResting and 
                not isDead 
            then
                --_actionProcessorState.currentTime = time
                _actionProcessorState:tick(time)

                processTargeting()
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