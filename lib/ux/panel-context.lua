local Theme=require('./lib/ux/theme')
local PanelContext={}
local skillchainElements=require('./lib/skillchain-elements')
-- Windower element IDs: Fire through Dark. Physical/None have no decoration.
local elementNames={[0]='fire','ice','wind','earth','lightning','water','light','dark'}
local elementColors={
    fire      = {255, 65, 50},
    ice       = {130, 240, 255},
    wind      = {50, 225, 120},
    earth     = {235, 160, 50},
    lightning = {185, 100, 255},
    water     = {40, 140, 255},
    light     = {255, 235, 150},
    dark      = {155, 115, 190}
}
-- Names and blended colors are computed once, using the same mapping as
-- magic-burst eligibility and the same palette as color_element.
local skillchainDisplay={}
for name,elements in pairs(skillchainElements) do
    local rgb={0,0,0}
    for _,element in ipairs(elements) do
        local source=elementColors[element:lower()]
        for channel=1,3 do rgb[channel]=rgb[channel]+source[channel] end
    end
    for channel=1,3 do rgb[channel]=math.floor(rgb[channel]/#elements+0.5) end
    if name=='Light' or name=='Radiance' then
        -- Lift the darkest channel to 220 by blending toward white, preserving
        -- the elemental tint instead of flattening channels with a hard clamp.
        local minimum=math.min(unpack(rgb))
        if minimum<220 then
            local lift=(220-minimum)/(255-minimum)
            for channel=1,3 do
                rgb[channel]=math.floor(rgb[channel]+(255-rgb[channel])*lift+0.5)
            end
        end
    end
    skillchainDisplay[name:lower()]={
        text=('\\cs(%d,%d,%d)%s\\cr'):format(rgb[1],rgb[2],rgb[3],name),rgb=rgb}
end

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
        local display=skillchainDisplay[name:lower()]
        if not display then return color(name,unpack(Theme.colors.body)) end
        latest=display.rgb
        return display.text
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
