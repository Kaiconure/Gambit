local file=assert(io.open('lib/commands.lua'))
local source=file:read('*a')
file:close()

local block=assert(source:match("(handlers%['moblist'%] = function.-)\nhandlers%['slots'%]"))
local output,errors={},{}
local env={
    handlers={},
    writeMessage=function(value) output[#output+1]=value end,
    writeError=function(value) errors[#errors+1]=value end,
    windower={ffxi={}},
    SPAWN_TYPE_MOB=16,
    SPAWN_TYPE_PLAYER=13,
    SPAWN_TYPE_PLAYER2=1,
    CHAR_BULLET='<bullet>',
    text_mob=function(value) return '<mob:'..value..'>' end,
    text_player=function(value) return '<player:'..value..'>' end,
    text_npc=function(value) return '<npc:'..value..'>' end,
    text_number=function(value) return '<number:'..value..'>' end,
    text_direction=function(value) return '<direction:'..value..'>' end,
}
setmetatable(env,{__index=_G})
local chunk=assert(loadstring(block))
setfenv(chunk,env)
chunk()

env.windower.ffxi.get_mob_by_target=function(target)
    assert(target=='me')
    return {x=100,y=100}
end
env.windower.ffxi.get_mob_array=function()
    return {
        [1]={name='Goblin Digger',id=2134567,index=0x4AC,spawn_type=16,
            valid_target=true,x=100,y=95,is_npc=true},
        [2]={name='Goblin Smithy',id=2134568,index=0x4AD,spawn_type=16,
            valid_target=true,x=105,y=95,is_npc=true},
        [3]={name='Door',id=12,index=22,spawn_type=34,valid_target=true,x=100,y=90,is_npc=true},
        [4]={name='Nearby Player',id=13,index=23,spawn_type=13,valid_target=true,x=90,y=100},
        [5]={name='Invalid Goblin',id=14,index=24,spawn_type=16,valid_target=false,x=100,y=99,is_npc=true},
    }
end

local handler=env.handlers.moblist
handler({'-f','gOb','-d','10','-t','mob'})
assert(#errors==0,errors[1])
assert(output[1]=='Mob list: <number:2> matches within <number:10.0> yalms.',output[1])
assert(output[2]=='- <mob:Goblin Digger> (mob): <number:5.0y> <direction:E> '..
    '(<number:2134567><bullet><number:4AC>)',output[2])
assert(output[3]=='- <mob:Goblin Smithy> (mob): <number:7.1y> <direction:SE> '..
    '(<number:2134568><bullet><number:4AD>)',output[3])

output={}
handler({'-t','34'})
assert(#errors==0,errors[1])
assert(output[2]=='- <npc:Door> (npc): <number:10.0y> <direction:E> '..
    '(<number:12><bullet><number:016>)',output[2])

handler({'-d','10','-d','20'})
assert(#errors==1 and errors[1]:find('Usage: gbt moblist',1,true),errors[1])

print('moblist command tests passed')
