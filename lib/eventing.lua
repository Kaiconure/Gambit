local skillchain_ids = T{
    288,
    289,
    290,
    291,
    292,
    293,
    294,
    295,
    296,
    297,
    298,
    299,
    300,
    301,
    385,
    386,
    387,
    388,
    389,
    390,
    391,
    392,
    393,
    394,
    395,
    396,
    397,
    767,
    768,
    769,
    770
}

local sc_categories = S{
    'weaponskill_finish',
    'spell_finish',
    'job_ability',
    'mob_tp_finish',
    'avatar_tp_finish',
    'job_ability_unblinkable',
}

-- Shared by skillchain reporting as well as target-related observations.
local function isMyBattleTarget(id)
    local target = windower.ffxi.get_mob_by_target('t')
    local battleTarget = windower.ffxi.get_mob_by_target('bt')
    return
        (target and target.id == id and target.spawn_type == SPAWN_TYPE_MOB) or
        (battleTarget and battleTarget.id == id and battleTarget.spawn_type == SPAWN_TYPE_MOB)
end

-- Refer to: https://github.com/ekrividus/autoSC/blob/main/autoSC.lua
ActionPacket.open_listener(function (act)
    local selfResult
    local effects
    -- Enemy events/state take priority over secondary skillchain bookkeeping.
    if globals and globals.event_system then
        local resultOk,result=pcall(globals.event_system.selfResultAction,globals.event_system,act)
        if resultOk then selfResult=result else writeError('Self action observation: '..tostring(result)) end
        local selfOk,selfError=pcall(globals.event_system.selfSpellAction,globals.event_system,act)
        if not selfOk then writeError('Self spell observation: '..tostring(selfError)) end
        local ok,err=pcall(globals.event_system.enemyAction,globals.event_system,act)
        if not ok then writeError('Enemy observation: '..tostring(err)) end
        -- Opener/effect bookkeeping must precede detection of the resulting
        -- skillchain, while lifecycle handlers retain first response priority.
        local afterAction=globals.event_system.deps and globals.event_system.deps.afterAction
        if afterAction then
            local effectOk,result=pcall(afterAction,act)
            if effectOk then effects=result else writeError('Action effects: '..tostring(result)) end
        end
    end
    local actionPacket = ActionPacket.new(act)
    local category = actionPacket:get_category_string()

    if
        category == 'weaponskill_finish' or
        category == 'avatar_tp_finish' or
        category == 'mob_tp_finish'
    then
        local actorId = actionPacket:get_id()
        local actor = selfResult and selfResult.actor or windower.ffxi.get_mob_by_id(actorId)
        local context = actionStateManager:getContext()
        local my_target = (context and context.bt and context.bt.mob) or
            windower.ffxi.get_mob_by_target('bt') or
            windower.ffxi.get_mob_by_target('t')
        local is_actor_allied = actor and (actor.in_party or actor.in_alliance)

        if
            actor and actor.id -- Require an actor
        then
            local targetInfo = actionPacket:get_targets()()
            if
                targetInfo and targetInfo.id -- Require a target
            then
                local target = selfResult and selfResult.target or windower.ffxi.get_mob_by_id(targetInfo.id)
                if target and target.id then
                    local action = targetInfo:get_actions()()

                    local id = actionPacket.raw.param

                    local action_message = action and action.message and resources.action_messages[action.message]
                    local message = action_message and action_message.en or ''
                    local fields = fieldsearch(message)

                    local ability = nil
                    local is_ws = false
                    if selfResult and selfResult.kind=='weapon_skill' then
                        ability=selfResult.resource
                        is_ws=true
                    elseif selfResult and selfResult.kind=='job_ability' then
                        -- Respect the shared decoder's resource type even when
                        -- this JA used the weapon-skill packet category.
                        local resource=selfResult.resource
                        if resource and (resource.id==209 or resource.id==320) then ability=resource end
                    elseif id then
                        if
                            fields.ability
                        then
                            -- This is an ability. Test things like Wild Flourish, etc. Refer to Gambit.lua/_handle_actionChunk for cross-reference.
                            ability = resources.job_abilities[id]
                            if ability then
                                if 
                                    ability.id ~= 209 and   -- Wild Flourish
                                    ability.id ~= 320       -- Konzen-ittai
                                then
                                    ability = nil
                                end
                            end
                        elseif
                            fields.spell
                        then
                            -- This is a spell. TODO: Test things like chain affinity for BLU, etc.
                            ability = resources.spells[id]
                        else
                            -- fields.weapon_skill
                            if id < 256 then
                                ability = resources.weapon_skills[id]
                                is_ws = true
                            else
                                ability = resources.monster_abilities[id]
                            end
                        end
                    end

                    if ability then
                        local targets = actionPacket.raw and actionPacket.raw.targets
                        local target_count = actionPacket.raw and actionPacket.raw.target_count or 0
                        local first_target_action = targets and targets[1] and targets[1].actions and targets[1].actions[1]
                        local message_id = first_target_action and first_target_action.message
                        local message = message_id and
                            resources.action_messages[message_id] and
                            resources.action_messages[message_id].en
                        local fields = fieldsearch(message)

                        local damage = (action and type(action.param) == 'number' and action.param) or nil
                        local damage_text = ''
                        -- Decode each target's own result; the first target may
                        -- land a status while another target resists it.
                        for _,entry in ipairs(targets or {}) do
                            local detail=entry.actions and entry.actions[1]
                            local messageId=detail and (tonumber(detail.message) or 0)%32768
                            local messageResource=messageId and resources.action_messages[messageId]
                            local targetFields=fieldsearch(messageResource and messageResource.en or '')
                            local status=targetFields.status and detail and resources.buffs[detail.param]
                            if status then
                                local mt=windower.ffxi.get_mob_by_id(entry.id)
                                if mt and mt.valid_target and not (effects and effects.statuses and effects.statuses[mt.id]==status.id) then
                                    local me=windower.ffxi.get_mob_by_target('me')
                                    actionStateManager:setMobBuff(mt,status.id,true,ability.duration or 60,
                                        me and actorId==me.id or false,actor)
                                end
                            end
                        end
                        if damage then
                            if fields.status then
                                local status = resources.buffs[damage]
                                if status then
                                    damage_text = '(' .. text_buff(status.name) .. ')'

                                end
                            else
                                damage_text = damage > 0 and
                                    (
                                        'for %s':format(text_number(compress_number(damage), Colors.verbose))
                                    ) or
                                    (
                                        message_id == 188 and text_red('(miss)', Colors.verbose) or text_red('(no effect)')
                                    )
                            end
                        end

                        if
                            not is_ws or 
                            (ability.skillchain_a or '') ~= '' or
                            (ability.skillchain_b or '') ~= '' or
                            (ability.skillchain_c or '') ~= ''
                        then
                            if damage and damage > 0 then
                                -- Note: This will actually send blue magic abilities used by and on mobs. It's handled in
                                -- the underlying implementation of setPartyWeaponSkill.
                                if not (selfResult and selfResult.weapon_skill_published) then
                                    setPartyWeaponSkill(actor, ability, target)
                                end
                            end
                        else
                            if settings.verbosity >= VERBOSITY_DEBUG then
                                writeDebug('Non-chainable weapon skill %s detected!':format(text_weapon_skill(ability.name, Colors.debug)))
                            end
                        end

                        -- We'll still only output if it is our current battle target
                        if
                            target and
                            my_target and
                            (my_target.id == target.id or actor.in_party or actor.in_alliance)
                        then
                            writeVerbose('%s: %s %s %s%s %s':format(
                                text_player(actor.name, Colors.verbose),
                                text_weapon_skill(ability.name, Colors.verbose),
                                CHAR_RIGHT_ARROW,
                                target.spawn_type == SPAWN_TYPE_MOB and text_mob(target.name, Colors.verbose) or text_player(target.name, Colors.verbose),
                                target_count > 1 and text_number('+' .. (target_count - 1)) or '',
                                damage_text
                            ))
                        end
                    end
                end
            end
        end
    end

    -------------------------------------------------------------------------------------
    -- Skillchaining
    if sc_categories:contains(category) and actionPacket.param ~= 0 then
        local target = actionPacket:get_targets()()
        if target and target.id then
            local action = target:get_actions()()
            local add_effect = action:get_add_effect()
            if add_effect and skillchain_ids:contains(add_effect.message_id) then
                local skillchain = add_effect.animation:ucfirst()
                local name = skillchain

                if name then
                    setSkillchain(name, target)

                    -- NOTE: action.param is the closing WS damage; action.add_effect_param is the SC damage.
                    local damage = (action and type(action.add_effect_param) == 'number' and action.add_effect_param) or nil
                    local multiplier = 0
                    if damage and type(action.param) == 'number' and action.param > 0 then
                        multiplier = action.add_effect_param / action.param
                    end

                    -- We'll still only output if it is our current battle target
                    if isMyBattleTarget(target.id) then
                        local damage_text = (damage == nil and text_red('??', Colors.verbose)) or
                            (damage > 0 and
                                'for %s %s':format(
                                    text_number(compress_number(damage) .. ' HP', Colors.verbose),
                                    text_green('@%.2fx':format(multiplier), Colors.verbose)
                                ) or
                                text_red('(miss)', Colors.verbose))
                    
                        writeVerbose('Skillchain detected: %s %s':format(
                            text_weapon_skill(name, Colors.verbose),
                            damage_text
                        ))
                    end
                end
            end
        end
    end
end)
