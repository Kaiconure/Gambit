-- Opt-in evidence capture. No proc interpretation or gameplay side effects.
local copy=require('./lib/variable-values').copy
local Discovery={}
local capture
local limit=8192
function Discovery.active() return capture and not capture.full end
function Discovery.start(clock,metadata)
    if capture then return false end
    clock=clock or os.clock
    capture={clock=clock,started=clock(),metadata=copy(metadata),entries={}}
    return true
end
function Discovery.record(kind,data)
    if not Discovery.active() then return end
    local row=copy(data or {})
    row.kind=kind; row.time=capture.clock()-capture.started; row.step=#capture.entries+1
    capture.entries[#capture.entries+1]=row
    if #capture.entries>=limit then capture.full=true end
end
function Discovery.stop()
    if not capture then return end
    local result={version=1,purpose='weakness discovery; observations are not confirmed proc attribution',
        metadata=capture.metadata,duration=capture.clock()-capture.started,
        truncated=not not capture.full,entries=capture.entries}
    capture=nil
    return result
end
local function mob(m)
    if m then return {id=m.id,index=m.index,name=m.name,spawn_type=m.spawn_type,hpp=m.hpp,status=m.status} end
end
function Discovery.context(ffxi)
    local info=ffxi.get_info and ffxi.get_info()
    return {zone=info and info.zone,target=mob(ffxi.get_mob_by_target and ffxi.get_mob_by_target('t')),
        battle_target=mob(ffxi.get_mob_by_target and ffxi.get_mob_by_target('bt'))}
end
function Discovery.action(action,ffxi,resources)
    if not Discovery.active() then return end
    local data=Discovery.context(ffxi)
    data.action=action
    data.actor=mob(ffxi.get_mob_by_id(action.actor_id))
    data.targets={}
    for _,target in ipairs(action.targets or {}) do
        data.targets[#data.targets+1]=mob(ffxi.get_mob_by_id(target.id)) or {id=target.id}
    end
    -- Keep raw categories/IDs authoritative; name candidates are evidence only.
    data.resource_candidates={}
    for _,name in ipairs({'spells','job_abilities','weapon_skills','monster_abilities'}) do
        local resource=resources[name] and resources[name][action.param]
        if resource then data.resource_candidates[name]=resource.en or resource.name end
    end
    Discovery.record('action',data)
end
function Discovery.packet(id,original,modified,injected,blocked,deps,direction)
    direction=direction or 'incoming'
    if not Discovery.active() then return end
    if direction=='outgoing' then
        if id~=0x01A then return end
    elseif id~=0x029 and id~=0x02A and id~=0x02D and id~=0x038 then return end
    local data=Discovery.context(deps.windower.ffxi)
    data.id=id; data.direction=direction; data.injected=not not injected; data.blocked=not not blocked
    local raw=original or modified
    if type(raw)=='string' then data.hex=(raw:gsub('.',function(c) return string.format('%02X',c:byte()) end)) end
    local ok,parsed=pcall(deps.packets.parse,direction,raw)
    if ok and type(parsed)=='table' then
        data.fields={}
        for key,value in pairs(parsed) do
            if type(value)=='number' or type(value)=='boolean' then data.fields[key]=value end
        end
    else data.parse_error=tostring(parsed) end
    Discovery.record('packet',data)
end
return Discovery
