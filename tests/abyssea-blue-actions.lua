local json=require('./lib/jsonlua')
local f=assert(io.open('actions/lib/abyssea/blue-proc.json'));local definition=json.parse(f:read('*a'));f:close()
local pools={{'early'},{'middle'},{'late'}}
local state={ws_0614=pools[1],ws_1422=pools[2],ws_2206=pools[3]}
local env={vars={abyssea={blue_proc=state}},game_time={hour=0},
    log=function() return true end,logArray=function() end,
    arrayMerge=function(...)
        local result={}
        for _,pool in ipairs({...}) do
            for _,skill in ipairs(pool) do result[#result+1]=skill end
        end
        return result
    end,
    setVar=function(path,value) state[path:match('%.([^%.]+)$')]=value;return value end}
local selectors={}
for _,fn in ipairs(definition.functions) do
    selectors[fn.name]=true
    local offset=fn.name=='abyssea/blue/use-previous' and -8 or fn.name=='abyssea/blue/use-next' and 8 or 0
    for hour=0,23 do
        env.game_time.hour=hour
        state._blue_rotation={used={'old'}}
        for _,command in ipairs(fn.commands) do
            local run=assert(loadstring('return '..command));setfenv(run,env);run()
        end
        if fn.name=='abyssea/blue/use' then
            assert(#state.all_ws==3 and state.all_ws[1]=='early' and state.all_ws[2]=='middle'
                and state.all_ws[3]=='late',fn.name..' at '..hour)
        else
            assert(state.all_ws==pools[math.floor(((hour-6+offset)%24)/8)+1],fn.name..' at '..hour)
        end
        assert(state._allowed and not state._blue_rotation)
        assert(state.weapon_proc=='blue','manual selector must choose blue mode')
    end
end
for _,name in ipairs({'use','use-now','use-previous','use-next'}) do
    assert(selectors['abyssea/blue/'..name],'missing selector '..name)
end
assert(definition.actions[3].frequency=='infinity' and definition.actions[3].scope=='battle')
assert(definition.actions[4].commands[3]:find('abyssea.runBlueProc({',1,true))
assert(definition.vars['^abyssea'].blue_proc.on_stagger=='stop')
print('PASS: blue combined/current/previous/next pools at every hour, reset, manual enable and battle-frozen selection')
