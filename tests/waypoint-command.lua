local file=assert(io.open('lib/commands.lua')); local source=file:read('*a'); file:close()
local handler=assert(source:match("(handlers%['waypoint'%] = function.-)\nhandlers%['slots'%]"))

local output,errors,selected={},{}
local me={id=1,name='Tester',x=-4,y=8}
local target={id=42,name='Rune of Transfer',x=100,y=-50}
local named={id=77,name='Archaic Rampart',x=20,y=30}
local panel={setWaypoint=function(_,value) selected=value end}
local context={findByName=function(name) return name=='Archaic Rampart' and {mob=named} or nil end}
local env=setmetatable({handlers={},globals={status_panel=panel},
    windower={ffxi={get_info=function() return {zone=77} end,
        get_mob_by_target=function(symbol) return symbol=='t' and target or symbol=='me' and me end}},
    actionStateManager={getContext=function() return context end},
    writeMessage=function(value) output[#output+1]=value end,
    writeError=function(value) errors[#errors+1]=value end},{__index=_G})
local chunk=assert(loadstring(handler)); setfenv(chunk,env); chunk()
local waypoint=env.handlers.waypoint

waypoint({})
assert(selected.name=='Waypoint' and selected.x==-4 and selected.y==8 and selected.zone==77)
assert(selected.near==10 and selected.mid==30 and selected.far==50)

waypoint({'-pos','-12.5,4','-name','Camp','-range','5,15,40'})
assert(selected.name=='Camp' and selected.x==-12.5 and selected.y==4)
assert(selected.near==5 and selected.mid==15 and selected.far==40)

waypoint({'-t'})
assert(selected.name=='Rune of Transfer' and selected.x==100 and selected.y==-50 and selected.mob_id==nil)
waypoint({'-t','-d'})
assert(selected.name=='Rune of Transfer' and selected.mob_id==42 and selected.x==nil)
waypoint({'-t','-d','-name','Exit'})
assert(selected.name=='Exit' and selected.mob_id==42)

waypoint({'-n','Archaic Rampart'})
assert(selected.name=='Archaic Rampart' and selected.x==20 and selected.y==30)
waypoint({'-n','Archaic Rampart','-d'})
assert(selected.name=='Archaic Rampart' and selected.mob_id==77)

selected='unchanged'; waypoint({'-clear'})
assert(selected==nil and output[#output]=='Waypoint override cleared.')

local function invalid(args)
    local before=#errors; waypoint(args); assert(#errors==before+1)
end
invalid({'-d'})
invalid({'-t','-pos','1,2'})
invalid({'-pos','1'})
invalid({'-range','30,10,50'})
invalid({'-n','Missing'})
invalid({'-unknown'})

print('PASS: waypoint command position, target/name lookup, dynamic IDs, ranges, labels and validation')
