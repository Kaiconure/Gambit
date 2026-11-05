-- The action supplies the time-window pool. Blue hints identify weapon skill type.
local Blue={color='blue',stateKey='_blue_rotation',hintField='weapon_type',slots={'main','range'}}
function Blue.validate(config)
    require('./lib/abyssea-weapon-proc').validate(config,'blue')
    assert(type(config.all_ws)=='table','Invalid blue proc all_ws: expected selected WS array')
end
function Blue.candidates(config,weaponType,resource,skill)
    local expected=weaponType and require('./lib/abyssea-weakness').weaponSkill(weaponType)
    local result={}
    if weaponType and not expected then return result end
    for _,name in ipairs(config.all_ws) do
        local ws=resource(name)
        if ws and (not expected or ws.skill==expected) and (not skill or ws.skill==skill) then
            result[#result+1]=name
        end
    end
    return result
end
function Blue.slot(hint)
    if not hint then return end
    local skill=require('./lib/abyssea-weakness').weaponSkill(hint)
    return (skill==25 or skill==26) and 'range' or 'main'
end
function Blue.step(config,target,observation,deps)
    return require('./lib/abyssea-weapon-proc').step(config,target,observation,deps,Blue)
end
return Blue
