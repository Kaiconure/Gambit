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

local sc_info = T{
    Radiance = {elements={'Fire','Wind','Lightning','Light'}, closers={}, lvl=4},
    Umbra = {elements={'Earth','Ice','Water','Dark'}, closers={}, lvl=4},
    Light = {elements={'Fire','Wind','Lightning','Light'}, closers={Light={4,'Light','Radiance'}}, lvl=3},
    Darkness = {elements={'Earth','Ice','Water','Dark'}, closers={Darkness={4,'Darkness','Umbra'}}, lvl=3},
    Gravitation = {elements={'Earth','Dark'}, closers={Distortion={3,'Darkness'}, Fragmentation={2,'Fragmentation'}}, lvl=2},
    Fragmentation = {elements={'Wind','Lightning'}, closers={Fusion={3,'Light'}, Distortion={2,'Distortion'}}, lvl=2},
    Distortion = {elements={'Ice','Water'}, closers={Gravitation={3,'Darkness'}, Fusion={2,'Fusion'}}, lvl=2},
    Fusion = {elements={'Fire','Light'}, closers={Fragmentation={3,'Light'}, Gravitation={2,'Gravitation'}}, lvl=2},
    Compression = {elements={'Darkness'}, closers={Transfixion={1,'Transfixion'}, Detonation={1,'Detonation'}}, lvl=1},
    Liquefaction = {elements={'Fire'}, closers={Impaction={2,'Fusion'}, Scission={1,'Scission'}}, lvl=1},
    Induration = {elements={'Ice'}, closers={Reverberation={2,'Fragmentation'}, Compression={1,'Compression'}, Impaction={1,'Impaction'}}, lvl=1},
    Reverberation = {elements={'Water'}, closers={Induration={1,'Induration'}, Impaction={1,'Impaction'}}, lvl=1},
    Transfixion = {elements={'Light'}, closers={Scission={2,'Distortion'}, Reverberation={1,'Reverberation'}, Compression={1,'Compression'}}, lvl=1},
    Scission = {elements={'Earth'}, closers={Liquefaction={1,'Liquefaction'}, Reverberation={1,'Reverberation'}, Detonation={1,'Detonation'}}, lvl=1},
    Detonation = {elements={'Wind'}, closers={Compression={2,'Gravitation'}, Scission={1,'Scission'}}, lvl=1},
    Impaction = {elements={'Lightning'}, closers={Liquefaction={1,'Liquefaction'}, Detonation={1,'Detonation'}}, lvl=1},
}

local sc_categories = S{
    'weaponskill_finish',
    'spell_finish',
    'job_ability',
    'mob_tp_finish',
    'avatar_tp_finish',
    'job_ability_unblinkable',
}

local function isMyBattleTarget(id)
    local t = windower.ffxi.get_mob_by_target('t')
    local bt = windower.ffxi.get_mob_by_target('bt')

    return 
        (t and t.id == id and t.spawn_type == SPAWN_TYPE_MOB) or
        (bt and bt.id == id and bt.spawn_type == SPAWN_TYPE_MOB)
end

-- Refer to: https://github.com/ekrividus/autoSC/blob/main/autoSC.lua
ActionPacket.open_listener(function (act)
    local actionPacket = ActionPacket.new(act)
    local category = actionPacket:get_category_string()

    -------------------------------------------------------------------------------------
    -- Mob TP moves
    if category == 'weaponskill_begin' or category == 'mob_tp_finish' then
        local actorId = actionPacket:get_id()

        -- NOTE: For now, this only finds skills used by our current battle target. Maybe change this to be:
        --  - Skills used by any mob engaged with a party member
        if isMyBattleTarget(actorId) then
            local actor = actorId and windower.ffxi.get_mob_by_id(actorId)

            local targetInfo = actionPacket:get_targets()()
            local target = targetInfo and targetInfo.id and windower.ffxi.get_mob_by_id(targetInfo.id)
            local action = targetInfo:get_actions()()

            -- NOTES:
            --  - weaponskill_begin:
            --      - action.param is the monster ability id of the action
            --  - mob_tp_finish: 
            --      - actionPacket.raw.param is the moster ability id of the action
            --      - action.param is the damage dealt to the target

            -- TODO: Look at monster skills as well

            if category == 'weaponskill_begin' then
                local ability = action and action.param and resources.monster_abilities[action.param]

                if ability then
                    -- Need to load all the targets rather than just the first
                    markMobAbilityStart(actor, ability, {target})

                    writeVerbose('%s: Preparing %s %s %s':format(
                        text_mob(actor.name, Colors.verbose),
                        text_weapon_skill(ability.name, Colors.verbose),
                        CHAR_RIGHT_ARROW,
                        target.spawn_type == SPAWN_TYPE_MOB and text_mob(target.name) or text_player(target.name)
                    ))
                end
            elseif category == 'mob_tp_finish' then
                local ability = actionPacket.raw.param and resources.monster_abilities[actionPacket.raw.param]

                if ability then
                    -- writeMessage('%s: finishing %s':format(
                    --     text_mob(actor.name, Colors.verbose),
                    --     text_weapon_skill(ability.name, Colors.verbose)
                    -- ))
                    markMobAbilityEnd(actor)
                end
            end
        end
    end

    if
        category == 'weaponskill_finish' or
        category == 'avatar_tp_finish' or
        category == 'mob_tp_finish'
    then
        local actorId = actionPacket:get_id()
        local actor = windower.ffxi.get_mob_by_id(actorId)

        if actor and actor.valid_target and actor.in_alliance then
            local targetInfo = actionPacket:get_targets()()
            local target = targetInfo and targetInfo.id and windower.ffxi.get_mob_by_id(targetInfo.id)
            local action = targetInfo:get_actions()()

            local time = os.clock()

            local id = actionPacket.raw.param
            local animation = action.raw and action.raw.animation or nil

            local action_message = action and action.message and resources.action_messages[action.message]
            local message = action_message and action_message.en or ''
            local fields = fieldsearch(message)

            local ability = nil
            local is_ws = false
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

            if ability then
                local damage = (action and type(action.param) == 'number' and action.param) or nil
                local damage_text = (damage == nil and text_red('??', Colors.verbose)) or
                    (damage > 0 and
                        'for %s':format(text_number(damage, Colors.verbose)) or
                        text_red('(miss)', Colors.verbose))

                if
                    not is_ws or 
                    (ability.skillchain_a or '') ~= '' or
                    (ability.skillchain_b or '') ~= '' or
                    (ability.skillchain_c or '') ~= ''
                then
                    if damage > 0 then
                        setPartyWeaponSkill(actor, ability, target)
                    end
                else
                    writeComment('Non-chainable weapon skill %s detected!':format(text_weapon_skill(ability.name, Colors.comment)))
                end
                
                writeVerbose('%s: %s %s %s %s':format(
                    text_player(actor.name, Colors.verbose),
                    text_weapon_skill(ability.name, Colors.verbose),
                    CHAR_RIGHT_ARROW,
                    text_mob(target.name, Colors.verbose),
                    damage_text
                ))
            end
        end
    end

    -------------------------------------------------------------------------------------
    -- Skill chaining
    if sc_categories:contains(category) and actionPacket.param ~= 0 then
        local target = actionPacket:get_targets()()
        if target then
            if isMyBattleTarget(target.id) then
                local action = target:get_actions()()
                local add_effect = action:get_add_effect()
                if add_effect and skillchain_ids:contains(add_effect.message_id) then
                    local skillchain = add_effect.animation:ucfirst()
                    local name = skillchain

                    if name then
                        setSkillchain(name)

                        -- NOTE: action.param is the closing WS damage; action.add_effect_param is the SC damage.
                        local damage = (action and type(action.add_effect_param) == 'number' and action.add_effect_param) or nil
                        local multiplier = 0
                        if type(action.param) == 'number' and action.param > 0 then
                            multiplier = action.add_effect_param / action.param
                        end

                        local damage_text = (damage == nil and text_red('??', Colors.verbose)) or
                            (damage > 0 and
                                'for %s (%s)':format(
                                    text_number(damage, Colors.verbose),
                                    text_number('%.2fx':format(multiplier), Colors.verbose)
                                ) or
                                text_red('(miss)', Colors.verbose))

                        writeVerbose('Skillchain detected: %s %s':format(text_weapon_skill(name), damage_text))
                    end
                end
            end
        end
    end
end)