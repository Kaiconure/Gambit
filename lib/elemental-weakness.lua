-- Numeric encounter rules are deliberately scoped to the captured battlefield.
-- Add other bosses/zones only after verifying their message IDs and semantics.
local tracker = {}
local names = {[0]='fire','ice','wind','earth','thunder','water'}
local counters = {fire='water',water='thunder',thunder='earth',earth='wind',wind='ice',ice='fire'}
local function matches(zone, mob)
    return zone == 277 and mob and mob.name == 'Plouton' and mob.hpp > 0
end
local function uint(data, offset, length)
    local n=0
    for i=length-1,0,-1 do n=n*256+data:byte(offset+i+1) end
    return n
end

function tracker.message(data, zone, mob)
    if not matches(zone,mob) or #data < 32 then return end
    if uint(data,4,4) ~= mob.id or uint(data,26,2) % 32768 ~= 8495 then return end
    local element=names[uint(data,8,4)]
    if element then return {kind='confirmed',element=element,target_id=mob.id,source='message_8495'} end
end

function tracker.action(action, zone, mob, spells, knownElement)
    if not matches(zone,mob) or action.category ~= 4 then return end
    local spell=spells[action.param]
    local element=spell and names[spell.element]
    if not element then return end
    for _,target in ipairs(action.targets or {}) do
        if target.id == mob.id then
            for _,result in ipairs(target.actions or {}) do
                -- 7 is spell HP recovery. Restrict to elemental BlackMagic,
                -- so cures and drain recovery cannot be mistaken for probes.
                if spell.type == 'BlackMagic' and result.message == 7 and result.param > 0 then
                    return {kind='inferred',element=counters[element],absorbed=element,
                        target_id=mob.id,source='spell_absorption'}
                end
                if element == knownElement and result.message == 2 and result.param == 0 then
                    return {kind='unknown',target_id=mob.id,source='confirmed_element_zero_damage'}
                end
            end
        end
    end
end
return tracker
