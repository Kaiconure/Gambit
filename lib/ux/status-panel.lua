local Panel=require('./lib/ux/panel')
local Buffer=require('./lib/ux/log-buffer')
local factory=require('./lib/execution-factory')
local Config=require('./lib/ux/status-config')
local copy=require('./lib/variable-values').copy
local Theme=require('./lib/ux/theme')
local Status={}
Status.__index=Status
Status.defaults=Config.defaults
local function displayWidth(options)
    return math.max(options.width,options.show_log and 600 or 0)
end
local function longestLine(text)
    text=Buffer.uncolored(text)
    local longest=0
    for line in (text..'\n'):gmatch('(.-)\n') do
        -- Count UTF-8 code points rather than bytes (e.g. the right arrow).
        local _,count=line:gsub('[^\128-\191]','')
        longest=math.max(longest,count)
    end
    return longest
end
local function textWidth(item,text,fallback)
    item.text:text(text)
    -- Windower can report a positive but stale extent after text changes,
    -- especially when a hidden row reappears. Use stable spacing immediately
    -- rather than positioning from the previous frame's measured text.
    return longestLine(text)*fallback
end
function Status.new(deps,options)
    local self=setmetatable({deps=deps},Status)
    self:configure(options)
    self.unsubscribe=deps.subscribe(function(message) self.buffer:add(message) end)
    self.frameEvent=deps.windower.register_event('prerender',function() self:update() end)
    self.mouseEvent=deps.windower.register_event('mouse',function(kind,x,y,delta,blocked)
        return self.panel:mouse(kind,x,y,blocked)
    end)
    return self
end
function Status:configure(options,trackingOverride)
    options=Config.normalize(options)
    if trackingOverride==nil then trackingOverride=self.trackingOverride end
    if trackingOverride==false then trackingOverride=nil end
    local tracking=options.tracking.sets[options.tracking.current]
    if trackingOverride~=nil then
        local temporary=copy(options)
        temporary.tracking={current='temporary',sets={temporary=trackingOverride}}
        tracking=Config.normalize(temporary).tracking.sets.temporary
    end
    self.trackingOverride=trackingOverride~=nil and copy(tracking) or nil
    if self.panel then self.panel:destroy() end
    self.options=options; self.entries={}; self.nextUpdate=0
    self.buffer=self.buffer or Buffer.new(options.history_lines,self.deps.windower.from_shift_jis)
    self.buffer.limit=options.history_lines
    while #self.buffer.lines>options.history_lines do table.remove(self.buffer.lines,1); table.remove(self.buffer.ids,1) end
    local lineHeight=math.ceil(options.font_size*1.8)
    local trackingLines=0
    for _, entry in ipairs(tracking) do
        trackingLines=trackingLines+((entry.expression==nil and type(entry.value)=='table') and math.max(1,#entry.value)+1 or 1)
    end
    -- Consolas advances roughly 0.8 screen pixels per point at standard DPI.
    self.characterWidth=options.font_size*0.8
    local width=displayWidth(options)
    self.columns=math.max(8,math.floor((width-20)/self.characterWidth))
    self.panel=Panel.new({x=options.x,y=options.y,width=width,
        theme=options.theme,
        height=options.height or (72+(trackingLines+options.history_lines+1)*lineHeight),
        resolve_position=function(width,height) return self:screenPosition(width,height) end,
        on_move=function(x,y)
            self.options.x,self.options.y=self:anchorOffsets(x,y)
            self.panel:layout()
            self:persist()
        end},self.deps)
    self.title=self.panel:label(10,5,options.font_size,'heading')
    self.titleWidth=textWidth(self.title,'Gambit Status',(options.font_size+2)*0.8)
    self.toggle=self.panel:button(18+self.titleWidth,5,5*(options.font_size+2)*0.8,lineHeight,options.font_size,self.deps.toggle,'heading')
    self.toggle.text:bold(true)
    self.strategy=self.panel:label(self.toggle.x+self.toggle.width+2,5,options.font_size,'heading')
    self.strategy.text:bold(true)
    local versionSize=math.max(6,options.font_size-3)
    self.version=self.panel:label(0,(self.panel.background.skin.border or 0)+1,versionSize,'body')
    Theme.color(self.version.text,'version')
    local version=self.deps.version or (_addon and _addon.version) or __version
    self.versionText=version and ('v'..tostring(version):gsub('^v','')) or ''
    self.versionWidth=textWidth(self.version,self.versionText,versionSize*0.8)
    if self.version.text.italic then self.version.text:italic(true) end
    local row=1
    for _,definition in ipairs(tracking) do
        local entry={definition=definition,label=self.panel:label(10,32+row*lineHeight,options.font_size,'subheading'),
            valueLabel=self.panel:label(18,32+(row+1)*lineHeight,options.font_size,'subheading')}
        entry.valueLabel.text:bold(false)
        Theme.color(entry.valueLabel.text,'body')
        row=row+((definition.expression==nil and type(definition.value)=='table') and math.max(1,#definition.value)+1 or 1)
        if definition.expression~=nil then
            if type(definition.expression)=='table' then
                entry.fns={}
                for _,code in ipairs(definition.expression) do
                    local ok,fn=pcall(factory.get,code)
                    if ok then entry.fns[#entry.fns+1]=fn else entry.error=true end
                end
            else
                local ok,fn=pcall(factory.get,definition.expression)
                if ok then entry.fn=fn else entry.error=true end
            end
        end
        self.entries[#self.entries+1]=entry
    end
    self.logHeading=self.panel:label(10,0,options.font_size,'subheading')
    self.logs={}
    for i=1,options.history_lines do self.logs[i]=self.panel:label(10,0,options.font_size,'body') end
    self.log=self.logs[1] or self.panel:label(10,0,options.font_size,'body')
    self.panel:layout(); self.panel:show(false)
end
function Status:persist()
    if self.deps.save then self.deps.save(copy(self.options)) end
end
function Status:setVisible(visible)
    self.options.visible=visible
    self:update(); self:persist()
end
function Status:setLogVisible(visible)
    self.options.show_log=visible
    self.nextUpdate=0
    self:update(); self:persist()
end
function Status:setTracking(name)
    assert(self.options.tracking.sets[name], 'Unknown tracking set: '..tostring(name))
    local options=copy(self.options); options.tracking.current=name
    self:configure(options,false); self:update(); self:persist()
end
function Status:setTemporaryTracking(entries,append)
    -- Keep temporary rows outside options so unrelated preference saves cannot
    -- persist them. Display reconfiguration retains these rows until a reload
    -- or explicit tracking selection/reset clears the override.
    local override=entries
    assert(append==nil or type(append)=='boolean','Panel tracking append must be boolean')
    if append and entries~=nil then
        -- Validate the incoming array before merging so malformed keys cannot
        -- be silently discarded by ipairs. configure validates the result too.
        local temporary=copy(self.options)
        temporary.tracking={current='temporary',sets={temporary=entries}}
        local incoming=Config.normalize(temporary).tracking.sets.temporary
        override=copy(self.trackingOverride or self.options.tracking.sets[self.options.tracking.current])
        for _,entry in ipairs(incoming) do override[#override+1]=entry end
    end
    if override==nil then override=false end
    self:configure(self.options,override)
    self:update()
    return true
end
function Status:resetPosition()
    self:setPosition(Status.defaults.x,Status.defaults.y)
end
function Status:reset()
    self:configure(copy(Config.defaults),false)
    self:update()
    self:persist()
end
function Status:viewport()
    local get=self.deps.windower.get_windower_settings
    local screen=get and get() or {}
    return screen.ui_x_res or 0,screen.ui_y_res or 0
end
function Status:screenPosition(width,height)
    local sw,sh=self:viewport()
    local anchor=self.options.anchor
    local x=anchor.horizontal=='right' and sw-width-self.options.x or self.options.x
    local y=anchor.vertical=='bottom' and sh-height-self.options.y or self.options.y
    return math.max(0,x),math.max(0,y)
end
function Status:anchorOffsets(x,y)
    local sw,sh=self:viewport()
    local anchor=self.options.anchor
    return math.max(0,anchor.horizontal=='right' and sw-self.panel.width-x or x),
        math.max(0,anchor.vertical=='bottom' and sh-self.panel.height-y or y)
end
function Status:setAnchor(vertical,horizontal)
    local options=copy(self.options)
    options.anchor={vertical=vertical,horizontal=horizontal}
    options=Config.normalize(options)
    self.options.anchor=options.anchor
    self.panel:layout(); self:persist()
end
function Status:setPosition(x,y)
    local options=copy(self.options)
    if x~=nil then options.x=x end
    if y~=nil then options.y=y end
    options=Config.normalize(options)
    self.options.x=options.x; self.options.y=options.y
    self.panel.x=self.options.x; self.panel.y=self.options.y; self.panel:layout()
    self:persist()
end
function Status:setSize(width,height)
    local options=copy(self.options)
    if width~=nil then options.width=width end
    if height=='auto' then options.height=nil
    elseif height~=nil then options.height=height end
    self:configure(options)
    if height=='auto' then self.options.height=nil end
    self:update(); self:persist()
end
function Status:setTheme(name)
    local options=copy(self.options); options.theme=name
    self:configure(options); self:update(); self:persist()
end
function Status:setFontSize(size)
    local options=copy(self.options); options.font_size=size
    self:configure(options); self:update(); self:persist()
end
function Status:setText(item,text)
    local lineHeight=math.ceil(self.options.font_size*1.8)
    local capacity=math.max(0,math.floor((self.panel.height-item.y-8)/lineHeight))
    local lines={}
    for line in (text..'\n'):gmatch('(.-)\n') do
        if #lines>=capacity then break end
        -- Subtract the indent in pixels before converting to characters.
        -- Rounding the panel down and the indent up separately can lose a
        -- whole character even when automatic width reserved enough space.
        local columns=math.max(0,math.floor((self.panel.width-item.x-10)/self.characterWidth+0.000001))
        lines[#lines+1]=Buffer.clip(line,columns)
    end
    item.text:text(table.concat(lines,'\n'))
end
function Status:update()
    local ready=not self.deps.ready or self.deps.ready()
    local visible=ready and self.deps.loggedIn() and self.options.visible
    if not visible then
        if self.panel.visible then self.panel:show(false) end
        return
    end
    local enabled=self.deps.enabled()
    self.toggle.text:text(enabled and '[on]' or '[off]')
    Theme.color(self.toggle.text,enabled and 'green' or 'red')
    local strategy=self.deps.strategy and self.deps.strategy()
    local strategyText=strategy and ('['..tostring(strategy)..']') or ''
    if strategyText~=self.strategyText then self.nextUpdate=0 end
    self.strategyText=strategyText
    self.strategyWidth=textWidth(self.strategy,strategyText,(self.options.font_size+2)*0.8)
    Theme.color(self.strategy.text,(strategy=='aggressor' or strategy=='puller') and 'red' or 'green')
    if self.panel.visible and os.clock()<self.nextUpdate then return end
    self.nextUpdate=os.clock()+self.options.refresh_interval
    for _, entry in ipairs(self.entries) do
        local value=entry.definition.value
        if entry.definition.expression~=nil then
            value='[error]'
            if (entry.fn or entry.fns) and not entry.error then
                local ok,context=pcall(self.deps.context,'status panel')
                if not ok or not context then value='[unavailable]'
                else
                    if entry.fns then
                        value={}
                        for _,fn in ipairs(entry.fns) do
                            setfenv(fn,context)
                            local success,result=pcall(fn)
                            if not success then entry.error=true; value='[error]'; break end
                            if result~=nil then
                                if type(result)=='table' then
                                    for _,item in ipairs(result) do value[#value+1]=item end
                                else value[#value+1]=result end
                            end
                        end
                    else
                        setfenv(entry.fn,context)
                        local success,result=pcall(entry.fn)
                        if success then value=result else entry.error=true end
                    end
                end
            end
        end
        entry.hidden=value==nil or (type(value)=='table' and #value==0)
        entry.inline=type(entry.definition.expression or entry.definition.value)~='table' and type(value)~='table'
        local lines={}
        local function append(text)
            text=Buffer.plain(text,self.deps.windower.from_shift_jis)
            for line in (text..'\n'):gmatch('(.-)\n') do lines[#lines+1]=line end
        end
        if type(value)=='table' then
            for _, item in ipairs(value) do append(item) end
        else append(value==nil and '' or value) end
        entry.display=table.concat(lines,'\n'); entry.lineCount=math.max(1,#lines)
    end
    local headerEnd=self.strategyWidth>0 and (self.strategy.x+self.strategyWidth) or (self.toggle.x+self.toggle.width)
    local width=math.max(displayWidth(self.options),headerEnd+self.versionWidth+20)
    for _,entry in ipairs(self.entries) do
        if not entry.hidden then
            local name=Buffer.plain(entry.definition.name,self.deps.windower.from_shift_jis)
            entry.heading=name..(entry.inline and name~='' and ':' or '')
            local headingWidth=textWidth(entry.label,entry.heading,self.characterWidth)
            entry.valueLabel.x=entry.inline and (10+headingWidth+8) or 18
            local indent=entry.valueLabel.x-10
            width=math.max(width,20+math.max(headingWidth,longestLine(entry.display)*self.characterWidth+indent))
        end
    end
    self.panel.width=math.ceil(width)
    self.columns=math.max(8,math.floor((self.panel.width-20)/self.characterWidth))
    self.version.x=self.panel.width-self.versionWidth-6
    -- Expression arrays can change size at runtime: reflow rows and automatic
    -- height before clipping, without rebuilding controls or disturbing dragging.
    local lineHeight=math.ceil(self.options.font_size*1.8)
    local y=math.max(32,5+math.ceil((self.options.font_size+2)*1.8))
    for _, entry in ipairs(self.entries) do
        entry.label.y=y; entry.valueLabel.y=y+(entry.inline and 0 or lineHeight)
        if not entry.hidden then y=y+(entry.lineCount+(entry.inline and 0 or 1))*lineHeight end
    end
    local logLines=self.options.show_log and self.options.history_lines or 0
    self.logHeading.y=y+12
    local logY=self.logHeading.y+(logLines>0 and lineHeight or 0)
    local requiredHeight=math.max(80,(logLines>0 and logY or y)+logLines*lineHeight+12)
    self.panel.height=math.max(self.options.height or 0,requiredHeight)
    for i,item in ipairs(self.logs) do item.y=logY+(i-1)*lineHeight end
    self.panel:layout()
    self:setText(self.logHeading,logLines>0 and 'Log' or '')
    for _, entry in ipairs(self.entries) do
        self:setText(entry.label,entry.hidden and '' or entry.heading)
        self:setText(entry.valueLabel,entry.hidden and '' or entry.display)
        Theme.color(entry.valueLabel.text,entry.error and 'red' or 'body')
    end
    local visibleLogLines=math.min(#self.logs,math.max(0,math.floor((self.panel.height-logY-8)/lineHeight)))
    local firstLogLine=math.max(1,#self.buffer.lines-visibleLogLines+1)
    for i,item in ipairs(self.logs) do
        local index=firstLogLine+i-1
        local id=self.buffer.ids[index] or index
        Theme.color(item.text,index==#self.buffer.lines and 'log_latest' or (id%2==1 and 'log_odd' or 'log_even'))
        self:setText(item,self.options.show_log and i<=visibleLogLines and (self.buffer.lines[index] or '') or '')
    end
    -- Reveal a newly built/reconfigured panel only after final sizing and text.
    if not self.panel.visible then self.panel:show(true) end
end
function Status:destroy()
    self.unsubscribe()
    self.deps.windower.unregister_event(self.frameEvent)
    self.deps.windower.unregister_event(self.mouseEvent)
    self.panel:destroy()
end
return Status
