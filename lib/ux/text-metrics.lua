local widths=require('./meta/panel-font-widths')
local Buffer=require('./lib/ux/log-buffer')
local Metrics={}
function Metrics.advance(item,character)
    local size=item.fontSize
    if item.font=='Consolas' then return size*0.8 end
    local width=widths[item.bold and 'bold' or 'regular'][character:byte()]
    if #character==1 and width then return width*size end
    -- Wide fallback glyphs and unknown scripts get a conservative full em.
    return size*4/3
end
function Metrics.width(item,text)
    local key=item.font..':'..item.fontSize..':'..tostring(item.bold)
    local cached=item.measured
    if cached and cached.text==text and cached.key==key then return cached.width end
    local longest=0
    for line in (Buffer.uncolored(text)..'\n'):gmatch('(.-)\n') do
        local width=0
        for character in line:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
            width=width+Metrics.advance(item,character)
        end
        longest=math.max(longest,width)
    end
    item.measured={text=text,key=key,width=longest}
    return longest
end
function Metrics.clip(item,text,pixels)
    if Metrics.width(item,text)<=pixels then return text end
    return Buffer.clip(text,pixels,function(character) return Metrics.advance(item,character) end)
end
return Metrics
