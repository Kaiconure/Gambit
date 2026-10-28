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
    height = 140,
    font_size = 10,
    history_lines = 4,
    refresh_interval = 0.5,
    tracking =
    {
        current = 'default',
        sets =
        {
            default =
            {
                {name='Strategy',expression={'gambit.strategy'}},
                {name='Namespace',expression={"gambit.namespace or '(base settings)'"}},
                {name='Skillchain Progress',expression={"(party_weapon_skill and party_weapon_skill.name or nil) and format('%s%s', party_weapon_skill.name, skillchain and skillchain.name and (' → ' .. skillchain.name) or '')"}},
                {name='Spell Casting', expression={"(gambit.last_spell and gambit.last_spell.name and (gambit.last_spell.status == 'casting' or gambit.last_spell.age < 5) or nil) and format('%s%s (%s)', gambit.last_spell.name, gambit.last_spell.target and gambit.last_spell.target.name and (' → ' .. gambit.last_spell.target.name) or '', gambit.last_spell.status)"}},
                {name='Job Ability', expression={"(gambit.last_ability and gambit.last_ability.name and gambit.last_ability.age < 5 or nil) and format('%s%s', gambit.last_ability.name, gambit.last_ability.target and gambit.last_ability.target.name and (' → ' .. gambit.last_ability.target.name) or '')"}}
            },
            none={}
        }
    }
}

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
    -- Accept the initial prototype's single tracking array.
    if tracking[1] or next(tracking)==nil then tracking={current='default',sets={default=tracking,none={}}} end
    assert(type(tracking.sets)=='table','Panel tracking.sets must be an object')
    for name,entries in pairs(tracking.sets) do
        assert(type(name)=='string' and name:match('%S'),'Tracking set names must be nonempty strings')
        assert(type(entries)=='table','Tracking sets must be arrays')
        for index,entry in pairs(entries) do
            assert(type(index)=='number' and index%1==0 and index>=1 and index<=#entries,'Tracking sets must be arrays')
            assert(type(entry)=='table' and type(entry.name)=='string','Tracking entries require a name')
            assert(entry.expression==nil or type(entry.expression)=='string' or type(entry.expression)=='table',
                'Tracking expression must be a string or array')
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
    assert(type(tracking.current)=='string' and tracking.sets[tracking.current], 'Unknown current tracking set')
    result.tracking=tracking
    return result
end
return Config
