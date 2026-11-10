-- Windower adapter: listeners owned here, independent of action selection.
local Config=require('./lib/events/config')
local Runtime=require('./lib/events/runtime')
local paths=require('./lib/settings-paths')
local json=require('./lib/jsonlua')
local selectors=require('./lib/target-selectors')
local magicSkills=require('./meta/magic-skills')
local cureSpell=require('./lib/cure-spell')
local targetMetadata=require('./lib/target-metadata')
local pets=require('./lib/events/pets')
local enemies=require('./lib/events/enemies')
local partyWeaponSkills=require('./lib/events/party-weapon-skills')
local observations=require('./lib/action-observation')
local actionWait=require('./lib/action-wait')
local trace=require('./lib/events/weapon-skill-trace')
local verify=require('./lib/events/verification')
local discovery=require('./lib/events/discovery')
local Service={}
Service.__index=Service
local outgoing={ [3]={'spell','spells'},[7]={'weapon_skill','weapon_skills'},[9]={'job_ability','job_abilities'} }
-- The high bit is a message flag, not part of the resource message ID.
local function messageId(value) return (tonumber(value) or 0)%32768 end
local function dispatchAllowed(observation)
    if not observation then return true end
    if observation.abandoned or (observation.validate and not observation.validate()) then
        observation.outcome='cancelled'
        return false
    end
    return true
end
local rejected={ [17]=true,[18]=true,[55]=true,[56]=true,[78]=true,[84]=true,
    [87]=true,[88]=true,[89]=true,[90]=true,[94]=true,[104]=true,[191]=true,
    [308]=true,[313]=true,[325]=true,[428]=true,[429]=true }
function Service.new(deps)
    if deps.reactions then require('./lib/reactions').attach(deps.reactions) end
    local self=setmetatable({deps=deps,listeners={},injections={}},Service)
    local function listen(name,fn)
        self.listeners[#self.listeners+1]=deps.windower.register_event(name,function(...)
            local ok,result=pcall(fn,...)
            if not ok then deps.report('Event listener '..name..': '..tostring(result)); return end
            return result
        end)
    end
    listen('outgoing chunk',function(id,original,modified,injected,blocked)
        local result=self:outgoing(id,original,modified,injected,blocked)
        if discovery.active() then discovery.packet(id,original,modified,injected,blocked or result,deps,'outgoing') end
        return result
    end)
    listen('action',function(action)
        if self.encounterAction then self.encounterAction(action) end
        self:action(action)
    end)
    listen('incoming chunk',function(id,original,modified,injected,blocked)
        self:incoming(id,original,modified,injected,blocked)
        if self.weaknessIncoming then self.weaknessIncoming(id,original,modified,injected) end
        if self.transitionIncoming then self.transitionIncoming(id,original,modified,injected,blocked) end
        if discovery.active() then discovery.packet(id,original,modified,injected,blocked,deps) end
    end)
    listen('incoming text',function(original,modified,mode)
        if self.weaknessText then self.weaknessText(original) end
        if self.encounterText then self.encounterText(original) end
        if discovery.active() then
            local data=discovery.context(deps.windower.ffxi)
            data.original=original; data.modified=modified; data.mode=mode
            discovery.record('text',data)
        end
    end)
    listen('prerender',function()
        if deps.reactions then require('./lib/reactions').tick() end
        if self.weaknessTick then self.weaknessTick() end
        if verify.active() then verify.tick() end
        self:loadingTick()
        pets.tick(self)
        self:validatePendingTargets()
        if self.runtime then self.runtime:tick() end
        if self.transitionTick then self.transitionTick() end
    end)
    listen('logout',function()
        if self.weaknessClear then self.weaknessClear() end
        if self.encounterClear then self.encounterClear() end
        self:clear('logout'); self.runtime=nil
        if self.transitionLogout then self.transitionLogout() end
    end)
    require('./lib/events/transitions').attach(self,listen)
    require('./lib/events/buffs').attach(self,listen)
    require('./lib/events/abyssea').attach(self,listen)
    require('./lib/encounter-state').attach(self,listen)
    return self
end
function Service:verification(command)
    if command=='start' then
        assert(self.deps.verifyEquipment and self.deps.verifyReport,'Equipment verification is unavailable')
        verify.start({clock=self.deps.clock,snapshot=self.deps.verifyEquipment,report=self.deps.verifyReport})
        return 'Event equipment verification started.'
    elseif command=='stop' then
        verify.stop()
        return 'Event equipment verification stopped.'
    end
    return 'Usage: gbt events verify [start|stop]'
end
function Service:reload(outputProcessed,entryName)
    local deps=self.deps
    local player=deps.windower.ffxi.get_player()
    if not player then
        self:clear('reloaded')
        if deps.clearEquipmentLocks then deps.clearEquipmentLocks() end
        self.runtime=nil; self.selectedFile=nil; return
    end
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
    local config=Config.load(paths.eventFiles(player.name,player.main_job,groups),read,deps.report,function(required)
        return selectors.matchesPlayer(player,required,party.party1_leader==player.id)
    end,entryName,function(source)
        return math.floor(require('./lib/action-slots').priority(source or '',
            paths.getLoadedPrecedence(),player.name,player.main_job)/10)
    end)
    if outputProcessed and config.path and deps.writeProcessed then
        local name=config.path:match('([^/]+)%.json$') or player.main_job:lower()
        local outputPath=paths.writePath(player.name,'.output/'..name..'.events.processed.json')
        local ok,err=pcall(function()
            deps.writeProcessed(outputPath,require('./lib/events/processed')(config))
        end)
        if not ok then deps.report('Could not write processed events: '..tostring(err)) end
    end
    -- Load/compile completely before replacing the active configuration.
    self:clear('reloaded')
    if deps.clearEquipmentLocks then deps.clearEquipmentLocks() end
    self.selectedFile=entryName
    self.runtime=Runtime.new(config,{context=deps.context,report=deps.report,
        debug=function(message,lostLifecycle)
            if deps.debug then deps.debug(message) end
            if lostLifecycle and deps.diagnostic then deps.diagnostic(message) end
        end,
        retryReady=function(event)
            if event.kind~='job_ability' or not deps.abilityReady then return end
            local ability=deps.resources.job_abilities[event.id]
            -- A recharge timer cannot prove that a charged action failed.
            if not ability or ability.recast_id==102 or ability.recast_id==195 or ability.recast_id==231 then return end
            local player=deps.windower.ffxi.get_player()
            if player then return deps.abilityReady(player,ability) end
        end,
        clock=deps.clock or os.clock,schedule=deps.schedule,barrier=deps.barrier,equipmentSession=deps.equipmentSession,
        traceEquipment=deps.traceEquipment,
        targetSnapshot=function(target) return targetMetadata.refresh(target,deps.windower.ffxi) end})
    self.loadingPending=self.runtime
    self:loadingTick()
    if deps.announce then
        local path=config.path and (deps.formatPath and deps.formatPath(config.path) or config.path)
        deps.announce(path and ('Active event file: '..path) or 'No active event file (no matching file found).')
    end
    if deps.debug then
        for _,file in ipairs(config.files) do
            if file~=config.path then
                deps.debug('Event import: '..(deps.formatPath and deps.formatPath(file) or file))
            end
        end
        for _,file in ipairs(config.vars_files) do
            deps.debug('Event variables: '..(deps.formatPath and deps.formatPath(file) or file))
        end
    end
    return config
end
function Service:weaponSkillTrace(command)
    if command=='start' then
        trace.start(self.deps.clock)
        return 'Weapon skill trace started (maximum 2048 entries).'
    end
    if command~='stop' then return 'Usage: gbt events trace [start|stop]' end
    local result=trace.stop()
    if not result then return 'No weapon skill trace is active.' end
    local player=self.deps.windower.ffxi.get_player()
    assert(player and self.deps.writeProcessed,'A logged-in character and trace file writer are required')
    local path=paths.writePath(player.name,'.output/ws-trace-'..os.date('%Y%m%d-%H%M%S')..'.json')
    self.deps.writeProcessed(path,result)
    return 'Weapon skill trace saved: '..path
end
function Service:discovery(command)
    local deps=self.deps
    local player=deps.windower.ffxi.get_player()
    if command=='start' then
        if self.discoveryResult then return 'Save the pending discovery recording with gbt events discover stop first.' end
        if not player then return 'Log in before starting a discovery recording.' end
        local metadata=discovery.context(deps.windower.ffxi)
        metadata.player={id=player.id,name=player.name}
        metadata.started_at=os.date('!%Y-%m-%dT%H:%M:%SZ')
        if not discovery.start(deps.clock,metadata) then return 'A discovery recording already exists; stop/save it first.' end
        return 'Discovery recording started (maximum 8192 entries). Reproduce hints/procs, then use gbt events discover stop.'
    end
    if command~='stop' then return 'Usage: gbt events discover [start|stop]' end
    self.discoveryResult=self.discoveryResult or discovery.stop()
    if not self.discoveryResult then return 'No discovery recording is active.' end
    local write=deps.writeDiscovery or deps.writeProcessed
    assert(write,'Discovery file writer is unavailable')
    self.discoverySequence=(self.discoverySequence or 0)+1
    local name=self.discoveryResult.metadata.player.name
    local path=paths.writePath(name,'.output/discovery-'..os.date('%Y%m%d-%H%M%S')..'-'..self.discoverySequence..'.json')
    write(path,self.discoveryResult)
    local truncated=self.discoveryResult.truncated
    self.discoveryResult=nil
    return 'Discovery recording saved: '..path..(truncated and ' (entry limit reached; capture truncated)' or '')
end
function Service:loadingTick()
    local runtime=self.loadingPending
    if not runtime or runtime~=self.runtime then return end
    local deps=self.deps
    local ffxi=deps.windower.ffxi
    local player=ffxi.get_player()
    if not player then return end
    if ffxi.get_info then
        local info=ffxi.get_info()
        if not info or info.logged_in==false or info.zone==0 then return end
    end
    if ffxi.get_mob_by_target then
        local mob=ffxi.get_mob_by_target('me')
        if not mob or mob.id~=player.id or not mob.valid_target then return end
    end
    if deps.zoneReady and not deps.zoneReady() then return end
    self.loadingPending=nil
    runtime:loading()
end
function Service:clear(outcome)
    if self.deps.reactions then require('./lib/reactions').clear(outcome) end
    actionWait.clear(outcome,(self.deps.clock or os.clock)())
    if outcome=='reloaded' or outcome=='logout' or outcome=='unloaded' then self.loadingPending=nil end
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
    local mapping=outgoing[packet.Category]
    if mapping and require('./lib/reactions').blocksAction(mapping[1],
        self.deps.resources[mapping[2]] and self.deps.resources[mapping[2]][packet.Param]) then return false end
    if trace.active() and packet.Category==7 then
        trace.record('action_inject',{id=packet.Param,target=packet.Target,
            equipment=self.deps.traceEquipment and self.deps.traceEquipment()})
    end
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
function Service:outgoing(id,original,modified,injected,blocked,observation)
    if id~=0x01A then return end
    if trace.active() then
        local packet=self.deps.packets.parse('outgoing',modified or original)
        if packet.Category==7 then
            local data=modified or original
            trace.record('outgoing_action_observed',{packet=id,id=packet.Param,target=packet.Target,
                injected=not not injected,blocked_on_entry=not not blocked,
                sequence=type(data)=='string' and #data>=4 and (data:byte(3)+data:byte(4)*256) or nil})
        end
    end
    if injected and self:consumeInjection(original,modified) then return end
    if blocked or not self.runtime then return end
    local deps=self.deps
    local packet=deps.packets.parse('outgoing',modified or original)
    local mapping=outgoing[packet.Category]
    if not mapping then return end
    local resource=deps.resources[mapping[2]] and deps.resources[mapping[2]][packet.Param]
    if require('./lib/reactions').blocksAction(mapping[1],resource) then return true end
    if packet.Category==9 and resource and resource.prefix=='/pet' then mapping={'pet_ability','pet_abilities'} end
    local section=mapping[2]
    local rules=self.runtime.config.rules[section]
    if #rules.pre+#rules.mid+#rules.post==0 then
        -- Normal command-driven actions also honor already-queued gear, even
        -- when this action type has no event rules.
        if self.deps.equipmentPending and self.deps.equipmentPending() then
            if observation then observation.queued=true end
            self.deps.barrier(function(ready)
                if not dispatchAllowed(observation) then return end
                if ready then
                    if observation then observation.sent_at=(self.deps.clock or os.clock)() end
                    self:inject(packet)
                elseif observation then observation.outcome='failed' end
            end)
            return true
        end
        return
    end
    local player=deps.windower.ffxi.get_player()
    if not player or not resource then return end
    local pet=mapping[1]=='pet_ability' and pets.current(deps.windower.ffxi)
    if mapping[1]=='pet_ability' and not pet then return true end
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
        cast_time=mapping[1]=='spell' and resource.cast_time or nil,
        actor_id=player.id,
        actor=targetMetadata.snapshot({id=player.id,name=player.name},deps.windower.ffxi.get_mob_by_id(player.id),player.id),
        pet=pet and {id=pet.id,index=pet.index,name=pet.name} or nil,
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
    if event.kind=='weapon_skill' then
        require('./lib/weapon-skill-result').properties(event,resource)
        event.actor.is_party_member=true
        event.actor.is_alliance_member=true
    end
    event.target=targetMetadata.snapshot(event.target,target,player.id)
    return self.runtime:submit(event,function()
        if not dispatchAllowed(observation) then return false end
        local current=deps.windower.ffxi.get_player()
        local mob=deps.windower.ffxi.get_mob_by_id(event.target.id)
        if not current or current.id~=player.id or not mob or not mob.valid_target then return false end
        if pet then
            local live=pets.current(deps.windower.ffxi)
            if not live or live.id~=pet.id then return false end
        end
        packet['Target Index']=mob.index
        return self:inject(packet)
    end,observation)
end
-- Gambit's explicit packet dispatch goes through here too: it does not depend
-- on whether Windower echoes an addon's own injections to its chunk listener.
function Service:send(packet,observation)
    if not dispatchAllowed(observation) then return false end
    local raw=self.deps.packets.build(packet)
    if self:outgoing(0x01A,raw,raw,true,false,observation) then
        if observation and not observation.sent_at and not observation.outcome then
            -- A lifecycle may be pending behind equipment; its dispatch will set sent_at.
            local pending=false
            for _,request in ipairs(self.runtime and self.runtime.pending or {}) do
                if request.observation==observation then pending=true; break end
            end
            if not pending and not observation.queued then observation.outcome='cancelled' end
        end
        return true
    end
    if self.deps.barrier then
        self.deps.barrier(function(ready)
            if not dispatchAllowed(observation) then return end
            if ready then
                if observation then observation.sent_at=(self.deps.clock or os.clock)() end
                self:inject(packet)
            else
                if observation then observation.outcome='failed' end
                self.deps.report('Action withheld after equipment failure')
            end
        end)
        return true
    end
    if observation then observation.sent_at=(self.deps.clock or os.clock)() end
    return self:inject(packet)
end
function Service:enemyAction(action)
    return enemies.action(self,action,rejected)
end
function Service:selfSpellAction(action)
    local observation=observations.selfSpell(action,self.deps.windower.ffxi,self.deps.resources,rejected)
    if not observation then return false end
    actionWait.observe(observation,(self.deps.clock or os.clock)())
    if self.runtime and pets.action(self,action) then return true end
    if self.deps.observeSelfSpell then self.deps.observeSelfSpell(observation) end
    if self.runtime then
        if observation.phase=='mid' then
            if observation.detail then self.runtime:spellStarted(observation.id,observation.target_id) end
        else
            local matched=self.runtime:complete('spell',observation.id,nil,observation.outcome)
            if observation.outcome=='failed' and not matched then
                self:reject('spell',messageId(observation.detail.message))
            end
        end
    end
    if self.deps.afterSelfSpell then self.deps.afterSelfSpell(observation) end
    return true
end
function Service:selfResultAction(action)
    local observation=observations.selfResult(action,self.deps.windower.ffxi,self.deps.resources,rejected)
    if not observation then return false end
    actionWait.observe(observation,(self.deps.clock or os.clock)())
    if trace.active() and observation.kind=='weapon_skill' then
        trace.record('result',{id=observation.id,outcome=observation.outcome,target=observation.target_id,
            equipment=self.deps.traceEquipment and self.deps.traceEquipment()})
    end
    if self.deps.observeSelfResult then self.deps.observeSelfResult(observation) end
    if self.runtime then
        if pets.action(self,action) then return observation end
        if observation.kind=='weapon_skill' then
            self.wsObservedTargets=self.wsObservedTargets or setmetatable({}, {__mode='k'})
            for _,request in ipairs(self.runtime.pending) do
                local event=request.event
                if request.sent_at and event.kind=='weapon_skill' and event.id==observation.id
                    and event.target and require('./lib/weapon-skill-result').find(observation.results,event.target.id) then
                    self.wsObservedTargets[action]=event.target.id;break
                end
            end
        end
        local matched=self.runtime:complete(observation.kind,observation.id,nil,observation.outcome,observation.results,observation.resource)
        if not matched and observation.kind=='weapon_skill' then
            -- A visible self WS still has a post result if its outgoing request
            -- was not observed. Do not duplicate an existing lifecycle's post.
            partyWeaponSkills.action(self,action,rejected,true)
        end
        -- The server reports the roll resource for Double-Up. Exact roll
        -- matching wins; only then try an outstanding dispatched Double-Up.
        local ability=observation.kind=='job_ability' and observation.resource
        if not matched and ability and ability.type=='CorsairRoll' then
            matched=self.runtime:complete('job_ability',123,nil,observation.outcome)
        end
        if observation.outcome=='failed' and not matched then self:reject(observation.kind,observation.message) end
    end
    return observation
end
function Service:action(action)
    if not action then return end
    partyWeaponSkills.action(self,action,rejected)
    if discovery.active() then discovery.action(action,self.deps.windower.ffxi,self.deps.resources) end
    if self.deps.externalSelfResults and (action.category==3 or action.category==6 or action.category==14) then
        local player=self.deps.windower.ffxi.get_player()
        if player and action.actor_id==player.id then return end
    end
    if not self.deps.externalSelfResults and self:selfResultAction(action) then return end
    if self.deps.externalSelfSpells and (action.category==4 or action.category==8) then
        local player=self.deps.windower.ffxi.get_player()
        if player and action.actor_id==player.id then return end
    end
    if not self.deps.externalSelfSpells and self:selfSpellAction(action) then return end
    if not self.deps.externalEnemyActions and self:enemyAction(action) then return end
    if not self.runtime then return end
    if pets.action(self,action) then return end
end
-- Common explicit rejection messages. Unknown failures expire via timeout;
-- do not interpret every action message as a terminal result.
function Service:reject(kind,rejectionMessage)
    actionWait.reject(kind,(self.deps.clock or os.clock)())
    if not self.runtime then return end
    -- These messages do not consistently identify resource type/ID. Prefer a
    -- sole candidate, or a clearly newer recent dispatch; otherwise wait.
    local candidate,previous
    for _,request in ipairs(self.runtime.pending) do
        if request.sent_at and (not kind or request.event.kind==kind) then
            if not candidate or request.sent_at>candidate.sent_at then
                previous=candidate; candidate=request
            elseif not previous or request.sent_at>previous.sent_at then previous=request end
        end
    end
    if previous then
        -- Only prefer a newer dispatch when it is recent and clearly separated.
        -- Near-simultaneous requests remain ambiguous, including pet commands.
        local now=(self.deps.clock or os.clock)()
        if now-candidate.sent_at>2 or candidate.sent_at-previous.sent_at<0.25 then return end
    end
    if candidate then
        self.runtime:diagnostic(candidate,'recognized server rejection'..
            (rejectionMessage and (' (message '..tostring(rejectionMessage)..')') or '')..
            '; running post cleanup')
        self.runtime:finish(candidate,'failed')
    end
end
function Service:validatePendingTargets()
    if not self.runtime or #self.runtime.pending==0 then return end
    local pending={}
    for _,request in ipairs(self.runtime.pending) do pending[#pending+1]=request end
    for _,request in ipairs(pending) do
        local target=request.event.target
        if target and target.is_mob and target.id then
            local mob=self.deps.windower.ffxi.get_mob_by_id(target.id)
            if not mob or not mob.valid_target or mob.hpp==0 or mob.status==2 or mob.status==3 then
                self.runtime:diagnostic(request,'target unavailable; running post cleanup')
                self.runtime:finish(request,'failed')
            end
        end
    end
end
function Service:incoming(id,original,modified,injected,blocked)
    if id~=0x029 or injected then return end
    -- Blocking a message's display does not undo the server's rejection.
    local packet=self.deps.packets.parse('incoming',original or modified)
    if self.runtime and pets.incoming(self,packet) then return end
    local player=self.deps.windower.ffxi.get_player()
    if not player or packet.Actor~=player.id or not rejected[messageId(packet.Message)] then return end
    self:reject(nil,messageId(packet.Message))
end
function Service:destroy()
    if self.weaknessClear then self.weaknessClear() end
    discovery.stop()
    self:clear('unloaded')
    if verify.active() then verify.stop() end
    self.runtime=nil
    for _,id in ipairs(self.listeners) do self.deps.windower.unregister_event(id) end
    self.listeners={}
end
return Service
