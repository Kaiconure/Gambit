-- Windower adapter: listeners owned here, independent of action selection.
local Config=require('./lib/events/config')
local Runtime=require('./lib/events/runtime')
local paths=require('./lib/settings-paths')
local json=require('./lib/jsonlua')
local selectors=require('./lib/target-selectors')
local magicSkills=require('./meta/magic-skills')
local cureSpell=require('./lib/cure-spell')
local Service={}
Service.__index=Service
local outgoing={ [3]={'spell','spells'},[7]={'weapon_skill','weapon_skills'},[9]={'job_ability','job_abilities'} }
-- The high bit is a message flag, not part of the resource message ID.
local function messageId(value) return (tonumber(value) or 0)%32768 end
local rejected={ [17]=true,[18]=true,[55]=true,[56]=true,[78]=true,[84]=true,
    [87]=true,[88]=true,[89]=true,[90]=true,[94]=true,[104]=true,[191]=true,
    [308]=true,[313]=true,[325]=true,[428]=true,[429]=true }
function Service.new(deps)
    local self=setmetatable({deps=deps,listeners={},injections={}},Service)
    local function listen(name,fn)
        self.listeners[#self.listeners+1]=deps.windower.register_event(name,function(...)
            local ok,result=pcall(fn,...)
            if not ok then deps.report('Event listener '..name..': '..tostring(result)); return end
            return result
        end)
    end
    listen('outgoing chunk',function(...) return self:outgoing(...) end)
    listen('action',function(action) self:action(action) end)
    listen('incoming chunk',function(...) self:incoming(...) end)
    listen('prerender',function() if self.runtime then self.runtime:tick() end end)
    listen('logout',function() self:clear('logout'); self.runtime=nil end)
    listen('zone change',function() self:clear('zoned') end)
    return self
end
function Service:reload()
    local deps=self.deps
    local player=deps.windower.ffxi.get_player()
    if not player then self:clear('reloaded'); self.runtime=nil; return end
    local read=deps.read or function(path)
        local file=io.open((deps.windower.addon_path or '')..path,'r')
        if not file then return nil end
        local source=file:read('*a'); file:close()
        local ok,value=pcall(json.parse,source)
        assert(ok,path..': '..tostring(value))
        return value
    end
    local party=deps.windower.ffxi.get_party and deps.windower.ffxi.get_party() or {}
    local groups=selectors.entryPointGroups(player.main_job,party.party1_leader==player.id)
    local config=Config.load(paths.eventFiles(player.name,player.main_job,groups),read,deps.report)
    -- Load/compile completely before replacing the active configuration.
    self:clear('reloaded')
    self.runtime=Runtime.new(config,{context=deps.context,report=deps.report,
        clock=deps.clock or os.clock,schedule=deps.schedule,barrier=deps.barrier,equipmentSession=deps.equipmentSession})
    if deps.announce then
        local path=config.path and (deps.formatPath and deps.formatPath(config.path) or config.path)
        deps.announce(path and ('Active event file: '..path) or 'No active event file (no matching file found).')
        for _,file in ipairs(config.vars_files) do
            deps.announce('Event variables: '..(deps.formatPath and deps.formatPath(file) or file))
        end
    end
    return config
end
function Service:clear(outcome)
    if self.runtime then self.runtime:clear(outcome) end
end
function Service:pruneInjections()
    local now=(self.deps.clock or os.clock)()
    for i=#self.injections,1,-1 do
        if self.injections[i].expires<now then table.remove(self.injections,i) end
    end
end
function Service:consumeInjection(original,modified)
    self:pruneInjections()
    -- Header sequence bytes may change when Windower queues the packet. Match
    -- the payload, with one permit per injection, rather than a call-stack flag.
    local first=original and original:sub(5)
    local second=modified and modified:sub(5)
    for i,permit in ipairs(self.injections) do
        if permit.payload==first or permit.payload==second then
            table.remove(self.injections,i)
            return true
        end
    end
end
function Service:inject(packet)
    self:pruneInjections()
    local permit={payload=self.deps.packets.build(packet):sub(5),expires=(self.deps.clock or os.clock)()+10}
    if #self.injections>=128 then table.remove(self.injections,1) end
    self.injections[#self.injections+1]=permit
    local ok,err=pcall(self.deps.packets.inject,packet)
    if not ok then
        for i=#self.injections,1,-1 do
            if self.injections[i]==permit then table.remove(self.injections,i) end
        end
        error(err)
    end
    return true
end
function Service:outgoing(id,original,modified,injected,blocked)
    if id~=0x01A then return end
    if injected and self:consumeInjection(original,modified) then return end
    if blocked or not self.runtime then return end
    local deps=self.deps
    local packet=deps.packets.parse('outgoing',modified or original)
    local mapping=outgoing[packet.Category]
    if not mapping then return end
    local section=mapping[2]
    local rules=self.runtime.config.rules[section]
    if #rules.pre+#rules.mid+#rules.post==0 then
        -- Normal command-driven actions also honor already-queued gear, even
        -- when this action type has no event rules.
        if self.deps.equipmentPending and self.deps.equipmentPending() then
            self.deps.barrier(function(ready)
                if ready then self:inject(packet) end
            end)
            return true
        end
        return
    end
    local player=deps.windower.ffxi.get_player()
    local resource=deps.resources[mapping[2]][packet.Param]
    if not player or not resource then return end
    -- Positive client recasts prove this request cannot run. Missing timer data
    -- is not evidence of unavailability, and charge-based JAs need their helper.
    if packet.Category==3 and deps.windower.ffxi.get_spell_recasts then
        local timers=deps.windower.ffxi.get_spell_recasts()
        local remaining=timers and timers[resource.recast_id]
        if type(remaining)=='number' and remaining>0 then return true end
    elseif packet.Category==9 and deps.abilityReady then
        if deps.abilityReady(player,resource)==false then return true end
    end
    local target=deps.windower.ffxi.get_mob_by_id(packet.Target)
    local element=deps.resources.elements and deps.resources.elements[resource.element]
    local skill=deps.resources.skills and deps.resources.skills[resource.skill]
    local event={
        kind=mapping[1],
        id=resource.id,
        name=resource.en,
        actor_id=player.id,
        type=resource.type,
        element=resource.element,
        element_name=element and element.en,
        skill=resource.skill,
        skill_name=skill and skill.en,
        target={
            id=packet.Target,
            index=target and target.index or packet['Target Index'],
            name=target and target.name
        },
        injected=not not injected
    }
    if event.kind=='spell' then
        for name,id in pairs(magicSkills) do event[name]=resource.skill==id end
        event.curing=cureSpell(resource)
    end
    return self.runtime:submit(event,function()
        local current=deps.windower.ffxi.get_player()
        local mob=deps.windower.ffxi.get_mob_by_id(event.target.id)
        if not current or current.id~=player.id or not mob or not mob.valid_target then return false end
        packet['Target Index']=mob.index
        return self:inject(packet)
    end)
end
-- Gambit's explicit packet dispatch goes through here too: it does not depend
-- on whether Windower echoes an addon's own injections to its chunk listener.
function Service:send(packet)
    local raw=self.deps.packets.build(packet)
    if self:outgoing(0x01A,raw,raw,true,false) then return true end
    if self.deps.barrier then
        self.deps.barrier(function(ready)
            if ready then self:inject(packet) else self.deps.report('Action withheld after equipment failure') end
        end)
        return true
    end
    return self:inject(packet)
end
function Service:action(action)
    if not self.runtime or not action then return end
    local player=self.deps.windower.ffxi.get_player()
    if not player or action.actor_id~=player.id then return end
    local category=action.category
    if category==8 and action.param==28787 then
        self.runtime:complete('spell',nil,nil,'interrupted')
        return
    end
    local kind=category==4 and 'spell' or (category==6 or category==14) and 'job_ability'
        or category==3 and 'weapon_skill'
    if kind then
        -- AoE result order need not match the selected target: match resource.
        local first=action.targets and action.targets[1]
        local detail=first and first.actions and first.actions[1]
        local failed=detail and rejected[messageId(detail.message)]
        local matched=self.runtime:complete(kind,action.param,nil,failed and 'failed' or 'completed')
        -- Double-Up is requested as ability 123, but the server reports the
        -- resulting CorsairRoll resource. Prefer an exact roll request first;
        -- only a dispatched Double-Up may consume the unmatched roll result.
        local ability=kind=='job_ability' and self.deps.resources.job_abilities[action.param]
        if not matched and ability and ability.type=='CorsairRoll' then
            matched=self.runtime:complete('job_ability',123,nil,failed and 'failed' or 'completed')
        end
        if failed and not matched then self:reject(kind) end
    end
end
-- Common explicit rejection messages. Unknown failures expire via timeout;
-- do not interpret every action message as a terminal result.
function Service:reject(kind)
    -- These messages do not consistently identify resource type/ID. Only
    -- correlate when exactly one dispatched request is awaiting a result.
    local candidate
    for _,request in ipairs(self.runtime.pending) do
        if request.sent_at and (not kind or request.event.kind==kind) then
            if candidate then return end
            candidate=request
        end
    end
    if candidate then self.runtime:finish(candidate,'failed') end
end
function Service:incoming(id,original,modified,injected,blocked)
    if id~=0x029 or injected or not self.runtime then return end
    -- Blocking a message's display does not undo the server's rejection.
    local packet=self.deps.packets.parse('incoming',original or modified)
    local player=self.deps.windower.ffxi.get_player()
    if not player or packet.Actor~=player.id or not rejected[messageId(packet.Message)] then return end
    self:reject()
end
function Service:destroy()
    self:clear('unloaded')
    self.runtime=nil
    for _,id in ipairs(self.listeners) do self.deps.windower.unregister_event(id) end
    self.listeners={}
end
return Service
