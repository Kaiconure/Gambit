local Theme=require('./lib/ux/theme')
local PanelContext={}
local skillchainColors={
    liquefaction={255,125,110},induration={170,220,255},
    detonation={135,235,175},scission={225,195,130},
    impaction={205,175,255},reverberation={120,175,255},
    transfixion={250,235,160},compression={200,145,235},
    fusion={255,180,105},fragmentation={110,225,215},
    distortion={155,165,255},gravitation={200,155,195},
    light={255,245,220},radiance={255,245,220},
    darkness={205,180,245},umbra={205,180,245},
}
-- Windower element IDs: Fire through Dark. Physical/None have no decoration.
local elementNames={[0]='fire','ice','wind','earth','lightning','water','light','dark'}
local elementColors={
    fire={255,125,110},ice={170,220,255},wind={135,235,175},
    earth={225,195,130},lightning={205,175,255},water={120,175,255},
    light={255,245,220},dark={205,180,245},
}
function PanelContext.attach(context,canShareClaim)
    local latest
    local function color(text,r,g,b)
        for _,component in ipairs({r,g,b}) do
            assert(type(component)=='number' and component>=0 and component<=255
                and component==math.floor(component),'Panel colors require integer RGB values from 0 to 255')
        end
        assert(r~=nil and g~=nil and b~=nil,'Panel colors require all three RGB values')
        latest={r,g,b}
        return ('\\cs(%d,%d,%d)%s\\cr'):format(r,g,b,tostring(text==nil and '' or text))
    end
    context.color_text=color
    context.color_latest=function(text)
        return color(text,unpack(latest or Theme.colors.body))
    end
    context.color_number=function(value)
        return color(value,unpack(Theme.colors.number))
    end
    context.color_status=function(status)
        local role=({casting='status_pending',interrupted='status_interrupted',
            completed='status_completed'})[status] or 'body'
        return color(status,unpack(Theme.colors[role]))
    end
    context.color_skillchain=function(chain)
        local name=type(chain)=='table' and chain.name or chain
        if type(name)~='string' or name=='' then return color('--',160,160,160) end
        return color(name,unpack(skillchainColors[name:lower()] or Theme.colors.body))
    end
    context.color_element=function(value)
        if type(value)~='table' then return value end
        local element=value.element
        local key=type(element)=='number' and elementNames[element]
            or (type(element)=='string' and element:lower())
        local rgb=elementColors[key]
        if not rgb or value.name==nil then return value.name end
        return color(value.name,unpack(rgb))
    end
    context.color_mob=function(mob)
        local role='target_npc'
        local name=mob and mob.name
        if not mob or not mob.valid_target or not name then
            return color('--',unpack(Theme.colors.target_invalid))
        end
        if mob.is_dead then return color(name,unpack(Theme.colors.target_dead))
        elseif mob.is_player then
            role=(mob.is_party_member or mob.is_alliance_member) and 'target_player' or 'target_other_player'
        elseif mob.is_mob or mob.is_pet then
            role=mob.is_engaged and 'target_engaged' or 'target_idle'
            local entity=mob.mob or mob
            if mob.is_engaged and (entity.claim_id or 0)>0 and canShareClaim
                and not canShareClaim(entity) then role='target_outside_claim' end
        end
        return color(name,unpack(Theme.colors[role]))
    end
    -- Each expression gets an independent latest color, even in an expression array.
    return function() latest=nil end
end
return PanelContext
