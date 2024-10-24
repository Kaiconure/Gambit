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

local categories = S{
    'weaponskill_finish',
    'spell_finish',
    'job_ability',
    'mob_tp_finish',
    'avatar_tp_finish',
    'job_ability_unblinkable',
}

-- Refer to: https://github.com/ekrividus/autoSC/blob/main/autoSC.lua
ActionPacket.open_listener(function (act)
    local actionPacket = ActionPacket.new(act)
    local category = actionPacket:get_category_string()

    if not categories:contains(category) or actionPacket.param == 0 then
        return
    end

    local target = actionPacket:get_targets()()
    if target then
        local t = windower.ffxi.get_mob_by_target('t')
        local bt = windower.ffxi.get_mob_by_target('bt')

        -- If the target of the action is either our current target or our current battle target, then we've got a hit
        if 
            (t  and t.valid_target  and t.id    == target.id) or
            (bt and bt.valid_target and bt.id   == target.id)
        then
            local action = target:get_actions()()
            local add_effect = action:get_add_effect()
            if add_effect and skillchain_ids:contains(add_effect.message_id) then
                local skillchain = add_effect.animation:ucfirst()
                local name = skillchain

                if name then
                    writeVerbose('Skillchain detected: %s':format(text_weapon_skill(name)))
                    setSkillchain(name)
                end
            end
        end
    end
end)