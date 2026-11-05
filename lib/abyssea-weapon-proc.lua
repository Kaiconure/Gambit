-- Shared red/blue equipment rotation and WS outcome handling.
local Rotation={}
function Rotation.validate(config,color)
    color=color or 'red'
    local name=color:sub(1,1):upper()..color:sub(2)
    assert(type(config)=='table','abyssea.run'..name..'Proc requires a configuration object')
    for _,field in ipairs({'weapons','all_ws','state','ws_allow_list','ws_black_list'}) do
        assert(config[field]==nil or type(config[field])=='table','Invalid '..color..' proc '..field..': expected table')
    end
    for _,ws in ipairs(config.all_ws or {}) do assert(type(ws)=='string','Invalid '..color..' proc WS name') end
    assert(config.enabled==nil or type(config.enabled)=='boolean','Invalid '..color..' proc enabled: expected boolean')
    assert(config.allow_outside_abyssea==nil or type(config.allow_outside_abyssea)=='boolean',
        'Invalid '..color..' proc allow_outside_abyssea: expected boolean')
    local condition=config.is_active
    assert(condition==nil or type(condition)=='function' or type(condition)=='string' or type(condition)=='table',
        'Invalid '..color..' proc is_active: expected expression string, array of strings, or function')
    if type(condition)=='table' then
        local count=0
        for key,value in pairs(condition) do
            assert(type(key)=='number' and key%1==0 and key>=1 and key<=#condition and type(value)=='string',
                'Invalid '..color..' proc is_active: expected contiguous array of expression strings')
            count=count+1
        end
        assert(count==#condition,'Invalid '..color..' proc is_active: expected contiguous array of expression strings')
    end
    assert(config.on_stagger==nil or config.on_stagger=='stop' or config.on_stagger=='full_rotation',
        'Invalid '..color..' proc on_stagger: expected stop or full_rotation')
    for _,field in ipairs({'swap_delay','empty_pass_delay','refresh_delay','equip_timeout'}) do
        local value=config[field]
        assert(value==nil or type(value)=='number' and value>=0 and value<=3600,
            'Invalid '..color..' proc '..field..': expected seconds between 0 and 3600')
    end
end
function Rotation.step(config,target,observation,deps,policy)
    local active=deps.active or (type(config.is_active)=='function' and config.is_active)
    if config.enabled==false or (active and not active()) or not target or target.hpp==0 or target.status==3 then return end
    local red=observation and observation[policy.color] or {}
    local element=not red.triggered and red[policy.hintField] or nil
    local owner=config.state or config
    local state=owner[policy.stateKey]
    local pool=table.concat(config.all_ws or {},'\0')
    if not state or state.target~=target.id or state.index~=target.index or state.pool~=pool then
        state={target=target.id,index=target.index,pool=pool,used={},visited={},landed={}}
        owner[policy.stateKey]=state
    end
    if red.triggered and not state.triggered then
        state.triggered=true
    end
    if red.triggered and config.on_stagger~='full_rotation' then return end
    if state.element~=element then
        state.element=element; state.visited={};state.pending=nil;state.settleUntil=nil;state.diagnostic=nil
        state.retryAt=nil;state.nextSwapAt=nil;state.usableInPass=nil
        state.exhausted=nil
        state.retryPending=nil;state.probeFailed=nil
        if not element then deps.log(policy.color:upper()..' PROC search: all candidates.') end
    end
    local setName=config.weapon_set_name or config.weapons
    if state.weaponSet~=setName then
        state.weaponSet=setName; state.visited={}; state.pending=nil
        state.retryAt=nil;state.nextSwapAt=nil;state.usableInPass=nil
        state.exhausted=nil
        state.retryPending=nil;state.probeFailed=nil
    end
    local wanted=policy.slot and policy.slot(element)
    if wanted and state.slot~=wanted then
        state.slot=wanted;state.lastWeapon=nil;state.pending=nil
    end
    local current=deps.current(state.slot or 'main')
    -- Empty/unavailable current equipment must not prevent selecting a configured
    -- weapon (especially a blue archery hint with no ranged weapon equipped).
    current=current or {id=0,key='empty:'..(state.slot or 'main'),skill=0}
    current.skill=current.skill or 0
    local identity=current.key or current.id
    if state.lastWeapon and state.lastWeapon~=identity then
        if not state.pending or identity~=(state.pending.key or state.pending.id) then
            -- A manual/GearSwap change supersedes an outstanding rotation swap.
            -- Keep completed attempts, but let equipment/abilities settle before
            -- using or replacing the externally selected weapon.
            state.pending=nil
            state.visited={}
            state.settleUntil=deps.clock()+2
            state.retryAt=nil;state.nextSwapAt=nil
            state.exhausted=nil
            state.retryPending=nil;state.probeFailed=nil
        end
    end
    state.lastWeapon=identity
    if state.retryAt and deps.clock()<state.retryAt then return end
    if state.exhausted or state.retryPending then
        state.exhausted=nil;state.retryPending=nil;state.probeFailed=nil;state.retryAt=nil;state.visited={};state.used={}
    end
    if state.settleUntil and deps.clock()<state.settleUntil then return end
    -- Wait for the requested main weapon to be acknowledged, then for abilities
    -- to refresh. Never infer readiness from the desired equipment alone.
    if state.pending then
        if identity~=(state.pending.key or state.pending.id) then
            if deps.clock()-state.pending.time<(config.equip_timeout or 10) then return end
            deps.log(policy.color:upper()..' PROC swap not confirmed:',state.pending.name or state.pending.id)
            state.probeFailed=true
            state.visited[state.pending.key or state.pending.id]=true
            state.pending=nil
        else
            if not state.pending.confirmedAt then
                state.pending.confirmedAt=deps.clock()
                if deps.debug then deps.debug(policy.color:upper()..' PROC equipped: '..tostring(state.pending.name or state.pending.id)..
                    ' - waiting for weapon skills to refresh.') end
            end
            if deps.clock()-state.pending.confirmedAt<(config.refresh_delay or 2) then return end
            state.pending=nil
        end
    end
    local usable=deps.usable(policy.candidates(config,element,deps.resource,current.skill))
    local checked=identity..':'..tostring(element)..':'..table.concat(usable,',')
    if state.checked~=checked then
        state.checked=checked
        if deps.debug then deps.debug(policy.color:upper()..' PROC weapon skills checked: '..tostring(current.name or current.id)..' - '..#usable..' usable candidate(s).') end
    end
    if #usable>0 then state.usableInPass=true end
    for _,name in ipairs(usable) do
        if not state.used[name] then
            if deps.ready(name) then
                -- Recheck observations immediately before dispatch, after waits.
                if deps.allowed() then
                    state.waitReason=nil
                    state.diagnostic=nil
                    deps.log('Using '..policy.color:upper()..' PROC weapon skill:',name)
                    local landed=deps.use(name)
                    -- Track attempts for rotation order, not elimination. Even a
                    -- miss/unknown result advances the pass and is retried later.
                    state.used[name]=true
                    if landed then state.landed[name]=true end
                end
            else
                local reason=deps.waitReason and deps.waitReason(name) or 'weapon skill is not ready'
                local message=reason..' ('..name..')'
                if state.waitReason~=message then
                    state.waitReason=message
                    deps.log(policy.color:upper()..' PROC waiting:',message)
                end
            end
            return -- Keep this weapon while waiting for TP or range.
        end
    end
    state.visited[identity]=true
    for _,slot in ipairs(policy.slots or {}) do
        if slot~=(state.slot or 'main') then
            local equipped=deps.current(slot)
            if equipped and not state.visited[equipped.key or equipped.id]
                and #policy.candidates(config,element,deps.resource,equipped.skill)>0 then
                state.slot=slot;state.lastWeapon=nil;return
            end
        end
    end
    local weapons=config.weapons
    local skipped={}
    for index,gear in ipairs(type(weapons)=='table' and weapons or {}) do
        local item,why=deps.resolve(gear,wanted)
        local reference=type(gear)=='table' and (gear.main or gear.range or gear) or gear
        local label=type(reference)=='table' and (reference.name or reference.equipment or reference.gear) or reference
        if type(label)~='string' then label='set '..index end
        if not item and why then skipped[#skipped+1]=label..': '..why end
        if item and not state.visited[item.key or item.id] and #policy.candidates(config,element,deps.resource,item.skill)>0 then
            if state.nextSwapAt and deps.clock()<state.nextSwapAt then return end
            -- Confirm this set can actually change equipment before waiting on it.
            if deps.equip(gear,item.slot) then
                state.nextSwapAt=deps.clock()+(config.swap_delay or 5)
                state.diagnostic=nil
                deps.log(policy.color:upper()..' PROC swap requested:',item.name or item.id)
                if item.slot and item.slot~=state.slot then state.slot=item.slot;state.lastWeapon=nil end
                state.pending={id=item.id,key=item.key,name=item.name,time=deps.clock()}; return
            end
            skipped[#skipped+1]=(item.name or label)..': equipment request made no changes'
            state.probeFailed=true
            state.visited[item.key or item.id]=true
        end
    end
    local reason
    if state.probeFailed then
        reason='pass incomplete: an equipment swap failed or was not confirmed; will retry.'
    elseif #policy.candidates(config,element,deps.resource)==0 then
        reason='no WS in the supplied pool match '..tostring(element or 'the search')..'.'
    elseif #usable>0 then
        reason='all current candidates attempted; starting another pass.'
    elseif type(weapons)~='table' or #weapons==0 then
        reason='no matching WS on current equipment and no rotation weapons supplied.'
    else
        reason='no further available configured weapons match the current candidates; starting another pass.'
    end
    if #skipped>0 then reason=reason..' Skipped: '..table.concat(skipped,'; ') end
    if state.diagnostic~=reason then
        state.diagnostic=reason
        deps.log(policy.color:upper()..' PROC rotation:',reason)
    end
    if not state.usableInPass or state.probeFailed then
        state.exhausted=not state.probeFailed
        state.retryPending=not not state.probeFailed
        state.retryAt=deps.clock()+(config.empty_pass_delay or 10)
    end
    state.usableInPass=nil
    -- Every candidate is eligible again, regardless of prior hit/miss outcomes.
    if not state.exhausted and not state.retryPending then state.used={};state.visited={} end
end
return Rotation
