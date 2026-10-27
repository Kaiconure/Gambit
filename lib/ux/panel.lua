-- Small Windower surface: movable title bar, labels, and clickable buttons.
local Panel = {}
local Theme=require('./lib/ux/theme')
local Background=require('./lib/ux/background')
Panel.__index = Panel
function Panel.new(options, primitives)
    local self=setmetatable({x=options.x,y=options.y,width=options.width,
        height=options.height,labels={},buttons={},visible=false},Panel)
    self.primitives=primitives
    self.onMove=options.on_move
    self.background=Background.new(options.theme,primitives)
    return self
end
function Panel:label(x,y,size,role)
    local text=self.primitives.texts.new('')
    text:visible(false)
    text:draggable(false); text:bg_visible(false)
    Theme.apply(text,role,size)
    local item={text=text,x=x,y=y}
    self.labels[#self.labels+1]=item
    return item
end
function Panel:button(x,y,width,height,size,callback,role)
    local item=self:label(x,y,size,role)
    item.width=width; item.height=height; item.callback=callback
    self.buttons[#self.buttons+1]=item
    return item
end
function Panel:layout()
    -- Hide primitives without releasing an active title-bar drag capture.
    if self.visible then
        self.background:visible(false)
        for _, item in ipairs(self.labels) do item.text:visible(false) end
    end
    self.background:layout(self.x,self.y,self.width,self.height)
    for _, item in ipairs(self.labels) do item.text:pos(self.x+item.x,self.y+item.y) end
    if self.visible then self:show(true) end
end
function Panel:show(visible)
    self.visible=visible
    self.background:visible(visible)
    for _, item in ipairs(self.labels) do item.text:visible(visible) end
    if not visible then self.capture=nil end
end
local function inside(x,y,left,top,width,height)
    return x>=left and y>=top and x<left+width and y<top+height
end
function Panel:mouse(kind,x,y,blocked)
    if not self.visible then return end
    if self.capture then
        if kind==0 then
            if self.capture.drag then
                self.x=math.max(0,x-self.capture.x); self.y=math.max(0,y-self.capture.y)
                self:layout()
            end
            return true
        elseif kind==2 then
            local captured=self.capture; self.capture=nil
            if captured.drag and self.onMove then self.onMove(self.x,self.y) end
            local button=captured.button
            if button and inside(x,y,self.x+button.x,self.y+button.y,button.width,button.height) then button.callback() end
            return true
        end
    end
    if blocked then return end
    if kind==1 and inside(x,y,self.x,self.y,self.width,self.height) then
        for _, button in ipairs(self.buttons) do
            if inside(x,y,self.x+button.x,self.y+button.y,button.width,button.height) then
                self.capture={button=button}; return true
            end
        end
        if y<self.y+28 then self.capture={drag=true,x=x-self.x,y=y-self.y} end
        return true
    end
end
function Panel:destroy()
    self:show(false)
    for _, item in ipairs(self.labels) do item.text:destroy() end
    self.background:destroy()
end
return Panel
