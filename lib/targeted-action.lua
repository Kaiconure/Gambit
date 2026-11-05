local targeted = {}
local actionWait=require('./lib/action-wait')
local categories=require('./meta/outgoing-action-categories')
local kinds={
    [categories.SPELL]='spell',
    [categories.WEAPON_SKILL]='weapon_skill',
    [categories.JOB_ABILITY]='job_ability',
}

-- Outgoing 0x01A uses resource IDs for spells, weapon skills, and job abilities.
-- Resolve the index again at dispatch time: an old context is not authoritative.
function targeted.send(category, resource, targetId, observation)
    if observation and observation.validate and not observation.validate() then return false end
    if not kinds[category] or not resource or
        type(resource.id) ~= 'number' or type(targetId) ~= 'number' then return false end
    local mob = windower.ffxi.get_mob_by_id(targetId)
    if not mob or not mob.valid_target or type(mob.index) ~= 'number' then return false end
    local packet = packets.new('outgoing', 0x01A, {
        ['Target']=targetId, ['Target Index']=mob.index,
        ['Category']=category, ['Param']=resource.id,
        ['X Offset']=0, ['Y Offset']=0, ['Z Offset']=0,
    })
    if observation then actionWait.register(observation,kinds[category],resource.id,targetId,os.clock()) end
    if globals and globals.event_system then
        globals.event_system:send(packet, observation)
    else
        if observation then observation.sent_at=os.clock() end
        packets.inject(packet)
    end
    return true -- Submission only; spell completion is observed separately.
end

return targeted
