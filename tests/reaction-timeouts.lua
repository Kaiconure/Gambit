local reactions=require('./lib/reactions')
local compiler=require('./lib/reaction-rules')
local json=require('./lib/jsonlua')
local now,zone,enabled,player,actor
local function reset()
 now=0;zone=1;enabled=true;player={vitals={hp=100}}
 actor={id=2,index=2,hpp=100,valid_target=true}
 reactions.attach({clock=function()return now end,zone=function()return zone end,
 enabled=function()return enabled end,player=function()return player end,mob=function()return actor end,
 cancelMovement=function()end,unlock=function()end,faceAway=function()end,restore=function()end})
end
local event={actor={id=2,index=2},id=10,kind='enemy_ability'}
local post={actor={id=2,index=2},id=10,kind='enemy_ability',phase='post',completed=true}
local function start(options)
 assert(reactions.faceAway(event,options))
end
for _,options in ipairs({{},json.parse('{"timeout":null}'),{timeout='inf'},
 {timeout='infinity'},{timeout=' INF '},{timeout=math.huge}})do
 reset();start(options)
 for _,hold in pairs(reactions.state())do assert(hold.expires==nil)end
 assert(json.stringify(reactions.state()))
 now=1000000;reactions.tick(true);assert(reactions.active())
 reactions.observe(post);assert(reactions.active()) -- Default release wait remains finite.
 now=now+0.25;reactions.tick(true);assert(not reactions.active())
 compiler.compile({{names='Ability',options=options}})
end
reset();start({bracket=true,key='shield',wait=1})
now=1000000;reactions.tick(true);reactions.observe(post);assert(reactions.active())
reactions.release(event,{key='shield'});assert(reactions.active())
now=now+1;reactions.tick(true);assert(not reactions.active())
reset();start({timeout=2,wait=10});now=1;reactions.observe(post)
now=2;reactions.tick(true);assert(not reactions.active()) -- Finite deadline caps release wait.
reset();start({timeout=0});assert(not reactions.active())
for _,invalid in ipairs({-1,'forever','15',false,{},-math.huge,0/0})do
 reset()
 assert(not pcall(start,{timeout=invalid}))
 assert(not pcall(compiler.compile,{{names='Ability',options={timeout=invalid}}}))
end
for _,cleanup in ipairs({function()actor.hpp=0 end,function()actor=nil end,
 function()actor.valid_target=false end,function()player.vitals.hp=0 end,
 function()zone=2 end,function()enabled=false end,function()reactions.clear()end})do
 reset();start({timeout='infinity'});now=1000000
 cleanup();reactions.tick(true);assert(not reactions.active())
end
reactions.clear()
print('PASS: omitted/JSON-null/inf/infinity deadlines, finite and zero expiry, release waits, unlimited brackets, cleanup and load-time/direct validation')
