local A=require('./lib/alignment')
local json=require('./lib/jsonlua')
local function width(spec)
 local total=0;for _,r in ipairs(A.intervals(spec))do total=total+r[2]-r[1]end;return total
end
local multi={arcs={{25,10},{200,20},{205,20}}}
assert(width(multi)==65) -- Overlap is not counted twice.
for _,spec in ipairs({A.parse('side'),A.parse('backside'),A.parse('330-30'),multi})do
 local total=0
 for i=1,6 do
  local slice=A.slice(spec,i,6);total=total+width(slice)
  for _,r in ipairs(A.intervals(slice))do assert(A.contains(spec,(r[1]+r[2])/2))end
  local candidates=A.distributedCandidates(spec,slice,140,6)
  for _,angle in ipairs(candidates)do assert(A.contains(spec,angle))end
 end
 assert(math.abs(total-width(spec))<0.00001)
end
assert(A.slice(A.parse(180),1,6).exact==180)
assert(A.slice(A.parse(nil),1,6).free)
local names={'Tank','B','A','Mage'}
local orders={{'Tank','B','A','Mage'},{'B','Mage','Tank','A'},{'A','Tank','Mage','B'},{'Mage','A','B','Tank'}}
local clients,queue={},{}
local now=0
local ids={Tank=100,B=101,A=102,Mage=103}
for i,name in ipairs(names)do
 local client={name=name,zone=1,leader=100}
 client.module=dofile('lib/party-alignment.lua')
 client.module.attach({json=json,clock=function()return now end,
  send=function(message)queue[#queue+1]={sender=client,message=message}end,
  ffxi={get_player=function()return {id=ids[name],name=name}end,
   get_info=function()return {zone=client.zone,logged_in=true}end,
   get_party=function()
    local p={party1_leader=client.leader}
    for n,member in ipairs(orders[i])do p['p'..(n-1)]={name=member}end
    return p
   end}})
 clients[name]=client
end
local function flush()
 local messages=queue;queue={}
 for _,m in ipairs(messages)do for _,c in pairs(clients)do
  if c~=m.sender then assert(c.module.receive(m.message))end
 end end
end
local target={id=500,index=20}
local options={distribute=true}
local spec=A.parse('side')
for _,name in ipairs({'A','B'})do clients[name].module.plan(target,spec,2,options)end
clients.Mage.module.plan(target,spec,12,options);flush()
now=2;clients.Tank.module.tick();flush()
local a=assert(clients.A.module.plan(target,spec,2,options))
local b=assert(clients.B.module.plan(target,spec,2,options))
assert(a.count==2 and b.count==2)
assert(A.contains(b.preferred,90) and not A.contains(b.preferred,270))
assert(A.contains(a.preferred,270) and not A.contains(a.preferred,90))
assert(not clients.Mage.module.plan(target,spec,12,options)) -- Separate distance group.
clients.A.module.accept(a,90)
a=assert(clients.A.module.plan(target,spec,2,options));assert(a.fallback and A.contains(a.preferred,90))
now=3;clients.Tank.module.tick();flush()
assert(clients.A.module.plan(target,spec,2,options).fallback) -- Routine refresh doesn't reclaim the slice.
orders[1]={'Tank','A','B','Mage'};now=4;clients.Tank.module.tick();flush()
a=assert(clients.A.module.plan(target,spec,2,options));assert(not a.fallback and A.contains(a.preferred,90))
-- Equivalent parsed ranges share a group regardless of the input spelling.
clients.A.module.plan(target,A.parse('frontside'),2,options)
clients.B.module.plan(target,A.parse('330-30'),2,options);flush()
now=5;clients.Tank.module.tick();flush()
a=assert(clients.A.module.plan(target,A.parse('frontside'),2,options))
assert(a.count==2 and not a.fallback)
assert(not clients.A.module.plan(target,A.parse(180),2,options))
assert(not clients.A.module.plan(target,A.parse(nil),2,options))
assert(not clients.A.module.receive('something else'))
assert(clients.A.module.receive('alignment invalid json'))
-- Stale or unrelated leaders/zones cannot change the shared assignment.
local before=clients.B.module.plan(target,A.parse('frontside'),2,options)
clients.B.module.receive('alignment '..json.stringify({kind='roster',zone=999,leader=100,sender=100,members={}}))
assert(clients.B.module.plan(target,A.parse('frontside'),2,options).key==before.key)
clients.B.leader=102
assert(not clients.B.module.plan(target,A.parse('frontside'),2,options))
-- Settle reload requests, then unchanged profiles stay quiet until the heartbeat.
clients.B.leader=100
for i=1,4 do
 for _,c in pairs(clients)do c.module.tick()end
 flush()
end
assert(#queue==0)
now=6
for _,c in pairs(clients)do c.module.tick()end
assert(#queue==0,'unchanged alignment must not send every second')
now=16
clients.Mage.module.tick()
assert(#queue==1,'active profile must send a ten-second heartbeat')
flush()
-- Reload advertises immediately and asks unchanged peers to respond immediately.
clients.Mage.module.reset();clients.Mage.module.tick()
assert(#queue==1 and json.parse(queue[1].message:sub(11)).request_profiles)
flush()
clients.A.module.tick()
assert(#queue==1,'reload request must force an immediate peer response')
flush()
print('PASS: generic arc union/slices, leader-relative ordering, distance groups, remembered fallback, roster reset, equivalent arcs, exact/free bypass and IPC validation')
for _,path in ipairs({'Gambit.lua','lib/action-context.lua','lib/action-processing.lua'})do
 local f=assert(io.open(path));local source=f:read('*a');f:close()
 source=source:gsub("\\'",'\1')
 source=source:gsub("('[^'\r\n]*'):format",'(%1):format')
 source=source:gsub('\1',"\\'")
 local fn,message=loadstring(source)
 assert(fn,path..': '..tostring(message))
end
print('PASS: IPC sender/receiver and action integration syntax')
