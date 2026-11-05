-- Encounter observations shared by action contexts. No equipment or action dispatch.
local Weakness={}
-- STAGGERED zone-text bases from LandSandBoat scripts/zones/Abyssea-*/IDs.lua.
-- The mechanics and relative message layout are shared across Abyssea; Attohwa
-- and Uleguerand have a different text-table offset. Altepa is capture-verified.
local zones={[15]=7341,[45]=7341,[132]=7341,[215]=7240,[216]=7341,
    [217]=7341,[218]=7341,[253]=7240,[254]=7341}
local records={}
local elements={fire=true,ice=true,wind=true,earth=true,lightning=true,water=true,light=true,darkness=true}
local elementNames={'fire','ice','wind','earth','lightning','water','light','darkness'}
local weaponTypes={'hand-to-hand','dagger','sword','great sword','axe','great axe','scythe',
    'polearm','katana','great katana','club','staff','archery','marksmanship'}
function Weakness.weaponType(index) return weaponTypes[index] end
function Weakness.weaponSkill(name)
    for index,value in ipairs(weaponTypes) do
        if value==name then return index<=12 and index or index+12 end
    end
end
function Weakness.elementName(index) return elementNames[index] end
function Weakness.messages(zone)
    local base=zones[zone]
    if base then return {stagger=base,red_stagger=base+3,red_hint=base+6,
        yellow_stagger=base+1,yellow_hint=base+4,blue_stagger=base+2,blue_hint=base+5} end
end
function Weakness.clear() records={} end
function Weakness.get(zone,mob)
    if not zones[zone] or not mob then return end
    if mob.hpp==0 or mob.status==3 then records[mob.id]=nil; return end
    local record=records[mob.id]
    if record and (record.zone~=zone or record.index~=mob.index) then records[mob.id]=nil; return end
    return record
end
function Weakness.update(zone,mob,element,triggered,actor,color)
    color=color or 'red'
    if color~='red' and color~='yellow' and color~='blue' then return end
    if not zones[zone] or not mob or mob.spawn_type~=16 or mob.hpp==0 or mob.status==3 then return end
    if element~=nil and not (color=='blue' and Weakness.weaponSkill(element) or color~='blue' and elements[element]) then return end
    local record=Weakness.get(zone,mob) or {zone=zone,id=mob.id,index=mob.index,red={},yellow={},blue={}}
    record[color]=record[color] or {}
    local weakness=record[color]
    local changed=false
    local field=color=='blue' and 'weapon_type' or 'element'
    if element and weakness[field]~=element then weakness[field]=element; changed=true end
    if triggered and not weakness.triggered then weakness.triggered=true; weakness.actor=actor; changed=true end
    records[mob.id]=record
    return changed,record
end
function Weakness.prune(ffxi)
    for id,record in pairs(records) do
        local mob=ffxi.get_mob_by_id(id)
        -- An unclaimed idle mob has reset its encounter (including deaggro).
        if not mob or mob.index~=record.index or mob.hpp==0 or mob.status==3
            or (mob.status==0 and mob.claim_id==0) then records[id]=nil end
    end
end
function Weakness.isZone(zone) return not not zones[zone] end
return Weakness
