local Status=require('./lib/ux/status-panel')
local Buffer=require('./lib/ux/log-buffer')
local buffer=Buffer.new(2)
buffer:add('\30\2first\30\1\nsecond'); buffer:add('third')
assert(#buffer.lines==2 and buffer.lines[1]=='second' and buffer.lines[2]=='third')
assert(Buffer.clip('a'..string.char(0x81,0xA8)..'b',2)=='a')
assert(Buffer.uncolored('A\\cs(255,215,0)gold\\crZ')=='AgoldZ')
assert(Buffer.clip('\\cs(255,215,0)gold\\crZ',2)=='\\cs(255,215,0)go\\cr')
assert(Buffer.clip('\\cs(255,215,0)gold\\crZ',5)=='\\cs(255,215,0)gold\\crZ')
assert(Buffer.uncolored('\\cs(999,0,0)x')=='\\cs(999,0,0)x')
local sjisArrow=string.char(0x81,0xA8)
local utfArrow=string.char(0xE2,0x86,0x92)
local conversions=0
local function convert(text)
    conversions=conversions+1
    return (text:gsub(sjisArrow,utfArrow))
end
local encoded=Buffer.new(2,convert)
encoded:add('Next '..sjisArrow..' step')
assert(encoded.lines[1]=='Next '..utfArrow..' step' and conversions==1)
encoded:add(utfArrow)
assert(conversions==1 and Buffer.clip(utfArrow..'A',1)==utfArrow)
encoded:add('last')
assert(encoded.ids[1]==2 and encoded.ids[2]==3)
local objects={}
local function primitive()
    local object={}
    for _, method in ipairs({'draggable','color','alpha','pos','size','visible','bg_visible','font','bold','path','fit','repeat_xy'}) do
        object[method]=function(self,...) self[method..'Value']={...} end
    end
    object.path=function(self,value)
        assert(self.visibleValue and self.visibleValue[1]==false, 'Hide image before loading its texture')
        assert(self.fitValue and self.fitValue[1]==false, 'Disable native texture sizing before loading')
        self.pathValue={value}
    end
    object.visible=function(self,value)
        if value then
            assert(self.posValue, 'Position primitive before revealing it')
            if self.pathValue then assert(self.sizeValue, 'Size image before revealing it') end
        end
        self.visibleValue={value}
    end
    object.text=function(self,value) self.value=value end
    object.extents=function() return 1,1 end -- Positive stale measurements must not drive layout.
    object.destroy=function(self) self.destroyed=true end
    objects[#objects+1]=object
    return object
end
local events,removed={},{}
local enabled,loggedIn=false,true
local strategy='leader'
local ready=false
local listener,unsubscribed,toggles,contexts=nil,false,0,0
local saves={}
local options={x=10,y=20,width=500,font_size=10,history_lines=2,show_log=true,refresh_interval=0.1,
    anchor={horizontal='left',vertical='top'},
    tracking={current='custom',sets={custom={{name='Strategy',expression={'gambit.strategy'}},
        {name='False',expression='false',value='fallback'},
        {name='Nil',expression='nil',value='fallback'},
        {name='Note',value='Reminder'},
        {name='Bad',expression='error("bad")'},
        {name='Syntax',expression='('}}}}}
local panel=Status.new({texts={new=primitive},images={new=primitive},
    version='1.0.5',
    windower={register_event=function(name,fn) events[name]=fn; return name end,
        unregister_event=function(id) removed[id]=true end},
    enabled=function() return enabled end,loggedIn=function() return loggedIn end,
    strategy=function() return strategy end,
    ready=function() return ready end,
    toggle=function() toggles=toggles+1; enabled=not enabled end,
    subscribe=function(fn) listener=fn; return function() unsubscribed=true end end,
    save=function(config) saves[#saves+1]=config end,
    context=function()
        contexts=contexts+1
        return setmetatable({gambit={strategy='leader'}},{__index=_G})
    end,
},options)
listener('\30\2Hello\30\1')
events.prerender()
assert(not panel.panel.visible and contexts==0)
ready=true
events.prerender()
assert(panel.panel.visible and panel.log.text.value=='Hello')
assert(panel.logHeading.text.value=='Log')
assert(panel.logs[1].y==panel.logHeading.y+math.ceil(options.font_size*1.8))
local longLine=string.rep('x',100)
panel:setText(panel.logs[1],longLine)
assert(#panel.logs[1].text.value==72) -- 580 usable pixels / 8-pixel Consolas advance.
panel:setText(panel.logs[1],'Hello')
assert(panel.entries[1].label.text.value=='Strategy' and panel.entries[1].valueLabel.text.value=='leader')
assert(panel.entries[2].valueLabel.text.value=='false')
assert(panel.entries[3].valueLabel.text.value=='' and panel.entries[3].label.text.value=='')
assert(panel.entries[4].label.y==panel.entries[3].label.y)
assert(panel.entries[4].valueLabel.text.value=='Reminder')
assert(panel.entries[5].valueLabel.text.value=='[error]')
assert(panel.entries[6].valueLabel.text.value=='[error]')
local firstContexts=contexts
panel.nextUpdate=0
events.prerender(); assert(contexts==firstContexts+3) -- Failed entries stop retrying.
local toggleX=panel.panel.x+panel.toggle.x+2
local toggleY=panel.panel.y+panel.toggle.y+2
assert(events.mouse(1,toggleX,toggleY,0,false))
assert(events.mouse(2,toggleX,toggleY,0,false) and toggles==1)
events.prerender(); assert(panel.toggle.text.value=='[on]')
assert(events.mouse(1,20,25,0,false))
assert(events.mouse(0,100,100,0,false))
assert(events.mouse(2,100,100,0,false) and toggles==1)
assert(panel.panel.x==90 and panel.panel.y==95)
assert(#saves==1 and saves[1].x==90 and saves[1].y==95)
assert(not events.mouse(1,100,100,0,true))
panel:setVisible(false); assert(not panel.panel.visible and #saves==2)
panel:setVisible(true); assert(panel.panel.visible and #saves==3)
local config=require('./lib/variable-values').copy(panel.options)
config.tracking.sets.notes={{name='Steps',value={'First','Second'}}}
panel:configure(config)
panel:setTracking('notes')
assert(panel.entries[1].label.text.value=='Steps' and panel.entries[1].valueLabel.text.value=='First\nSecond')
local Theme=require('./lib/ux/theme')
assert(panel.entries[1].label.text.colorValue[1]==Theme.colors.subheading[1])
assert(panel.entries[1].valueLabel.text.colorValue[1]==Theme.colors.body[1])
assert(panel.entries[1].valueLabel.x>panel.entries[1].label.x)
listener('Next line'); panel.nextUpdate=0; events.prerender()
assert(panel.logs[1].text.colorValue[1]~=panel.logs[2].text.colorValue[1])
assert(panel.logs[2].text.colorValue[1]==Theme.colors.log_latest[1])
listener('Third line'); panel.nextUpdate=0; events.prerender()
assert(panel.logs[1].text.colorValue[1]==Theme.colors.log_even[1])
assert(panel.logs[2].text.colorValue[1]==Theme.colors.log_latest[1])
-- Restore the original history used by the remaining assertions.
panel:setSize(nil,panel.logs[1].y+8+math.ceil(panel.options.font_size*1.8))
assert(panel.panel.height>panel.options.height)
assert(panel.logs[1].text.value=='Next line' and panel.logs[2].text.value=='Third line')
assert(panel.logs[2].text.colorValue[1]==Theme.colors.log_latest[1])
panel:setSize(nil,'auto')
panel.buffer.lines={'Hello'}; panel.buffer.ids={1}; panel.buffer.serial=1
panel.nextUpdate=0; events.prerender()
local arrayConfig=require('./lib/variable-values').copy(panel.options)
arrayConfig.tracking.sets.dynamic={{name='Dynamic',expression='{"One", "Two", false}'},
    {name='After',value='Tail'}}
panel:configure(arrayConfig); panel:setTracking('dynamic')
panel:setSize(nil,80)
local savedBeforeGrowth=#saves
panel.entries[1].fn=function() return {'One','Two','Three','Four','Five'} end
panel.nextUpdate=0; events.prerender()
assert(panel.panel.height>80 and panel.options.height==80 and #saves==savedBeforeGrowth)
assert(saves[#saves].height==80)
panel.entries[1].fn=function() return {'One','Two',false} end
panel.nextUpdate=0; events.prerender()
assert(panel.entries[1].valueLabel.text.value=='One\nTwo\nfalse')
assert(panel.entries[2].label.y>=panel.entries[1].valueLabel.y+3*math.ceil(panel.options.font_size*1.8))
local tall=panel.panel.height
panel.entries[1].fn=function() return nil end
panel.nextUpdate=0; events.prerender()
local hiddenHeight=panel.panel.height
assert(panel.entries[1].label.text.value=='' and panel.entries[1].valueLabel.text.value=='')
assert(panel.entries[2].label.y==32 and hiddenHeight<tall)
panel.entries[1].fn=function() return {'Only'} end
panel.nextUpdate=0; events.prerender()
assert(panel.panel.height<tall and panel.entries[1].valueLabel.text.value=='Only')
assert(panel.panel.height>hiddenHeight and panel.entries[1].label.text.value=='Dynamic')
assert(panel.options.height==80 and #saves==savedBeforeGrowth)
panel:setSize(nil,'auto')
panel:setTracking('notes')
assert(panel.log.text.value=='Hello' and panel.options.tracking.current=='notes')
local beforeInvalid=#saves
assert(not pcall(panel.setTracking,panel,'missing'))
assert(panel.options.tracking.current=='notes' and #saves==beforeInvalid)
assert(not pcall(panel.configure,panel,{width=-1}))
assert(panel.options.tracking.current=='notes' and panel.panel.visible)
panel:setTracking('none'); assert(#panel.entries==0 and panel.log.text.value=='Hello')
local temporaryRows={{name='Temporary',value={'First','Second'}},
    {name='Strategy',expression={'gambit.strategy'}}}
local beforeTemporary=#saves
local retainedLog=panel.buffer
local contextFile=assert(io.open('lib/action-context.lua'))
local contextSource=contextFile:read('*a'); contextFile:close()
local contextFunction=assert(contextSource:match('(context.setPanelTracking = function%(entries, append%).-\n    end)'))
local actionContext={}
local attach=assert(loadstring(contextFunction))
setfenv(attach,{context=actionContext,globals={status_panel=panel},assert=assert}); attach()
assert(actionContext.setPanelTracking(temporaryRows)==true)
assert(#panel.entries==2 and panel.entries[1].valueLabel.text.value=='First\nSecond')
assert(panel.entries[2].valueLabel.text.value=='leader')
assert(#saves==beforeTemporary and panel.buffer==retainedLog)
assert(panel.options.tracking.current=='none' and #panel.options.tracking.sets.none==0)
temporaryRows[1].value[1]='Changed externally'
assert(panel.entries[1].definition.value[1]=='First')
local temporaryPanel=panel.panel
assert(not pcall(panel.setTemporaryTracking,panel,{{value='Missing name'}}))
assert(panel.panel==temporaryPanel and #saves==beforeTemporary)
panel:setPosition(panel.options.x,panel.options.y)
assert(saves[#saves].tracking.current=='none' and saves[#saves].tracking.sets.none==nil)
panel:setTemporaryTracking({}); assert(#panel.entries==0)
panel:setTemporaryTracking(temporaryRows)
panel:setTemporaryTracking(nil); assert(#panel.entries==0)
panel:setTemporaryTracking(temporaryRows)
panel:configure(panel.options); panel:update()
assert(#panel.entries==2 and panel.buffer==retainedLog)
panel:setSize(550,300)
assert(#panel.entries==2 and panel.options.tracking.current=='none')
panel:setTheme('ffxi')
assert(#panel.entries==2 and panel.buffer==retainedLog)
panel:setTemporaryTracking({})
panel:setSize(500,100)
assert(#panel.entries==0 and panel.trackingOverride~=nil)
panel:setTemporaryTracking(temporaryRows)
panel:configure(panel.options,false); panel:update()
assert(#panel.entries==0 and panel.buffer==retainedLog)
panel:setTracking('notes')
local beforeAppend=#saves
assert(actionContext.setPanelTracking({{name='Extra',value='Added'}},true))
assert(#panel.entries==2 and panel.entries[1].definition.name=='Steps' and panel.entries[2].definition.name=='Extra')
assert(#panel.options.tracking.sets.notes==1 and #saves==beforeAppend)
actionContext.setPanelTracking({{name='Another',value='Last'}},true)
assert(#panel.entries==3 and panel.entries[3].definition.name=='Another')
panel:setSize(500,100)
assert(#panel.entries==3)
local beforeInvalidAppend=panel.panel
assert(not pcall(actionContext.setPanelTracking,{bad={name='Bad'}},true))
assert(panel.panel==beforeInvalidAppend and #panel.entries==3)
actionContext.setPanelTracking({},true); assert(#panel.entries==3)
actionContext.setPanelTracking(temporaryRows,false); assert(#panel.entries==2)
actionContext.setPanelTracking(nil,true); assert(#panel.entries==1)
panel:setTracking('none')
local beforeAutoWidth=#saves
local wideValue=string.rep('x',100)..string.char(0xE2,0x86,0x92)
panel:setTemporaryTracking({{name='Wide',value={'Short',wideValue}}})
assert(panel.panel.width>600 and panel.entries[1].valueLabel.text.value=='Short\n'..wideValue)
assert(panel.options.width==500 and #saves==beforeAutoWidth)
local expandedWidth=panel.panel.width
panel.nextUpdate=math.huge; events.prerender()
assert(panel.panel.width==expandedWidth) -- Throttled frames must retain the computed width.
panel:setTemporaryTracking({{name='Short',value='Fits'}})
assert(panel.panel.width==600)
listener(string.rep('L',200)); panel.nextUpdate=0; events.prerender()
assert(panel.panel.width==600) -- Logging never drives automatic width.
panel:setTemporaryTracking({{name=string.rep('H',100),value='Fits'}})
assert(panel.panel.width>600) -- Inline heading includes colon, gap, and value.
panel:setTemporaryTracking(nil)
panel.buffer.lines={'Hello'}; panel.buffer.ids={1}; panel.buffer.serial=1
panel.nextUpdate=0; events.prerender()
panel:resetPosition(); assert(panel.panel.x==Status.defaults.x and panel.panel.y==Status.defaults.y)
panel:setPosition(41,152)
assert(panel.panel.x==41 and panel.panel.y==152 and saves[#saves].x==41)
panel:setPosition(42,nil); assert(panel.panel.x==42 and panel.panel.y==152)
panel:setPosition(nil,153); assert(panel.panel.x==42 and panel.panel.y==153)
local beforeBadPosition=#saves
assert(not pcall(panel.setPosition,panel,-1,20))
assert(not pcall(panel.setPosition,panel,20,1.5))
assert(panel.panel.x==42 and panel.panel.y==153 and #saves==beforeBadPosition)
panel:setSize(600,80)
panel:setSize(200,nil)
assert(panel.panel.width==600 and panel.options.width==200 and saves[#saves].width==200)
assert(panel.columns==72 and panel.toggle.width<100)
local savesBeforeWidthUpdate=#saves
panel.nextUpdate=0; events.prerender()
assert(#saves==savesBeforeWidthUpdate and panel.options.width==200)
panel:setLogVisible(false)
assert(panel.panel.width>=200 and panel.columns==math.floor((panel.panel.width-20)/panel.characterWidth) and saves[#saves].width==200)
panel:setLogVisible(true)
assert(panel.panel.width==600 and panel.logs[1].text.value=='Hello')
panel:setSize(600,nil)
assert(panel.panel.width==600 and panel.panel.height>80 and panel.options.height==80)
assert(panel.log.text.value=='Hello')
local neededHeight=panel.panel.height
panel:setSize(450,nil)
assert(panel.panel.width==600 and panel.panel.height==neededHeight and saves[#saves].height==80)
panel:setSize(nil,300)
assert(panel.panel.width==600 and panel.panel.height==300 and panel.log.text.value=='Hello')
local beforeBadSize=#saves
assert(not pcall(panel.setSize,panel,100,300))
assert(not pcall(panel.setSize,panel,nil,40))
assert(panel.options.width==450 and panel.options.height==300 and #saves==beforeBadSize)
panel:setSize(nil,'auto')
assert(panel.options.height==nil and panel.panel.width==600)
local expandedHeight=panel.panel.height
panel:setLogVisible(false)
assert(panel.panel.height<expandedHeight and panel.log.text.value=='')
assert(panel.logHeading.text.value=='')
assert(saves[#saves].show_log==false)
listener('While hidden'); panel.nextUpdate=0; events.prerender()
assert(panel.log.text.value=='')
panel:setLogVisible(true)
assert(panel.panel.height==expandedHeight and panel.logs[2].text.value=='While hidden')
assert(panel.logHeading.text.value=='Log')
panel:setSize(nil,300); panel:setLogVisible(false)
assert(panel.panel.height==300 and panel.log.text.value=='')
panel:setTheme('ff8')
local parts=panel.panel.background.parts
local count=0; for _ in pairs(parts) do count=count+1 end
assert(count==9 and parts.center.pathValue[1]=='content/ui/ff8/center.png')
assert(parts['top-left'].sizeValue[1]==5 and parts['top-left'].sizeValue[2]==5)
assert(parts.center.sizeValue[1]==panel.panel.width-10)
panel:setSize(600,250)
parts=panel.panel.background.parts
assert(parts.center.sizeValue[1]==590 and parts.center.sizeValue[2]==240)
assert(parts.right.posValue[1]==panel.panel.x+595)
assert(saves[#saves].theme=='ff8')
assert(not pcall(panel.setTheme,panel,'missing'))
assert(panel.options.theme=='ff8')
panel:setTheme('ff7')
parts=panel.panel.background.parts
assert(parts.center.pathValue[1]=='content/ui/ff7/center.png')
assert(parts['top-left'].sizeValue[1]==10 and parts['top-left'].sizeValue[2]==10)
assert(parts.center.sizeValue[1]==panel.panel.width-20)
assert(saves[#saves].theme=='ff7')
panel:setTheme('ffxi')
parts=panel.panel.background.parts
assert(not parts.left and not parts.right and not parts['top-left'] and not parts['bottom-right'])
assert(parts.center.sizeValue[1]==panel.panel.width and parts.center.posValue[1]==panel.panel.x)
assert(parts.top.sizeValue[1]==panel.panel.width)
assert(parts.center.repeat_xyValue[2]==(panel.panel.height-12)/400)
panel:setSize(nil,400)
parts=panel.panel.background.parts
assert(parts.center.repeat_xyValue[2]==388/400)
panel:setTheme('solid'); assert(panel.panel.background.parts.top==nil)
local screenWidth,screenHeight=1920,1080
panel.deps.windower.get_windower_settings=function() return {ui_x_res=screenWidth,ui_y_res=screenHeight} end
panel:setPosition(30,40)
panel:setAnchor('top','right')
assert(panel.panel.x==1920-panel.panel.width-30 and panel.panel.y==40)
panel:setTemporaryTracking({{name='Long',value=string.rep('x',120)}})
assert(panel.panel.x+panel.panel.width==1890)
assert(panel.options.x==30 and saves[#saves].anchor.horizontal=='right')
panel:setAnchor('bottom','right')
assert(panel.panel.y+panel.panel.height==1040)
screenWidth=1600; screenHeight=900
panel.nextUpdate=0; events.prerender()
assert(panel.panel.x+panel.panel.width==1570 and panel.panel.y+panel.panel.height==860)
local dragX,dragY=panel.panel.x+5,panel.panel.y+5
assert(events.mouse(1,dragX,dragY,0,false))
assert(events.mouse(0,dragX-20,dragY-10,0,false))
assert(events.mouse(2,dragX-20,dragY-10,0,false))
assert(panel.options.x==50 and panel.options.y==50)
assert(saves[#saves].x==50 and saves[#saves].y==50)
local oldAnchor=panel.options.anchor
assert(not pcall(panel.setAnchor,panel,'middle','right'))
assert(panel.options.anchor==oldAnchor)
panel:setAnchor('bottom','left')
assert(panel.panel.x==50 and panel.panel.y+panel.panel.height==850)
panel:setAnchor('top','left')
assert(panel.panel.x==50 and panel.panel.y==50)
loggedIn=false; events.prerender(); assert(not panel.panel.visible)
loggedIn=true
panel:setTemporaryTracking({
    {name='Inline',expression="'short'"},
    {name='Array',expression={"'first'","nil","{'second', false}"}},
    {name='Single array',expression={"'one'"}},
    {name='Returned array',expression="{'a','b'}"},
    {name='Absent',expression={'nil','{}'}},
})
assert(panel.toggle.text.value=='[on]' or panel.toggle.text.value=='[off]')
assert(panel.toggle.y==panel.title.y and panel.toggle.width<100)
assert(panel.toggle.text.sizeValue[1]==panel.title.text.sizeValue[1])
assert(panel.toggle.text.fontValue[1]==panel.title.text.fontValue[1])
assert(panel.toggle.text.boldValue[1]==true)
assert(panel.version.y==(panel.panel.background.skin.border or 0)+1)
assert(panel.version.text.colorValue[1]==Theme.colors.version[1])
assert(panel.version.text.value=='v1.0.5')
assert(panel.version.x+panel.versionWidth==panel.panel.width-6)
assert(panel.strategy.text.value=='[leader]' and panel.strategy.y==panel.toggle.y)
assert(panel.strategy.x>=panel.toggle.x+panel.toggle.width)
assert(panel.strategy.x+panel.strategyWidth+10<=panel.version.x)
strategy='aggressor'; events.prerender()
assert(panel.strategy.text.value=='[aggressor]')
assert(panel.strategy.text.colorValue[1]==Theme.colors.red[1])
assert(panel.entries[1].label.text.value=='Inline:' and panel.entries[1].inline)
assert(panel.entries[1].label.y==panel.entries[1].valueLabel.y)
assert(panel.entries[1].valueLabel.x>=panel.entries[1].label.x+
    require('./lib/ux/text-metrics').width(panel.entries[1].label,'Inline:'))
assert(panel.entries[1].label.text.sizeValue[1]==panel.entries[1].valueLabel.text.sizeValue[1])
assert(panel.entries[1].label.text.fontValue[1]==panel.entries[1].valueLabel.text.fontValue[1])
assert(panel.entries[1].valueLabel.text.boldValue[1]==false)
assert(panel.entries[2].valueLabel.text.value=='first\nsecond\nfalse' and not panel.entries[2].inline)
assert(panel.entries[3].valueLabel.y>panel.entries[3].label.y)
assert(not panel.entries[4].inline and panel.entries[4].valueLabel.text.value=='a\nb')
assert(panel.entries[5].hidden and panel.entries[5].label.text.value=='')
assert(not pcall(panel.setTemporaryTracking,panel,{{name='Invalid',expression={true}}}))
-- Fractional character widths and indented rows must not clip their final
-- character after automatic sizing (11pt => estimated 8.8px advance).
local fractional=require('./lib/variable-values').copy(panel.options)
fractional.font_size=11
panel:configure(fractional,false)
local completeLine='Events: \\cs(100,235,130)'..string.rep('x',100)..' (global namespace)\\cr'
panel:setTemporaryTracking({{name='Automation',value={completeLine}}})
assert(panel.entries[1].valueLabel.text.value==completeLine)
panel:setTemporaryTracking({{name='Inline',value=completeLine}})
assert(panel.entries[1].valueLabel.text.value==completeLine)
local fontSaves=#saves
panel:setFontSize(12)
assert(panel.options.font_size==12 and saves[#saves].font_size==12 and #saves==fontSaves+1)
assert(panel.trackingOverride and panel.entries[1].definition.name=='Inline')
assert(not pcall(panel.setFontSize,panel,31) and panel.options.font_size==12)
panel:destroy()
assert(unsubscribed and removed.mouse and removed.prerender)
for _, object in ipairs(objects) do assert(object.destroyed) end
local file=assert(io.open('lib/logging.lua')); local logging=file:read('*a'); file:close()
local chat,observed={},{}
local logEnv=setmetatable({globals={selfShortName='gbt'},Colors={default=1,gray=2},
    colorize=function(_,message) return message end,
    windower={add_to_chat=function(_,message) chat[#chat+1]=message end},
},{__index=_G})
local logChunk=assert(loadstring(assert(logging:match('(local logSubscribers.-)\nfunction writeWarning'))))
setfenv(logChunk,logEnv); logChunk()
local unsubscribe=logEnv.subscribeGambitLog(function(message) observed[#observed+1]=message end)
logEnv.subscribeGambitLog(function() error('Broken listener must not break logging') end)
logEnv.writeMessage('plain output')
assert(chat[1]=='[gbt] plain output' and observed[1]=='plain output')
logEnv.globals.suppress_logging=true; logEnv.writeMessage('hidden')
assert(#observed==1 and #chat==1)
logEnv.globals.suppress_logging=false; unsubscribe(); logEnv.writeMessage('after unsubscribe')
assert(#observed==1 and #chat==2)
print('PASS: status tracking, errors, history, toggle, drag capture, visibility and cleanup')
