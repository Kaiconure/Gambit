MAX_SKILLCHAIN_TIME     = 5     -- The maximum amount of time we'll allow ourselves to respond to a skillchain event
MAX_WEAPON_SKILL_TIME   = 6     -- The maximum amount of time we'll allow ourselves to respond to a weapon skill event
RANGED_ATTACK_DELAY     = 15    -- The maximum amount of time we'll allow ourselves to finish a ranged attack

WEAPON_SKILL_DELAY      = 2     -- The minimum amount of time to wait after one weapon skill before we try to skillchain with another


local state_manager = {
    needsRecompile = true,

    currentTime = 0,
    cycles = 0,
    
    idleWakeTime = 0,
    actionWakeTime = 0,

    actionType = nil,
    actions = { },
    actionTypeStartTime = os.clock(),

    skillchain = {
        time = 0
    },

    currentSpell = {
        time = 0,
        castTime = 0,
        spell = nil
    }
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
        if mode ~= newMode then
            writeDebug(string.format(
                'Transitioning from %s to %s after %s',
                text_red(mode, Colors.debug),
                text_red(newMode, Colors.debug),
                pluralize(string.format('%.1f', self:elapsedTimeInType()), 'second', 'seconds', Colors.debug)
            ))

            self.actionTypeStartTime = os.clock()
            self.cycles = 0
            
            -- Reset some mob state tracking on state change
            self.skillchain = { time = 0 }
            self.mobAbilities = { }
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
-- Marks the start of a new cycle
state_manager.tick = function(self, currentTime)
    self.currentTime = currentTime
    self.cycles = self.cycles + 1
end

-----------------------------------------------------------------------------------------
--
state_manager.setSkillchain = function(self, name)
    self.skillchain = {
        name = name,
        time = self.currentTime
    }
end

-----------------------------------------------------------------------------------------
--
state_manager.getSkillchain = function(self)
    if self.skillchain.time > 0 and (self.currentTime - self.skillchain.time) > MAX_SKILLCHAIN_TIME then
        self:setSkillchain(nil)
    end

    return self.skillchain
end

-----------------------------------------------------------------------------------------
--
state_manager.setPartyWeaponSkill = function(self, actor, skill, mob)
    if actor and skill and mob then
        local skillchains = {}

        if skill.skillchain_a and skill.skillchain_a ~= '' then skillchains[#skillchains + 1] = skill.skillchain_a end
        if skill.skillchain_b and skill.skillchain_b ~= '' then skillchains[#skillchains + 1] = skill.skillchain_b end
        if skill.skillchain_c and skill.skillchain_c ~= '' then skillchains[#skillchains + 1] = skill.skillchain_c end

        self.weaponSkill = {
            time = self.currentTime,
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
    if self.weaponSkill.time > 0 and (self.currentTime - self.weaponSkill.time) > MAX_WEAPON_SKILL_TIME then
        self:setPartyWeaponSkill()
    end

    return self.weaponSkill
end

-----------------------------------------------------------------------------------------
--
state_manager.setMobAbility = function(self, mob, ability, targets)
    self.mobAbilities[mob.id] = {
        time = self.currentTime,
        mob = mob,
        ability = ability,
        target = targets and targets[1],
        targets = targets
    }
end

-----------------------------------------------------------------------------------------
--
state_manager.clearMobAbility = function(self, mob)
    self.mobAbilities[mob.id] = nil
end

-----------------------------------------------------------------------------------------
--
state_manager.getMobAbilityInfo = function(self, mob)
    local info = self.mobAbilities[mob.id]
    if info then
        -- We'll set a maximum time that we'll allow a mob ability to remaing active
        if self.currentTime - info.time > 10 then
            self.mobAbilities[mob.id] = nil
            info = nil
        end            
    end

    return info
end

-----------------------------------------------------------------------------------------
--
state_manager.markRangedAttackStart = function(self)
    self.rangedAttack = {
        time = self.currentTime
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
        elseif self.currentTime - ra.time > RANGED_ATTACK_DELAY then
            self:markRangedAttackCompleted()
            ra = nil
        end
    end

    return ra
end

-----------------------------------------------------------------------------------------
--
state_manager.setSpellStart = function(self, spell)
    self.currentSpell = {
        time = self.currentTime,
        spell = spell,
        interrupted = false
    }
    return self.currentTime
end

-----------------------------------------------------------------------------------------
--
state_manager.setSpellCompleted = function(self, interrupted)
    self.currentSpell = {
        time = self.currentTime,
        spell = nil,
        interrupted = interrupted
    }
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
    self.rangedAttack = { time = 0}
    self.actionTypeStartTime = os.clock()
    self.actions = { }
    self.vars = { }
end

return state_manager