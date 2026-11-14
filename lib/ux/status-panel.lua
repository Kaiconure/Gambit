local Panel=require('./lib/ux/panel')
local Buffer=require('./lib/ux/log-buffer')
local factory=require('./lib/execution-factory')
local Config=require('./lib/ux/status-config')
local copy=require('./lib/variable-values').copy
local Theme=require('./lib/ux/theme')
local Metrics=require('./lib/ux/text-metrics')
local PanelContext=require('./lib/ux/panel-context')
local Waypoint=require('./lib/ux/waypoint')
local Background=require('./lib/ux/background')
local Status={}
Status.__index=Status
Status.defaults=Config.defaults
local function displayWidth(options)
    return math.max(options.width,options.show_log and 600 or 0)
end
local function textWidth(item,text)
    item.text:text(text)
    -- Windower can report a positive but stale extent after text changes,
    -- especially when a hidden row reappears. Use stable spacing immediately
    -- rather than positioning from the previous frame's measured text.
    return Metrics.width(item,text)
end
local function sameWaypointSource(a,b)
    return a~=nil and b~=nil and a.zone==b.zone and a.mob_id==b.mob_id
        and a.mob_name==b.mob_name and a.x==b.x and a.y==b.y
end
local function entryVisibility(entry,deps)
    if not entry.showFns then return true end
    if entry.showError then return true,'[error]' end
    local ok,context=pcall(deps.context,'status panel visibility')
    if not ok or not context then return true,'[unavailable]' end
    local resetColor=PanelContext.attach(context,deps.canShareClaim)
    resetColor()
    for _,fn in ipairs(entry.showFns) do
        setfenv(fn,context)
        local success,result=pcall(fn)
        if not success then entry.showError=true; return true,'[error]' end
        if not result then return false,nil,context,resetColor end
    end
    return true,nil,context,resetColor
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
function Status:configure(options,trackingOverride,waypointOverride)
    options=Config.normalize(options)
    local previousWaypoint=self.waypoint
    if trackingOverride==nil then trackingOverride=self.trackingOverride end
    if trackingOverride==false then trackingOverride=nil end
    local tracking=options.tracking.sets[options.tracking.current]
    if trackingOverride~=nil then
        local temporary=copy(options)
        temporary.tracking.current='temporary'
        temporary.tracking.sets.temporary=trackingOverride
        tracking=Config.normalize(temporary).tracking.sets.temporary
    end
    self.trackingOverride=trackingOverride~=nil and copy(tracking) or nil
    tracking=Config.expandTracking(tracking,options.tracking.sets)
    local supplementNames={}
    for name,enabled in pairs(self.trackingSupplements or {}) do
        if enabled then supplementNames[#supplementNames+1]=name end
    end
    table.sort(supplementNames)
    for _,name in ipairs(supplementNames) do
        local supplement=assert(options.tracking.sets[name],
            'Unknown panel tracking supplement: '..tostring(name))
        for _,entry in ipairs(Config.expandTracking(supplement,options.tracking.sets)) do
            tracking[#tracking+1]=entry
        end
    end
    if waypointOverride==nil then waypointOverride=self.waypointOverride end
    if waypointOverride==false then waypointOverride=nil end
    waypointOverride=Config.normalizeWaypoint(waypointOverride)
    self.waypointOverride=waypointOverride and copy(waypointOverride) or nil
    self.waypointConfig=self.waypointOverride or options.waypoint
    if self.waypoint and self.waypoint.background then self.waypoint.background:destroy() end
    if self.panel then self.panel:destroy() end
    self.options=options; self.entries={}; self.nextUpdate=0
    self.buffer=self.buffer or Buffer.new(options.history_lines,self.deps.windower.from_shift_jis)
    self.buffer.limit=options.history_lines
    while #self.buffer.lines>options.history_lines do table.remove(self.buffer.lines,1); table.remove(self.buffer.ids,1) end
    local lineHeight=math.ceil(options.font_size*1.8)
    local trackingLines=0
    for _, entry in ipairs(tracking) do
        trackingLines=trackingLines+((entry.format==nil and entry.expression==nil and type(entry.value)=='table') and
            math.max(1,#entry.value)+1 or 1)
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
    if self.waypointConfig then
        local waypoint=self.waypointConfig
        self.waypoint={config=waypoint,
            background=Background.new(options.theme,self.deps),
            name=self.panel:label(0,5,options.font_size,'subheading'),
            icon=self.panel:icon(0,0,waypoint.size),
            distance=self.panel:label(0,0,math.max(6,options.font_size-1),'body')}
        if previousWaypoint and sameWaypointSource(previousWaypoint.config,waypoint) then
            self.waypoint.lastKnown=previousWaypoint.lastKnown
        end
        self.waypoint.icon.visible=false
        Theme.color(self.waypoint.distance.text,'number')
    else self.waypoint=nil end
    self.title=self.panel:label(10,5,options.font_size,'heading')
    self.titleWidth=textWidth(self.title,'Gambit Status')
    self.toggle=self.panel:button(18+self.titleWidth,5,5*(options.font_size+2)*0.8,lineHeight,options.font_size,self.deps.toggle,'heading')
    self.toggle.text:bold(true)
    self.strategy=self.panel:label(self.toggle.x+self.toggle.width+2,5,options.font_size,'heading')
    self.strategy.text:bold(true)
    self.targetDistance=self.panel:label(0,7,math.max(6,options.font_size-2),'heading')
    self.targetDistance.text:bold(false)
    local versionSize=math.max(6,options.font_size-3)
    self.version=self.panel:label(0,(self.panel.background.skin.border or 0)+1,versionSize,'body')
    Theme.color(self.version.text,'version')
    local version=self.deps.version or (_addon and _addon.version) or __version
    self.versionText=version and ('v'..tostring(version):gsub('^v','')) or ''
    self.versionWidth=textWidth(self.version,self.versionText)
    if self.version.text.italic then self.version.text:italic(true) end
    local row=1
    for _,definition in ipairs(tracking) do
        local entry={definition=definition,label=self.panel:label(10,32+row*lineHeight,options.font_size,'subheading'),
            valueLabel=self.panel:label(18,32+(row+1)*lineHeight,options.font_size,'subheading')}
        entry.valueLabel.text:bold(false)
        entry.valueLabel.bold=false
        Theme.color(entry.valueLabel.text,'body')
        if definition.show_when~=nil then
            entry.showFns={}
            local conditions=type(definition.show_when)=='table' and definition.show_when or {definition.show_when}
            for _,code in ipairs(conditions) do
                local ok,fn=pcall(factory.get,code)
                if ok then entry.showFns[#entry.showFns+1]=fn else entry.showError=true end
            end
        end
        row=row+((definition.format==nil and definition.expression==nil and type(definition.value)=='table') and
            math.max(1,#definition.value)+1 or 1)
        if definition.checklist~=nil then
            entry.checks={}
            for _,objective in ipairs(definition.checklist) do
                local path='vars.panel.'..definition.id..'.'..objective.id
                local button=self.panel:button(18,0,0,lineHeight,options.font_size,function()
                    if objective.checked_when~=nil then return end
                    local context=self.deps.context('status panel checklist')
                    context.setVar(path,not context.getVar(path))
                    self.nextUpdate=0
                    self:update()
                end,'subheading')
                button.text:bold(false)
                button.bold=false
                Theme.color(button.text,'checklist')
                button.onHover=function(hovered)
                    Theme.color(button.text,hovered and objective.checked_when==nil and 'yellow' or 'checklist')
                end
                local size=math.max(10,math.floor(options.font_size*1.2+0.5))
                local icon=self.panel:icon(18,0,size)
                local check={button=button,path=path,objective=objective,icon=icon,size=size,
                    automatic=objective.checked_when~=nil}
                if objective.format~=nil then
                    check.formatFns={}
                    for index=2,#objective.format do
                        local ok,fn=pcall(factory.get,objective.format[index])
                        if ok then check.formatFns[#check.formatFns+1]=fn else check.labelError=true end
                    end
                elseif objective.expression~=nil then
                    local ok,fn=pcall(factory.get,objective.expression)
                    if ok then check.labelFn=fn else check.labelError=true end
                end
                if objective.checked_when~=nil then
                    check.conditions={}
                    for _,code in ipairs(objective.checked_when) do
                        local ok,fn=pcall(factory.get,code)
                        if ok then check.conditions[#check.conditions+1]=fn else check.conditionError=true end
                    end
                end
                entry.checks[#entry.checks+1]=check
            end
        elseif definition.format~=nil then
            entry.formatFns={}
            for index=2,#definition.format do
                local ok,fn=pcall(factory.get,definition.format[index])
                if ok then entry.formatFns[#entry.formatFns+1]=fn else entry.error=true end
            end
        elseif definition.expression~=nil then
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
    if self.deps.save then self.deps.save(Config.forSave(self.options)) end
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
function Status:saveTracking(name,force)
    assert(type(name)=='string' and name:find('%S'), 'Tracking set name must not be empty')
    assert(not Config.defaults.tracking.sets[name], 'Cannot overwrite built-in tracking set: '..name)
    assert(force or not self.options.tracking.sets[name],
        'Tracking set already exists: '..name..'. Use -force to overwrite it.')
    local options=copy(self.options)
    local current=self.trackingOverride or options.tracking.sets[options.tracking.current]
    options.tracking.sets[name]=copy(Config.expandTracking(current,options.tracking.sets))
    options.tracking.current=name
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
        temporary.tracking.current='temporary'
        temporary.tracking.sets.temporary=entries
        local incoming=Config.normalize(temporary).tracking.sets.temporary
        override=copy(self.trackingOverride or self.options.tracking.sets[self.options.tracking.current])
        for _,entry in ipairs(incoming) do override[#override+1]=entry end
    end
    if override==nil then override=false end
    self:configure(self.options,override)
    self:update()
    return true
end
function Status:setWaypoint(waypoint)
    local override=waypoint
    if waypoint==nil then override=false end
    self:configure(self.options,nil,override)
    self:update()
    return true
end
function Status:setTrackingSupplement(name,enabled)
    assert(type(name)=='string' and name:match('%S'),
        'Panel tracking supplement requires a name')
    assert(enabled==nil or type(enabled)=='boolean',
        'Panel tracking supplement enabled flag must be boolean')
    assert(self.options.tracking.sets[name],
        'Unknown panel tracking supplement: '..tostring(name))
    self.trackingSupplements=self.trackingSupplements or {}
    if enabled==false then self.trackingSupplements[name]=nil
    else self.trackingSupplements[name]=true end
    self:configure(self.options)
    self:update()
    return true
end
function Status:resetPosition()
    self:setPosition(Status.defaults.x,Status.defaults.y)
end
function Status:reset()
    local options=copy(Config.defaults)
    options.tracking.sets=copy(self.options.tracking.sets)
    self:configure(options,false,false)
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
    local pixels=math.max(0,self.panel.width-item.x-10)
    local previous=item.rendered
    if previous and previous.text==text and previous.capacity==capacity and previous.pixels==pixels then return end
    item.rendered={text=text,capacity=capacity,pixels=pixels}
    local lines={}
    for line in (text..'\n'):gmatch('(.-)\n') do
        if #lines>=capacity then break end
        -- Clip with the same font metrics used to reserve display width.
        lines[#lines+1]=Metrics.clip(item,line,pixels)
    end
    item.text:text(table.concat(lines,'\n'))
end
function Status:update()
    local ready=not self.deps.ready or self.deps.ready()
    local visible=ready and self.deps.loggedIn() and self.options.visible
    if not visible then
        if self.waypoint then self.waypoint.background:visible(false) end
        if self.panel.visible then self.panel:show(false) end
        return
    end
    local enabled=self.deps.enabled()
    self.toggle.text:text(enabled and '[on]' or '[off]')
    Theme.color(self.toggle.text,enabled and 'green' or 'red')
    local strategy=self.deps.strategy and self.deps.strategy()
    local distance=self.deps.maxDistance and self.deps.maxDistance()
    local strategyText=strategy and tostring(strategy) or ''
    local distanceText=''
    if strategy and type(distance)=='number' then
        local rgb=Theme.colors.number
        distanceText=string.format('→\\cs(%d,%d,%d)%.1f\\cr',rgb[1],rgb[2],rgb[3],distance)
    end
    if strategyText~=self.strategyText or distanceText~=self.distanceText then self.nextUpdate=0 end
    self.strategyText=strategyText
    self.distanceText=distanceText
    self.strategyWidth=textWidth(self.strategy,strategyText)
    self.targetDistance.x=self.strategy.x+self.strategyWidth+6
    self.distanceWidth=textWidth(self.targetDistance,distanceText)
    local strategyColor=(strategy=='aggressor' or strategy=='puller') and 'red' or 'green'
    Theme.color(self.strategy.text,strategyColor)
    Theme.color(self.targetDistance.text,'body')
    if self.panel.visible and os.clock()<self.nextUpdate then return end
    self.nextUpdate=os.clock()+self.options.refresh_interval
    if self.waypoint then
        local ok,context=pcall(self.deps.context,'status panel waypoint')
        local state=ok and context and Waypoint.resolve(
            self.waypoint.config,context,self.waypoint.lastKnown) or nil
        if state and state.current then
            self.waypoint.lastKnown={x=state.x,y=state.y,id=state.id}
        end
        self.waypoint.state=state
        local name=state and self.waypoint.config.name or ''
        local distanceLabel=state and state.label or ''
        self.waypoint.nameWidth=textWidth(self.waypoint.name,name)
        self.waypoint.distanceWidth=textWidth(self.waypoint.distance,distanceLabel)
        self.waypoint.icon.visible=state~=nil
        if state then
            local key=state.color..':'..state.frame
            if self.waypoint.texture~=key then
                self.waypoint.icon.image:path((self.deps.windower.addon_path or '')..
                    'content/ui/general/direction/'..state.color..'/'..string.format('%02d.png',state.frame))
                self.waypoint.texture=key
            end
        end
        if self.panel.visible then self.waypoint.icon.image:visible(self.waypoint.icon.visible) end
    end
    for _, entry in ipairs(self.entries) do
        local shown,visibilityValue,visibilityContext,visibilityReset=entryVisibility(entry,self.deps)
        entry.visibilityFailure=visibilityValue~=nil
        local value
        if not shown then value=nil
        elseif visibilityValue~=nil then value=visibilityValue
        else
        value=entry.definition.value
        if entry.checks then
            value={}
            local ok,context=true,visibilityContext
            if not context then ok,context=pcall(self.deps.context,'status panel checklist') end
            local resetColor=visibilityReset or (ok and context and PanelContext.attach(context,self.deps.canShareClaim))
            for _,check in ipairs(entry.checks) do
                local checked=not not (ok and context and context.getVar(check.path))
                if check.conditions then
                    checked=not not (ok and context and not check.conditionError)
                    if checked then
                        for _,fn in ipairs(check.conditions) do
                            setfenv(fn,context)
                            local success,result=pcall(fn)
                            if not success or not result then checked=false; break end
                        end
                    end
                end
                if check.checked~=checked then
                    local prefix=check.automatic and 'automatic-' or ''
                    check.icon.image:path((self.deps.windower.addon_path or '')..
                        'content/ui/checklist/'..prefix..(checked and 'checked' or 'unchecked')..'.png')
                    check.checked=checked
                end
                local label=check.objective.text
                if check.objective.format~=nil then
                    label='[error]'
                    if not ok or not context then label='[unavailable]'
                    elseif not check.labelError then
                        resetColor()
                        local args={}
                        local valid=true
                        for index,fn in ipairs(check.formatFns) do
                            setfenv(fn,context)
                            local success,result=pcall(fn)
                            if not success then valid=false; break end
                            args[index]=result
                        end
                        if valid then
                            local success,result=pcall(string.format,check.objective.format[1],unpack(args,1,#check.formatFns))
                            if success then label=result end
                        end
                    end
                elseif check.objective.expression~=nil then
                    label='[error]'
                    if not ok or not context then label='[unavailable]'
                    elseif check.labelFn and not check.labelError then
                        resetColor()
                        setfenv(check.labelFn,context)
                        local success,result=pcall(check.labelFn)
                        if success and type(result)~='table' then label=result==nil and '' or tostring(result) end
                    end
                end
                check.display=Buffer.plain(label,self.deps.windower.from_shift_jis):gsub('[\r\n]+',' ')
                value[#value+1]=check.display
            end
        elseif entry.definition.format~=nil then
            value='[error]'
            if entry.formatFns and not entry.error then
                local ok,context=true,visibilityContext
                if not context then ok,context=pcall(self.deps.context,'status panel') end
                if not ok or not context then value='[unavailable]'
                else
                    local resetColor=visibilityReset or PanelContext.attach(context,self.deps.canShareClaim)
                    resetColor()
                    local args={}
                    for index,fn in ipairs(entry.formatFns) do
                        setfenv(fn,context)
                        local success,result=pcall(fn)
                        if not success then entry.error=true; break end
                        args[index]=result
                    end
                    if not entry.error then
                        local success,result=pcall(string.format,entry.definition.format[1],
                            unpack(args,1,#entry.formatFns))
                        if success then value=result else entry.error=true end
                    end
                end
            end
        elseif entry.definition.expression~=nil then
            value='[error]'
            if (entry.fn or entry.fns) and not entry.error then
                local ok,context=true,visibilityContext
                if not context then ok,context=pcall(self.deps.context,'status panel') end
                if not ok or not context then value='[unavailable]'
                else
                    local resetColor=visibilityReset or PanelContext.attach(context,self.deps.canShareClaim)
                    if entry.fns then
                        value={}
                        for _,fn in ipairs(entry.fns) do
                            resetColor()
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
        end
        entry.hidden=value==nil or (type(value)=='table' and #value==0)
        entry.inline=(not entry.checks or entry.visibilityFailure) and (entry.visibilityFailure or
            entry.definition.format~=nil or
            (type(entry.definition.expression or entry.definition.value)~='table' and type(value)~='table'))
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
    if self.distanceWidth>0 then headerEnd=self.targetDistance.x+self.distanceWidth end
    local width=math.max(displayWidth(self.options),headerEnd+self.versionWidth+20)
    for _,entry in ipairs(self.entries) do
        if not entry.hidden then
            local name=Buffer.plain(entry.definition.name,self.deps.windower.from_shift_jis)
            entry.heading=name..(entry.inline and name~='' and ':' or '')
            local headingWidth=textWidth(entry.label,entry.heading)
            entry.valueLabel.x=entry.inline and (10+headingWidth+8) or
                (entry.checks and entry.checks[1] and (18+entry.checks[1].size+5) or 18)
            local indent=entry.valueLabel.x-10
            width=math.max(width,36+math.max(headingWidth,Metrics.width(entry.valueLabel,entry.display)+indent))
        end
    end
    self.panel.width=math.ceil(width)
    if self.waypoint then
        local waypoint=self.waypoint
        local border=waypoint.background.skin.border or 0
        local padding=math.max(6,border+2)
        local sideWidth=math.max(waypoint.config.size,waypoint.nameWidth or 0,waypoint.distanceWidth or 0)+padding*2
        local sideX=self.options.anchor.horizontal=='right' and -sideWidth-8 or self.panel.width+8
        local lineHeight=math.ceil(self.options.font_size*1.8)
        local distanceHeight=waypoint.config.show_distance and math.ceil(math.max(6,self.options.font_size-1)*1.8) or 0
        waypoint.name.x=sideX+math.floor((sideWidth-(waypoint.nameWidth or 0))/2)
        waypoint.name.y=padding
        waypoint.icon.x=sideX+math.floor((sideWidth-waypoint.config.size)/2)
        waypoint.icon.y=padding+lineHeight
        waypoint.distance.x=sideX+math.floor((sideWidth-(waypoint.distanceWidth or 0))/2)
        waypoint.distance.y=waypoint.icon.y+waypoint.config.size+2
        waypoint.sideX=sideX
        waypoint.sideWidth=sideWidth
        waypoint.sideHeight=waypoint.distance.y+distanceHeight+padding
    end
    self.columns=math.max(8,math.floor((self.panel.width-20)/self.characterWidth))
    self.version.x=self.panel.width-self.versionWidth-6
    -- Expression arrays can change size at runtime: reflow rows and automatic
    -- height before clipping, without rebuilding controls or disturbing dragging.
    local lineHeight=math.ceil(self.options.font_size*1.8)
    local y=math.max(32,5+math.ceil((self.options.font_size+2)*1.8))
    for _, entry in ipairs(self.entries) do
        entry.label.y=y; entry.valueLabel.y=y+(entry.inline and 0 or lineHeight)
        for i,check in ipairs(entry.checks or {}) do
            check.button.y=y+i*lineHeight
            check.button.x=entry.valueLabel.x
            check.button.width=self.panel.width-check.button.x-10
            check.button.hitX=18; check.button.hitWidth=self.panel.width-28
            check.icon.y=check.button.y+math.floor((lineHeight-check.size)/2)
            check.icon.visible=not entry.hidden and not entry.visibilityFailure
            if self.panel.visible then check.icon.image:visible(check.icon.visible) end
            if not check.icon.visible then check.button.hitWidth=0 end
        end
        if not entry.hidden then y=y+(entry.lineCount+(entry.inline and 0 or 1))*lineHeight end
    end
    local logLines=self.options.show_log and self.options.history_lines or 0
    self.logHeading.y=y+12
    local logY=self.logHeading.y+(logLines>0 and lineHeight or 0)
    local requiredHeight=math.max(80,(logLines>0 and logY or y)+logLines*lineHeight+12)
    self.panel.height=math.max(self.options.height or 0,requiredHeight)
    for i,item in ipairs(self.logs) do item.y=logY+(i-1)*lineHeight end
    self.panel:layout()
    if self.waypoint then
        local waypoint=self.waypoint
        waypoint.background:layout(self.panel.x+waypoint.sideX,self.panel.y,
            waypoint.sideWidth,waypoint.sideHeight)
    end
    self:setText(self.logHeading,logLines>0 and 'Log' or '')
    for _, entry in ipairs(self.entries) do
        self:setText(entry.label,entry.hidden and '' or entry.heading)
        self:setText(entry.valueLabel,(entry.hidden or (entry.checks and not entry.visibilityFailure)) and '' or entry.display)
        for _,check in ipairs(entry.checks or {}) do
            self:setText(check.button,(entry.hidden or entry.visibilityFailure) and '' or check.display)
        end
        Theme.color(entry.valueLabel.text,(entry.error or (entry.visibilityFailure and entry.showError)) and 'red' or 'body')
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
    if self.waypoint then
        self.waypoint.background:visible(self.waypoint.state~=nil)
    end
end
function Status:destroy()
    self.unsubscribe()
    self.deps.windower.unregister_event(self.frameEvent)
    self.deps.windower.unregister_event(self.mouseEvent)
    if self.waypoint then self.waypoint.background:destroy() end
    self.panel:destroy()
end
return Status
