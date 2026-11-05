-- Explicit spell-search policy. No action paths, day selection or named functions.
local Yellow={}
function Yellow.validate(config)
    assert(type(config)=='table','abyssea.runYellowProc requires a configuration object')
    assert(type(config.spells)=='table','Invalid yellow proc spells: expected candidate array')
    for _,field in ipairs({'state','tools','ws_allow_list','ws_black_list'}) do
        assert(config[field]==nil or type(config[field])=='table','Invalid yellow proc '..field..': expected table')
    end
    for _,name in ipairs(config.spells) do assert(type(name)=='string','Invalid yellow proc spell name') end
    for _,tools in pairs(config.tools or {}) do
        assert(type(tools)=='table','Invalid yellow proc tools entry: expected table')
        assert(tools.items==nil or type(tools.items)=='table','Invalid yellow proc tool items: expected array')
        assert(tools.bags==nil or type(tools.bags)=='table','Invalid yellow proc tool bags: expected array')
    end
    assert(config.enabled==nil or type(config.enabled)=='boolean','Invalid yellow proc enabled: expected boolean')
    assert(config.allow_outside_abyssea==nil or type(config.allow_outside_abyssea)=='boolean',
        'Invalid yellow proc allow_outside_abyssea: expected boolean')
    assert(config.on_stagger==nil or config.on_stagger=='stop' or config.on_stagger=='full_rotation',
        'Invalid yellow proc on_stagger: expected stop or full_rotation')
end
function Yellow.matches(resource,element)
    return resource and (not element or require('./lib/abyssea-weakness').elementName((resource.element or -2)+1)==element)
end
function Yellow.step(config,target,observation,deps)
    if config.enabled==false or not target or target.hpp==0 or target.status==3 then return end
    local owner=config.state or config
    local state=owner._yellow_rotation
    if not state or state.target~=target.id or state.index~=target.index or state.pool~=config.spells then
        state={target=target.id,index=target.index,pool=config.spells,used={},deferred={}}
        owner._yellow_rotation=state
    end
    local yellow=observation and observation.yellow or {}
    if yellow.triggered and not state.triggered then
        state.triggered=true
    end
    if yellow.triggered and config.on_stagger~='full_rotation' then return end
    local element=not yellow.triggered and yellow.element or nil
    if state.element~=element then
        state.element=element;state.used={}
        if not element then deps.log('YELLOW PROC search: all elements.') end
    end
    local clock=deps.clock or os.clock
    local function waiting(reason,debugOnly)
        if state.waiting~=reason then
            state.waiting=reason
            if debugOnly then
                if deps.debug then deps.debug('YELLOW PROC waiting: '..reason) end
            else deps.log('YELLOW PROC waiting:',reason) end
        end
    end
    if deps.busy and deps.busy() then waiting('another spell or ranged action is still active',true);return end
    if state.retryAt and clock()<state.retryAt then return end
    state.deferred=state.deferred or {}
    local candidates,seen={},{}
    for _,name in ipairs(config.spells) do
        if not seen[name] and Yellow.matches(deps.resource(name),element) then
            candidates[#candidates+1]=name;seen[name]=true
        end
    end
    if #candidates==0 then waiting('no supplied spells match '..tostring(element or 'the search'));return end
    local reasons={}
    for pass=1,2 do
        for _,name in ipairs(candidates) do
            if not state.used[name] and (not state.deferred[name] or clock()>=state.deferred[name])
                and deps.ready(name) and deps.prepare(name) then
                if not deps.allowed(name) then return end
                local success,result=deps.use(name)
                if success or (result and result.started) then
                    state.waiting=nil
                    state.used[name]=true -- Completed/interrupted casts are retried on later passes.
                    state.deferred[name]=nil
                else
                    -- A dispatch failure is not a cast. Avoid the scheduler's
                    -- rapid incomplete-action retry churning through spell names.
                    state.retryAt=clock()+3
                    state.deferred[name]=clock()+6
                    waiting('cast did not start ('..tostring(result and result.outcome or 'not_ready')..'); retrying')
                    if deps.debug then deps.debug('YELLOW PROC '..name..' did not start: '..
                        tostring(result and result.outcome or 'not_ready')) end
                end
                return
            elseif not state.used[name] and (not state.deferred[name] or clock()>=state.deferred[name]) then
                local reason=deps.waitReason and deps.waitReason(name) or 'spell not ready or tools unavailable'
                reasons[reason]=true
            end
        end
        state.used={}
    end
    local summary={};for reason in pairs(reasons) do summary[#summary+1]=reason end;table.sort(summary)
    waiting(#summary>0 and table.concat(summary,'; ') or 'candidates are temporarily deferred')
end
return Yellow
