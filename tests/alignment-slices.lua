local alignment=require('./lib/alignment')
local f=assert(io.open('lib/action-context.lua'));local source=f:read('*a');f:close()
local block=assert(source:match('(local function alignmentPositionMatches.-)    context%.align2 ='))
local me={x=0,y=0}
local target={id=1,index=1,x=0,y=0,heading=0,valid_target=true,hpp=100}
local clock,attempts=0,{}
local context={action={},battleScope=1,movementAvailable=function()return true end,postpone=function()end}
local smart={tolerance=0.33}
function smart:findMobOffset(t,a,d)return {t.x+math.cos(a)*d,t.y-math.sin(a)*d}end
context.move=function(p)attempts[#attempts+1]=p;clock=clock+p.duration;me.x=p.x*0.1;return false,'timeout'end
local env=setmetatable({context=context,alignment=alignment,smartMove=smart,
 windower={ffxi={get_mob_by_target=function()return me end,get_mob_by_id=function()return target end}},
 os={clock=function()return clock end},directionality={faceTarget=function()end}}, {__index=_G})
local chunk=assert(loadstring(block));setfenv(chunk,env);chunk()
local function duration(distance,budget,options)
 me.x=0;clock=0;attempts={};context.action={}
 local success,reason=context.align(target,0,distance,budget,false,0.01,options)
 assert(not success and reason=='progress' and #attempts==1)
 return attempts[1].duration
end
local options={movement_slice_min=1,movement_slice_max=5}
assert(duration(2,10,options)==1)
assert(duration(12,10,options)==3)
assert(duration(100,10,options)==5)
assert(duration(100,3,options)==3)
assert(duration(12,10,{movement_slice_min=1,movement_slice_max=1})==1)
assert(duration(100,10,{movement_slice_min=3,movement_slice_max=2})==3)
assert(duration(100,10,{movement_slice_min='bad',movement_slice_max=math.huge})==5)
assert(duration(12,10,{})==10) -- Unconfigured non-distributed callers unchanged.
env.require=function(name)
 if name=='./lib/party-alignment'then return {plan=function(_,spec)return {preferred=spec,full=spec,fallback=true,key='one',count=2}end}end
 return require(name)
end
assert(duration(12,10,{distribute=true})==3)
assert(duration(100,2,{distribute=true})==2)
local buffs={}
env.windower.ffxi.get_player=function()return {buffs=buffs}end
for _,id in ipairs({2,19,7,10,11,28})do
 buffs={id};attempts={}
 local ok,reason=context.align(target,0,20,10,false,0.01,options)
 assert(not ok and reason=='immobilized' and #attempts==0)
end
buffs={};attempts={};context.action={}
context.move=function(p)attempts[#attempts+1]=p;return nil,'immobilized'end
local ok,reason=context.align(target,0,20,10,false,0.01,options)
assert(not ok and reason=='immobilized' and #context.action._alignment.pending==1)
local first=attempts[1]
context.align(target,0,20,10,false,0.01,options)
assert(attempts[2].x==first.x and attempts[2].y==first.y)
print('PASS: distance-scaled slices, configured bounds, overall budget, progress retry, legacy fixed slices and unaffected non-distributed callers')
