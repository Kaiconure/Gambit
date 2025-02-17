MAX_SKILLCHAIN_TIME     = 7.5   -- The maximum amount of time we'll allow ourselves to respond to a skillchain event
MAX_WEAPON_SKILL_TIME   = 7.5   -- The maximum amount of time we'll allow ourselves to respond to a weapon skill event
MAX_MOB_ABILITY_TIME    = 5     -- The maximum amount of time we'll allow ourselves to respond to a mob ability event
RANGED_ATTACK_DELAY     = 15    -- The maximum amount of time we'll allow ourselves to finish a ranged attack

SKILLCHAIN_DELAY        = 5     -- The minimum amount of time to wait after one weapon skill before we try to skillchain with another


local state_manager = {
    needsRecompile = true,

    currentTime = 0,
    cycles = 0,
    
    idleWakeTime = 0,
    actionWakeTime = 0,

    actionType = nil,
    actionTransitionCounter = 0,
    actions = { },
    actionTypeStartTime = os.clock(),

    skillchain = {
        time = 0
    },

    currentSpell = {
        time = 0,
        castTime = 0,
        spell = nil
    },

    meritPointInfo = { current = 0, max = 30, limits = 0 },
    capacityPointInfo = { capacityPoints = 0, jobPoints = 0 },

    othersSpells = { },

    timedAbilities = { },

    memberBuffs = {        
    },

    mobBuffs = {
    },

    rolls = {
    },
    latestRoll = {
    },

    context = nil
}

-----------------------------------------------------------------------------------------
--
state_manager.isIdleSnoozing = function (self)
    return self.currentTime < self.idleWakeTime
end

-----------------------------------------------------------------------------------------
--
state_manager.extendActionWakeTime = function(self, duration)
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
end

-----------------------------------------------------------------------------------------
--
state_manager.isActionSnoozing = function(self)
    return self.currentTime < self.actionWakeTime
end

-----------------------------------------------------------------------------------------
-- Set the most recently created context
state_manager.setContext = function(self, context)
    self.context = context
end
-----------------------------------------------------------------------------------------
-- Set the most recently created context
state_manager.getContext = function(self)
    return self.context
end

-----------------------------------------------------------------------------------------
-- Set/get merit/limit point info
state_manager.setMeritPointInfo = function(self, current, max, limits)
    self.meritPointInfo = {
        current = current,
        max = max > 0 and max or 30,
        limits = limits
    }
end
state_manager.getMeritPointInfo = function(self)
    return self.meritPointInfo
end

-----------------------------------------------------------------------------------------
-- Set/get capacity/job point info
state_manager.setCapacityPointInfo = function(self, capacityPoints, jobPoints)
    self.capacityPointInfo = {
        capacityPoints = capacityPoints,
        jobPoints = jobPoints
    }
end
state_manager.getCapacityPointInfo = function(self)
    return self.capacityPointInfo
end

-----------------------------------------------------------------------------------------
-- Sets the action type being executed, used to track how long we're in a type
state_manager.setActionType = function (self, newType)
    
    -- If we're running actions, it's time to wake up from action snooze
    self.actionWakeTime = 0

    -- If we're running non-idle actions,it's time to wake up from idling
    if newType ~= 'idle' then
        self.idleWakeTime = 0
    end
    
    if self.actionType ~= newType and newType ~= nil then
        local isInit = self.actionType == nil
        local isResting = self.actionType == 'resting'
        local isDead = self.actionType == 'dead'
        local isIdlePull = (self.actionType == 'idle' or self.actionType == 'pull')
        local isBattle = (self.actionType == 'battle')

        --local isIdlePullTarget = (newType == 'idle' or newType == 'pull' or self.actionType == 'resting')
        local isNewTypeResting = newType == 'resting'
        local isNewTypeDead = newType == 'dead'
        local isNewTypeIdlePull = newType == 'idle' or newType == 'pull'
        local isNewTypeBattle = newType == 'battle'

        local mode = (isInit and 'init')
            or (isResting and 'resting')
            or (isDead and 'dead')
            or (isIdlePull and 'idle/pull')
            or (isBattle and 'battle')

        local newMode = (isNewTypeResting and 'resting')
            or (isNewTypeDead and 'dead')
            or (isNewTypeIdlePull and 'idle/pull')
            or (isNewTypeBattle and 'battle')

        -- Only reset time if we're transitioning between idle/pull and battle
        --if mode ~= newMode then
        if mode ~= newMode then
            writeVerbose(string.format(
                'Transitioning from %s to %s after %s',
                text_red(mode, Colors.verbose),
                text_red(newMode, Colors.verbose),
                pluralize(string.format('%.1f', self:elapsedTimeInType()), 'second', 'seconds', Colors.verbose)
            ))

            -- Sync up the latest mob state on mode change
            self:validateBuffsForMobs()

            self.actionTypeStartTime = os.clock()
            self.cycles = 0
            
            -- Reset some mob state tracking on state change
            self.skillchain = { time = 0 }
            self.mobAbilities = { }

            self.actionTransitionCounter = self.actionTransitionCounter + 1
        end

        self.actionType = newType
    end
end

-----------------------------------------------------------------------------------------
-- Return how long we've been in the current action type
state_manager.elapsedTimeInType = function (self)
    return os.clock() - (self.actionTypeStartTime or 0)
end

-----------------------------------------------------------------------------------------
-- How many cycles have been processed in the current action type
state_manager.cyclesInType = function(self)
    return self.cycles
end

-----------------------------------------------------------------------------------------
-- Resets tracking of time in the current action state
state_manager.resetActionTime = function(self)
    self.actionTypeStartTime = os.clock()
    self.cycles = 0
end

-----------------------------------------------------------------------------------------
-- Marks the start of a new cycle
state_manager.tick = function(self, currentTime)
    self.currentTime = currentTime
    self.cycles = self.cycles + 1
end

-----------------------------------------------------------------------------------------
-- Roll counts
state_manager.setRollCount = function(self, rollId, count)
    rollId = tonumber(rollId) or 0
    if rollId <= 0 then return 0 end

    count = tonumber(count) or 0
    if 
        self.rolls[rollId] == nil and
        count <= 0
    then
        return 0 
    end

    if count <= 0 then 
        self.rolls[rollId] = nil
        return 0
    end

    local ability = resources.job_abilities[rollId]
    if
        ability == nil or
        ability.type ~= 'CorsairRoll'
    then
        return 0
    end

    if self.rolls[rollId] == nil then
        self.rolls[rollId] = {
            id = rollId,
            name = ability.name,
            status = ability.status,
            count = count,
            time = os.clock()
        }
    else
        self.rolls[rollId].count = count
    end

    self.latestRoll = self.rolls[rollId]
    return self.latestRoll.count
end

state_manager.getRollCount = function(self, rollId)
    rollId = tonumber(rollId) or 0
    if rollId <= 0 then return 0 end
    
    if self.rolls[rollId] then
        local roll = self.rolls[rollId]
        if roll then
            if hasBuff(nil, roll.status, true) then
                return self.rolls[rollId].count
            end
        end

        self.rolls[rollId] = nil
    end

    return 0
end
state_manager.getRolls = function(self, fullInfo)
    local results = {}
    for id, value in pairs(self.rolls) do
        if self:getRollCount(id) > 0 then
            if fullInfo then
                results[id] = value
            else
                results[id] = value.count
            end
        end
    end
    return results
end
state_manager.applySnakeEye = function(self)
    -- NOTE: Discovered that Snake Eye makes the next roll a 1, it
    -- does not actually increase the roll number by 1!!

    local latest = self:getLatestRoll()
    if latest then
        writeMessage('Applying %s to %s (%s)':format(
            text_ability('Snake Eye'),
            text_buff(latest.name),
            text_number(tostring(latest.count))
        ))
        --self:setRollCount(latest.id, latest.count + 1)
    end
end

state_manager.getLatestRoll = function(self)
    local latest = self.latestRoll
    if latest then
        if self:getRollCount(latest.id) > 0 then
            return latest
        end
    end
end

-----------------------------------------------------------------------------------------
--
state_manager.setSkillchain = function(self, name)
    self.skillchain = {
        name = name,
        time = os.clock()
    }
end

-----------------------------------------------------------------------------------------
--
state_manager.getSkillchain = function(self)
    if self.skillchain.time > 0 and (os.clock() - self.skillchain.time) > MAX_SKILLCHAIN_TIME then
        self:setSkillchain(nil)
    end

    return self.skillchain
end

-----------------------------------------------------------------------------------------
--
state_manager.setPartyWeaponSkill = function(self, actor, skill, mob)
    if actor and skill and mob then
        local skillchains = {}

        -- if skill.skillchain_a and skill.skillchain_a ~= '' then skillchains[#skillchains + 1] = skill.skillchain_a end
        -- if skill.skillchain_b and skill.skillchain_b ~= '' then skillchains[#skillchains + 1] = skill.skillchain_b end
        -- if skill.skillchain_c and skill.skillchain_c ~= '' then skillchains[#skillchains + 1] = skill.skillchain_c end

        self.weaponSkill = {
            time = os.clock(),
            skill = skill,
            name = skill.name,
            actor = actor,
            mob = mob,
            skillchains = skillchains
        }
    else
        self.weaponSkill = { time = 0 }
    end
end

-----------------------------------------------------------------------------------------
--
state_manager.getPartyWeaponSkillInfo = function(self)
    -- Keep alive for at most 6 seconds
    if self.weaponSkill.time > 0 and (os.clock() - self.weaponSkill.time) > MAX_WEAPON_SKILL_TIME then
        self:setPartyWeaponSkill()
    end

    return self.weaponSkill
end

-----------------------------------------------------------------------------------------
--
state_manager.setMobAbility = function(self, mob, ability, targets)
    if not self.mobAbilities then self.mobAbilities = { } end

    self.mobAbilities[mob.id] = {
        time = os.clock(),
        mob = mob,
        ability = ability,
        target = targets and targets[1],
        targets = targets
    }
end

-----------------------------------------------------------------------------------------
--
state_manager.clearMobAbility = function(self, mob, finalize)
    if self.mobAbilities and self.mobAbilities[mob.id] then
        if finalize then
            self.mobAbilities[mob.id] = nil
        else
            self.mobAbilities[mob.id].cleared = true
        end
    end
end

-----------------------------------------------------------------------------------------
--
state_manager.getMobAbilityInfo = function(self, mob, windowed)
    if self.mobAbilities then
        local info = self.mobAbilities[mob.id]
        if info then
            -- If the maximum time has ellapsed, then we'll clear the ability
            if os.clock() - info.time > MAX_MOB_ABILITY_TIME then
                self.mobAbilities[mob.id] = nil
                info = nil
            end

            -- If we have a tracked ability and we're either windowed or haven't been cleared yet,
            -- we can return the info we have at this point.
            if info and (windowed or not info.cleared) then
                return info
            end
        end
    end
end

-----------------------------------------------------------------------------------------
--
state_manager.markRangedAttackStart = function(self)
    self.rangedAttack = {
        time = os.clock()
    }

    return self.rangedAttack
end

-----------------------------------------------------------------------------------------
--
state_manager.markRangedAttackCompleted = function(self, success)
    self.rangedAttack = {
        time = 0,
        success = success
    }
end

-----------------------------------------------------------------------------------------
--
state_manager.getRangedAttack = function(self) 
    ra = self.rangedAttack
    if ra then
        if ra.time == 0 then
            ra = nil
        elseif os.clock() - ra.time > RANGED_ATTACK_DELAY then
            self:markRangedAttackCompleted()
            ra = nil
        end
    end

    return ra
end

-----------------------------------------------------------------------------------------
--
state_manager.getRangedAttackSuccessful = function(self) 
    ra = self.rangedAttack
    return ra and ra.success
end

-----------------------------------------------------------------------------------------
--
state_manager.setSpellStart = function(self, spell)
    self.currentSpell = {
        time = os.clock(),
        spell = spell,
        interrupted = false
    }
    return self.currentSpell.time
end

-----------------------------------------------------------------------------------------
--
state_manager.setSpellCompleted = function(self, interrupted)
    self.currentSpell = {
        time = os.clock(),
        spell = nil,
        interrupted = interrupted
    }
end

state_manager.setOthersSpellStart = function(self, spell, actor, target)
    if spell and actor then
        local now = os.clock()
        self.othersSpells[actor.id] = {
            actorId = actor.id,
            time = now,
            expires = now + (spell.cast_time * 2) + 10,
            spell = spell,
            interrupted = false,
            targetId = target and target.id
        }
    end
end

state_manager.setOthersSpellCompleted = function(self, mob, interrupted)
    if type(mob) == 'table' and type(mob.id) == 'number' then
        self.othersSpells[mob.id] = nil
    end
end

state_manager.getOthersSpellInfo = function(self, mob)
    if type(mob) == 'table' and type(mob.id) == 'number' then
        local info = self.othersSpells[mob.id]
        if 
            info and
            info.expires > os.clock() 
        then
            return info
        end
    end
end

state_manager.clearOthersSpells = function(self, expiredOnly)
    if expiredOnly then
        local now = os.clock()
        for actorId, info in pairs(self.othersSpells) do
            if
                info and
                info.expires < now
            then
                self.othersSpells[actorId] = nil
            end
        end
    else
        self.othersSpells = { }
    end
end

state_manager.markTimedAbility = function(self, ability, target)
    self.timedAbilities[ability.id] = {
        ability = ability,
        time = os.clock(),
        target = target
    }
end

state_manager.getTimedAbilityInfo = function(self, abilityId)
    return self.timedAbilities[abilityId]
end

-----------------------------------------------------------------------------------------
-- 
state_manager.setMemberBuffs = function(self, buffs)
    -- The following is a data sample. The key is the mob id of the member.
    -- {
    --   "689675": { "249": true, "255": true, "253": true, "40": true },
    --   "688767": { "255": true }
    -- }

    self.memberBuffs = buffs or { }
end

-----------------------------------------------------------------------------------------
-- 
state_manager.getMemberBuffs = function(self)
    return self.memberBuffs or { }
end

-----------------------------------------------------------------------------------------
-- 

state_manager.getMemberBuffsFor = function (self, member)
    -- Use ourself if no mob is specified
    if member == nil then member = windower.ffxi.get_mob_by_target('me') end

    return self:getMemberBuffs()[member.id] or { }
end

-- Validate the buff state for the given trust
state_manager.validateBuffsForMob = function (self, id)
    local value = self.mobBuffs[id]
    if value then
        local mob = windower.ffxi.get_mob_by_id(value.id)
        if 
            mob == nil or
            not mob.valid_target or
            mob.hpp == 0 or
            (mob.spawn_type ~= SPAWN_TYPE_TRUST and mob.spawn_type ~= SPAWN_TYPE_MOB) or            
            mob.index ~= value.index or
            mob.name ~= value.name
        then
            self.mobBuffs[id] = nil
            return false
        else

            local obj = self.mobBuffs[id]
            local now = os.clock()

            for i, buffId in ipairs(obj.buffs) do
                local byMe = obj.byMe[buffId]
                if not byMe then
                    local expiration = obj.expirations and obj.expirations[buffId]
                    if expiration == nil or expiration <= now then
                        obj.byMe[buffId] = nil
                        
                        if obj.actors then obj.actors[buffId] = nil end
                        if obj.expirations then obj.expirations[buffId] = nil end

                        local index = arrayIndexOf(obj.buffs, buffId)
                        if index then
                            table.remove(obj.buffs, index)
                        end
                    end
                end
            end


            -- If there are no buffs being tracked for this mob, then we're done
            if self.mobBuffs[id].buffs == nil or #self.mobBuffs[id].buffs == 0 then
                self:removeBuffsForMob(id)
                return false
            end

            -- Otherwise, we're valid!
            return true
        end
    end
end

-- Validate the entire trust buff state
state_manager.validateBuffsForMobs = function(self)
    local remove = { }
    for id, value in pairs(self.mobBuffs) do
        self:validateBuffsForMob(id)
    end
end

-- Remove all tracked buffs for this mob
state_manager.removeBuffsForMob = function(self, id)
    if self.mobBuffs and self.mobBuffs[id] then
        self.mobBuffs[id] = nil
    end
end

-- Set the buff state of a trust
state_manager.setMobBuff = function(self, mob, buffId, activate, timer, byMe, actor)
    self:validateBuffsForMob(mob.id)

    if not self.mobBuffs[mob.id] then
        -- If this is a deactivation while there are no statuses, we can just bail
        if not activate then
            return
        end

        self.mobBuffs[mob.id] = {
            id = mob.id,
            index = mob.index,
            name = mob.name,
            buffs = { },
            byMe = { },
            actors = { },
            expirations = { }
        }
    end

    local obj = self.mobBuffs[mob.id]
    local location = arrayIndexOf(obj.buffs, buffId)
    if location then
        if not activate then
            -- When found and deactivating, remove it
            table.remove(obj.buffs, location)

            -- Remove supplemental data
            if obj.byMe then obj.byMe[buffId] = nil end
            if obj.actors then obj.actors[buffId] = nil end
            if obj.expirations then obj.expirations[buffId] = nil end

            return
        end
    end

    -- If we got to this point and aren't activating a buff, then it's not valid
    if not activate then
        return
    end

    -- If we don't have a location, create a new one
    if not location then
        location = #obj.buffs + 1
    end
       
    if not obj.byMe then
        obj.byMe = {}
    end

    if not obj.actors then
        obj.actors = {}
    end

    obj.byMe[buffId] = byMe
    obj.actors[buffId] = actor
    obj.buffs[location] = buffId
    
    -- If there's a timer, apply it
    if timer then
        if not obj.expirations then
            obj.expirations = { }
        end
        obj.expirations[buffId] = os.clock() + timer                
    end
end

-- Get the active buffs for the specified trust
state_manager.getBuffsForMob = function(self, id)
    self:validateBuffsForMob(id)

    if self.mobBuffs[id] then
        return self.mobBuffs[id].buffs
    end

    return { }
end

state_manager.clearMobBuff = function(self, mob, buff, strict)
    local buffs = mob and
        self.mobBuffs and 
        self.mobBuffs[mob.id] and
        self.mobBuffs[mob.id].buffs

    if buffs and #buffs > 0 then
        local foundBuff = hasBuffInArray(buffs, buff, strict)
        if foundBuff then
            self:setMobBuff(mob, foundBuff.id, false)
        end
    end
end

-- Get the buffs for all trusts, indexed by mob id
state_manager.getBuffsForMobs = function(self)
    self:validateBuffsForMobs()

    local result = {}
    for id, value in pairs(self.mobBuffs) do
        result[id] = self.mobBuffs[id].buffs
    end

    return result
end

state_manager.getBuffedMobs = function(self)
    local result = {}
    if self.mobBuffs then
        local next = 1
        for i, id in pairs(self.mobBuffs) do
            result[next] = i
            next = next + 1
        end
    end

    return result
end

state_manager.getBuffInfoForMob = function(self, id)
    self:validateBuffsForMob(id)

    local result = {
        mob = nil,
        buffs = {},
        details = {}
    }

    local root = self.mobBuffs and self.mobBuffs[id]
    local now = os.clock()
    if root then
        local buffs = root.buffs
        if buffs then
            local expirations = root.expirations or { }
            local actors = root.actors or { }

            result.buffs = buffs

            for i, buffId in ipairs(buffs) do
                local expiration = tonumber(expirations[buffId])
                local actor = actors[buffId]
                local byMe = root.byMe and root.byMe[buffId]

                if expiration or actor or byMe then
                    result.details[buffId] = {
                        buffId = buffId,
                        expiry = expiration,
                        timer = (expiration and expiration - now) or nil,
                        actor = actor,
                        byMe = byMe
                    }
                end
            end

            result.mob = windower.ffxi.get_mob_by_id(id)
        end
    end

    return result
end

--
-- Just get the direct mob buffs array for the given mob, without any extra
-- validation. Always returns an array, empty if no data is tracked.
state_manager.getRawBuffsForMob = function(self, id)
    return self.mobBuffs and self.mobBuffs[id] and self.mobBuffs[id].buffs or {}
end

-----------------------------------------------------------------------------------------
--
state_manager.reset = function (self)
    self.currentTime = 0
    self.cycles = 0
    self.idleWakeTime = 0
    self.actionWakeTime = 0
    self.actionType = nil
    self.skillchain = { time = 0 }
    self.mobAbilities = {}
    self.weaponSkill = { time = 0 }
    self.currentSpell = { time = 0 }
    self.othersSpells = { }
    self.timedAbilities = { }
    self.rangedAttack = { time = 0 }
    self.actionTypeStartTime = os.clock()
    self.actions = { }
    self.vars = { }
    self.meritPointInfo = { current = 0, max = 30, limits = 0 }
    self.capacityPointInfo = { capacityPoints = 0, jobPoints = 0 }
    -- self.memberBuffs = { }   -- Don't remove these; maintain state across reloads (of settings, NOT addon) since they are independent of that
    -- self.mobBuffs = { }    -- Don't remove these; maintain state across reloads (of settings, NOT addon) since they are independent of that
end

return state_manager