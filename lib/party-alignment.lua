-- One local preference profile per client; the leader publishes one shared
-- roster/profile view so self-relative party slots cannot disagree.
local alignment=require('./lib/alignment')
local M={}
local deps,own,peers,roster,fallbacks,lastSent,lastRoster,identity,assignment,requestPending,lastRosterPayload
local prefix='alignment '
local heartbeat=10
function M.reset()
    own=nil;peers={};roster=nil;fallbacks={};lastSent=nil;lastRoster=nil;identity=nil;assignment=nil
    requestPending=true;lastRosterPayload=nil
end
M.reset()
function M.attach(options) deps=options;M.reset() end
local function live()
    if not deps then return end
    local player=deps.ffxi.get_player()
    local info=deps.ffxi.get_info()
    local party=deps.ffxi.get_party()
    if not player or not info or info.logged_in==false or not info.zone or not party or not party.party1_leader then return end
    return player,info,party
end
local function members(party)
    local result={}
    for i=0,5 do
        local member=party['p'..i]
        local name=member and (member.name or member.mob and member.mob.name)
        if type(name)=='string' and name~='' then result[#result+1]=name end
    end
    return result
end
local function emit(message)
    deps.send(prefix..deps.json.stringify(message))
end
local function refreshIdentity(player,info,party)
    local key=tostring(info.zone)..':'..tostring(party.party1_leader)
    if identity~=key then
        M.reset();identity=key
    end
end
function M.receive(message)
    if type(message)~='string' or message:sub(1,#prefix)~=prefix then return false end
    local player,info,party=live()
    if not player then return true end
    refreshIdentity(player,info,party)
    local ok,data=pcall(deps.json.parse,message:sub(#prefix+1))
    if not ok or type(data)~='table' or data.zone~=info.zone or data.leader~=party.party1_leader then return true end
    if data.kind=='member' and type(data.name)=='string' and (data.group==false or type(data.group)=='string') then
        for _,name in ipairs(members(party)) do
            if name==data.name then
                if peers[name]~=data.group then lastRoster=nil end
                peers[name]=data.group
                -- A reloaded client needs fresh profiles, even if ours hasn't changed.
                if data.request_profiles then lastSent=nil;lastRoster=nil end
                break
            end
        end
    elseif data.kind=='roster' and data.sender==party.party1_leader and type(data.members)=='table' and #data.members<=6 then
        local valid,seen=true,{}
        for _,member in ipairs(data.members) do
            if type(member)~='table' or type(member.name)~='string' or seen[member.name]
                or (member.group~=false and type(member.group)~='string') then valid=false;break end
            seen[member.name]=true
        end
        if valid then roster=data end
    end
    return true
end
function M.tick()
    local player,info,party=live()
    if not player then if identity then M.reset() end;return end
    refreshIdentity(player,info,party)
    local now=deps.clock()
    if not lastSent or own and now-lastSent>=heartbeat then
        lastSent=now
        peers[player.name]=own or false
        emit({kind='member',zone=info.zone,leader=party.party1_leader,name=player.name,group=own or false,
            request_profiles=requestPending or nil})
        requestPending=false
    end
    local active=false
    for _,name in ipairs(members(party)) do if peers[name] then active=true;break end end
    if active and party.party1_leader==player.id then
        local data={kind='roster',zone=info.zone,leader=player.id,sender=player.id,members={}}
        for _,name in ipairs(members(party)) do data.members[#data.members+1]={name=name,group=peers[name] or false} end
        local payload=deps.json.stringify(data)
        if not lastRoster or payload~=lastRosterPayload or now-lastRoster>=heartbeat then
            lastRoster=now;lastRosterPayload=payload
            roster=data;emit(data)
        end
    end
end
function M.plan(target,spec,distance,options)
    if not deps then return end
    local player,info,party=live()
    if not player then return end
    refreshIdentity(player,info,party)
    if not options or not options.distribute or spec.exact or spec.free or not target or not target.id then
        if own then own=nil;lastSent=nil;fallbacks={} end
        return
    end
    local ranges=alignment.intervals(spec)
    if #ranges==0 then
        if own then own=nil;lastSent=nil;fallbacks={};assignment=nil end
        return
    end
    local multiplier=options._radius_multiplier
    if type(multiplier)~='number' then multiplier=options.radius_multiplier end
    local parts={tostring(target.id),tostring(target.index),tostring(distance),tostring(multiplier)}
    for _,range in ipairs(ranges) do parts[#parts+1]=tostring(range[1])..','..tostring(range[2]) end
    local group=table.concat(parts,'|')
    if own~=group then own=group;lastSent=nil;fallbacks={} end
    M.tick()
    if not roster or roster.leader~=party.party1_leader then return end
    local index,names
    names={}
    for _,member in ipairs(roster.members) do
        if member.group==group then
            names[#names+1]=member.name
            if member.name==player.name then index=#names end
        end
    end
    if not index or #names<2 then assignment=nil;fallbacks={};return end
    local key=group..':'..tostring(party.party1_leader)..':'..table.concat(names,',')
    if assignment~=key then fallbacks={};assignment=key end
    return {full=spec,preferred=fallbacks[key] and spec or alignment.slice(spec,index,#names),
        key=key,count=#names,fallback=not not fallbacks[key]}
end
function M.accept(plan,bearing)
    if plan and not alignment.contains(plan.preferred,bearing) then fallbacks[plan.key]=true end
end
return M
