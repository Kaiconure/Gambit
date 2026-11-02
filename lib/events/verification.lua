-- Opt-in verification of observed equipment ordering, not server damage logic.
local copy=require('./lib/variable-values').copy
local Verify={}
local enabled=false
local records,current,failedOps={},nil,setmetatable({},{__mode='k'})
local clock,snapshot,report
local function compare(a,b)
    if not a or not b then return 'unknown' end
    if a.localId~=b.localId or (a.localId~=0 and a.bagId~=b.bagId) then return 'mismatch' end
    if a.localId==0 then return 'match' end
    if a.id==nil or b.id==nil then return 'unknown' end
    return a.id==b.id and 'match' or 'mismatch'
end
local function equipment()
    local ok,value=pcall(snapshot)
    return ok and type(value)=='table' and value or {}
end
local function issue(record,text,warning)
    if record.seen[text] then return end
    record.seen[text]=true
    record.issues[#record.issues+1]=text
    if warning then record.warning=true else record.incomplete=true end
end
local function check(record,expected,actual,label)
    for slot,item in pairs(expected) do
        local state=compare(item,actual[slot])
        if state~='match' then issue(record,label..' slot '..slot..(state=='unknown' and ' unconfirmed' or ' mismatch'),state=='mismatch') end
    end
end
local function emit(request,record)
    records[request]=nil
    local verdict=record.warning and 'WARNING' or record.incomplete and 'INCOMPLETE' or 'PASS'
    local detail
    if #record.issues>0 then detail=table.concat(record.issues,'; ',1,math.min(3,#record.issues))
    else
        local function phase(name)
            return record.phases[name] and next(record.phases[name].expected) and 'confirmed' or 'no swaps'
        end
        if record.outcome and record.outcome~='completed' then
            local outcome=record.outcome=='failed' and 'rejected' or record.outcome
            detail='handled '..outcome..'; post='..phase('post')..'; observed cleanup OK'
        else
            detail='pre='..phase('pre')..(request.event.kind=='spell' and ('; mid='..phase('mid')) or '')..
                '; post='..phase('post')..'; observed order OK'
        end
    end
    report(string.format('%s %s #%s: %s',verdict,tostring(request.event.name or request.event.id),
        tostring(request.event.request_id or '?'),detail))
end
function Verify.active() return enabled end
function Verify.stop()
    if enabled then
        for request,record in pairs(records) do issue(record,'verification stopped before settlement',false); emit(request,record) end
    end
    enabled=false; records={}; failedOps=setmetatable({},{__mode='k'}); current=nil
end
function Verify.start(deps)
    Verify.stop()
    clock=deps.clock or os.clock; snapshot=assert(deps.snapshot); report=assert(deps.report)
    enabled=true
end
function Verify.begin(request)
    if not enabled or (request.event.kind~='spell' and request.event.kind~='weapon_skill') then return end
    local count=0
    for _ in pairs(records) do count=count+1 end
    if count>=64 then
        for old,record in pairs(records) do issue(record,'verification capacity reached',false); emit(old,record); break end
    end
    records[request]={phases={},issues={},seen={},spell=request.event.kind=='spell'}
end
function Verify.enter(request,phase)
    local previous=current
    local record=records[request]
    if record then
        record.phases[phase]=record.phases[phase] or {expected={},ops={}}
        current={record=record,phase=record.phases[phase]}
    else current=nil end
    return previous
end
function Verify.leave(previous,ok,phase)
    if current and ok==false then issue(current.record,phase..' handler failed',false) end
    current=previous
end
function Verify.operations(operations,planned)
    if not current then return end
    for _,op in ipairs(operations) do current.phase.expected[op.slot]=copy(op.item) end
    for _,op in ipairs(planned) do current.phase.ops[#current.phase.ops+1]=op end
end
function Verify.failed(operations)
    for _,op in ipairs(operations) do if op.state~='acknowledged' then failedOps[op]=true end end
end
function Verify.dispatch(request)
    local record=records[request]; if not record then return end
    local actual=equipment()
    check(record,record.phases.pre and record.phases.pre.expected or {},actual,'pre at dispatch')
    record.dispatched=true; record.protected=copy(actual)
end
function Verify.ack(slot,item)
    for _,record in pairs(records) do
        if record.dispatched and not record.result then
            local mid=record.spell and record.phases.mid
            local desired=mid and mid.expected[slot]
            if desired and compare(desired,item)=='match' then record.protected[slot]=copy(item)
            elseif record.protected[slot] and compare(record.protected[slot],item)~='match' then
                local known=compare(record.protected[slot],item)=='mismatch'
                issue(record,known and ('equipment changed during action in slot '..slot)
                    or ('equipment identity unconfirmed during action in slot '..slot),known)
            end
        end
    end
end
function Verify.result(request,outcome)
    local record=records[request]; if not record then return end
    record.result=true
    record.outcome=outcome
    for phase,data in pairs(record.phases) do
        for _,op in ipairs(data.ops) do
            if failedOps[op] or op.state=='failed' then issue(record,phase..' equipment failed',true) end
        end
    end
    local handled=outcome=='interrupted' or outcome=='cancelled' or outcome=='failed'
        or outcome=='reloaded' or outcome=='zoned' or outcome=='logout' or outcome=='unloaded'
    if handled then
        if outcome=='failed' and not record.dispatched and not record.warning then
            issue(record,'action withheld before dispatch',false)
        end
        return -- Aborted actions need cleanup, not result-time mid gear.
    end
    if outcome~='completed' or not record.dispatched then
        issue(record,'outcome '..tostring(outcome)..(not record.dispatched and ' before dispatch' or ''),false)
        return
    end
    local expected={}
    for _,phase in ipairs(request.event.kind=='spell' and {'pre','mid'} or {'pre'}) do
        for slot,item in pairs(record.phases[phase] and record.phases[phase].expected or {}) do expected[slot]=item end
    end
    check(record,expected,equipment(),'at result')
end
function Verify.finish(request)
    local record=records[request]; if not record then return end
    record.finished=true; record.deadline=clock()+10
    Verify.tick()
end
function Verify.abort(request,reason)
    local record=records[request]; if not record then return end
    issue(record,reason,false); emit(request,record)
end
function Verify.tick()
    if not enabled then return end
    for request,record in pairs(records) do
        if record.finished then
            local pending=false
            local post=record.phases.post or {expected={},ops={}}
            for _,op in ipairs(post.ops) do
                if failedOps[op] or op.state=='failed' then issue(record,'post equipment failed',true)
                elseif op.state~='acknowledged' then pending=true end
            end
            if not pending or clock()>=record.deadline then
                if pending then issue(record,'post acknowledgment deadline exceeded',false) end
                if not pending then check(record,post.expected,equipment(),'post') end
                emit(request,record)
            end
        end
    end
end
return Verify
