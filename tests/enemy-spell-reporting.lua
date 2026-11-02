local file=assert(io.open('lib/action-processing.lua'))
local source=file:read('*a'); file:close()
local body=assert(source:match('(function reportEnemyObservation%(observation%).-)\nfunction setPartyWeaponSkill'))
body=body:gsub("('[^'\r\n]*'):format",'(%1):format')
local lines={}
local target={id=2,name='Enemy'}
local verbose=true
local env=setmetatable({windower={ffxi={get_mob_by_target=function() return target end}},
    VERBOSITY_VERBOSE=1,hasVerbosity=function() return verbose end,
    Colors={verbose=1},SPAWN_TYPE_MOB=16,CHAR_RIGHT_ARROW='->',
    text_mob=tostring,text_spell=tostring,text_target=tostring,text_green=tostring,
    text_red=tostring,text_weapon_skill=tostring,text_player=tostring,
    writeVerbose=function(line) lines[#lines+1]=line end},{__index=_G})
local chunk=assert(loadstring(body)); setfenv(chunk,env); chunk()
local observation={kind='enemy_spell',phase='pre',actor=target,
    resource={en='Fire'},target={name='Self'}}
env.reportEnemyObservation(observation)
assert(lines[1]=='Enemy: Casting Fire -> Self')
observation.phase='post'; observation.outcome='completed'
env.reportEnemyObservation(observation)
assert(lines[2]=='Enemy: Fire completed')
observation.resource=nil; observation.outcome='interrupted'
env.reportEnemyObservation(observation)
assert(lines[3]=='Enemy: Spell interrupted')
observation.actor={id=3,name='Unrelated'}
env.reportEnemyObservation(observation)
assert(#lines==3)
env.resources={action_messages={[1]={en='Magic Burst!'}},buffs={}}
env.fieldsearch=function() return {} end
env.compress_number=tostring; env.text_number=tostring; env.text_buff=tostring
env.reportSelfSpellObservation({phase='mid',resource={name='Fire'},target={name='Enemy'}})
assert(lines[4]=='Casting Fire -> Enemy')
env.reportSelfSpellObservation({phase='post',was_casting=true,outcome='interrupted',previous_spell={name='Fire'}})
assert(lines[5]=='  Fire has been interrupted!')
env.reportSelfSpellObservation({phase='post',was_casting=true,outcome='completed',
    previous_spell={name='Fire'},previous_target={name='Enemy'},detail={param=100,message=1}})
assert(lines[6]=='  Completed! Fire -> Enemy for 100 Magic Burst!')
verbose=false
env.windower.ffxi.get_mob_by_target=function() error('Muted reports must skip target lookups') end
env.text_spell=function() error('Muted reports must skip formatting') end
observation.actor=target
env.reportEnemyObservation(observation)
env.reportSelfSpellObservation({phase='mid',resource={name='Fire'}})
assert(#lines==6)
print('PASS: targeted enemy spell start/result/interruption chat reporting and unrelated actor suppression')
