local Theme=require('./lib/ux/theme')
local Background={}
Background.__index=Background
function Background.new(name,deps)
    local skin=assert(Theme.backgrounds[name or 'solid'],'Unknown panel theme')
    local self=setmetatable({skin=skin,parts={}},Background)
    local function image(key)
        if skin.pieces then
            if not skin.pieces[key] then return end
            local vertical,horizontal=key:match('^(%a+)%-(%a+)$')
            if vertical and (not skin.pieces[vertical] or not skin.pieces[horizontal]) then return end
        end
        local item=deps.images.new({texture={fit=false}})
        item:visible(false)
        item:draggable(false); item:alpha(skin.opacity)
        if skin.folder then
            item:color(255,255,255)
            -- Explicit layout owns dimensions; asynchronous texture loading must
            -- not resize the primitive back to the PNG's native dimensions.
            item:fit(false)
            item:path((deps.windower and deps.windower.addon_path or '')..skin.folder..key..'.png')
            item:repeat_xy(1,1)
        else item:color(unpack(skin.color)) end
        item:visible(false)
        self.parts[key]=item
    end
    if skin.folder then
        -- Center first so the decorative frame always draws over it.
        for _, key in ipairs({'center','top','bottom','left','right','top-left','top-right','bottom-left','bottom-right'}) do image(key) end
    else image('center') end
    return self
end
function Background:layout(x,y,width,height)
    local b=self.skin.border or 0
    b=math.min(b,width/2,height/2)
    local l=self.parts.left and b or 0
    local r=self.parts.right and b or 0
    local t=self.parts.top and b or 0
    local d=self.parts.bottom and b or 0
    local w,h=width-l-r,height-t-d
    local rects={center={x+l,y+t,w,h},top={x+l,y,w,b},bottom={x+l,y+height-b,w,b},
        left={x,y+t,b,h},right={x+width-b,y+t,b,h},
        ['top-left']={x,y,b,b},['top-right']={x+width-b,y,b,b},
        ['bottom-left']={x,y+height-b,b,b},['bottom-right']={x+width-b,y+height-b,b,b}}
    for key,item in pairs(self.parts) do
        local r=rects[key]; item:pos(r[1],r[2]); item:size(r[3],r[4])
        if key=='center' and self.skin.texture_height then
            -- Preserve stripe spacing as panel height changes, cropping/repeating
            -- the texture rather than squeezing the entire image into the panel.
            item:repeat_xy(1,h/self.skin.texture_height)
        end
    end
end
function Background:visible(value) for _, item in pairs(self.parts) do item:visible(value) end end
function Background:destroy() for _, item in pairs(self.parts) do item:destroy() end end
return Background
