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

    lockTarget(player, mob)
    resetCurrentMob(mob)
end

local function shouldAquireNewTarget(player)
    local checkEngagement = true

    -- Make sure we don't fixate on a mob we can't actually engage
    local currentTarget = globals.target
    local currentMob = currentTarget:mob()
    if currentMob then
        checkEngagement = false

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
    end

    if checkEngagement then
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

    -- If we get to this point, we will only allow target acquisition if we're idle or resting
    if 
        player.status == STATUS_IDLE or
        player.status == STATUS_RESTING
    then
        return true
    end

    return false
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
function processTargeting()
    local player = windower.ffxi.get_player()
    if not shouldAquireNewTarget(player) then
        return
    end

    local strategy = settings.strategy
    local party = windower.ffxi.get_party()
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
            leaderMob.status == STATUS_ENGAGED
        then
            local target = windower.ffxi.get_mob_by_index(leaderMob.target_index)
            if 
                target and
                target.valid_target and
                target.status == STATUS_ENGAGED and
                target.spawn_type == SPAWN_TYPE_MOB
            then
                -- If the party leader is engaged with the target -AND- the target is engaged, then this is
                -- the mob we're looking for. Move along, move along.
                setTargetMob(target)
            end
        end

        return
    end

    local maxDistanceSquared = settings.maxDistance * settings.maxDistance
    local bestMatchingMob = nil
    local nearestAggroingMob = nil

    -- Build a map of party members by their id so we can easily identify if we are the mob claim owner
    local party_by_id = { }
    if party.p0 and party.p0.mob then party_by_id[party.p0.mob.id] = party.p0 end
    if party.p1 and party.p1.mob then party_by_id[party.p1.mob.id] = party.p1 end
    if party.p2 and party.p2.mob then party_by_id[party.p2.mob.id] = party.p2 end
    if party.p3 and party.p3.mob then party_by_id[party.p3.mob.id] = party.p3 end
    if party.p4 and party.p4.mob then party_by_id[party.p4.mob.id] = party.p4 end
    if party.p5 and party.p5.mob then party_by_id[party.p5.mob.id] = party.p5 end
    
    for id, candidateMob in pairs(mobs) do
        local isValidCandidate = 
            candidateMob.distance <= maxDistanceSquared
            and candidateMob.valid_target 
            and candidateMob.spawn_type == 16
            and not candidateMob.charmed
            and candidateMob.hpp > 0
            and math.abs(meMob.z - candidateMob.z) <= settings.maxDistanceZ
            and (candidateMob.status == 1 or strategy == TargetStrategy.aggressor)

        local shouldIgnore = false
        if isValidCandidate then
            local ignoreListItem = findIgnoreListMatch(candidateMob)

            if ignoreListItem then
                shouldIgnore = true

                if
                    -- strategy == TargetStrategy.nearest or
                    -- strategy == TargetStrategy.aggressor 
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
            if (candidateMob.claim_id == 0 or party_by_id[candidateMob.claim_id]) then

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
                    local isHpEqual = (bestMatchingMob.hpp == candidateMob.hpp)
                    local isHpStrategy = (strategy == TargetStrategy.maxhp) or (settings.strategy == TargetStrategy.minhp)
                    local isNearer = candidateMob.distance < bestMatchingMob.distance

                    local assumeStrategy = strategy
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

    -- At this point, we'll take the nearest aggroing mob or the best match we found via strategy
    local mobToTarget = nearestAggroingMob or bestMatchingMob
    if mobToTarget ~= nil then
        setTargetMob(mobToTarget)
    end
end