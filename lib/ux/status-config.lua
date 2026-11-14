local copy=require('./lib/variable-values').copy
local Config={}
Config.defaults =
{
    visible = true,
    show_log = false,
    theme = 'ffxi',
    x = 130,
    y = 48,
    anchor = {
        vertical = 'top',
        horizontal = 'right'
    },
    width = 450,
    height = 85,
    font_size = 12,
    history_lines = 4,
    refresh_interval = 0.5,
    tracking =
    {
        current = 'default',
        sets =
        {
            default =
            {
                {
                    name='Summary',
                    expression={
                        'format("%s %s%s%s", color_mob(me), color_job(me.main_job .. me.main_job_level), me.sub_job and ("/" .. color_job(me.sub_job .. me.sub_job_level)) or "", me.is_mastered and me.master_level and (" "..color_number("ML"..me.master_level)) or "")',
                        '"  Actions: " .. format("%s", color_text(gambit.namespace or "global", 0, 255, 255)) .. "→" .. color_text(format("%s", gambit.entrypoint_relative), 241, 241, 183)',
                        '"  Events: " .. format("%s", color_text(gambit.event_namespace or "global", 0, 255, 255)) .. "→" .. color_text(format("%s", gambit.events_relative), 241, 241, 183)',
                        '"  Target: " .. color_mob(cursor) .. (cursor and cursor.valid_target and job_string(cursor) and (" " .. color_job(job_string(cursor))) or "") .. (cursor and cursor.valid_target and format("→%s %s•%s", color_number(format("%.2f", cursor.distance)), color_muted(cursor.id), color_muted(format("%03X", cursor.index))) or "")'
                    }
                },
                {
                    name='Skillchain',
                    show_when='party_weapon_skill and party_weapon_skill.name',
                    expression={
                        "format('%s%s%s (~%s)', color_element(party_weapon_skill.skill or party_weapon_skill), skillchain and skillchain.name and (' → ' .. color_skillchain(skillchain)) or '', bt and (' → ' .. color_mob(bt)) or '', color_number(format('%.1fs', (skillchain or party_weapon_skill).lifetime)))"
                    }
                },
                {
                    name='Spell',
                    show_when="gambit.last_spell and gambit.last_spell.name and (gambit.last_spell.status == 'casting' or gambit.last_spell.age < 5)",
                    expression={
                        "format('%s%s (%s)', color_element(gambit.last_spell), gambit.last_spell.target and gambit.last_spell.target.name and (' → ' .. color_mob(gambit.last_spell.target)) or '', color_status(gambit.last_spell.status))"
                    }
                },
                {
                    name='Job Ability',
                    show_when='gambit.last_ability and gambit.last_ability.name and gambit.last_ability.age < 5',
                    expression={
                        "format('%s%s', color_element(gambit.last_ability), gambit.last_ability.target and gambit.last_ability.target.name and (' → ' .. color_mob(gambit.last_ability.target)) or '')"
                    }
                }
            },
            compact = {
                {
                    name='Summary',
                    expression={
                        'format("%s %s%s%s", color_mob(me), color_job(me.main_job .. me.main_job_level), me.sub_job and ("/" .. color_job(me.sub_job .. me.sub_job_level)) or "", me.is_mastered and me.master_level and (" "..color_number("ML"..me.master_level)) or "")',
                        '"  Actions: " .. format("%s", color_text(gambit.namespace or "global", 0, 255, 255)) .. "→" .. color_text(format("%s", gambit.entrypoint_relative), 241, 241, 183)',
                        '"  Events: " .. format("%s", color_text(gambit.event_namespace or "global", 0, 255, 255)) .. "→" .. color_text(format("%s", gambit.events_relative), 241, 241, 183)',
                        '"  Target: " .. color_mob(cursor) .. (cursor and cursor.valid_target and job_string(cursor) and (" " .. color_job(job_string(cursor))) or "") .. (cursor and cursor.valid_target and format("→%s %s•%s", color_number(format("%.2f", cursor.distance)), color_muted(cursor.id), color_muted(format("%03X", cursor.index))) or "")'
                    }
                }
            },
            nyzul = {
                {
                    id='nyzul_floor',
                    name='Nyzul Floor Objective',
                    show_when='session.nyzul and session.nyzul.objective',
                    checklist={
                        {
                            id='objective',
                            format={'%s','session.nyzul.objective'},
                            checked_when={'session.nyzul.objective_completed'}
                        }
                    }
                },
                {
                    name='Nyzul Status',
                    show_when='session.nyzul and (session.nyzul.current_floor or (session.nyzul.time_remaining_until and session.nyzul.time_remaining_until > time))',
                    format={
                        '%s%s',
                        "session.nyzul.current_floor and format('%s', color_number('Floor '..session.nyzul.current_floor)) or ''",
                        "session.nyzul.time_remaining_until and session.nyzul.time_remaining_until > time and format('%s%s', session.nyzul.current_floor and ' • ' or '', color_number(format('%d:%02d', (max(0, session.nyzul.time_remaining_until - time) + 0.999) / 60, (max(0, session.nyzul.time_remaining_until - time) + 0.999) % 60))) or ''"
                    }
                },
                {
                    name='Restriction',
                    show_when='session.nyzul and session.nyzul.restriction',
                    format={'%s','color_yellow(session.nyzul.restriction)'}
                }
            },
            none = {
            }
        }
    }
}

-- Expand at display time; keep references in saved preferences so stock updates
-- continue to flow through composed sets.
function Config.expandTracking(entries,sets,visiting)
    visiting=visiting or {}
    local result={}
    for _,entry in ipairs(entries) do
        if entry.references~=nil then
            local name=entry.references
            assert(sets[name],'Unknown referenced tracking set: '..tostring(name))
            assert(not visiting[name],'Circular tracking reference: '..name)
            visiting[name]=true
            for _,row in ipairs(Config.expandTracking(sets[name],sets,visiting)) do
                result[#result+1]=row
            end
            visiting[name]=nil
        else result[#result+1]=copy(entry) end
    end
    return result
end

function Config.normalizeWaypoint(value)
    if value==nil then return nil end
    assert(type(value)=='table','Panel waypoint must be an object')
    local waypoint=copy(value)
    assert(type(waypoint.name)=='string' and waypoint.name:match('%S'),
        'Panel waypoint requires a name')
    assert((type(waypoint.zone)=='number' and waypoint.zone==math.floor(waypoint.zone))
        or (type(waypoint.zone)=='string' and waypoint.zone:match('%S')),
        'Panel waypoint requires a numeric zone ID or zone name')
    local function finite(number)
        return type(number)=='number' and number==number and number~=math.huge and number~=-math.huge
    end
    local coordinates=finite(waypoint.x) and finite(waypoint.y)
    assert((waypoint.x==nil and waypoint.y==nil) or coordinates,
        'Panel waypoint x and y must both be numeric')
    assert(waypoint.mob_id==nil or (type(waypoint.mob_id)=='number' and waypoint.mob_id>0
        and waypoint.mob_id==math.floor(waypoint.mob_id)),
        'Panel waypoint mob_id must be a positive integer')
    assert(waypoint.mob_name==nil or (type(waypoint.mob_name)=='string' and waypoint.mob_name:match('%S')),
        'Panel waypoint mob_name must be a nonempty string')
    assert(coordinates or waypoint.mob_id~=nil or waypoint.mob_name~=nil,
        'Panel waypoint requires x/y, mob_id, or mob_name')
    waypoint.near=waypoint.near==nil and 10 or waypoint.near
    waypoint.mid=waypoint.mid==nil and 30 or waypoint.mid
    assert(finite(waypoint.near) and waypoint.near>=0,'Panel waypoint near must be nonnegative')
    assert(finite(waypoint.mid) and waypoint.mid>waypoint.near,
        'Panel waypoint mid must be greater than near')
    assert(waypoint.far==nil or (finite(waypoint.far) and waypoint.far>=waypoint.mid),
        'Panel waypoint far must be at least mid')
    assert(waypoint.show_distance==nil or type(waypoint.show_distance)=='boolean',
        'Panel waypoint show_distance must be boolean')
    waypoint.show_distance=waypoint.show_distance~=false
    waypoint.distance_format=waypoint.distance_format or '%.1f yalms'
    assert(type(waypoint.distance_format)=='string','Panel waypoint distance_format must be a string')
    waypoint.size=waypoint.size or 32
    assert(type(waypoint.size)=='number' and waypoint.size==math.floor(waypoint.size)
        and waypoint.size>=16 and waypoint.size<=64,'Panel waypoint size must be an integer from 16 to 64')
    return waypoint
end

function Config.normalize(input)
    input=copy(input or {})
    assert(type(input)=='table','Panel settings must be an object')
    local result=copy(Config.defaults)
    for key,value in pairs(input) do result[key]=value end
    result.anchor=result.anchor or {vertical='top',horizontal='left'}
    assert(type(result.anchor)=='table','Panel anchor must be an object')
    result.anchor.vertical=result.anchor.vertical or 'top'
    result.anchor.horizontal=result.anchor.horizontal or 'left'
    assert(result.anchor.vertical=='top' or result.anchor.vertical=='bottom','Panel vertical anchor must be top or bottom')
    assert(result.anchor.horizontal=='left' or result.anchor.horizontal=='right','Panel horizontal anchor must be left or right')
    for key,range in pairs({x={0,100000},y={0,100000},width={180,2000},font_size={6,30},
        history_lines={0,100},refresh_interval={0.1,60}}) do
        local value=result[key]
        assert(type(value)=='number' and value==value and value>=range[1] and value<=range[2],
            'Invalid panel setting: '..key)
        if key~='refresh_interval' then assert(value==math.floor(value),'Panel '..key..' must be an integer') end
    end
    assert(type(result.visible)=='boolean','Panel visible must be boolean')
    assert(require('./lib/ux/theme').reload()[result.theme],'Unknown panel theme: '..tostring(result.theme))
    assert(type(result.show_log)=='boolean','Panel show_log must be boolean')
    if result.height~=nil then
        assert(type(result.height)=='number' and result.height>=80 and result.height<=2000
            and result.height==math.floor(result.height),'Panel height must be an integer from 80 to 2000')
    end
    local tracking=result.tracking
    assert(type(tracking)=='table','Panel tracking must be an object')
    -- Old single-array settings belonged to the stock default set.
    if tracking[1] or next(tracking)==nil then tracking={current='default',sets={}} end
    tracking.current=tracking.current or 'default'
    tracking.sets=tracking.sets or {}
    assert(type(tracking.sets)=='table','Panel tracking.sets must be an object')
    -- Stock names are owned by Gambit, including names added in future releases.
    -- Replace saved copies before validation so obsolete definitions are ignored.
    for name,entries in pairs(Config.defaults.tracking.sets) do
        tracking.sets[name]=copy(entries)
    end
    for name,entries in pairs(tracking.sets) do
        assert(type(name)=='string' and name:match('%S'),'Tracking set names must be nonempty strings')
        assert(type(entries)=='table','Tracking sets must be arrays')
        for index,entry in pairs(entries) do
            assert(type(index)=='number' and index%1==0 and index>=1 and index<=#entries,'Tracking sets must be arrays')
            assert(type(entry)=='table','Tracking entries must be objects')
            if entry.references~=nil then
                assert(type(entry.references)=='string' and entry.references:match('%S'),
                    'Tracking references must name a tracking set')
            else
            assert(type(entry.name)=='string','Tracking entries require a name')
            if entry.show_when~=nil then
                assert(type(entry.show_when)=='string' or type(entry.show_when)=='table',
                    'Tracking show_when must be a string or array')
                if type(entry.show_when)=='table' then
                    for i,code in pairs(entry.show_when) do
                        assert(type(i)=='number' and i%1==0 and i>=1 and i<=#entry.show_when and
                            type(code)=='string','Tracking show_when arrays must contain strings')
                    end
                end
            end
            if entry.checklist~=nil then
                local function validId(id)
                    return type(id)=='string' and id:match('^[%a_][%w_-]*$')
                end
                assert(validId(entry.id),'Checklists require an id without dots or spaces')
                assert(type(entry.checklist)=='table','Checklist must be an array')
                local ids={}
                for i,item in pairs(entry.checklist) do
                    assert(type(i)=='number' and i%1==0 and i>=1 and i<=#entry.checklist,
                        'Checklist must be an array')
                    assert(type(item)=='table','Checklist items must be objects')
                    if item.format~=nil then
                        assert(type(item.format)=='table' and #item.format>=1,'Checklist format requires a format string')
                        for index,code in pairs(item.format) do
                            assert(type(index)=='number' and index%1==0 and index>=1 and index<=#item.format and
                                type(code)=='string','Checklist format must be an array of strings')
                        end
                    elseif item.expression~=nil then
                        assert(type(item.expression)=='string','Checklist item expression must be a string')
                    else
                        assert(type(item.text)=='string' and not item.text:find('[\r\n]'),
                            'Checklist items require single-line text or an expression')
                    end
                    item.id=item.id or ('objective_'..i)
                    assert(validId(item.id),'Checklist item ids must not contain dots or spaces')
                    assert(not ids[item.id],'Duplicate checklist item id: '..item.id)
                    ids[item.id]=true
                    if item.checked_when~=nil then
                        assert(type(item.checked_when)=='table','checked_when must be an array of expressions')
                        for index,code in pairs(item.checked_when) do
                            assert(type(index)=='number' and index%1==0 and index>=1 and
                                index<=#item.checked_when and type(code)=='string',
                                'checked_when must be an array of expressions')
                        end
                    end
                end
            else
                if entry.format~=nil then
                    assert(type(entry.format)=='table' and #entry.format>=1,
                        'Tracking format requires a format string')
                    for i,code in pairs(entry.format) do
                        assert(type(i)=='number' and i%1==0 and i>=1 and i<=#entry.format and
                            type(code)=='string','Tracking format must be an array of strings')
                    end
                end
                assert(entry.expression==nil or type(entry.expression)=='string' or type(entry.expression)=='table',
                    'Tracking expression must be a string or array')
                if type(entry.expression)=='table' then
                    for i,code in pairs(entry.expression) do
                        assert(type(i)=='number' and i%1==0 and i>=1 and i<=#entry.expression and type(code)=='string',
                            'Tracking expression arrays must contain strings')
                    end
                end
                assert(entry.value==nil or type(entry.value)=='string' or type(entry.value)=='table',
                    'Tracking value must be a string or array')
                if type(entry.value)=='table' then
                    for i,line in pairs(entry.value) do
                        assert(type(i)=='number' and i%1==0 and i>=1 and i<=#entry.value and type(line)=='string',
                            'Tracking value arrays must contain strings')
                    end
                end
            end
            end
        end
    end
    for _,entries in pairs(tracking.sets) do Config.expandTracking(entries,tracking.sets) end
    assert(type(tracking.current)=='string' and tracking.sets[tracking.current], 'Unknown current tracking set')
    result.tracking=tracking
    result.waypoint=Config.normalizeWaypoint(result.waypoint)
    return result
end

-- Keep runtime stock definitions out of personal preferences without mutating them.
function Config.forSave(options)
    local result=copy(options)
    if result.tracking and result.tracking.sets then
        for name in pairs(Config.defaults.tracking.sets) do
            result.tracking.sets[name]=nil
        end
    end
    return result
end
return Config
