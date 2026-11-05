local json=require('./lib/jsonlua')
local f=assert(io.open('actions/lib/abyssea/yellow-proc.json'));local definition=json.parse(f:read('*a'));f:close()
local use
for _,fn in ipairs(definition.functions) do if fn.name=='abyssea/yellow/use' then use=fn end end
assert(use and use.silent and use.max_iterations==1)
assert(use.commands[1]==definition.actions[2].commands[1])
local settings=definition.vars['^abyssea'].yellow_proc
local env={vars={abyssea={yellow_proc=settings,weapon_proc='blue'}},string=tostring,
    arrayCount=function(value) return #value end,randomize=function(value) return value end,
    usableSpells=function(value) return value end,log=function() end,logArray=function() end,
    setVar=function(path,value) settings[path:match('%.([^%.]+)$')]=value end,
    arrayMerge=function(...)
        local result={};for _,list in ipairs({...}) do for _,name in ipairs(list) do result[#result+1]=name end end
        return result
    end}
for day=0,7 do
    env.game_time={day=day,yesterday=(day+7)%8,tomorrow=(day+1)%8}
    settings._yellow_rotation={used={Old=true}}
    for _,command in ipairs(definition.macros.initialize_abyssea_yellow) do
        local run=assert(loadstring('return '..command));setfenv(run,env);run()
    end
    assert(#settings.all_spells==21 and settings.usable_count==21 and not settings._yellow_rotation)
    local expected={}
    for _,d in ipairs({env.game_time.day,env.game_time.yesterday,env.game_time.tomorrow}) do
        for _,name in ipairs(settings.spells_by_day[settings.days_by_id[tostring(d)]]) do expected[name]=true end
    end
    for _,name in ipairs(settings.all_spells) do assert(expected[name]) end
    assert(env.vars.abyssea.weapon_proc=='blue')
end
print('PASS: full yellow manual initializer, shared auto macro, all day boundaries and independent weapon mode')
