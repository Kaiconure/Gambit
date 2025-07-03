--------------------------------------------------------------------------------------
-- These are mobs that should be ignored when you have an elvorseal
local ELVORSEAL_BACKGROUND_MOBS = {
    "Eschan Corse",
    "Eschan Il'Aern",
    "Eschan Sorcerer",
    "Eschan Warrior",
    "Eschan Yovra",
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

    writeMessage('Identified %s as the next best target...':format(
        text_mob(mob.name),
        text_number("%03Xh":format(mob.index))
    ))

    -- Cancel any active movement job now that we have a target
    smartMove:cancelJob()

    lockTarget(player, mob, true)
    resetCurrentMob(mob)
end

local function shouldAquireNewTarget(player, party)
    local checkEngagement = true

    local current_t = windower.ffxi.get_mob_by_target('t') or windower.ffxi.get_mob_by_target('bt')

    -- Make sure we don't fixate on a mob we can't actually engage
    local currentTarget = globals.target
    local currentMob = currentTarget:mob()
    if settings.strategy ~= TargetStrategy.manual then
        if currentMob and current_t and current_t.id == currentMob.id then
            checkEngagement = false

            local runtime = currentTarget:runtime()

            -- Certain environments are set up to allow any number of parties to engage with the same mobs
            local allowMultiPartyMobs = 
                hasBuff(player, BUFF_ELVORSEAL) or
                hasBuff(player, BUFF_BATTLEFIELD)

            -- Don't swap off the current mob if you have an Elvorseal (multi-party mobs)
            local mobClaimed = currentMob.claim_id > 0
            local mobClaimedByParty = partyInfo:canShareClaim(currentMob.claim_id)

            local refDistance = settings.maxDistance + 2
            local maxDistanceSquared = refDistance * refDistance

            local claimStolen = 
                mobClaimed and
                not mobClaimedByParty
            local claimTimedOut = 
                not mobClaimed and
                runtime >= settings.maxChaseTime
            local claimOutOfRange = 
                not mobClaimed and
                currentMob.distance > maxDistanceSquared

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
-- Locks the player onto the specified target
local lock_target_id = 1
function lockTarget(player, mob, battleTarget)
    local id = lock_target_id
    lock_target_id = lock_target_id + 1

    if player and mob then
        if 
            mob.valid_target and
            mob.hpp > 0
        then
            local max_tabs = settings.maxTabs
            local tabs_remaining = 0
            local forced_tabbing = false
            
            if
                mob.spawn_type == SPAWN_TYPE_TRUST or
                mob.spawn_type == SPAWN_TYPE_MOB or
                mob.spawn_type == SPAWN_TYPE_PLAYER
            then
                if settings.debugging then
                    writeMessage('DBG: lockTarget called from ' .. debug.traceback())
                end

                packets.inject(packets.new('incoming', PACKET_TARGET_LOCK, {
                    ['Player'] = player.id,
                    ['Target'] = mob.id,
                    ['Player Index'] = player.index,
                }))

                -- Give it a moment to target
                coroutine.sleep(0.125)
            else
                max_tabs = 10
                tabs_remaining = max_tabs
                forced_tabbing = true
            end

            -- In laggy situations, it can take a while for the target to be acquired. This gives us 
            -- some time to try and ensure we can get the target.
            if 1 == 1 then
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
                        target.id == mob.id and
                        target.index == mob.index
                    then
                        if duration >= 2 then
                            writeVerbose('Target acquisition of %s was %s after %s':format(
                                text_mob(mob.name, Colors.verbose),
                                text_green('successful', Colors.verbose),
                                text_number('%.1fs':format(duration), Colors.verbose)
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
                        
                        return true
                    end                    

                    local now = os.clock()
                    duration = now - start

                    -- If tabs are allowed, we'll occasionally revert to direct tab presses
                    -- when we've been unable to get a lock in a reasonable time.
                    if duration > 1.5 or max_tabs > 0 then
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
                                sleep_duration = 0.25
                                
                                local command = ''

                                -- If we haven't tabbed yet, we'll send a few escapes to close out menus and chat
                                if not has_tabbed then
                                    if not forced_tabbing then
                                        writeVerbose('Falling back to tab-basted targeting...')
                                    end

                                    local targeting_key = mob.spawn_type == SPAWN_TYPE_PLAYER and 'f9' or 'f8'

                                    command = command .. 
                                        'setkey numpad5 down; wait 0.2; setkey numpad5 up; wait 0.3;' ..
                                        'setkey escape down;  wait 0.1; setkey escape up;  wait 0.1;' ..
                                        'setkey escape down;  wait 0.1; setkey escape up;  wait 0.1;' ..
                                        'setkey escape down;  wait 0.1; setkey escape up;  wait 0.1;' ..
                                        'setkey escape down;  wait 0.1; setkey escape up;  wait 0.1;' ..
                                        'setkey escape down;  wait 0.1; setkey escape up;  wait 0.2;' ..
                                        'setkey %s down; wait 0.1; setkey %s up; wait 0.2;':format(targeting_key, targeting_key)
                                        
                                    sleep_duration = sleep_duration + 2.2
                                    has_tabbed = true
                                else
                                    -- Construct and send the tab press command
                                    command = command .. 'setkey tab down; wait 0.1; setkey tab up;'
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

                    if duration < settings.targetingDuration then
                        coroutine.sleep(sleep_duration)
                    else
                        looping = false
                    end
                end

                writeVerbose('Target acquisition of %s has %s after %s':format(
                    text_mob(mob.name, Colors.verbose),
                    text_red('failed', Colors.verbose),
                    text_number('%.1fs':format(duration), Colors.verbose)
                ))

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
        
        -- Cancel any pending follow jobs
        smartMove:cancelJob()

        targetScope = targetScope + 1

        local _temp = {
            _scopeId = targetScope,
            _mob = mob,
            _start = os.clock(),            

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
                        resetCurrentMob(nil, true)
                        return nil
                    end
                end
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
            setTargetMob(mob)

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
    if strategy == TargetStrategy.leader and party.party1_leader then
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
                -- If the party leader is engaged with the target -AND- the target is engaged, then this is
                -- the mob we're looking for. Move along, move along.
                --setTargetMob(target)

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
                    setTargetMob(t)
                end
            end
        end

        return
    end

    local maxDistanceSquared = settings.maxDistance * settings.maxDistance
    local bestMatchingMob = nil
    local nearestAggroingMob = nil

    local can_initiate = strategy == TargetStrategy.aggressor or strategy == TargetStrategy.puller
    
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
                        candidateMob.distance < nearestAggroingMob.distance
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
                    if (assumeStrategy == TargetStrategy.nearest and isNearer) or
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
        setTargetMob(mobToTarget)
    end
end