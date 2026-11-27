local selectors = require('./lib/target-selectors')
local json = require('./lib/jsonlua')
local ipc = {}
local prefix = 'gbt-send-v1 '
local presencePrefix = 'gbt-presence-v1 '
local domains = {all=true, party=true, zone=true}
local online, announced, nextAnnouncement = {}, nil, 0
local presenceLifetime = 35

local function presence(player, info, party)
    return {name=player.name,id=player.id,zone=info.zone,main_job=player.main_job,
        main_job_level=player.main_job_level,is_party_leader=party.party1_leader==player.id}
end

function ipc.tick(windower, now)
    local player, info = windower.ffxi.get_player(), windower.ffxi.get_info()
    if not player or not info or not info.zone or info.zone <= 0 then return end
    local current = presence(player,info,windower.ffxi.get_party() or {})
    local encoded = json.stringify(current)
    if now >= nextAnnouncement or encoded ~= announced then
        current.request = announced == nil
        announced, nextAnnouncement = encoded, now+10
        windower.send_ipc_message(presencePrefix..json.stringify(current))
    end
    for name, entry in pairs(online) do
        if entry.expires <= now then online[name]=nil end
    end
end

function ipc.reset(windower)
    if announced then
        local current=json.parse(announced)
        windower.send_ipc_message(presencePrefix..json.stringify({name=current.name,offline=true}))
    end
    online, announced, nextAnnouncement = {}, nil, 0
end

local function observePresence(windower, payload)
    local ok, entry = pcall(json.parse,payload)
    if not ok or type(entry)~='table' or type(entry.name)~='string' then return end
    local key=entry.name:lower()
    local player=windower.ffxi.get_player()
    if not player or player.name:lower()==key then return end
    if entry.offline==true then online[key]=nil; return end
    if type(entry.id)~='number' or type(entry.zone)~='number' or entry.zone<=0 then return end
    entry.expires=os.clock()+presenceLifetime
    online[key]=entry
    if entry.request==true then
        local info=windower.ffxi.get_info()
        if info and info.zone and info.zone>0 then
            windower.send_ipc_message(presencePrefix..json.stringify(
                presence(player,info,windower.ffxi.get_party() or {})))
        end
    end
end

local function recipients(targets)
    if targets == nil then return {'*'} end
    if type(targets) == 'string' then targets = {targets} end
    if type(targets) ~= 'table' then return end
    local result, positive = {}, false
    for index, target in pairs(targets) do
        if type(index) ~= 'number' or index%1 ~= 0 or index < 1 or index > #targets
            or type(target) ~= 'string' or not target:match('%S') or target == '~' then return end
        result[index] = target
        positive = positive or target:sub(1,1) ~= '~'
    end
    for index=1,#targets do if result[index] == nil then return end end
    if #result > 0 and not positive then result[#result+1] = '*' end
    return result
end

local function matches(windower, player, party, message, isSender)
    if message.domain == 'zone' then
        local info = windower.ffxi.get_info()
        if not info or info.zone ~= message.zone then return false end
    elseif message.domain == 'party' and not isSender then
        local sameParty = false
        for index=1,5 do
            local member = party['p'..index]
            if member and member.name == message.sender then
                sameParty = true
                break
            end
        end
        if not sameParty then return false end
    end
    if message.exact==true then
        for _, name in ipairs(message.targets) do
            if player.name:lower()==name:lower() then return true end
        end
        return false
    end
    return selectors.matchesPlayer(player,message.targets,party.party1_leader==player.id,isSender)
end

local function filterNames(windower, message, player, info, party, predicate)
    local partyNames = {[player.name:lower()]=true}
    for index=1,5 do
        local member=party['p'..index]
        if member and member.name then partyNames[member.name:lower()]=true end
    end
    local candidates={[player.name:lower()]=presence(player,info,party)}
    local now=os.clock()
    for key, entry in pairs(online) do
        if entry.expires>now and not candidates[key] then candidates[key]=entry end
    end
    local names={}
    for key, entry in pairs(candidates) do
        local inZone=entry.zone==info.zone
        if (message.domain~='party' or partyNames[key]) and (message.domain~='zone' or inZone)
            and selectors.matchesPlayer(entry,message.targets,entry.is_party_leader==true,key==player.name:lower()) then
            local mob=inZone and windower.ffxi.get_mob_by_id(entry.id) or nil
            if mob and mob.name~=entry.name then mob=nil end
            local distance=mob and type(mob.distance)=='number' and math.sqrt(mob.distance) or nil
            local valid=mob and mob.valid_target==true or false
            local recipient={name=entry.name,id=entry.id,zone=entry.zone,main_job=entry.main_job,
                main_job_level=entry.main_job_level,has_mob_data=mob~=nil,valid_target=valid,
                is_participant=valid and partyNames[key]==true and mob.hpp~=0 and distance~=nil and distance<=20,
                mob=mob,distance=distance}
            if predicate(recipient) then names[#names+1]=entry.name end
        end
    end
    return names
end

function ipc.send(windower, domain, command, targets, findPrimaryTank, predicate)
    local selected = assert(recipients(targets),'Expected a recipient name or an array of selectors')
    assert(type(command)=='string' and command:match('%S'),'Expected a Windower command')
    local player = windower.ffxi.get_player()
    local info = windower.ffxi.get_info()
    if not player or not info or not info.zone or info.zone <= 0 then return false end
    local party = windower.ffxi.get_party() or {}
    for index,target in ipairs(selected) do
        local key = target:lower()
        local exclusion, slot = key:match('^(~?)(p[0-5])$')
        local member = slot and party[slot]
        local tankExclusion, otherOnly = key:match('^(~?)(%^?)primary_tank$')
        if tankExclusion and findPrimaryTank then
            local tank = findPrimaryTank()
            if tank and (otherOnly == '' or tank.id ~= player.id) then
                member = tank
                exclusion = tankExclusion
            end
        end
        if member and member.name then selected[index] = exclusion..member.name end
    end
    local message = {domain=domain,sender=player.name,zone=info.zone,targets=selected,command=command}
    if predicate then
        message.targets=filterNames(windower,message,player,info,party,predicate)
        message.exact=true
        selected=message.targets
    end
    if #selected == 0 then return false end
    windower.send_ipc_message(prefix..json.stringify(message))
    if matches(windower,player,party,message,true) then windower.send_command(command) end
    return true
end

function ipc.receive(windower, payload)
    if type(payload)=='string' and payload:sub(1,#presencePrefix)==presencePrefix then
        observePresence(windower,payload:sub(#presencePrefix+1))
        return true
    end
    if type(payload) ~= 'string' or payload:sub(1,#prefix) ~= prefix then return false end
    local ok, message = pcall(json.parse,payload:sub(#prefix+1))
    if not ok or type(message) ~= 'table' or not domains[message.domain] or type(message.sender) ~= 'string'
        or type(message.zone) ~= 'number' or message.zone <= 0 or type(message.targets) ~= 'table'
        or type(message.command) ~= 'string' or not message.command:match('%S') then return true end
    if message.exact==true then
        if not recipients(message.targets) then return true end
    else
        message.targets = recipients(message.targets)
    end
    local player = windower.ffxi.get_player()
    if player and message.targets and player.name ~= message.sender
        and matches(windower,player,windower.ffxi.get_party() or {},message,false) then
        windower.send_command(message.command)
    end
    return true
end

return ipc
