local Service=require('./lib/events/init')
local State=require('./lib/self-action-state')
local globals={}
local actor={id=100,name='Self',spawn_type=1,in_party=true}
local target={id=200,name='Enemy',spawn_type=16,index=2}
local ability={id=11,en='Provoke',name='Provoke',type='JobAbility',element=6}
local roll={id=98,en="Corsair's Roll",type='CorsairRoll'}
local ws={id=42,en='Savage Blade',name='Savage Blade',skillchain_a='Fragmentation'}
local resources={job_abilities={[11]=ability,[98]=roll},weapon_skills={[42]=ws},
    action_messages={[0]={en='Damage'}}}
local order,calls={},{}
local state={getContext=function() end,setPartyWeaponSkill=function(_,source,resource,mob)
    assert(source==actor and resource==ws and mob==target)
    order[#order+1]='state-ws'
end}
local ffxi={get_player=function() return {id=100} end,
    get_mob_by_id=function(id) return id==100 and actor or id==200 and target or nil end,
    get_mob_by_target=function(name) if name=='bt' or name=='t' then return target end end}
local deps={externalSelfResults=true,externalEnemyActions=true,externalSelfSpells=true,
    resources=resources,windower={ffxi=ffxi,register_event=function() end},
    observeSelfResult=function(observation)
        State.apply(observation,state,globals,function() return 10 end)
        if observation.kind=='job_ability' and observation.resource then
            assert(globals.last_ability.id==observation.id)
            order[#order+1]='state-ja'
        end
    end}
local service=Service.new(deps)
local match=true
service.runtime={pending={},complete=function(_,kind,id,_,outcome)
    calls[#calls+1]={kind,id,outcome}; order[#order+1]='post'
    return match or id==123
end}
local function action(category,id,damage,message,targetId)
    return {actor_id=100,category=category,param=id,target_count=1,
        targets={{id=targetId or 200,actions={{param=damage,message=message or 0}}}}}
end
assert(service:selfResultAction(action(6,11)))
assert(table.concat(order,',')=='state-ja,post')
assert(globals.last_ability.name=='Provoke' and globals.last_ability.target.id==200)
order={}; assert(service:selfResultAction(action(14,11)))
assert(table.concat(order,',')=='state-ja,post')
order={}; local packet=action(3,42,100)
local observation=service:selfResultAction(packet)
assert(observation.weapon_skill_published and table.concat(order,',')=='state-ws,post')
order={}; service:action(packet); assert(#order==0)
order={}; observation=service:selfResultAction(action(3,42,0))
assert(not observation.weapon_skill_published and table.concat(order,',')=='post')
order={}; observation=service:selfResultAction(action(3,42,100,0,999))
assert(not observation.weapon_skill_published and table.concat(order,',')=='post')
calls={}; match=false; service:selfResultAction(action(6,98))
assert(#calls==2 and calls[1][2]==98 and calls[2][2]==123)
calls={}; match=true; service:selfResultAction(action(6,98))
assert(#calls==1 and calls[1][2]==98)
calls={}; service:selfResultAction(action(6,11,0,32768+88))
assert(calls[1][3]=='failed')
local foreign=action(6,11); foreign.actor_id=200
assert(not service:selfResultAction(foreign))
service.runtime=nil; globals.last_ability=nil
assert(service:selfResultAction(action(6,11)) and globals.last_ability)

-- Exercise the actual early packet listener and its later skillchain/reporting
-- path: the self WS record must not be published a second time after post.
service.runtime={pending={},complete=function() order[#order+1]='post'; return true end}
service.selfSpellAction=function() return false end
service.enemyAction=function() return false end
globals.event_system=service
local file=assert(io.open('lib/eventing.lua')); local source=file:read('*a'); file:close()
source=source:gsub("('[^'\r\n]*'):format",'(%1):format')
local listener
local detail={param=100,message=0}
local targetInfo={id=200,get_actions=function() return function() return detail end end}
local env=setmetatable({globals=globals,resources=resources,actionStateManager=state,
    windower={ffxi=ffxi},SPAWN_TYPE_MOB=16,Colors={verbose=1},CHAR_RIGHT_ARROW='->',
    T=function(value) return value end,S=function(value) value.contains=function() return false end; return value end,
    ActionPacket={open_listener=function(fn) listener=fn end,new=function(raw)
        return {raw=raw,get_category_string=function() return 'weaponskill_finish' end,
            get_id=function() return 100 end,get_targets=function() return function() return targetInfo end end}
    end},fieldsearch=function() return {} end,
    text_number=tostring,text_mob=tostring,text_player=tostring,text_weapon_skill=tostring,
    text_red=tostring,compress_number=tostring,
    writeVerbose=function() order[#order+1]='report' end,
    writeError=function(err) error(err) end,
    setPartyWeaponSkill=function() error('duplicate self WS publication') end,
},{__index=_G})
local chunk=assert(loadstring(source)); setfenv(chunk,env); chunk()
order={}; listener(packet)
assert(table.concat(order,',')=='state-ws,post,report')
print('PASS: self JA/WS publication before post, history, Double-Up matching, rejection, misses, no-runtime state and single raw-listener WS write')

-- Damaging JA results can use category 3; resource ID alone is ambiguous.
resources.job_abilities[46]={id=46,en='Shield Bash',name='Shield Bash'}
resources.weapon_skills[46]={id=46,en='Expiacion',name='Expiacion',skillchain_a='Distortion'}
resources.action_messages[110]={en='${actor} uses ${ability}. ${target} takes ${number} points of damage.'}
resources.action_messages[185]={en='${actor} uses ${weapon_skill}. ${target} takes ${number} points of damage.'}
local Observation=require('./lib/action-observation')
local bash=action(3,46,100,110)
observation=Observation.selfResult(bash,ffxi,resources,{})
assert(observation.kind=='job_ability' and observation.resource.en=='Shield Bash')
State.apply(observation,state,globals)
assert(globals.last_ability.name=='Shield Bash' and not observation.weapon_skill_published)
observation=Observation.selfResult(action(3,46,100,185),ffxi,resources,{})
assert(observation.kind=='weapon_skill' and observation.resource.en=='Expiacion')
order={}; listener(bash)
assert(table.concat(order,',')=='state-ja,post','Shield Bash must not publish/report Expiacion or open a skillchain')
print('PASS: overlapping Shield Bash / Expiacion IDs preserve JA/WS identity in shared observations and reporting')
