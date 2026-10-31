-- Lightweight classification shared by context symbols and recorded targets.
local metadata={}
local fields={'spawn_type','status','valid_target','target_index','x','y','z','heading','in_party','in_alliance'}
function metadata.apply(target,mob,playerId)
    for _,field in ipairs(fields) do
        if mob then target[field]=mob[field] else target[field]=nil end
    end
    local function known(value) if mob then return value end end
    local spawn=mob and mob.spawn_type
    target.is_mob=known(spawn==16)
    target.is_player=known(spawn==1 or spawn==13)
    target.is_trust=known(spawn==14)
    target.is_me=known(mob and mob.id==playerId)
    target.is_party_member=known(mob and mob.in_party==true)
    target.is_alliance_member=known(mob and mob.in_alliance==true)
    local status=mob and mob.status
    target.is_idle=status==0 or nil
    target.is_engaged=status==1 or nil
    target.is_dead=(status==2 or status==3) or nil
    target.is_cutscene=status==4 or nil
    target.is_resting=status==33 or nil
    target.is_mounted=(status==5 or status==85) or nil
    target.is_crafting=status==44 or nil
    target.can_follow=(target.is_idle or target.is_engaged or target.is_mounted or target.is_resting) or nil
    return target
end
function metadata.snapshot(identity,mob,playerId)
    if not identity then return nil end
    if mob and (mob.id~=identity.id or (identity.index and mob.index~=identity.index)) then mob=nil end
    return metadata.apply({id=identity.id,name=identity.name,index=identity.index},mob,playerId)
end
function metadata.refresh(identity,ffxi)
    if not identity then return nil end
    local player=ffxi.get_player()
    local mob=identity.id and ffxi.get_mob_by_id(identity.id)
    return metadata.snapshot(identity,mob,player and player.id)
end
return metadata
