local json=require('./lib/jsonlua')
local factory=require('./lib/execution-factory')
local values=require('./lib/variable-values')
local root='settings/_namespaces/ambuscade/dullahan/actions/lib/dullahan/'
local function read(name)local f=assert(io.open(root..name));local d=json.parse(f:read('*a'));f:close();return d end
local f=assert(io.open('lib/action-context.lua'));local source=f:read('*a');f:close()
source=source:gsub("('[^'\r\n]*'):format", '(%1):format')
local start=assert(source:find('local function setArrayEnumerators(context)',1,true))
local finish=assert(source:find('local function setEnumerators(context)',start,true))
local chunk=assert(loadstring(source:sub(start,finish-1)..'\nreturn setArrayEnumerators'))
setfenv(chunk,setmetatable({varargs=function(args) if #args==1 and type(args[1])=='table' then return args[1] end return args end},{__index=_G}))
local context={vars=read('setup.json').vars,action={enumerators={}},results={},me={name='Miyajima'},time=0}
chunk()(context)
require('./tests/helpers/dullahan-party').attach(context)
local ids,people={},{}
for i,name in ipairs(context.partyNames({'*'}))do people[name]={id=i,name=name,distance=10}end
context.findByName=function(name)context.find_result=people[name];return context.find_result end
context.partyByName=function(name)context.member=people[name];return context.member end
context.setVar=function(path,value)
 local keys=values.path(path);local node=context.vars
 for i=1,#keys-1 do node[keys[i]]=node[keys[i]] or {};node=node[keys[i]] end
 node[keys[#keys]]=value;return value
end
context.canUseSpell=function(name)ids[name]=ids[name] or (#ids+1);context.spell={id=name,name=name};return true end
context.canUseAbility=function()return true end
context.hasBuff=function(_,name)return name~='Hymnus' end
context.hasEffectOf=function()return false end
context.mobById=function(id)for _,person in pairs(people)do if person.id==id then return person end end end
local cast
context.useSpell=function(target)cast=target;return true end
local songRules=read('songs.json').actions
local rule=songRules[2]
context.evaluateAllConditions=function()return false end
local function execute(code)local fn=factory.get(code);setfenv(fn,context);return fn()end
local counts={}
for tick=1,54 do
 context.time=tick*120
 for _,condition in ipairs(rule.when)do assert(execute(condition),condition)end
 local profile=context.results.dullahan_song_target
 local recipient=context.vars.dullahan.current_recipient
 local key=profile.id..':'..recipient;counts[key]=(counts[key]or 0)+1
 local expected=profile.songs[((counts[key]-1)%#profile.songs)+1]
 assert(context.vars.dullahan.current_song==expected,recipient..' got another profile song')
 context.member={id=999,name='Wrong'} -- Ability/event work must not change the captured recipient.
 for _,command in ipairs(rule.commands)do execute(command)end
 assert(cast.name==recipient)
 if profile.id=='mages' then
  assert(not context.vars.dullahan.current_song:find('March',1,true))
 end
end
print('PASS: real iterator keeps every song in its recipient profile and casts at the captured target through Pianissimo')
-- Real grouping expressions must permit area songs only for an isolated mage camp.
context.ipairs=ipairs
context.evaluateAllConditions=function(conditions)
 for _,code in ipairs(conditions)do if not execute(code)then return false end end
 return true
end
for _,person in pairs(people)do person.distance=20 end
for _,name in ipairs(context.partyNames({'mages'}))do people[name].distance=5 end
assert(context.evaluateAllConditions(context.vars.dullahan.mage_song_group_ready))
local dd=context.partyNames({'melee_dps'})[1]
people[dd].distance=8
assert(not context.evaluateAllConditions(context.vars.dullahan.mage_song_group_ready))
people[dd].distance=20
context.hasBuff=function()return false end
context.cancelBuff=function()error('No Pianissimo should be needed')end
context.vars.dullahan.song_times={};context.time=10000
local casts=0
context.useSpell=function(target)assert(target==context.me);casts=casts+1;return true end
for tick=1,30 do
 local matches=true
 for _,code in ipairs(songRules[1].when)do if not execute(code)then matches=false;break end end
 if matches then for _,code in ipairs(songRules[1].commands)do execute(code)end end
end
assert(casts==3) -- Missing buff observations must not cause Hymnus to loop.
for _,name in ipairs(context.partyNames({'mages'}))do
 for _,song in ipairs(context.vars.dullahan.song_targets[2].songs)do
  assert(context.vars.dullahan.song_times[name][song]==10000)
 end
end
local combat=read('combat.json').actions
local diaIndex,songIndex
for i,action in ipairs(combat)do
 if action.comment and action.comment:find('The bard feeds minimal TP',1,true)then diaIndex=i end
 if action.import=='dullahan/songs'then songIndex=i end
end
assert(diaIndex<songIndex)
-- Existing Hymnus blocks both targeted upkeep and another area Hymnus.
context.vars.dullahan.current_song="Goddess's Hymnus"
context.hasBuff=function(_,name)return name=='Hymnus' end
for _,condition in ipairs(rule.when)do
 if condition:find("hasBuff(find_result, 'Hymnus')",1,true)then assert(not execute(condition))end
end
context.vars.dullahan.song_times={};context.time=11000;casts=0
for tick=1,30 do
 local matches=true
 for _,code in ipairs(songRules[1].when)do if not execute(code)then matches=false;break end end
 if matches then for _,code in ipairs(songRules[1].commands)do execute(code)end end
end
assert(casts==2) -- Ballads still cast, existing Hymnus does not.
local originalFind=context.findByName
context.findByName=function(name)
 if name=='Bozzetto Retributionist'then context.find_result={};return context.find_result end
 return originalFind(name)
end
context.encounters={state=function()context.encounter_state={phase='boiling'};return context.encounter_state end}
for _,songRule in ipairs(songRules)do
 local matches=true
 for _,code in ipairs(songRule.when)do if not execute(code)then matches=false;break end end
 assert(not matches)
end
assert(diaIndex==3) -- Only emergency retreat and phase-gated Miasma burst precede Boiling Dia.
print('PASS: isolated mage camp gets three area songs with shared refresh times; nearby DDs force fallback; Boiling Dia precedes songs')
print('PASS: known Hymnus prevents targeted/area recasts; both song paths pause during Boiling')
