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
                coroutine.sleep(0.25)

                -- Unlock from the target if necessary
                player = windower.ffxi.get_player()
                if player and player.target_locked then
                    printDebug('Unlocking from lost target %s/%d':format(currentMob.name, currentMob.id))
                    
                    windower.send_command('input /lockon')
                    coroutine.sleep(0.25)
                end

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

local function sendKeys(...)
    for i, key in ipairs({...}) do
        windower.send_command('setkey %s down; wait 0.1; setkey %s up; wait 0.1;':format(key, key))
        coroutine.sleep(0.25)
    end
end
local sendKey = sendKeys

local function closeUx(max_seconds)
    local info = windower.ffxi.get_info()

    if not info.logged_in then
        return
    end

    max_seconds = tonumber(max_seconds) or 5

    local start_t = os.clock()
    
    -- Back out of the menu
    while info.menu_open do
        local age = os.clock() - start_t
        if age >= max_seconds then
            return
        end

        sendKeys('escape')
        info = windower.ffxi.get_info()
    end

    -- Back out of the chat box
    while info.chat_open do
        local age = os.clock() - start_t
        if age >= max_seconds then
            return
        end
        
        sendKeys('escape')
        info = windower.ffxi.get_info()
    end

    return os.clock() - start_t
end

--------------------------------------------------------------------------------------
-- Locks the player onto the specified target
local lock_target_id = 1
function lockTarget(player, mob, battleTarget, skip_packet_targeting)
    local id = lock_target_id
    lock_target_id = lock_target_id + 1

    -- We will store the id of the most recent mob we tried to lock onto
    globals.last_lock_target_id = mob and type(mob.id) == 'number' and mob.id

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
            if battleTarget then
                windower.send_ipc_message('set_bt -from %s -id %s -index %s -zone %s':format(
                    tostring(globals.me_id) or 'n/a',
                    tostring(mob.id) or 'n/a',
                    tostring(mob.index) or 'n/a',
                    tostring(globals.currentZone and globals.currentZone.id) or 'n/a'
                ))
            end

            local mob_name = mob.name
            local mob_id = mob.id

            local start_t = os.clock()
            local fail_fast = false

            -- We'll first try and see if the mob is already targeted. This will often be the case during battle, as any member
            -- who is in the leader strategy will use a /assist command to set the cursor before calling lockTarget.
            local t = windower.ffxi.get_mob_by_target('t')
            if t and t.id == mob.id then
                if t.valid_target then
                    printDebug('%s/%d already targeted, exiting after %.2fs.':format(mob.name, mob.id, os.clock() - start_t))
                    return true, nil
                else
                    printDebug('%s/%d is invalid, exiting after %.2fs.':format(mob.name, mob.id, os.clock() - start_t))
                    return false, nil
                end
            end

            -- For players, we can shortcut targeting by simply using their name
            if
                isMobPlayer(mob)
            then
                windower.send_command('input /target %s;':format(mob.name))
                coroutine.sleep(0.5)

                t = windower.ffxi.get_mob_by_target('t')
                return t and t.id == mob.id and t.valid_target, nil
            end

            -- For trusts, we'll shortcut targeting by going directly after their party member symbol
            if
                mob.spawn_type == SPAWN_TYPE_TRUST
            then
                local target_symbol = partyInfo:memberSymbolById(mob.id)
                if target_symbol then
                    windower.send_command('input /target %s;':format(target_symbol))
                    coroutine.sleep(0.5)

                    t = windower.ffxi.get_mob_by_target('t')
                    return t and t.id == mob.id and t.valid_target, nil
                end
            end
            
            if
                mob.spawn_type == SPAWN_TYPE_TRUST or
                mob.spawn_type == SPAWN_TYPE_MOB
            then
                skip_packet_targeting = skip_packet_targeting or settings.skipPacketTargeting

                if not skip_packet_targeting then
                    local num_attempted = 0

                    local max_attempts = 1

                    -- We'll try a few times to establish our target directly
                    for i = 1, max_attempts do
                        num_attempted = num_attempted + 1

                        packets.inject(packets.new('incoming', PACKET_TARGET_LOCK, {
                            ['Player'] = player.id,
                            ['Target'] = mob.id,
                            ['Player Index'] = player.index,
                        }))

                        coroutine.sleep(0.5)

                        t = windower.ffxi.get_mob_by_target('t')
                        if 
                            t and
                            t.id == mob.id
                        then
                            if not t.valid_target then
                                -- The fail fast flag ensures that later code doesn't try to target the mob again
                                fail_fast = true
                                break
                            end

                            printDebug('Packet targeting of %s/%d was successful after %.2fs (%d/%d)':format(
                                t.name,
                                t.id,
                                os.clock() - start_t,
                                num_attempted,
                                max_attempts
                            ))

                            return true, nil
                        end
                    end

                    printDebug('Packet targeting %s/%d failed after %.2fs and %d attempt(s)':format(
                        mob.name,
                        mob.id,
                        os.clock() - start_t,
                        num_attempted
                    ))
                else
                    --printDebug('Packet targeting has been disabled. Re-enable with: gbt config -spt off')
                end
            end

            -- In laggy situations, it can take a while for the target to be acquired. This gives us 
            -- some time to try and ensure we can get the target.
            if not fail_fast then
                local looping = true

                local has_st    = false
                local has_fps   = false
                local is_trust = mob.spawn_type == SPAWN_TYPE_TRUST

                local num_tabs = 0

                -- Toggle whether we will ignore trusts in targeting or not
                --windower.send_command('input /ignorefaith %s':format(is_trust and 'off' or 'on'))
                --coroutine.sleep(0.15)

                if closeUx() then
                    while 
                        looping and 
                        (globals.enabled or not battleTarget)   -- This ensures that we stop trying to find a battle target if the addon is disabled.
                    do
                        local mob = windower.ffxi.get_mob_by_id(mob.id)
                        if mob and mob.valid_target then

                            -- Face toward our target. It's important that we do this before sending the FPS view
                            -- mode command, because even if we're out of sync (already in FPS) this will ensure
                            -- that our camera is always facing the mob.
                            directionality.faceTarget(mob)

                            -- Enter fps view. This ensures that the camera is facing toward the mob we want, so
                            -- that our tabbing stays in the general vicinity of our desired target.
                            if not has_fps then
                                sendKey('numpad5')
                                coroutine.sleep(0.33)
                                -- coroutine.sleep(0.25)
                                -- sendKey('numpad5')
                                -- coroutine.sleep(0.25)
                                has_fps = true
                            end

                            --coroutine.sleep(0.2)

                            -- Start selecting NPC's.
                            if not has_st then
                                --sendKey('f8')  
                                --coroutine.sleep(0.25)

                                windower.send_command('input /ta <stnpc>;')
                                coroutine.sleep(0.33)

                                has_st = true
                            end

                            local st = windower.ffxi.get_mob_by_target('st')
                            if st then
                                if st.id == mob.id then
                                    -- When our st matches our target, commit it using the enter key. We'll then clear
                                    -- the has_st flag, and indicate that we should exit the loop.
                                    sendKey('enter')
                                    has_st = false
                                    looping = false

                                    printDebug('Command-based target of %s/%d was successful after %.2fs with %d tab(s)':format(
                                        st.name,
                                        st.id,
                                        os.clock() - start_t,
                                        num_tabs
                                    ))
                                else
                                    sendKey('tab')

                                    num_tabs = num_tabs + 1

                                    coroutine.sleep(0.15)
                                end
                            else
                                -- If we have no st, clear the flag and we can try again
                                has_st = false
                                coroutine.sleep(0.15)
                            end
                        else
                            looping = false
                        end

                        -- Detect our external end conditions
                        if looping then
                            if
                                os.clock() - start_t >= settings.targetingDuration 
                            then
                                looping = false
                            end
                        end
                    end
                end

                -- Really make sure we're out of the target selection cursor
                for i = 1, 5 do
                    local st = windower.ffxi.get_mob_by_target('st')
                    if st then
                        --printDebug('Post-exiting of target selection cursor...')
                        sendKey(st.valid_target and st.id == mob.id and 'enter' or 'escape')
                        coroutine.sleep(0.1)
                    else
                        break
                    end
                end

                -- Exit from fps camera view
                if has_fps then
                    --printDebug('Post-exiting of first-person view...')
                    sendKey('numpad5')
                end

                t = windower.ffxi.get_mob_by_target('t')
                if t and t.valid_target and t.id == mob.id then
                    writeVerbose('Target acquisition of %s (%s) was %s after %s%s':format(
                        text_mob(t.name, Colors.verbose),
                        text_number(tostring(t.id), Colors.verbose),
                        text_green('successful', Colors.verbose),
                        text_number('%.2fs':format(os.clock() - start_t), Colors.verbose),
                        overridden and text_yellow(' (overridden)') or ''
                    ))
                    return true, nil
                end

                writeVerbose('Target acquisition of %s/%s has %s after %s':format(
                    text_mob(mob_name, Colors.verbose),
                    text_number(mob_id, Colors.verbose),
                    text_red('failed', Colors.verbose),
                    text_number('%.2fs':format(os.clock() - start_t), Colors.verbose)
                ))
            end
        end
    end

    return false, nil
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
                leaderMob.valid_target and
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
                    local t = windower.ffxi.get_mob_by_target('t')
                    if 
                        t and
                        t.id == target.id and
                        t.index == target.index
                    then
                        -- If we've already got the mob targeted, we're done. Success if it's the right type of mob.
                        if
                            t.spawn_type == SPAWN_TYPE_MOB and
                            t.valid_target
                        then
                            setTargetMob(t)
                        end
                    else
                        -- If we don't have the mob targeted
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