-- Configurable observational state. No encounter names, phases or combat policy.
local copy=require('./lib/variable-values').copy
local factory=require('./lib/execution-factory')
local aliases=require('./lib/resource-name-aliases')
local M={}
local trackers={}
local clock=os.clock
local function fields(value,label)
    assert(value==nil or type(value)=='table',label..' must be an object')
    for key,item in pairs(value or {}) do
        assert(type(key)=='string' and (type(item)=='string' or type(item)=='number' or type(item)=='boolean'),
            label..' requires named scalar fields')
    end
end
function M.clear() for _,t in pairs(trackers) do t.records={} end end
-- Definitions belong to the loaded actions; loading actions register them again.
function M.reset() trackers={} end
function M.remove(name) trackers[name]=nil end
function M.configure(name,definition,parameters)
    assert(type(name)=='string' and name~='', 'Encounter tracker requires a name')
    assert(type(definition)=='table' and type(definition.actors)=='table', 'Encounter tracker requires actors')
    definition=copy(definition)
    for actor,spec in pairs(definition.actors) do
        assert(type(actor)=='string' and type(spec)=='table', 'Invalid encounter actor')
        assert(spec.text_aliases==nil or type(spec.text_aliases)=='table','text_aliases must be an array')
        for _,alias in ipairs(spec.text_aliases or {}) do
            assert(type(alias)=='string' and alias~='', 'Text aliases must be non-empty strings')
        end
        fields(spec.initial,'initial')
        assert(spec.rules==nil or type(spec.rules)=='table','rules must be an array')
        for _,rule in ipairs(spec.rules or {}) do
            assert(type(rule)=='table','Encounter rules must be objects')
            assert(type(rule.kind)=='string','Encounter rules require a kind')
            assert(rule.kind=='text' or rule.kind=='enemy_ability' or rule.kind=='enemy_spell'
                or rule.kind=='auto_attack' or rule.kind=='party_weapon_skill'
                or rule.kind=='action_message','Unknown encounter observation kind')
            assert(rule.messages==nil or type(rule.messages)=='table','messages must be an array')
            for _,message in ipairs(rule.messages or {}) do
                assert(type(message)=='number' and message>0 and message==math.floor(message),'Invalid action message ID')
            end
            assert(rule.after==nil or type(rule.after)=='table','after must be an object')
            for key,seconds in pairs(rule.after or {}) do
                assert(type(key)=='string' and type(seconds)=='number' and seconds>=0,'Invalid clock threshold')
            end
            if rule.contains then assert(type(rule.contains)=='string','contains must be literal text') end
            fields(rule.set,'set'); fields(rule.reset,'reset'); fields(rule.when,'when')
            assert(rule.increment==nil or type(rule.increment)=='table','increment must be an object')
            assert(rule.timestamp==nil or type(rule.timestamp)=='string','timestamp must name a clock')
            assert(rule.names==nil or type(rule.names)=='string' or type(rule.names)=='table','names must be a string or array')
            assert(rule.phase==nil or type(rule.phase)=='string','phase must be a string')
            assert(rule.outcome==nil or type(rule.outcome)=='string','outcome must be a string')
            for _,flag in ipairs({'stop','only_on_change'}) do
                assert(rule[flag]==nil or type(rule[flag])=='boolean',flag..' must be boolean')
            end
            for key,value in pairs(rule.increment or {}) do
                assert(type(key)=='string' and type(value)=='number','Invalid encounter counter')
            end
        end
    end
    for _,expression in pairs(definition.conditions or {}) do factory.get(expression) end
    local latches={}
    for _,condition in ipairs(definition.latch_conditions or {}) do
        assert(type(condition)=='string' and definition.conditions and definition.conditions[condition],
            'Latched conditions must name a configured condition')
        latches[condition]=true
    end
    trackers[name]={definition=definition,parameters=copy(parameters or {}),records={},latches=latches}
end
local function record(t,mob)
    local spec=mob and t.definition.actors[mob.name]
    if not spec or not mob.id then return end
    if mob.hpp==0 or mob.is_dead or mob.valid_target==false then
        t.records[mob.id]=nil
        return
    end
    local r=t.records[mob.id]
    if not r or r.index~=mob.index or r.name~=mob.name then
        r={id=mob.id,index=mob.index,name=mob.name,revision=0,values=copy(spec.initial or {}),timestamps={},latched={}}
        t.records[mob.id]=r
    end
    return r,spec
end
function M.get(name,mob)
    local t=trackers[name]; if not t then return end
    local r=record(t,mob); if not r then return end
    local result=copy(r.values)
    result.id=r.id; result.index=r.index; result.name=r.name; result.revision=r.revision
    result.ages={}
    for key,time in pairs(r.timestamps) do result.ages[key]=math.max(0,clock()-time) end
    return result
end
function M.evaluate(name,condition,mob,context,visiting)
    local t=trackers[name]
    local state=M.get(name,mob)
    local expression=t and t.definition.conditions and t.definition.conditions[condition]
    if not state or not expression then return false end
    local r=record(t,mob)
    if r.latched[condition] then return true end
    visiting=visiting or {}
    local key=name..':'..tostring(mob.id)..':'..condition
    assert(not visiting[key],'Circular encounter condition: '..condition)
    visiting[key]=true
    local env=setmetatable({encounter=state,encounter_target=mob,encounter_config=copy(t.parameters)}, {__index=context})
    env.encounter_test=function(other,target)
        return M.evaluate(name,other,target or mob,context,visiting)
    end
    local fn=factory.get(expression); setfenv(fn,env)
    local ok,value=pcall(fn)
    visiting[key]=nil
    if not ok then error(value,0) end
    local result=not not value
    if result and t.latches[condition] then r.latched[condition]=true end
    return result
end
local function contains(values,value)
    if type(values)=='string' then return values==value end
    for _,v in ipairs(values or {}) do if v==value then return true end end
    return false
end
local function apply(r,spec,event)
    for _,rule in ipairs(spec.rules or {}) do
        local match=rule.kind==event.kind and (not rule.phase or rule.phase==event.phase)
            and (not rule.outcome or rule.outcome==event.outcome)
            and (not rule.names or aliases.matchesAny({en=event.name},type(rule.names)=='table' and rule.names or {rule.names}))
            and (not rule.messages or contains(rule.messages,event.message))
            and (not rule.contains or event.text and event.text:find(rule.contains,1,true))
        for key,value in pairs(rule.when or {}) do if r.values[key]~=value then match=false end end
        for key,seconds in pairs(rule.after or {}) do
            if not r.timestamps[key] or clock()-r.timestamps[key]<seconds then match=false end
        end
        if match then
            local changed=false
            for key,value in pairs(rule.set or {}) do if r.values[key]~=value then changed=true end end
            -- Duplicate state messages must not reset counters or timestamps.
            if not rule.only_on_change or changed then
                for key,value in pairs(rule.set or {}) do r.values[key]=copy(value) end
                for key,value in pairs(rule.reset or {}) do r.values[key]=copy(value); r.timestamps[key]=nil end
                for key,value in pairs(rule.increment or {}) do r.values[key]=(r.values[key] or 0)+value end
                if rule.timestamp then r.timestamps[rule.timestamp]=clock() end
                r.revision=r.revision+1
            end
            if rule.stop then break end
        end
    end
end
function M.observe(event,mob)
    for _,t in pairs(trackers) do
        local r,spec=record(t,mob)
        if r then apply(r,spec,event) end
    end
end
local function matchesText(text,name,spec)
    if text:find(name,1,true) then return true end
    for _,alias in ipairs(spec.text_aliases or {}) do
        if text:find(alias,1,true) then return true end
    end
    return false
end
function M.text(text,mob)
    if type(text)~='string' or not mob or not mob.name then return end
    text=text:gsub(string.char(0x1E)..'.',''):gsub(string.char(0x1F)..'.','')
    for _,t in pairs(trackers) do
        local spec=t.definition.actors[mob.name]
        if spec and matchesText(text,mob.name,spec) then
            local r=record(t,mob)
            if r then apply(r,spec,{kind='text',text=text}) end
        end
    end
end
function M.enemy(o)
    if o then M.observe({kind=o.kind,name=o.resource and o.resource.en,phase=o.phase,outcome=o.outcome},o.actor) end
end
function M.action(action,ffxi)
    if not next(trackers) then return end
    if not action or not ffxi.get_mob_by_id then return end
    -- Expose packet message IDs without assigning encounter-specific meaning.
    -- Inspect additional effects too: they can have independent result messages.
    for _,target in ipairs(action.targets or {}) do
        local seen={}
        for _,detail in ipairs(target.actions or {}) do
            for _,key in ipairs({'message','add_effect_message','spike_effect_message'}) do
                local message=(tonumber(detail[key]) or 0)%32768
                if message>0 and not seen[message] then
                    seen[message]=true
                    M.observe({kind='action_message',message=message},ffxi.get_mob_by_id(target.id))
                end
            end
        end
    end
    if action.category==1 then
        M.observe({kind='auto_attack'},ffxi.get_mob_by_id(action.actor_id))
    elseif action.category==3 then
        local actor=ffxi.get_mob_by_id(action.actor_id)
        local player=ffxi.get_player and ffxi.get_player()
        if not actor or not (actor.in_party or actor.in_alliance or player and player.id==actor.id) then return end
        local seen={}
        for _,target in ipairs(action.targets or {}) do
            if not seen[target.id] then
                seen[target.id]=true
                M.observe({kind='party_weapon_skill',actor=actor},ffxi.get_mob_by_id(target.id))
            end
        end
    end
end
function M.attach(service)
    clock=service.deps.clock or os.clock
    local ffxi=service.deps.windower.ffxi
    service.encounterText=function(text)
        if type(text)~='string' then return end
        local relevant=false
        for _,t in pairs(trackers) do for name,spec in pairs(t.definition.actors) do
            if matchesText(text,name,spec) then relevant=true; break end
        end end
        if not relevant then return end
        local candidates,counts={},{}
        for _,mob in pairs(ffxi.get_mob_array and ffxi.get_mob_array() or {}) do
            local matched=false
            for _,t in pairs(trackers) do
                local spec=t.definition.actors[mob.name]
                if spec and matchesText(text,mob.name,spec) then matched=true; break end
            end
            if mob.valid_target and (mob.hpp or 0)>0 and type(mob.name)=='string'
                and matched then
                candidates[mob.name]=mob
                counts[mob.name]=(counts[mob.name] or 0)+1
            end
        end
        for name,mob in pairs(candidates) do
            -- Chat has no entity ID. Ambiguous same-name actors must not all
            -- inherit a transition; action packets still identify them exactly.
            if counts[name]==1 then M.text(text,mob) end
        end
    end
    service.encounterAction=function(action) M.action(action,ffxi) end
    service.encounterClear=M.clear
end
return M
