-- Event rules must finish synchronously; the normal yielding scheduler is unused.
local copy=require('./lib/variable-values').copy
local Matches=require('./lib/events/matches')
local Runner={}
Runner.__index=Runner
function Runner.new(config,context,report,equipmentSession,targetSnapshot)
    return setmetatable({config=config,context=context,report=report,equipmentSession=equipmentSession,targetSnapshot=targetSnapshot},Runner)
end
local function evaluate(expression,context)
    local thread=coroutine.create(function()
        setfenv(expression.fn,context)
        return expression.fn()
    end)
    local ok,value=coroutine.resume(thread)
    if not ok then error(value,0) end
    assert(coroutine.status(thread)=='dead','Event rules cannot yield or wait')
    return value
end
function Runner:run(request,phase)
    local rules=self.config.rules[request.section][phase]
    if #rules==0 then return true end
    local session=self.equipmentSession and self.equipmentSession()
    local previous=request.variables.equipment
    local stack=copy(request.variables.vars._.eq_stack)
    request.variables.equipment=session
    local function discard()
        if session then
            session:discard()
            request.variables.vars._.eq_stack=stack
        end
        request.variables.equipment=previous
    end
    local ok,context=pcall(self.context,'event '..phase,request.variables)
    if not ok or not context then
        discard()
        self.report('Event context unavailable: '..tostring(context))
        return false
    end
    context.event=copy(request.event)
    if request.event.target and self.targetSnapshot then
        context.event.target=self.targetSnapshot(request.event.target)
    end
    context.event.phase=phase
    Matches.attach(context.event)
    local active=true
    local phaseFailed=false
    local stopped=false
    context.cancelEvent=function(reason)
        assert(active and phase=='pre' and not request.finished and not request.observational,
            'cancelEvent is only valid during this request\'s pre phase for an outgoing player action')
        request.event.cancelled=true
        request.event.reason=request.event.reason or (reason and tostring(reason))
        context.event.cancelled=true
        context.event.reason=request.event.reason
        return true
    end
    context.stopEvent=function(cancel)
        assert(active,'stopEvent is only valid during this request\'s active phase')
        assert(cancel==nil or type(cancel)=='boolean','stopEvent cancel flag must be a boolean')
        if cancel then context.cancelEvent() end
        stopped=true
        return true
    end
    -- Shared configuration variables are cloned per request; internal equipment
    -- stacks and changes persist only across that request's phases.
    for _,rule in ipairs(rules) do
        context.event.cancelled=request.event.cancelled
        context.event.reason=request.event.reason
        context.event.source=rule.source
        context.event.rule_id=rule.id
        if not rule.failed then
            local matched=false
            local success,message=pcall(function()
                for _,condition in ipairs(rule.conditions) do
                    if not evaluate(condition,context) then return end
                end
                matched=true
                for _,command in ipairs(rule.commands) do evaluate(command,context) end
            end)
            if not success then
                phaseFailed=true
                rule.failed=true
                self.report(rule.source..': '..tostring(message))
                if phase=='pre' and not request.observational then
                    request.event.cancelled=true
                    request.event.reason=request.event.reason or 'pre-rule error'
                end
            elseif matched and rule.stop then break end
        elseif phase=='pre' then
            phaseFailed=true
            -- A quarantined pre rule must not silently bypass its cancellation.
            if not request.observational then
                request.event.cancelled=true
                request.event.reason=request.event.reason or 'pre-rule disabled after error'
            end
        end
        if stopped then break end
    end
    active=false
    if phaseFailed or (phase=='pre' and request.event.cancelled) then
        discard()
    elseif session then
        local committed,message=pcall(session.commit,session)
        if not committed then
            discard()
            self.report('Event equipment commit: '..tostring(message))
            return false
        end
    end
    request.variables.equipment=previous
    return not phaseFailed
end
return Runner
