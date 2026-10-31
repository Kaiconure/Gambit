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
                    name='Automation',
                    expression={
                        '"Actions: " .. color_text(format("%s (%s namespace)", gambit.entrypoint_relative, gambit.namespace or "global"), 100,235,130)',
                        '"Events: " .. color_text(format("%s (%s namespace)", gambit.events_relative, gambit.event_namespace or "global"), 100,235,130)',
                        '"Target: " .. color_mob(cursor) .. (cursor and cursor.valid_target and format(" (%s / %s)", color_number(cursor.id), color_number(format("%03X", cursor.index))) or "")'
                    }
                },
                {
                    name='Skillchain',
                    expression={
                        "(party_weapon_skill and party_weapon_skill.name or nil) and format('%s%s%s (~%ss)', color_element(party_weapon_skill.skill or party_weapon_skill), skillchain and skillchain.name and (' → ' .. color_skillchain(skillchain)) or '', bt and (' → ' .. color_mob(bt)) or '', color_number(format('%.1f', (skillchain or party_weapon_skill).lifetime)))"
                    }
                },
                {
                    name='Spell',
                    expression={
                        "(gambit.last_spell and gambit.last_spell.name and (gambit.last_spell.status == 'casting' or gambit.last_spell.age < 5) or nil) and format('%s%s (%s)', color_element(gambit.last_spell), gambit.last_spell.target and gambit.last_spell.target.name and (' → ' .. color_mob(gambit.last_spell.target)) or '', color_status(gambit.last_spell.status))"
                    }
                },
                {
                    name='Job Ability',
                    expression={
                        "(gambit.last_ability and gambit.last_ability.name and gambit.last_ability.age < 5 or nil) and format('%s%s', color_element(gambit.last_ability), gambit.last_ability.target and gambit.last_ability.target.name and (' → ' .. color_mob(gambit.last_ability.target)) or '')"
                    }
                }
            },
            compact = {
                {
                    name='Automation',
                    expression={
                        '"Actions: " .. color_text(format("%s (%s namespace)", gambit.entrypoint_relative, gambit.namespace or "global"), 100,235,130)',
                        '"Events: " .. color_text(format("%s (%s namespace)", gambit.events_relative, gambit.event_namespace or "global"), 100,235,130)',
                        '"Target: " .. color_mob(cursor) .. (cursor and cursor.valid_target and format(" (%s / %s)", color_number(cursor.id), color_number(format("%03X", cursor.index))) or "")'
                    }
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
                    assert(type(item)=='table' and type(item.text)=='string' and not item.text:find('[\r\n]'),
                        'Checklist items require single-line text')
                    item.id=item.id or ('objective_'..i)
                    assert(validId(item.id),'Checklist item ids must not contain dots or spaces')
                    assert(not ids[item.id],'Duplicate checklist item id: '..item.id)
                    ids[item.id]=true
                end
            else
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
