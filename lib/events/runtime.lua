-- Request lifecycle. No dependency on Windower packets or the Gambit scheduler.
local copy=require('./lib/variable-values').copy
local Runner=require('./lib/events/runner')
local restoreEquipment=require('./lib/equipment/restore')
local trace=require('./lib/events/weapon-skill-trace')
local verify=require('./lib/events/verification')
local Runtime={}
Runtime.__index=Runtime
local sections={spell='spells',job_ability='job_abilities',weapon_skill='weapon_skills',pet_ability='pet_abilities'}
local function responseTimeout(event)
    if event.kind=='job_ability' or event.kind=='weapon_skill' then return 3 end
    if event.kind=='spell' then return math.max(3,(tonumber(event.cast_time) or 0)*2+3) end
    return 30 -- Pet commands may wait for the pet to begin and finish acting.
end
function Runtime:diagnostic(request,message,lostLifecycle)
    if self.deps.debug then
        local now=request.event.completed_at or self.deps.clock()
        local elapsed=math.max(0,now-request.event.time)
        local dispatch=request.sent_at and string.format(', %.3fs since dispatch',math.max(0,now-request.sent_at))
            or ', not dispatched'
        self.deps.debug('Event '..tostring(request.event.name or request.event.id)..' #'..
            tostring(request.event.request_id)..': '..message..
            string.format(' [%.3fs since creation%s]',elapsed,dispatch),lostLifecycle)
    end
end
function Runtime.new(config,deps)
    local self=setmetatable({config=config,deps=deps,pending={},sequence=0,
        runner=Runner.new(config,deps.context,deps.report,deps.equipmentSession,deps.targetSnapshot)},Runtime)
    self:compileReactions()
    return self
end
function Runtime:compileReactions()
    self.faceAwaySource=self.config.vars.reactions and self.config.vars.reactions.face_away
    self.faceAwayStockSource=self.config.vars.reactions and self.config.vars.reactions.stock_face_away
    self.faceAwayStockEnabled=not self.config.vars.reactions or self.config.vars.reactions.stock_face_away_enabled~=false
    self.faceAwayRules=self.config.faceAwaySource==self.faceAwaySource
        and self.config.faceAwayStockSource==self.faceAwayStockSource
        and self.config.faceAwayStockEnabled==self.faceAwayStockEnabled and self.config.faceAwayRules
        or require('./lib/reaction-rules').compile(self.faceAwaySource,
            self.faceAwayStockEnabled and self.faceAwayStockSource or nil)
    require('./lib/reactions').setDebug(self.config.vars.reactions and self.config.vars.reactions.debug==true)
end
function Runtime:eventVariables()
    local seen={}
    if self.faceAwaySource then seen[self.faceAwaySource]=self.faceAwayRules end
    if self.faceAwayStockSource then seen[self.faceAwayStockSource]=self.faceAwayRules end
    return copy(self.config.vars,seen)
end
function Runtime:run(request,phase)
    local verifying=verify.active()
    local previous
    if verifying then previous=verify.enter(request,phase) end
    local tracing=trace.active() and request.event.kind=='weapon_skill'
    if tracing then trace.record('phase_begin',{request=request.event.request_id,phase=phase,id=request.event.id}) end
    self.running=true
    local ok,result=pcall(self.runner.run,self.runner,request,phase)
    self.running=false
    if verifying then verify.leave(previous,ok and result or false,phase) end
    if tracing then trace.record('phase_end',{request=request.event.request_id,phase=phase,id=request.event.id,
        ok=ok and result,equipment=self.deps.traceEquipment and self.deps.traceEquipment()}) end
    if not ok then self.deps.report('Event '..phase..': '..tostring(result)); return false end
    return result
end
function Runtime:loading()
    if self.loaded then return end
    self.loaded=true
    if not self.config.path then return end
    local vars=copy(self.config.vars)
    vars._={eq_stack={}}
    local request={section='loading',event={kind='loading',cancelled=false,time=self.deps.clock()},
        variables={vars=vars,original=copy(vars)}}
    if self:run(request,'actions') then
        vars._=nil
        self.config.vars=vars
        self:compileReactions()
    end
end
-- Observed transitions are independent notifications, not cancellable actions.
-- Each notification gets isolated vars and one equipment phase; gear persists.
function Runtime:observe(event,phase)
    local section=event.kind=='status' and ('statuses.'..tostring(event.category))
        or event.kind=='zone' and 'zones'
        or event.kind=='buff' and 'buffs'
        or event.kind=='enemy_spell' and 'enemy_spells'
        or event.kind=='enemy_ability' and 'enemy_abilities'
        or event.kind=='party_weapon_skill' and 'party_weapon_skills'
        or event.kind=='weapon_skill' and 'weapon_skills'
    local rules=self.config.rules[section]
    if not rules or not rules[phase] or #rules[phase]==0 then return end
    if self.running then self.deps.report('Event rules cannot dispatch nested events'); return end
    self.sequence=self.sequence+1
    event=copy(event)
    event.request_id=self.sequence
    event.time=self.deps.clock()
    event.cancelled=false
    local vars=self:eventVariables()
    vars._={eq_stack={}}
    local request={section=section,event=event,observational=true,variables={vars=vars,original=copy(vars)}}
    self:run(request,phase)
    request.variables.vars._.eq_stack={}
end
function Runtime:finish(request,outcome)
    if request.finished then return end
    if request.event.kind=='weapon_skill' and not request.event.results then
        require('./lib/weapon-skill-result').apply(request.event,{},request.event.target and request.event.target.id)
    end
    request.finished=true
    if request.observation and outcome~='completed' and outcome~='interrupted' then
        request.observation.outcome=request.observation.outcome or outcome
    end
    if verify.active() then verify.result(request,outcome) end
    request.event.outcome=outcome
    request.event.completed=outcome=='completed'
    request.event.interrupted=outcome=='interrupted'
    request.event.failed=outcome=='failed'
    request.event.timed_out=outcome=='timeout'
    request.event.cancelled=request.event.cancelled or outcome=='cancelled'
    request.event.completed_at=self.deps.clock()
    request.event.duration=math.max(0,request.event.completed_at-request.event.time)
    if outcome=='failed' or outcome=='timeout' then
        self:diagnostic(request,'outcome '..tostring(outcome)..'; running post cleanup',outcome=='timeout')
    end
    self:run(request,'post')
    local stack=request.variables.vars._.eq_stack
    local baseline
    for _,entry in ipairs(stack) do
        if entry.event_baseline then baseline=entry.removed; break end
    end
    if self.config.rules[request.section].use_equipment_snapshot and baseline then
        local previous
        if verify.active() then previous=verify.enter(request,'post') end
        local ok,message=pcall(function()
            local session=self.deps.equipmentSession()
            local restored,err=pcall(function()
                restoreEquipment(stack,session.inventory)
                session:commit()
            end)
            if not restored then session:discard(); error(err,0) end
        end)
        if verify.active() then verify.leave(previous,ok,'post restoration') end
        if not ok then self.deps.report('Event equipment restoration: '..tostring(message)) end
    end
    if verify.active() then verify.finish(request) end
    request.variables.vars._.eq_stack={}
    for i=#self.pending,1,-1 do if self.pending[i]==request then table.remove(self.pending,i) end end
end
function Runtime:submit(event,dispatch,observation)
    local section=sections[event.kind]
    if not section then return end
    local rules=self.config.rules[section]
    if self.running then
        self.deps.report('Event rules cannot dispatch nested actions')
        return true
    end
    if #rules.pre+#rules.mid+#rules.post==0 then return end
    -- Recover expired requests even if a retry arrives before the next render.
    self:tick()
    -- A retry while the same request is unresolved must not create a second
    -- equipment stack whose saved state is already the temporary gear.
    for _,pending in ipairs(self.pending) do
        local previous=pending.event
        if previous.kind==event.kind and previous.id==event.id
            and (previous.target and previous.target.id)==(event.target and event.target.id) then
            if pending.sent_at and self.deps.clock()-pending.sent_at>=1
                and self.deps.retryReady and self.deps.retryReady(previous)==true then
                self:diagnostic(pending,'retry remains ready after dispatch; recovering stale lifecycle')
                self:finish(pending,'timeout')
                break
            end
            if not pending.suppression_logged then
                pending.suppression_logged=true
                self:diagnostic(pending,pending.sent_at and 'duplicate suppressed while awaiting result'
                    or 'duplicate suppressed while awaiting equipment dispatch')
            end
            return true
        end
    end
    self.sequence=self.sequence+1
    event=copy(event)
    event.request_id=self.sequence
    event.time=self.deps.clock()
    event.cancelled=false
    local vars=self:eventVariables()
    vars._={eq_stack={}}
    local request={section=section,event=event,variables={vars=vars,original=copy(vars)},observation=observation}
    if verify.active() then verify.begin(request) end
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
            if verify.active() then verify.abort(request,'equipment snapshot unavailable') end
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
            if observation then observation.sent_at=request.sent_at end
            if verify.active() then verify.dispatch(request) end
            if trace.active() and event.kind=='weapon_skill' then
                trace.record('dispatch',{request=event.request_id,id=event.id,
                    equipment=self.deps.traceEquipment and self.deps.traceEquipment()})
            end
            local ok,message=pcall(dispatch)
            if not ok or message==false then
                self.deps.report('Event dispatch failed: '..tostring(message))
                self:finish(request,'failed')
            elseif not request.finished and event.kind~='pet_ability' then self:run(request,'mid') end
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
function Runtime:spellStarted(id,targetId)
    for _,request in ipairs(self.pending) do
        local event=request.event
        if request.sent_at and event.kind=='spell' and event.id==id
            and event.target and event.target.id==targetId then
            -- Repeated start notifications must not extend the deadline.
            request.started_at=request.started_at or self.deps.clock()
            return true
        end
    end
end
function Runtime:complete(kind,id,targetId,outcome,results,resource)
    for _,request in ipairs(self.pending) do
        local event=request.event
        if request.sent_at and event.kind==kind and (id==nil or event.id==id)
            and (targetId==nil or not event.target or event.target.id==targetId)
            and (not results or not event.target or require('./lib/weapon-skill-result').find(results,event.target.id)) then
            if results then
                local wsResult=require('./lib/weapon-skill-result')
                wsResult.apply(event,results,event.target and event.target.id)
                if resource then wsResult.properties(event,resource) end
                local selected=wsResult.find(results,event.target and event.target.id)
                outcome=selected and selected.outcome or outcome
            end
            self:finish(request,outcome)
            return true
        end
    end
end
function Runtime:tick()
    for i=#self.pending,1,-1 do
        local request=self.pending[i]
        local limit=request.sent_at and responseTimeout(request.event) or 10
        local since=request.sent_at or request.event.time
        if request.sent_at and request.event.kind=='spell' then
            if request.started_at then since=request.started_at
            else limit=3 end
        end
        if self.deps.clock()-since>=limit then
            if request.event.kind=='spell' and request.sent_at then
                self:diagnostic(request,request.started_at and 'spell completion missing'
                    or 'spell start never confirmed')
            end
            self:finish(request,'timeout')
        end
    end
end
function Runtime:clear(outcome)
    local pending={}
    -- Preserve request identity (and deferred callbacks' finished flag).
    for i=1,#self.pending do pending[i]=self.pending[i] end
    for _,request in ipairs(pending) do self:finish(request,outcome) end
end
return Runtime
