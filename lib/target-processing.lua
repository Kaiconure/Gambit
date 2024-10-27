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
        
        if not couldEngage and isZoneApplicable then
            if 
                item.index == mob.index and
                item.zone == zoneId
            then
                return item
            end

            -- Check for a name match, and a zone match if configured
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

    lockTarget(player, mob)
    resetCurrentMob(mob)
end

local function shouldAquireNewTarget(player)
    -- Make sure we don't fixate on a mob we can't actually engage
    local currentTarget = globals.target
    local currentMob = currentTarget:mob()
    if currentMob then
        -- We start checking to see if we're properly engaged after a configurable amount of time 
        -- has elapsed. If not configured, a dynamic value based on mob distance is used.
        local properlyEngaged = currentTarget:runtime() < settings.maxChaseTime
        if not properlyEngaged then
            local party = windower.ffxi.get_party()
            local selfEngaged = player.status == STATUS_ENGAGED
            local hasTrusts = false
            local partyEngaged = false
            local trustsEngaged = false
            local mobClaimedByParty = false

            if party then
                for key, member in pairs(party) do
                    if member and type(member) == 'table' and type(member.mob) == 'table' and member.mob.in_party then
                        if currentMob.status == STATUS_ENGAGED and currentMob.claim_id == member.mob.id then
                            -- Flag for if the mob is engaged with anyone in the party
                            mobClaimedByParty = true
                        end

                        -- Flag for if anyone in the party is engaged
                        if member.mob.status == STATUS_ENGAGED then partyEngaged = true end

                        if member.mob.spawn_type == SPAWN_TYPE_TRUST and member.mob.in_party then
                            -- Flag for if anyone in the party is a Trust
                            hasTrusts = true

                            if member.mob.status == STATUS_ENGAGED then
                                -- Flag for if any of our trusts are engaged
                                trustsEngaged = true
                            end
                        end
                    end
                end
            end

            if mobClaimedByParty then
                -- Is this dangerous? Just because the mob is claimed, does that mean we can reach it? 
                -- TODO: Experiment
                properlyEngaged = true
            else
                -- Otherwise, we'll be properly engaged when:
                --  1. We're within 10 units of the mob
                --  2. We are engaged
                --  3. The mob has some HP missing
                properlyEngaged = 
                    (currentMob.distance < (10 * 10) and player.status == STATUS_ENGAGED and currentMob.hpp < 100)
            end
        end

        -- If we're still properly engaged with the mob we have, then we have no further work to do for now
        if properlyEngaged then
            return false
        end

        writeMessage('Cannot engage current target, will find another...')
        windower.ffxi.follow(-1)
        windower.send_command('input /attack off')
        resetCurrentMob(nil)
    else
        -- If we don't have a target, we won't try to find a new one until the retarget delay has elapsed
        local timeWithTarget = currentTarget:runtime()
        
        -- Before we retrn, we'll detect if we're engaged with an unregistered target, e.g. we're fighting
        -- something that was not assigned via automation. It could be that the addon was loaded/reloaded
        -- while engaged, or the player manually engaged a mob.
        if player.status == STATUS_ENGAGED then
            local t = windower.ffxi.get_mob_by_target('t') or windower.ffxi.get_mob_by_target('bt')
            if t and t.valid_target and t.hpp > 0 and t.spawn_type == SPAWN_TYPE_MOB then
                writeVerbose('You are engaged with an unregistered target. Syncing up now.')
                
                resetCurrentMob(t)                
                return false
            else
                -- If we are engaged and have no valid t or bt, then we're ready to start looking for our
                -- next target. This could be mob status latency, or an actual in-game auto-target that we
                -- aren't properly facing.
                if timeWithTarget >= settings.retargetDelay then
                    writeDebug('Engaged without a valid target, forcing new target search.')
                    return true
                end
            end
        end

        -- Hold retargeting until the optional retarget delay period has elapsed
        if timeWithTarget < settings.retargetDelay then
            return false
        end
    end

    -- If we get to this point, we will not try to acquire a new target unless we're sitting idle
    if player.status ~= STATUS_IDLE then
        return false
    end

    return true
end

--------------------------------------------------------------------------------------
-- Locks the player onto the specified target
function lockTarget(player, mob)
    if player and mob then
        if 
            mob.valid_target and
            mob.hpp > 0
        then
            packets.inject(packets.new('incoming', PACKET_TARGET_LOCK, {
                ['Player'] = player.id,
                ['Target'] = mob.id,
                ['Player Index'] = player.index,
            }))
        end
    end
end


--------------------------------------------------------------------------------------
--
function resetCurrentMob(mob, force)
    -- We're setting the same mob if both old and new are nil, or both old and new share the same mob id
    local isSameMob = 
        (mob == nil and globals.target._mob == nil) or
        (mob ~= nil and globals.target._mob ~= nil and mob.id == globals.target._mob.id)
    local allowReset = force or not isSameMob

    -- Only do an update if the new mob is different from the old, or if we're doing a forced update
    if allowReset then
        local _temp = {
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
            end
        }

        globals.target = _temp
    end
end

--------------------------------------------------------------------------------------
-- 
function processTargeting()
    local player = windower.ffxi.get_player()
    if not shouldAquireNewTarget(player) then
        return
    end

    local party = windower.ffxi.get_party()
    local mobs = windower.ffxi.get_mob_array()
    local meMob = windower.ffxi.get_mob_by_target('me')

    local maxDistanceSquared = settings.maxDistance * settings.maxDistance
    local bestMatchingMob = nil
    local nearestAggroingMob = nil

    for id, candidateMob in pairs(mobs) do
        local isValidCandidate = candidateMob.distance <= maxDistanceSquared
            and candidateMob.valid_target 
            and candidateMob.spawn_type == 16
            and not candidateMob.charmed
            and candidateMob.hpp > 0
            and math.abs(meMob.z - candidateMob.z) <= settings.maxDistanceZ
            and (candidateMob.status == 1 or settings.strategy == TargetStrategy.aggressor)

        local shouldIgnore = false
        if isValidCandidate then
            local ignoreListItem = findIgnoreListMatch(candidateMob)

            if ignoreListItem then
                shouldIgnore = true

                if
                    settings.strategy == TargetStrategy.nearest or
                    settings.strategy == TargetStrategy.aggressor 
                then
                    local downgrade = ignoreListItem.downgrade == true

                    -- Is this a hack? We fake the distance if a deprioritization factor is present...
                    if downgrade then
                        local originalDistance = candidateMob.distance
                        local distance = math.max(math.sqrt(originalDistance), 1) * math.max(settings.maxDistance, 1)

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
            for i = 0, 5 do
                local partyIndex = 'p' .. i
                local member = party[partyIndex]

                if member ~= nil then
                    -- Don't chase mobs that are claimed by someone else
                    if (candidateMob.claim_id == 0 or candidateMob.claim_id == member.mob.id) then

                        -- We'll store the nearest aggroing mob, and give it priority over others
                        if candidateMob.status == STATUS_ENGAGED then
                            if nearestAggroingMob == nil then
                                nearestAggroingMob = candidateMob
                            elseif candidateMob.distance < nearestAggroingMob.distance then
                                nearestAggroingMob = candidateMob
                            end
                        end

                        if bestMatchingMob == nil then
                            -- If we don't have any point of reference yet, this is the one to start with
                            bestMatchingMob = candidateMob
                        else
                            local isHpEqual = bestMatchingMob.hpp == candidateMob.hpp
                            local isHpStrategy = settings.strategy == TargetStrategy.maxhp or
                                settings.strategy == TargetStrategy.minhp
                            local isNearer = candidateMob.distance < bestMatchingMob.distance

                            local assumeStrategy = settings.strategy
                            if assumeStrategy == TargetStrategy.aggressor then
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
        end
    end

    local mobToTarget = nearestAggroingMob or bestMatchingMob
    if mobToTarget ~= nil then
        setTargetMob(mobToTarget)
    end
end

--------------------------------------------------------------------------------------
-- Handle auto-detection of aggroing mobs
-- NOTE: This was moved to be part of the action processing cycle
-- function cr_targetDetector()
--     local sleepTimeSeconds = 0.5

--     while true do
--         if globals.enabled then

--             local player = windower.ffxi.get_player()
--             local playerStatus = player.status
--             local isEngaged = player.status == STATUS_ENGAGED
--             local isMounted = (playerStatus == 85 or playerStatus == 5)     -- 85 is mount, 5 is chocobo
--             local isResting = (playerStatus == 33)                          -- 33 is taking a knee
--             local isDead = player.vitals.hp <= 0                            -- Dead

--             if
--                 not isMounted and
--                 not isResting and 
--                 not isDead 
--             then
--                 processTargeting()
--             end
--         end

--         coroutine.sleep(sleepTimeSeconds)
--     end
-- end