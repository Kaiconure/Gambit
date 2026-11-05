local Weakness=require('./lib/abyssea-weakness')
local Abyssea={}
function Abyssea.attach(service,listen)
    local deps=service.deps
    local ffxi=deps.windower.ffxi
    local clock=deps.clock or os.clock
    local pending
    local function zone() local info=ffxi.get_info and ffxi.get_info(); return info and info.zone end
    local function observe(mob,element,triggered,actor,remote,color)
        color=color or 'red'
        local previous=Weakness.get(zone(),mob)
        previous=previous and previous[color] or {}
        local oldElement,oldTriggered=previous[color=='blue' and 'weapon_type' or 'element'],previous.triggered
        local changed,record=Weakness.update(zone(),mob,element,triggered,actor,color)
        if changed and deps.notifyWeakness then
            local prefix=color:upper()..' PROC '
            local name=mob.name or tostring(mob.id)
            local source=remote and ' [IPC]' or ''
            if element and element~=oldElement then
                deps.notifyWeakness(prefix..'search: '..element..' ('..name..').'..source)
            end
            if triggered and not oldTriggered then
                deps.notifyWeakness(prefix..'confirmed on '..name..
                    (actor and ' by '..actor or '')..'.'..source)
            end
        end
        if changed and not remote and deps.windower.send_ipc_message then
            local prefix=color=='red' and 'gambit_weakness_v1' or 'gambit_weakness_v2 '..color
            deps.windower.send_ipc_message(table.concat({prefix,record.zone,record.id,
                record.index,element and element:gsub(' ','_') or '-',triggered and '1' or '0',actor or '-'},' '))
        end
    end
    service.weaknessIncoming=function(id,original,modified,injected)
        if id~=0x02A or injected or not Weakness.isZone(zone()) then return end
        local ok,p=pcall(deps.packets.parse,'incoming',original or modified)
        if not ok or type(p)~='table' or not ffxi.get_mob_by_id then return end
        local mob=ffxi.get_mob_by_id(p.Player)
        if not mob or mob.spawn_type~=16 or mob.index~=p['Player Index'] then pending=nil; return end
        local actor=pending and pending.mob.id==mob.id and clock()-pending.time<1 and pending.actor
        pending={mob=mob,time=clock(),actor=actor or nil}
        local messages=Weakness.messages(zone())
        if messages then
            local message=(tonumber(p['Message ID']) or 0)%32768
            if message==messages.red_hint then
                local element=Weakness.elementName(p['Param 1'])
                if element then observe(mob,element,false) end
            elseif message==messages.yellow_hint then
                local element=Weakness.elementName(p['Param 1'])
                if element then observe(mob,element,false,nil,false,'yellow') end
            elseif message==messages.blue_hint then
                local weapon=Weakness.weaponType(p['Param 1'])
                if weapon then observe(mob,weapon,false,nil,false,'blue') end
            elseif message==messages.stagger then
                -- 0x02A's variable string starts at byte offset 0x1E; the
                -- generic parser folds its first two bytes into _unknown1.
                pending.actor=type(original)=='string' and original:sub(31):match('^([%a]+)%z') or nil
            elseif message==messages.red_stagger then observe(mob,nil,true,pending.actor)
            elseif message==messages.yellow_stagger then observe(mob,nil,true,pending.actor,false,'yellow')
            elseif message==messages.blue_stagger then observe(mob,nil,true,pending.actor,false,'blue') end
        end
    end
    service.weaknessText=function(original)
        if not pending or clock()-pending.time>1 or type(original)~='string' then return end
        local element=original:match('^The fiend appears vulnerable to (%a+) elemental weapon skills!')
        if element then observe(pending.mob,element,false); return end
        element=original:match('^The fiend appears vulnerable to (%a+) elemental magic!')
        if element then observe(pending.mob,element,false,nil,false,'yellow'); return end
        local weapon=original:match('^The fiend appears vulnerable to ([%a %-]+) weapon skills!')
        if weapon then observe(pending.mob,weapon,false,nil,false,'blue'); return end
        local actor=original:match("^(%a+)'s attack staggers the fiend!")
        if actor then pending.actor=actor end
        if original:match('^The fiend is frozen in its tracks%.') and pending.actor then
            observe(pending.mob,nil,true,pending.actor)
        elseif original:match('^The fiend is unable to cast magic%.') and pending.actor then
            observe(pending.mob,nil,true,pending.actor,false,'yellow')
        elseif original:match('^The fiend is unable to use special attacks%.') and pending.actor then
            observe(pending.mob,nil,true,pending.actor,false,'blue')
        end
    end
    listen('ipc message',function(message)
        local color,payload=message:match('^gambit_weakness_v2 (%a+) (.+)$')
        if color then
            if color~='yellow' and color~='red' and color~='blue' then return end
            message='gambit_weakness_v1 '..payload
        else color='red' end
        local z,id,index,element,triggered,actor=message:match('^gambit_weakness_v1 (%d+) (%d+) (%d+) ([%a_%-]+) ([01]) ([%a%-]+)$')
        if not z then
            z,id,index,element,triggered,actor=message:match('^gambit_weakness_v1 (%d+) (%d+) (%d+) (%-) ([01]) ([%a%-]+)$')
        end
        if tonumber(z)~=zone() or not ffxi.get_mob_by_id then return end
        local mob=ffxi.get_mob_by_id(tonumber(id))
        if not mob or mob.index~=tonumber(index) then return end
        if color=='blue' then element=element and element:gsub('_',' ') end
        observe(mob,element~='-' and element or nil,triggered=='1',actor~='-' and actor or nil,true,color)
    end)
    service.weaknessTick=function() if ffxi.get_mob_by_id then Weakness.prune(ffxi) end end
    service.weaknessClear=function() pending=nil; Weakness.clear() end
end
return Abyssea
