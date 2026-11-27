local ipc=require('./lib/context-send')
local messages={}
local function client(player,zone,party)
    local commands={}
    return {
        ffxi={get_player=function() return player end,
            get_info=function() return {zone=zone} end,
            get_party=function() return party end},
        send_command=function(command) commands[#commands+1]=command end,
        send_ipc_message=function(payload) messages[#messages+1]=payload end,
    },commands
end
local leader={id=100,name='Leaderchar',main_job='PLD'}
local sender,localCommands=client(leader,1,{party1_leader=100,p1={name='Healer'}})
local member,partyCommands=client({id=200,name='Healer',main_job='WHM'},2,
    {party1_leader=100,p1={name=leader.name}})
local neighbor,zoneCommands=client({id=300,name='Neighbor',main_job='BLM'},1,
    {party1_leader=300})
local function deliver()
    local payload=messages[#messages]
    assert(ipc.receive(sender,payload))
    assert(ipc.receive(member,payload))
    assert(ipc.receive(neighbor,payload))
end
local command=[[input /echo "100% ready"; gbt config -strat leader]]
assert(ipc.send(sender,'all',command))
deliver()
assert(#localCommands==1 and localCommands[1]==command)
assert(partyCommands[1]==command and zoneCommands[1]==command)
assert(ipc.send(sender,'party','party only','~me'))
deliver()
assert(#localCommands==1 and partyCommands[2]=='party only' and #zoneCommands==1)
assert(ipc.send(sender,'zone','zone only',{'*','~me'}))
deliver()
assert(#localCommands==1 and #partyCommands==2 and zoneCommands[2]=='zone only')
assert(ipc.send(sender,'all','casters',{'mages','~Healer'}))
deliver()
assert(#localCommands==1 and #partyCommands==2 and zoneCommands[3]=='casters')
assert(ipc.send(sender,'all','named','healer'))
deliver()
assert(partyCommands[3]=='named' and #zoneCommands==3)
assert(ipc.send(sender,'all','exclude sending tank','^tank'))
deliver()
assert(#localCommands==1 and #partyCommands==3 and #zoneCommands==3)
assert(ipc.send(sender,'party','party slot','p1'))
deliver()
assert(partyCommands[4]=='party slot' and #localCommands==1 and #zoneCommands==3)
local tank=leader
local function findTank() return tank end
assert(ipc.send(sender,'party','tank only','primary_tank',findTank))
deliver()
assert(localCommands[2]=='tank only' and #partyCommands==4)
tank={id=200,name='Healer'}
assert(ipc.send(sender,'party','new tank','primary_tank',findTank))
deliver()
assert(partyCommands[5]=='new tank' and #localCommands==2)
assert(ipc.send(sender,'party','except tank','~primary_tank',findTank))
deliver()
assert(localCommands[3]=='except tank' and #partyCommands==5)
tank=nil
assert(ipc.send(sender,'party','missing tank','primary_tank',findTank))
deliver()
assert(#localCommands==3 and #partyCommands==5)
assert(not ipc.send(sender,'all','nobody',{}))
assert(ipc.receive(member,'gbt-send-v1 broken JSON'))
assert(not ipc.receive(member,'unrelated IPC'))
local json=require('./lib/jsonlua')
local function announce(entry)
    assert(ipc.receive(sender,'gbt-presence-v1 '..json.stringify(entry)))
end
sender.ffxi.get_mob_by_id=function(id)
    if id==300 then return {name='Neighbor',distance=100,valid_target=true,hpp=100} end
end
local before=#messages
ipc.tick(sender,os.clock())
assert(#messages==before+1 and messages[#messages]:find('"request":true',1,true))
announce({id=200,name='Healer',zone=2,main_job='WHM',main_job_level=99,request=true})
assert(#messages==before+2)
announce({id=300,name='Neighbor',zone=1,main_job='BLM',main_job_level=99})
assert(ipc.send(sender,'party','remote healer','mages',nil,function(recipient)
    assert(recipient.name=='Healer' and not recipient.has_mob_data and not recipient.valid_target)
    return not recipient.is_participant and recipient.distance==nil and recipient.main_job_level>=75
end))
deliver()
assert(partyCommands[6]=='remote healer')
assert(ipc.send(sender,'zone','nearby','~me',nil,function(recipient)
    return recipient.has_mob_data and recipient.distance==10
end))
deliver()
assert(zoneCommands[4]=='nearby')
announce({name='Healer',offline=true})
assert(not ipc.send(sender,'party','absent','~me',nil,function() return true end))
ipc.tick(sender,os.clock()+36)
assert(not ipc.send(sender,'all','stale','~me',nil,function() return true end))
print('PASS: IPC context send domains, sender exclusion, live selectors, and literal command transport')
