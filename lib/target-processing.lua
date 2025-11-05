--------------------------------------------------------------------------------------
-- These are mobs that should be ignored when you have an elvorseal
local ELVORSEAL_BACKGROUND_MOBS = {
    "Eschan Corse",
    "Eschan Il'Aern",
    "Eschan Sorcerer",
    "Eschan Warrior",
    "Eschan Yovra",
}

local ELVORSEAL_MOBS = {
    "Azi Dahaka",
    "Azi Dahaka's Dragon",
    "Naga Raja",
    "Naga Raja's Lamia",
    "Quetzalcoatl",
    "Quetzalcoatl's Sibilus",
    "Mireu"
}

--------------------------------------------------------------------------------------
-- Determines if a mob should be ignored by the auto-engage algorithm.
-- Note that this assumes the mob passes all other checks, and it just
-- runs it by the ignore list to see if it gets a hit.
local function findIgnoreListMatch(mob)
    local zoneId = globals.currentZone and globals.currentZone.id or -1

    for i = 1, #settings.ignoreList do
        local item = settings.ignoreList[i]

        -- We'll skip the check for this mob entirely if it's aggroing and the ignore list
        -- item lets us attack aggroing mobs -- there's no way this item could apply.
        local couldEngage = (not item.ignoreAlways and mob.status == STATUS_ENGAGED)
        
        -- We can only match if this item applies to the current zone
        local isZoneApplicable = item.zone == nil or item.zone == zoneId
        
        if 
            isZoneApplicable and
            (item.downgrade or not couldEngage)
        then
            -- Check for an index match
            if
                item.index == mob.index
            then
                return item
            end

            -- Check for a name match
            if
                string.lower(item.name or '') == string.lower(mob.name)
            then
                return item
            end 
        end
    end

    return nil
end


local function setTargetMob(mob)
    if mob == nil then
        resetCurrentMob(nil)
        return
    end

    local player = windower.ffxi.get_player()

    -- We won't overwrite the target if we're already fighting something
    if player.status == STATUS_ENGAGED then
        return
    end

    -- Don't message if we're just re-targeting the same mob
    --local currentTarget = globals.target
    --if not currentTarget or not currentTarget.id or currentTarget.id ~= mob.id then
        writeMessage('Identified %s %s as the next best target...':format(
            text_mob(mob.name),
            text_number(tostring(mob.id))
        ))
    --end

    -- Cancel any active movement job now that we have a target. As of v0.96.0-beta11, this cancellation
    -- will only happen if the slowTargetTransitions setting is enabled (off by default).
    if settings and settings.slowTargetTransitions then
        smartMove:cancelJob()
    end

    local result, overridden = lockTarget(player, mob, true)
    if result then
        if overridden then
            printDebug('Was looking for %d, identified %d':format(mob.id, overridden.id))
        end
        
        resetCurrentMob(overridden or mob)
    end

    -- if lockTarget(player, mob, true) then
    --     resetCurrentMob(mob)
    -- end
end

local function shouldAquireNewTarget(player, party)
    local checkEngagement = true

    local current_t = windower.ffxi.get_mob_by_target('t')
    local current_bt = windower.ffxi.get_mob_by_target('bt')

    current_t = (current_t and current_t.spawn_type == SPAWN_TYPE_MOB and current_t) or current_bt

    -- Make sure we don't fixate on a mob we can't actually engage
    local currentTarget = globals.target
    local currentMob = currentTarget:mob()

    -- if 
    --     current_t and 
    --     current_t.status == STATUS_ENGAGED and
    --     player.status == STATUS_ENGAGED and
    --     --(currentMob and currentMob.id == current_t.id) and
    --     partyInfo:canShareClaim(current_t.claim_id)
    -- then
    --     if currentMob == nil or currentMob.id ~= current_t.id then
    --         print('GBT: Early sync unregistered with %d/%s':format(current_t.id, current_t.name))
    --         print(debug.traceback())
    --         writeVerbose('GBT: Early syncing with unregistered engagement target: %s':format(text_mob(current_t.name)))
    --         resetCurrentMob(current_t)
    --     end

    --     return false
    -- end
    
    if settings.strategy ~= TargetStrategy.manual then
        if 
            currentMob and (
                (current_t and current_t.id == currentMob.id) or    -- Our current target is the same as the tracked mob    -OR-
                (not partyInfo:canShareClaim(currentMob.claim_id))  -- The current target is not something we can claim
            )
        then
            checkEngagement = false

            local runtime = currentTarget:runtime()

            -- Don't swap off the current mob if you have an Elvorseal (multi-party mobs)
            local mobClaimed = partyInfo:isClaimedMob(currentMob)
            local partyCanClaim = partyInfo:canShareClaimOnMob(currentMob)

            -- If the mob is claimed and the party can claim it, we'll mark the mob as having been claimed
            if mobClaimed and partyCanClaim then
                currentTarget:markClaim()
            end

            local refDistance = settings.maxDistance + 2
            local maxDistanceSquared = refDistance * refDistance

            local claimStolen = 
                mobClaimed and
                not partyCanClaim
            local claimTimedOut = 
                not mobClaimed and                  -- Not current claimed -AND-
                not currentTarget:hadClaim() and    -- Has not BEEN claimed -AND-
                runtime >= settings.maxChaseTime    -- The max chasedown time has ellapsed
            local claimOutOfRange = 
                not mobClaimed and
                currentMob.distance > maxDistanceSquared


            if not mobClaimed and currentTarget:hadClaim() then
                printDebug('Detected lost claim on %d/%s':format(currentMob.id, currentMob.name))
            end

            -- if not claimStolen and not claimOutOfRange then
            --     if claimTimedOut and current_t.hpp > 99 then
            --         claimTimedOut = false
            --         print('GBT: Bypassing potentially fake timeout call.')
            --     end
            -- end

            if 
                claimStolen or
                claimTimedOut or
                claimOutOfRange
            then
                writeMessage('%s / %s: Stolen=%s, TimedOut=%s (%s), TooFar=%s. Looking for another...':format(
                    text_mob(currentMob.name),
                    text_number(currentMob.id),
                    text_number(claimStolen and 'yes' or 'no'),
                    text_number(claimTimedOut and 'yes' or 'no'),
                    text_number('%.1fs':format(runtime)),
                    text_number(claimOutOfRange and 'yes' or 'no')
                ))

                smartMove:cancelJob()
                windower.send_command('input /attack off')

                resetCurrentMob(nil)
            else
                return false
            end
        end
    end

    if checkEngagement then
        -- If we don't have a target, we won't try to find a new one until the retarget delay has elapsed
        local timeWithTarget = currentTarget:runtime()
        
        -- Before we retrn, we'll detect if we're engaged with an unregistered target, e.g. we're fighting
        -- something that was not assigned via automation. It could be that the addon was loaded/reloaded
        -- while engaged, or the player manually engaged a mob.
        if player.status == STATUS_ENGAGED then
            if 
                current_t and
                current_t.valid_target and
                current_t.hpp > 0 and
                current_t.spawn_type == SPAWN_TYPE_MOB and
                (currentMob == nil or currentMob.id ~= current_t.id) 
            then
                writeVerbose('Syncing with unregistered engagement target: %s':format(text_mob(current_t.name)))                
                resetCurrentMob(current_t)                
                return false
            else
                -- If we are engaged and have no valid t or bt, then we're ready to start looking for our
                -- next target. This could be mob status latency, or an actual in-game auto-target that we
                -- aren't properly facing.
                if timeWithTarget >= settings.retargetDelay then
                    -- Return true here, unless we're manually targeting
                    return settings.strategy ~= TargetStrategy.manual
                end
            end
        end

        -- Hold retargeting until the optional retarget delay period has elapsed
        if timeWithTarget < settings.retargetDelay then
            return false
        end
    end

    -- If we get to this point, we will only allow target acquisition if we're idle or resting
    if 
        player.status == STATUS_IDLE or
        player.status == STATUS_RESTING
    then
        -- Return true here, unless we're manually targeting
        return settings.strategy ~= TargetStrategy.manual
    end

    return false
end

--------------------------------------------------------------------------------------
-- Certain mobs are only targetable when they are actively engaged
local BATTLE_ONLY_MOBS = {
    ['Amphiptere'] = true,
    ['Eschan Yovra'] = true,
    ['Greater Amphiptere'] = true,
    ['Turul'] = true
}

--------------------------------------------------------------------------------------
-- Locks the player onto the specified target
local lock_target_id = 1
function lockTarget(player, mob, battleTarget, noTabs)
    local id = lock_target_id
    lock_target_id = lock_target_id + 1

    -- if battleTarget and player and player.status == STATUS_ENGAGED then
    --     writeMessage('WARN: Attempting to acquire mob %s/%s while already engaged!':format(
    --         text_number(mob and mob.id or -1),
    --         text_mob(mob and mob.name or 'unknown')
    --     ))
    --     printDebug('WARN: Attempting to acquire mob %d/%s while already engaged!':format(
    --         mob and mob.id or -1,
    --         mob and mob.name or 'unknown'
    --     ))
    --     return false, nil
    -- end

    if player and mob then
        if 
            mob.valid_target and
            (not BATTLE_ONLY_MOBS[mob.name] or mob.status == STATUS_ENGAGED) and
            mob.hpp > 0
        then
            local max_tabs = (noTabs and 0) or settings.maxTabs
            local tabs_remaining = 0
            local forced_tabbing = false
            local fail_fast = false

            -- NEW: Mobs require tabs at this point
            if mob.spawn_type == SPAWN_TYPE_MOB then
                max_tabs = math.max(max_tabs, 5)
            end

            -- Bail early for players, since we can target them by name
            if
                isMobPlayer(mob)
            then
                windower.send_command('input /target %s;':format(mob.name))
                coroutine.sleep(0.5)

                local t = windower.ffxi.get_mob_by_target('t')
                return t and t.id == mob.id and t.valid_target, nil
            end
            
            if
                mob.spawn_type == SPAWN_TYPE_TRUST or
                (mob.spawn_type == SPAWN_TYPE_MOB and max_tabs <= 0) or
                isMobPlayer(mob)    -- This should no longer be necessary due to the early bail above
            then
                if settings.debugging then
                    writeMessage('DBG: lockTarget called from ' .. debug.traceback())
                end

                -- We'll try a few times to establish our target directly
                for i = 1, 3 do
                    packets.inject(packets.new('incoming', PACKET_TARGET_LOCK, {
                        ['Player'] = player.id,
                        ['Target'] = mob.id,
                        ['Player Index'] = player.index,
                    }))

                    -- Give it a moment to target
                    coroutine.sleep((0.5 * (i - 1)) + 0.125)

                    local t = windower.ffxi.get_mob_by_target('t')
                    if 
                        t and
                        t.id == mob.id and
                        (not mob.index or t.index == mob.index)
                    then
                        if not t.valid_target then
                            fail_fast = true
                            break
                        end

                        -- writeVerbose('Direct target acquisition of %s was %s!':format(
                        --     text_mob(mob.name, Colors.verbose),
                        --     text_green('successful', Colors.verbose)
                        -- ))

                        return true, nil
                    end
                end
            else
                -- We always need to go back to tabbing if we're going after a target of this spawn type (not a trust, mob, or player)
                max_tabs = 10
                tabs_remaining = max_tabs
                forced_tabbing = true
            end

            -- In laggy situations, it can take a while for the target to be acquired. This gives us 
            -- some time to try and ensure we can get the target.
            if not fail_fast then
                local start = os.clock()
                local duration = 0
                
                local has_tabbed = false
                local last_tab = start
                local looping = true
                local tried_bt = false
                
                while looping and (not battleTarget or globals.enabled) do
                    local sleep_duration = 0.25

                    -- We're done if the target was acquired
                    local target = windower.ffxi.get_mob_by_target('t')
                    if 
                        target and 
                        (
                            (target.id == mob.id and target.index == mob.index) or
                            (
                                mob.spawn_type == SPAWN_TYPE_MOB and mob.valid_target and mob.hpp > 0 and (
                                    (settings.selection_mode == 'any_aggressive' and target.spawn_type == mob.spawn_type and target.status == STATUS_ENGAGED and target.distance <= (settings.maxDistance ^ 2)) or
                                    (settings.selection_mode == 'any' and target.spawn_type == mob.spawn_type and target.distance <= (settings.maxDistance ^ 2))
                                ) and
                                partyInfo:canShareClaim(target.claim_id)
                            )
                        ) 
                    then
                        local overridden = target.id ~= mob.id and target or nil

                        if 
                            --duration >= 2 or
                            duration >= 0 or
                            target.id ~= mob.id
                        then
                            writeVerbose('Target acquisition of %s (%s) was %s after %s%s':format(
                                text_mob(mob.name, Colors.verbose),
                                text_number(tostring(mob.id), Colors.verbose),
                                text_green('successful', Colors.verbose),
                                text_number('%.1fs':format(duration), Colors.verbose),
                                overridden and text_yellow(' (overridden)') or ''
                            ))
                            
                        end

                        -- Pull out of first person view if we tabbed
                        if has_tabbed then
                            windower.send_command('setkey numpad5 down; wait 0.2; setkey numpad5 up; wait 0.3;')
                            coroutine.sleep(0.5)
                        end

                        -- if settings.debugging then
                        --     writeMessage('DBG: lockTarget exiting with %s':format(text_green('success')))
                        -- end
                        
                        return true, overridden
                    end

                    local now = os.clock()
                    duration = now - start

                    -- We will always re-acquire the mob at this point. If it's moved while retrying, we want to
                    -- set ourselves back up for its new position.
                    mob = windower.ffxi.get_mob_by_id(mob.id)
                    if mob and mob.valid_target then
                        -- If tabs are allowed, we'll occasionally revert to direct tab presses
                        -- when we've been unable to get a lock in a reasonable time.
                        if 
                            duration > 1.5 or max_tabs > 0
                        then
                            local bt = battleTarget and windower.ffxi.get_mob_by_target('bt')
                            local just_tried_bt = false
                            if bt and bt.valid_target and bt.hpp > 0 then
                                if tabs_remaining <= 0 and mob.spawn_type == SPAWN_TYPE_MOB then
                                    -- If the current battle target id matches that of our intended target, we will try
                                    -- try exactly once to use that for direct client-side targeting.
                                    if 
                                        bt and
                                        bt.id == mob.id and
                                        bt.has_claim and
                                        bt.status == STATUS_ENGAGED
                                    then
                                        windower.send_command('input /ta <bt>;')
                                        tried_bt = true
                                        just_tried_bt = true
                                        sleep_duration = 0.5
                                    end                            
                                end
                            elseif
                                not just_tried_bt and max_tabs > 0 
                            then
                                directionality.faceTarget(mob)
                                
                                if tabs_remaining > 0 then
                                    tabs_remaining = tabs_remaining - 1
                                    sleep_duration = 0.3
                                    
                                    local command = ''

                                    -- If we haven't tabbed yet, we'll send a few escapes to close out menus and chat
                                    if not has_tabbed then
                                        if not forced_tabbing then
                                            writeVerbose('Falling back to tab-basted targeting...')
                                        end

                                        local targeting_key = isMobPlayer(mob) and 'f9' or 'f8'

                                        -- Enter first-person view
                                        command = command .. 
                                                'setkey numpad5 down; wait 0.1; setkey numpad5 up; wait 0.2;'
                                        sleep_duration = sleep_duration + 0.3

                                        local info = windower.ffxi.get_info()
                                        if info.menu_open then
                                            -- When the menu is open, we need to send several escapes to close it out
                                            command = command ..
                                                'setkey escape down;  wait 0.1; setkey escape up;  wait 0.1;' ..
                                                'setkey escape down;  wait 0.1; setkey escape up;  wait 0.1;' ..
                                                'setkey escape down;  wait 0.1; setkey escape up;  wait 0.1;' ..
                                                'setkey escape down;  wait 0.1; setkey escape up;  wait 0.1;' ..
                                                'setkey escape down;  wait 0.1; setkey escape up;  wait 0.2;'

                                            sleep_duration = sleep_duration + 1.2
                                        elseif info.chat_open then
                                            -- When the chat is open, we need to send a single escape to close it out
                                            command = command ..
                                                'setkey escape down;  wait 0.1; setkey escape up;  wait 0.1;'

                                            sleep_duration = sleep_duration + 0.2
                                        end

                                        command = command .. 
                                            'setkey %s down; wait 0.1; setkey %s up; wait 0.2;':format(targeting_key, targeting_key)

                                        sleep_duration = sleep_duration + 0.3
                                        has_tabbed = true
                                    else
                                        -- Construct and send the tab press command
                                        command = command .. 'setkey tab down; wait 0.1; setkey tab up;'
                                        sleep_duration = sleep_duration + 0.1
                                    end
                                    
                                    windower.send_command(command)                                
                                    
                                    -- Mark the last tab time, and also use it to update the current duration
                                    last_tab = os.clock()
                                    duration = last_tab - start
                                elseif now - last_tab > 1 then
                                    tabs_remaining = max_tabs
                                end
                            end
                        end

                        coroutine.sleep(sleep_duration)
                        if duration >= settings.targetingDuration then
                            looping = false
                        end
                    else
                        looping = false
                    end                    
                end

                if mob then
                    writeVerbose('Target acquisition of %s has %s after %s':format(
                        text_mob(mob.name, Colors.verbose),
                        text_red('failed', Colors.verbose),
                        text_number('%.1fs':format(duration), Colors.verbose)
                    ))
                end

                -- Pull out of first person view if we tabbed
                if has_tabbed then
                    windower.send_command('setkey numpad5 down; wait 0.2; setkey numpad5 up; wait 0.1;')
                    coroutine.sleep(0.5)
                end
            end
        end
    end

    -- if settings.debugging then
    --     writeMessage('DBG: lockTarget exiting with %s':format(text_red('failure')))
    -- end
end


local targetScope = 0
--------------------------------------------------------------------------------------
--
function resetCurrentMob(mob, force)
    --printDebug('Entering resetCurrentMob (%d) with force=%s':format(mob and mob.id or -1, force and 'true' or 'false'))

    -- local info = windower.ffxi.get_info()
    -- if not info or not info.logged_in then
    --     return
    -- end

    --print('resetCurrentMob: %s':format(debug.traceback()))

    -- We're setting the same mob if both old and new are nil, or both old and new share the same mob id
    local isSameMob = globals.target and (
        (mob == nil and globals.target._mob == nil) or
        (mob ~= nil and globals.target._mob ~= nil and mob.id == globals.target._mob.id)
    )
    local allowReset = force or not isSameMob

    -- Only do an update if the new mob is different from the old, or if we're doing a forced update
    if allowReset then

        -- Reset certain battle-specific built-in context variables
        local context = actionStateManager:getContext()
        if context and context.vars then
            context.vars.__suppress_offensive_magic = false
            context.vars.__suppress_weapon_skills = false
        end
        
        -- Cancel any pending follow jobs. As of v0.96.0-beta11, this cancellation will
        -- only happen if the slowTargetTransitions setting is enabled (off by default).
        if settings and settings.slowTargetTransitions then
            smartMove:cancelJob()
        end

        targetScope = targetScope + 1

        local _temp = {
            _scopeId = targetScope,
            _mob = mob,
            _start = os.clock(),
            _claim_mark = false,

            id = mob and mob.id,

            --------------------------------------------------------------------------------------
            -- Gets the mob, as it was originally set when found
            initialMob = function (self)
                return self._mob
            end,

            --------------------------------------------------------------------------------------
            -- Gets the mob in its current state
            mob = function (self)
                local mob = self._mob
                if mob then
                    mob = windower.ffxi.get_mob_by_id(mob.id)
                    if 
                        mob and 
                        mob.valid_target and 
                        mob.spawn_type == SPAWN_TYPE_MOB and 
                        mob.hpp > 0
                    then
                        return mob
                    else
                        -- TODO: Is this dangerous? Resetting the mob on a fetch?
                        --resetCurrentMob(nil, true)
                        return nil
                    end
                end
            end,

            --------------------------------------------------------------------------------------
            -- Marks the mob as having been claimed
            markClaim = function(self)
                self._claim_mark = true
            end,

            --------------------------------------------------------------------------------------
            -- Determine whether the mob had received the claim mark
            hadClaim = function(self)
                return self._claim_mark
            end,

            runtime = function (self)
                return os.clock() - self._start
            end,

            scopeId = function (self)
                return self._scopeId
            end
        }

        globals.target = _temp
    end
end

--------------------------------------------------------------------------------------
-- 
function processTargeting(player, party)
    player = player or windower.ffxi.get_player()
    party = party or windower.ffxi.get_party()

    if actionStateManager.user_target_id then
        local id = actionStateManager.user_target_id
        actionStateManager.user_target_id = nil

        local mob = windower.ffxi.get_mob_by_id(id)
        if
            mob and
            mob.valid_target and
            mob.hpp > 0 and
            mob.spawn_type == SPAWN_TYPE_MOB
        then
            smartMove:cancelJob()
            windower.send_command('input /attack off')
            coroutine.sleep(1)
            setTargetMob(mob)   -- Only on explicit set

            return
        end
    end

    if not shouldAquireNewTarget(player, party) then
        return
    end

    local strategy = settings.strategy
    local mobs = windower.ffxi.get_mob_array()
    local meMob = windower.ffxi.get_mob_by_target('me')

    -- In 'manual' strategy, we won't do any automated target acquisition
    if strategy == TargetStrategy.manual then
        return
    end

    -- If we're using the 'leader' strategy and we are the leader, then we'll fall back to the 
    -- 'nearest' behavior. This ensures we don't sit around getting smacked while there's no
    -- one else to start the battle for us.
    if strategy == TargetStrategy.leader then
        if 
            not meMob or party.party1_leader == meMob.id
        then
            strategy = TargetStrategy.nearest
        end
    end

    -- We will bail early if we're using the leader strategy. Either we take the leader's battle target,
    -- or the leader has no target and we remain idle.
    if strategy == TargetStrategy.leader then
        if party.party1_leader then
            local leaderMob = windower.ffxi.get_mob_by_id(party.party1_leader)
            if 
                leaderMob and
                type(leaderMob.target_index) == 'number' and
                leaderMob.target_index > 0 and
                leaderMob.status == STATUS_ENGAGED and
                player.status == STATUS_IDLE
            then
                local target = windower.ffxi.get_mob_by_index(leaderMob.target_index)
                if 
                    target and
                    target.valid_target and
                    target.status == STATUS_ENGAGED and
                    target.spawn_type == SPAWN_TYPE_MOB and
                    (target.claim_id and target.claim_id > 0) and
                    partyInfo:canShareClaim(target.claim_id)
                then
                    -- Let's just try a /assist command here and let it do its thing
                    windower.send_command('input /assist "%s";':format(leaderMob.name))
                    coroutine.sleep(0.5)

                    local t = windower.ffxi.get_mob_by_target('t')
                    if 
                        t and
                        t.spawn_type == SPAWN_TYPE_MOB and
                        t.valid_target and 
                        t.id == target.id and
                        t.index == target.index
                    then
                        setTargetMob(t) -- Match up with the party leader's target, which we've already acquired
                    end
                end
            end
        end

        return
    end

    local maxDistanceSquared = settings.maxDistance * settings.maxDistance
    local bestMatchingMob = nil
    local nearestAggroingMob = nil

    local can_initiate = strategy == TargetStrategy.aggressor or strategy == TargetStrategy.puller

    local hasElvorseal = hasBuff(player, BUFF_ELVORSEAL)
    
    for id, candidateMob in pairs(mobs) do
        local isValidCandidate = 
            (candidateMob.distance <= maxDistanceSquared) 
            and candidateMob.valid_target 
            and candidateMob.spawn_type == 16
            and candidateMob.is_npc
            and (tonumber(candidateMob.model_scale) or 0) > 0
            and (tonumber(candidateMob.model_size) or 0) > 0
            and not candidateMob.charmed
            and candidateMob.hpp > 0
            and math.abs(meMob.z - candidateMob.z) <= settings.maxDistanceZ
            and (candidateMob.status == STATUS_ENGAGED or can_initiate)
            and (not hasElvorseal or arrayIndexOfStrI(ELVORSEAL_MOBS, candidateMob.name))   -- Don't target background stuff while in DI


        -- This ensures that the 'puller' strategy only tries to get mobs that are at full health,
        -- or are already claimed by a member of our party. This prevents pullers
        -- from fetching mobs that may already have hate for some other person.
        -- NOTE: This is based on AoE pullers in other parties camped nearby.
        if 
            isValidCandidate and
            strategy == TargetStrategy.puller 
        then
            isValidCandidate = 
                candidateMob.hpp == 100 or partyInfo:canShareClaim(candidateMob.claim_id)
        end

        -- Weird bug with tomb worms; mobs can be engaged and not claimed.
        -- if candidateMob.status == STATUS_ENGAGED and candidateMob.name == 'Locus Tomb Worm' and (candidateMob.claim_id or 0) == 0 then
        --     isValidCandidate = false
        -- end

        local shouldIgnore = false
        if isValidCandidate then
            local ignoreListItem = findIgnoreListMatch(candidateMob)

            if ignoreListItem then
                shouldIgnore = true

                if
                    true
                then
                    local downgrade = ignoreListItem.downgrade == true

                    -- Is this a hack? We fake the distance if a deprioritization factor is present...
                    if downgrade then
                        local originalDistance = candidateMob.distance
                        local distance = settings.maxDistance

                        -- Is this hacky? Setting the distance to the new value to make it look further away?
                        candidateMob.distance = distance * distance
                        shouldIgnore = false
                    end
                end
            end
        end

        if 
            isValidCandidate and 
            not shouldIgnore 
        then
            if 
                candidateMob.claim_id == 0 or 
                partyInfo:canShareClaim(candidateMob.claim_id)
            then

                -- We'll store the nearest aggroing mob, and give it priority over others
                if candidateMob.status == STATUS_ENGAGED then
                    if 
                        nearestAggroingMob == nil
                    then
                        nearestAggroingMob = candidateMob
                    elseif 
                        candidateMob.distance < nearestAggroingMob.distance and
                        (
                            (nearestAggroingMob.claim_id or 0) == 0 or      -- Our best match is unclaimed --OR--
                            (candidateMob.claim_id or 0) ~= 0               -- Our current match is claimed
                        )
                    then
                        -- If the mob we're already tracking isn't claimed by the party, update the
                        -- nearest to match the current candidate. This ensures that all members
                        -- theoretically target the same claimed mob (assuming strategies allow).
                        if 
                            not partyInfo:isMember(nearestAggroingMob.claim_id) or partyInfo:isMember(candidateMob.claim_id)
                        then
                            nearestAggroingMob = candidateMob
                        else
                            writeMessage('skipping mob %d':format(candidateMob.id))
                        end
                    end
                end

                if bestMatchingMob == nil then
                    -- If we don't have any point of reference yet, this is the one to start with
                    bestMatchingMob = candidateMob
                else
                    local isHpEqual = (bestMatchingMob.hpp == candidateMob.hpp)
                    local isHpStrategy = (strategy == TargetStrategy.maxhp) or (settings.strategy == TargetStrategy.minhp)
                    local isNearer = candidateMob.distance < bestMatchingMob.distance

                    local assumeStrategy = strategy
                    if can_initiate then
                        assumeStrategy = TargetStrategy.nearest
                    end

                    -- If we've already got a point of reference, compare that with the current 
                    -- to see if it's better than what we've already looked at.
                    if 
                        (assumeStrategy == TargetStrategy.nearest and isNearer) or
                        (assumeStrategy == TargetStrategy.maxhp and candidateMob.hpp > bestMatchingMob.hpp) or
                        (assumeStrategy == TargetStrategy.minhp and candidateMob.hpp < bestMatchingMob.hpp) or
                        (isHpStrategy and isHpEqual and isNearer) -- Pick the nearest mob with the same HP if we're tracking HP
                    then
                        bestMatchingMob = candidateMob
                    end
                end
            end
        end
    end

    -- At this point, we'll take the nearest aggroing mob or the best match we found via strategy
    local mobToTarget = nearestAggroingMob or bestMatchingMob
    if mobToTarget ~= nil then
        setTargetMob(mobToTarget)   -- Set the mob that was selected based on strategy, ignore list, and other settings
    end
end