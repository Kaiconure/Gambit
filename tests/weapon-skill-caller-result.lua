local Wait=require('./lib/action-wait')
local Result=require('./lib/weapon-skill-result')
local file=assert(io.open('lib/action-processing.lua')); local source=file:read('*a');file:close()
local body=assert(source:match('(function sendObservedAction.-)\nfunction sendSpellCastingCommand'))
local message,dispatch=188,true
local environment=setmetatable({actionWait=Wait,
    windower={ffxi={get_mob_by_target=function() return {id=200} end}},
    smartMove={resetJitter=function() end},os={clock=function() return 0 end},
    coroutine={sleep=function() error('completed result must not wait') end},
    targetedAction={send=function(_,_,target,record)
        if not dispatch then return false end
        record.target_id=target; record.sent_at=0;record.completed_at=0;record.outcome='completed'
        record.results=Result.targets({{id=201,actions={{message=185}}},{id=target,actions={{message=message}}}})
        return true
    end}},{__index=_G})
local chunk=assert(loadstring(body));setfenv(chunk,environment);chunk()
local context={action={}}
local completed,result=environment.sendObservedAction(7,{id=20},'t',context,{result_timeout=1},false)
assert(completed and result.completed and result.missed and not result.landed)
assert(result.target_id==200 and result.results[1].landed and context.action.complete)
completed,result=environment.sendObservedAction(7,{id=20},'t',context,{result_timeout=1,require_landed=true},false)
assert(not completed and result.completed and result.missed and context.action.complete,
    'strict effect policy must not rewrite lifecycle completion')
message=225
completed,result=environment.sendObservedAction(7,{id=22},200,context,{result_timeout=1},false)
assert(completed and result.landed and result.effect=='landed')
dispatch=false
completed,result=environment.sendObservedAction(7,{id=22},200,context,{result_timeout=1},false)
assert(not completed and result.failed and result.outcome=='failed' and not result.landed)
print('PASS: caller completion boolean, structured per-target result, strict proc policy and dispatch failure')
