local json=require('./lib/jsonlua')
local definitions={}
for _,color in ipairs({'red','blue'}) do
    local f=assert(io.open('actions/lib/abyssea/'..color..'-proc.json'))
    definitions[color]=json.parse(f:read('*a'));f:close()
end
local vars={abyssea={red_proc={_allowed=true},blue_proc={_allowed=true,all_ws={'Sword'}}}}
local env={vars=vars,bt={id=200},arrayLength=function(value) return #value end}
local function runnable(action)
    for _,condition in ipairs(action.when) do
        local fn=assert(loadstring('return '..condition));setfenv(fn,env)
        if not fn() then return false end
    end
    return true
end
local function check(mode,red,blue)
    vars.abyssea.weapon_proc=mode
    assert(runnable(definitions.red.actions[3])==red)
    assert(runnable(definitions.blue.actions[4])==blue)
end
check('red',true,false);check('blue',false,true)
check('none',false,false);check(nil,false,false)
check('unexpected',false,false);check(false,false,false);check(123,false,false);check({},false,false)
for color,definition in pairs(definitions) do
    for _,fn in ipairs(definition.functions) do
        assert(fn.commands[1]=="setVar('vars.abyssea.weapon_proc', '"..color.."')")
    end
    assert(definition.vars['^abyssea'].weapon_proc=='none')
end
print('PASS: exclusive red/blue selection, harmless nil/none/unknown modes and manual mode selection')
