local targeted = {}

-- Outgoing 0x01A uses resource IDs for magic (3) and job abilities (9).
-- Resolve the index again at dispatch time: an old context is not authoritative.
function targeted.send(category, resource, targetId)
    if (category ~= 3 and category ~= 9) or not resource or
        type(resource.id) ~= 'number' or type(targetId) ~= 'number' then return false end
    local mob = windower.ffxi.get_mob_by_id(targetId)
    if not mob or not mob.valid_target or type(mob.index) ~= 'number' then return false end
    local packet = packets.new('outgoing', 0x01A, {
        ['Target']=targetId, ['Target Index']=mob.index,
        ['Category']=category, ['Param']=resource.id,
        ['X Offset']=0, ['Y Offset']=0, ['Z Offset']=0,
    })
    packets.inject(packet)
    return true -- Submission only; spell completion is observed separately.
end

return targeted
