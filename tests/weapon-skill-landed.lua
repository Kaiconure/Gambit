local Observation=require('./lib/action-observation')
local Wait=require('./lib/action-wait')
local ffxi={get_player=function() return {id=100} end,get_mob_by_id=function(id) return {id=id} end}
local resources={weapon_skills={[20]={id=20,en='Cyclone'}},action_messages={}}
local function result(targets,strict)
    local record={sent_at=0,require_landed=strict}
    Wait.register(record,'weapon_skill',20,200,0)
    local observation=Observation.selfResult({actor_id=100,category=3,param=20,targets=targets},ffxi,resources,{[88]=true})
    Wait.observe(observation,1)
    Wait.release(record)
    if strict and record.outcome=='completed' then
        return record.landed and 'completed' or record.effect
    end
    return record.outcome
end
local function target(id,...)
    local actions={}
    for _,message in ipairs({...}) do actions[#actions+1]={message=message,param=0} end
    return {id=id,actions=actions}
end
assert(result({target(201,185),target(200,188)},true)=='missed','nearby hit must not hide intended-target miss')
assert(result({target(201,188),target(200,185)},true)=='completed','find intended target anywhere in result list')
assert(result({target(200,188,185)},true)=='completed','inspect all intended-target results')
assert(result({target(200,225)},true)=='completed','Energy Drain MP result counts as landed')
assert(result({target(200,185+32768)},true)=='completed','strip message flag')
assert(result({target(200,189)},true)=='no_effect','no-effect result must not claim a hit')
assert(result({target(200,9999)},true)=='unknown','unknown result must not claim a hit')
assert(result({target(201,185)},true)==nil,'unrelated target cannot complete intended-target request')
assert(result({target(200,188)},false)=='completed','ordinary WS lifecycle completion semantics remain unchanged')
assert(result({target(200,88)},false)=='failed')
assert(result({target(200,88)},true)=='failed','explicit failures retain their classification')
local record={sent_at=0,require_landed=true}
Wait.register(record,'weapon_skill',20,200,0)
Wait.reject('weapon_skill',1)
assert(record.outcome=='failed','range/cancellation rejection remains failed')
Wait.release(record)
print('PASS: intended-target WS hit/miss/unknown, AoE ordering, drain, message flags and rejection')
