local json=require('./lib/jsonlua')
local Compiler=require('./lib/reaction-rules')
local function read(path)
 local f=assert(io.open(path));local d=json.parse(f:read('*a'));f:close();return d
end
local stock=read('events/lib/reactions/face-away.json').vars.reactions.stock_face_away
assert(#Compiler.flatten(stock)==12)
local query=Compiler.compile({},stock)
local function event(actor,name,kind,phase)
 return {actor={name=actor},name=name,kind=kind or 'enemy_ability',phase=phase or 'pre',completed=true}
end
local function check(actor,name,key,wait,kind,phase)
 local results=query(event(actor,name,kind,phase));assert(#results==1,actor..' / '..name)
 local r=results[1];assert(r.options.key==key and r.options.wait==wait)
 assert(r.options.timeout==nil);return r
end
assert(check('Assailer Chariot','Discoid','stock-assailer-discoid',2).options.distance==12)
assert(check('Raja','Royal Decree','stock-raja-royal-decree',2).options.distance==20)
assert(check('Glavoid','Baleful Gaze','stock-glavoid-abilities',4).options.allow_offensive_magic)
assert(check('Urmahlullu','Anything','stock-urmahlullu-abilities',2).options.no_turn)
check('Rani','Anything','stock-rani-abilities',2)
for _,name in ipairs({'Afflicting Gaze','Baleful Gaze','Blaster','Grim Glower','Mortal Blast','Mortal Ray','Oppressive Glare'})do
 check('Crab',name,'stock-gaze-abilities',2)
end
check('Crab','Deathly Glare','stock-deathly-glare',4)
assert(check('Crab','Shah Mat','stock-shah-mat',6).options.allow_offensive_magic)
assert(check('Glavoid','Fire','stock-glavoid-spells',4,'enemy_spell').options.no_turn)
assert(check('Urmahlullu','Fire','stock-urmahlullu-spells',2,'enemy_spell').options.no_turn)
for _,case in ipairs({{'Amphitrite','Palsynyxis','Painful Whip','stock-amphitrite-bracket'},
 {'Cloud of Darkness','Primordial Surge','Waning Vigor','stock-cloud-of-darkness-bracket'}})do
 assert(#query(event(case[1],case[2]))==0)
 local start=check(case[1],case[2],case[4],2,nil,'post');assert(start.operation=='start' and start.options.bracket)
 local release=check(case[1],case[3],case[4],2,nil,'post');assert(release.operation=='release')
end
assert(check('Cloud of Darkness','Expunge','stock-cloud-of-darkness-bracket',2,nil,'post').operation=='release')
assert(#query(event('Crab','Bubble Shower'))==0)
local custom=Compiler.compile({{names='Baleful Gaze',options={wait=3,allow_offensive_magic=true}}},stock)
local results=custom(event('Crab','Baleful Gaze'))
assert(#results==1 and not results[1].stock and results[1].options.wait==3)
custom=Compiler.compile({{key='stock-gaze-abilities',disabled=true}},stock)
assert(#custom(event('Crab','Baleful Gaze'))==0)
assert(#custom(event('Rani','Baleful Gaze'))==1)
custom=Compiler.compile({{key='stock-glavoid-spells',actor='Glavoid',kind='enemy_spell',names='*',options={wait=7}}},stock)
results=custom(event('Glavoid','Fire','enemy_spell'))
assert(#results==1 and results[1].options.wait==7 and not results[1].options.no_turn)
custom=Compiler.compile({{start={abilities='Painful Whip'},release={abilities='End'}}},stock)
results=custom(event('Amphitrite','Painful Whip',nil,'post'))
assert(#results==2 and results[2].operation=='release')
local Runtime=require('./lib/events/runtime')
local config={vars={reactions={face_away={},stock_face_away=stock,stock_face_away_enabled=false}},rules={}}
local runtime=Runtime.new(config,{context=function()end,report=function(e)error(e)end})
assert(#runtime.faceAwayRules(event('Crab','Baleful Gaze'))==0)
local vars=runtime:eventVariables()
assert(type(vars.reactions.face_away)=='function' and type(vars.reactions.stock_face_away)=='function')
config.vars.reactions.stock_face_away_enabled=true;runtime:compileReactions()
assert(#runtime.faceAwayRules(event('Crab','Baleful Gaze'))==1)
for _,name in ipairs({'face-away-on-spell','face-away-bracketed'})do
 assert(#read('actions/lib/reactions/'..name..'.json').actions==0)
end
local legacy=read('actions/lib/reactions/face-away-on-ability.json')
assert(#legacy.actions==1 and legacy.actions[1].commands[2]:find('gear_removal.execute',1,true))
assert(legacy.vars['^face_away_on_ability'].gear_removal.abilities['Hurricane Breath'])
assert(#read('actions/lib/reactions/use-stun.json').actions==2)
print('PASS: all stock ability/spell/bracket rules, legacy waits/distances, actor precedence, custom overrides/disables, bracket releases, stock toggle, shared snapshots and polling retirement with gear/stun preservation')
