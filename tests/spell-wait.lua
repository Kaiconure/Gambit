local Wait=require('./lib/action-wait')
local function scenario(options)
    local now=0
    local record={}
    Wait.register(record,options.kind or 'spell',10,200,0)
    local started,finished=false,false
    local function advance(seconds)
        now=now+seconds
        if now>=options.dispatch then record.sent_at=options.dispatch end
        if options.start and now>=options.start and not started then
            started=true
            Wait.observe({kind='spell',id=options.wrongSpell and 11 or 10,
                target_id=options.wrongTarget and 201 or 200,phase='mid'},now)
        end
        if options.finish and now>=options.finish and not finished then
            finished=true
            Wait.observe({kind=options.kind or 'spell',id=10,target_id=200,phase='post',
                outcome=options.interrupted and 'interrupted' or 'completed'},now)
        end
        if options.reject and now>=options.reject then Wait.reject(nil,now) end
    end
    local ok=Wait.run(record,options.policy or {start=true,result_timeout=7,padding=3},function() return now end,advance)
    return ok,now,record
end
local ok,time=scenario{dispatch=1.5,start=2,finish=3.5}
assert(ok and time>=6.5 and time<6.7,'padding must follow completion')
ok,time=scenario{dispatch=0,finish=0.1}
assert(ok and time>=3.1 and time<3.3,'post-only fast completion')
ok,time=scenario{dispatch=0}
assert(not ok and time>=2 and time<2.2,'bounded start wait')
ok,time=scenario{dispatch=0,start=0.5,wrongSpell=true}
assert(not ok and time<0.7,'different spell exits early')
ok,time=scenario{dispatch=0,start=0.5,wrongTarget=true}
assert(not ok and time<0.7,'different target exits early')
ok,time=scenario{dispatch=0,reject=0.5}
assert(not ok and time<0.7,'rejection exits early')
local tracking
ok,time,tracking=scenario{dispatch=20}
assert(not ok and tracking.abandoned and time>=10 and time<10.2)
ok,time=scenario{dispatch=0,start=0.2,finish=0.5,interrupted=true}
assert(not ok and time>=3.5)
ok,time=scenario{kind='weapon_skill',dispatch=1.5,finish=2,policy={result_timeout=3,padding=1}}
assert(ok and time>=3 and time<3.2,'WS result margin')
ok,time=scenario{kind='job_ability',dispatch=1.5,finish=2,policy={result_timeout=3,padding=0.2,minimum=1.5}}
assert(ok and time>=3 and time<3.2,'JA minimum begins at dispatch')
ok,time=scenario{kind='job_ability',dispatch=0,policy={result_timeout=3,padding=0.2}}
assert(not ok and time>=3 and time<3.2,'missing result bounded')
local record={sent_at=1}
Wait.register(record,'spell',10,200,0)
Wait.observe({kind='spell',id=11,target_id=200,phase='post',outcome='completed'},2)
assert(not record.outcome)
Wait.clear('logout',3)
assert(record.outcome=='logout' and record.abandoned)
Wait.release(record)
print('PASS: shared spell/JA/WS wait policies, delayed dispatch/start, post-only results, conflicts, rejection, missing packets and teardown')
