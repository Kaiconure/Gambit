local Theme={}
local json=require('./lib/jsonlua')
local copy=require('./lib/variable-values').copy
local pieces={'center','top','bottom','left','right','top-left','top-right','bottom-left','bottom-right'}
function Theme.validate(definitions,exists)
    assert(type(definitions)=='table' and definitions.solid,'Theme registry must define solid')
    local result=copy(definitions)
    for name,skin in pairs(result) do
        assert(type(name)=='string' and name:match('^[a-z][a-z0-9_-]*$'),'Invalid theme name')
        assert(type(skin)=='table','Theme definition must be an object: '..name)
        skin.opacity=skin.opacity or 255
        if skin.texture_height~=nil then
            assert(skin.folder and type(skin.texture_height)=='number' and skin.texture_height>=1
                and skin.texture_height<=10000 and skin.texture_height==math.floor(skin.texture_height),
                'Invalid theme texture height: '..name)
        end
        assert(type(skin.opacity)=='number' and skin.opacity>=0 and skin.opacity<=255
            and skin.opacity==math.floor(skin.opacity),'Invalid theme opacity: '..name)
        if skin.folder then
            assert(type(skin.folder)=='string' and skin.folder:match('^[%w_/-]+/$')
                and not skin.folder:match('^/'),'Theme folder must be an addon-relative directory: '..name)
            assert(type(skin.border)=='number' and skin.border>=1 and skin.border<=100
                and skin.border==math.floor(skin.border),'Invalid theme border: '..name)
            if exists then
                skin.pieces={}
                for _,piece in ipairs(pieces) do
                    local path=skin.folder..piece..'.png'
                    skin.pieces[piece]=not not exists(path)
                    if piece=='center' then assert(skin.pieces[piece],'Missing theme asset: '..path) end
                end
            end
        else
            assert(type(skin.color)=='table' and #skin.color==3,'Solid theme requires an RGB color: '..name)
            for _,value in ipairs(skin.color) do
                assert(type(value)=='number' and value>=0 and value<=255 and value==math.floor(value),
                    'Invalid theme color: '..name)
            end
        end
    end
    return result
end
function Theme.reload()
    local root=windower and windower.addon_path or ''
    local file=assert(io.open(root..'content/ui/themes.json','r'))
    local source=file:read('*a'); file:close()
    local definitions=Theme.validate(json.parse(source),function(path)
        local asset=io.open(root..path,'rb')
        if not asset then return false end
        asset:close(); return true
    end)
    Theme.backgrounds=definitions
    return definitions
end
Theme.reload()
Theme.colors={green={100,235,130},red={255,80,80},yellow={245,215,110},orange={245,160,80},
    white={255,255,255},turquoise={100,225,215},magenta={235,100,235},
    target_player={193,251,255},target_idle={241,241,183},target_engaged={255,130,130},
    target_outside_claim={244,122,244},target_other_player={255,255,255},
    target_npc={100,235,130},target_dead={160,160,160},target_invalid={160,160,160},
    number={241,241,183},status_pending={245,215,110},
    status_interrupted={255,130,130},status_completed={100,235,130},
    heading={245,245,250},subheading={155,200,245},body={230,230,238},
    version={240,240,24},
    log_odd={225,230,240},log_even={165,185,210},log_latest={255, 255, 0}}
Theme.styles={heading={font='Segoe UI',size_offset=2,bold=true,color='heading'},
    subheading={font='Segoe UI',size_offset=0,bold=true,color='subheading'},
    body={font='Consolas',size_offset=0,bold=false,color='body'}}
function Theme.color(text,name) text:color(unpack(Theme.colors[name])) end
function Theme.apply(text,role,size)
    local style=Theme.styles[role or 'body']
    text:font(style.font,'Segoe UI Symbol','Meiryo')
    text:size(size+style.size_offset); text:bold(style.bold)
    Theme.color(text,style.color)
end
return Theme
