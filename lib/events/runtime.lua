-- Request lifecycle. No dependency on Windower packets or the Gambit scheduler.
local copy=require('./lib/variable-values').copy
local Runner=require('./lib/events/runner')
local Runtime={}
Runtime.__index=Runtime
local sections={spell='spells',job_ability='job_abilities',weapon_skill='weapon_skills'}
function Runtime.new(config,deps)
    return setmetatable({config=config,deps=deps,pending={},sequence=0,
        runner=Runner.new(config,deps.context,deps.report,deps.equipmentSession)},Runtime)
end
function Runtime:run(request,phase)
    self.running=true
    local ok,result=pcall(self.runner.run,self.runner,request,phase)
    self.running=false
    if not ok then self.deps.report('Event '..phase..': '..tostring(result)); return false end
    return result
end
function Runtime:finish(request,outcome)
    if request.finished then return end
    request.finished=true
    request.event.outcome=outcome
    request.event.completed=outcome=='completed'
    request.event.interrupted=outcome=='interrupted'
    request.event.failed=outcome=='failed'
    request.event.timed_out=outcome=='timeout'
    request.event.cancelled=request.event.cancelled or outcome=='cancelled'
    request.event.completed_at=self.deps.clock()
    self:run(request,'post')
    local stack=request.variables.vars._.eq_stack
    local baseline
    for _,entry in ipairs(stack) do
        if entry.event_baseline then baseline=entry.removed; break end
    end
    if self.config.rules[request.section].use_equipment_snapshot and baseline then
        local ok,message=pcall(function()
            local session=self.deps.equipmentSession()
            local restored,err=pcall(function()
                session.inventory.restore_equipment(baseline)
                session:commit()
            end)
            if not restored then session:discard(); error(err,0) end
        end)
        if not ok then self.deps.report('Event equipment restoration: '..tostring(message)) end
    end
    request.variables.vars._.eq_stack={}
    for i=#self.pending,1,-1 do if self.pending[i]==request then table.remove(self.pending,i) end end
end
function Runtime:submit(event,dispatch)
    local section=sections[event.kind]
    if not section then return end
    local rules=self.config.rules[section]
    if self.running then
        self.deps.report('Event rules cannot dispatch nested actions')
        return true
    end
    if #rules.pre+#rules.mid+#rules.post==0 then return end
    -- A retry while the same request is unresolved must not create a second
    -- equipment stack whose saved state is already the temporary gear.
    for _,pending in ipairs(self.pending) do
        local previous=pending.event
        if previous.kind==event.kind and previous.id==event.id
            and (previous.target and previous.target.id)==(event.target and event.target.id) then return true end
    end
    self.sequence=self.sequence+1
    event=copy(event)
    event.request_id=self.sequence
    event.time=self.deps.clock()
    event.cancelled=false
    local vars=copy(self.config.vars)
    vars._={eq_stack={}}
    local request={section=section,event=event,variables={vars=vars,original=copy(vars)}}
    do
        local ok,message=pcall(function()
            assert(self.deps.equipmentSession,'Equipment sessions are unavailable')
            local session=self.deps.equipmentSession()
            local captured,snapshot=pcall(session.inventory.snapshot_equipment)
            session:discard()
            if not captured then error(snapshot,0) end
            vars._.eq_stack[1]={removed=snapshot,event_baseline=true}
        end)
        if not ok then
            self.deps.report('Event equipment snapshot: '..tostring(message))
            return true -- Fail closed before running any rules or dispatching.
        end
    end
    if not self:run(request,'pre') then
        event.cancelled=true; event.reason=event.reason or 'pre phase failed'
    end
    if event.cancelled then self:finish(request,'cancelled'); return true end
    if #self.pending>=16 then
        event.cancelled=true; event.reason='too many pending requests'
        self:finish(request,'cancelled'); return true
    end
    self.pending[#self.pending+1]=request
    local function release(ready)
            if request.finished then return end
            if ready==false then self:finish(request,'failed'); return end
            request.sent_at=self.deps.clock()
            local ok,message=pcall(dispatch)
            if not ok or message==false then
                self.deps.report('Event dispatch failed: '..tostring(message))
                self:finish(request,'failed')
            elseif not request.finished then self:run(request,'mid') end
    end
    -- Reserve pre's dispatch boundary synchronously with its phase commit.
    -- There is no timer gap in which another caller can insert gear before it.
    local scheduled,err
    if self.deps.barrier then scheduled,err=pcall(self.deps.barrier,release)
    else scheduled,err=pcall(self.deps.schedule,function() release(true) end,0.1) end
    if not scheduled then
        self.deps.report('Could not schedule event dispatch: '..tostring(err))
        self:finish(request,'failed')
    end
    return true -- Block original; only the dispatch callback releases it.
end
function Runtime:complete(kind,id,targetId,outcome)
    for _,request in ipairs(self.pending) do
        local event=request.event
        if request.sent_at and event.kind==kind and (id==nil or event.id==id)
            and (targetId==nil or not event.target or event.target.id==targetId) then
            self:finish(request,outcome)
            return true
        end
    end
end
function Runtime:tick()
    for i=#self.pending,1,-1 do
        local request=self.pending[i]
        if self.deps.clock()-(request.sent_at or request.event.time)>120 then self:finish(request,'timeout') end
    end
end
function Runtime:clear(outcome)
    local pending={}
    -- Preserve request identity (and deferred callbacks' finished flag).
    for i=1,#self.pending do pending[i]=self.pending[i] end
    for _,request in ipairs(pending) do self:finish(request,outcome) end
end
return Runtime
