-- Rotation policy; callers own inventory, equipment confirmation and dispatch.
local Red={}
function Red.validate(config)
    return require('./lib/abyssea-weapon-proc').validate(config,'red')
end
Red.catalog={
    {'Cyclone','wind'}, {'Energy Drain','darkness'}, {'Red Lotus Blade','fire'},
    {'Seraph Blade','light'}, {'Freezebite','ice'}, {'Shadow of Death','darkness'},
    {'Raiden Thrust','lightning'}, {'Blade: Ei','darkness'}, {'Tachi: Jinpu','wind'},
    {'Tachi: Koki','light'}, {'Seraph Strike','light'}, {'Earth Crusher','earth'}, {'Sunburst','light'},
}
function Red.candidates(config,element,resource,skill)
    local allowed={}
    for _,entry in ipairs(Red.catalog) do allowed[entry[1]]=not element or entry[2]==element end
    local result={}
    local names=config.all_ws
    if not names then names={}; for _,entry in ipairs(Red.catalog) do names[#names+1]=entry[1] end end
    for _,name in ipairs(names) do
        local ws=resource(name)
        if allowed[name] and ws and (not skill or ws.skill==skill) then result[#result+1]=name end
    end
    return result
end
Red.color='red'
Red.stateKey='_rotation'
Red.hintField='element'
function Red.step(config,target,observation,deps)
    return require('./lib/abyssea-weapon-proc').step(config,target,observation,deps,Red)
end
return Red
