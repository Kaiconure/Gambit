local M=require('./lib/reactions')
local Runtime=require('./lib/events/runtime')
local lines,now,enabled,actor,zone={},0,true,{id=2,index=2,hpp=100,valid_target=true},1
M.attach({log=function(line)lines[#lines+1]=line end,clock=function()return now end,
 enabled=function()return enabled end,zone=function()return zone end,
 player=function()return {vitals={hp=100}}end,mob=function()return actor end,
 cancelMovement=function()end,unlock=function()end,faceAway=function()end,restore=function()end})
local event={actor={id=2,index=2,name='Crab'},id=10,name='Bubble Shower',kind='enemy_ability',phase='pre'}
M.faceAway(event);M.tick(true);M.clear();assert(#lines==0)
local config={vars={reactions={debug=true}},rules={}}
local runtime=Runtime.new(config,{context=function()end,report=function(err)error(err)end})
assert(lines[1]:find('debug enabled',1,true))
M.faceAway(event,{key='test',distance=20,wait=1,allow_offensive_magic=true})
local start=lines[#lines]
assert(start:find('start actor=Crab(2)',1,true) and start:find('key=test',1,true))
assert(start:find('Bubble Shower(10)',1,true) and start:find('distance=20',1,true))
assert(start:find('suppress_magic=false',1,true) and start:find('timeout=infinity',1,true))
local count=#lines
for i=1,100 do M.tick(true)end
M.faceAway(event,{key='test'});assert(#lines==count)
local request=M.distanceRequest()
M.movementStatus(request,'retreating',2);M.movementStatus(request,'retreating',3)
assert(#lines==count+1)
M.movementStatus(request,'safe',20);assert(#lines==count+2)
M.observe({actor=event.actor,id=10,kind='enemy_ability',phase='post',outcome='completed'})
count=#lines
M.observe({actor=event.actor,id=10,kind='enemy_ability',phase='post',outcome='completed'})
assert(#lines==count and lines[count]:find('reason=completed',1,true))
now=1;M.tick(true);assert(lines[#lines]:find('release wait elapsed',1,true))
M.faceAway(event,{timeout=1});now=2;M.tick(true)
assert(lines[#lines]:find('reason=timeout',1,true))
M.faceAway(event);actor.hpp=0;M.tick(true)
assert(lines[#lines]:find('reason=enemy defeated',1,true));actor.hpp=100
M.faceAway(event);M.clear('reloaded');assert(lines[#lines]:find('reason=reloaded',1,true))
M.faceAway(event);enabled=false;M.tick(true)
assert(lines[#lines]:find('reason=automation disabled',1,true));enabled=true
config.vars.reactions.debug=false;runtime:compileReactions();count=#lines
M.faceAway(event);M.clear();assert(#lines==count)
assert(not pcall(require('./lib/events/config').load,{'test'},function()
 return {vars={reactions={debug='true'}}}
end))
M.attach({log=function()error('console unavailable')end,clock=function()return now end,
 enabled=function()return true end,zone=function()return zone end,
 player=function()return {}end,mob=function()return actor end,
 cancelMovement=function()end,faceAway=function()end,restore=function()end})
M.setDebug(true);assert(M.faceAway(event));M.clear();M.setDebug(false)
print('PASS: config debug toggle, console details, movement transitions, lifecycle reasons, duplicate/frame dedup, default silence and logger failure isolation')
