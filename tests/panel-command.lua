local file=assert(io.open('lib/commands.lua')); local source=file:read('*a'); file:close()
local handler=assert(source:match("(handlers%['panel'%] = function.-)\nhandlers%['slots'%]"))
local output,errors={},{}
local options={visible=true,width=500,x=30,y=150,tracking={current='default',sets={default={},notes={}}}}
local panel={options=options,setVisible=function(_,visible) options.visible=visible end,
    setTheme=function(_,name) options.theme=name end,
    setLogVisible=function(_,visible) options.show_log=visible end,
    setAnchor=function(_,vertical,horizontal) options.anchor={vertical=vertical,horizontal=horizontal} end,
    setTracking=function(_,name) assert(options.tracking.sets[name],'Unknown tracking set'); options.tracking.current=name end,
    configure=function(_,value) assert(value=='disk'); options.visible=false end,
    panel={height=250},
    setPosition=function(_,x,y)
        if x then options.x=x end
        if y then options.y=y end
    end,
    setSize=function(self,width,height)
        if width then options.width=width end
        if height=='auto' then options.height=nil; self.panel.height=250
        elseif height then options.height=height; self.panel.height=height end
    end,
    resetPosition=function() options.reset=true end,
    reset=function() options.allReset=true end,update=function() end}
local env=setmetatable({handlers={},globals={status_panel=panel},
    loadPanelSettings=function() return 'disk' end,
    writeMessage=function(value) output[#output+1]=value end,
    writeError=function(value) errors[#errors+1]=value end},{__index=_G})
local chunk=assert(loadstring(handler)); setfenv(chunk,env); chunk()
env.handlers.panel({'hide'}); assert(not options.visible)
env.handlers.panel({'anchor'}); assert(output[#output]=='Panel anchor: top left')
env.handlers.panel({'anchor','TOP','RIGHT'}); assert(options.anchor.horizontal=='right')
local anchorErrors=#errors
env.handlers.panel({'anchor','right','top'})
assert(#errors==anchorErrors+1 and options.anchor.horizontal=='right')
-- Restore output/error counts expected by the original command scenarios.
env.handlers.panel({'reset'})
assert(options.allReset and output[#output]=='Panel settings reset to defaults.')
options.allReset=nil
env.handlers.panel({'reset','extra'})
assert(not options.allReset)
output={}; errors={}
env.handlers.panel({'SHOW'}); assert(options.visible)
env.handlers.panel({'tracking','-list'}); assert(output[2]=='  default' and output[3]=='  notes')
env.handlers.panel({'tracking','-set','notes'}); assert(options.tracking.current=='notes')
env.handlers.panel({'tracking','-set','bad'}); assert(#errors==1 and options.tracking.current=='notes')
env.handlers.panel({'reload'}); assert(not options.visible)
env.handlers.panel({'reset-position'}); assert(options.reset)
local helpStart=#output+1
env.handlers.panel({}); assert(output[helpStart]:find('tracking: notes',1,true))
local help=table.concat(output,'\n',helpStart)
assert(help:find('gbt panel log [show | hide]',1,true))
assert(help:find('gbt panel height [<height>|auto]',1,true))
assert(help:find('gbt panel position [<x> <y>]',1,true))
assert(help:find('gbt panel tracking [-list | -set <name>]',1,true))
print('PASS: panel commands, tracking selection, errors, reload and position reset')
env.handlers.panel({'size','640','400'}); assert(options.width==640 and options.height==400)
env.handlers.panel({'width','700'}); assert(options.width==700 and options.height==400)
env.handlers.panel({'height','300'}); assert(options.width==700 and options.height==300)
env.handlers.panel({'height','AUTO'}); assert(options.height==nil and options.width==700)
env.handlers.panel({'size'}); assert(output[#output]:find('700 x 250',1,true))
local before=#errors
env.handlers.panel({'size','300'})
env.handlers.panel({'width','bad'})
assert(#errors==before+2 and options.width==700)
env.handlers.panel({'position','40','160'}); assert(options.x==40 and options.y==160)
env.handlers.panel({'x','41'}); assert(options.x==41 and options.y==160)
env.handlers.panel({'y','161'}); assert(options.x==41 and options.y==161)
env.handlers.panel({'position'}); assert(output[#output]=='Panel position: 41, 161')
local beforePositionErrors=#errors
env.handlers.panel({'position','20'})
env.handlers.panel({'x','bad'})
assert(#errors==beforePositionErrors+2 and options.x==41 and options.y==161)
env.handlers.panel({'log','hide'}); assert(options.show_log==false)
env.handlers.panel({'log'}); assert(output[#output]=='Panel recent log: hidden')
env.handlers.panel({'log','SHOW'}); assert(options.show_log==true)
env.handlers.panel({'theme','FF8'}); assert(options.theme=='ff8')
env.handlers.panel({'theme'}); assert(output[#output]=='Panel theme: ff8')
local themeListStart=#output+1
env.handlers.panel({'theme','-list'})
assert(output[themeListStart]=='Panel themes:')
assert(output[themeListStart+1]=='  ff7' and output[themeListStart+3]=='  ffxi'
    and output[themeListStart+4]=='  solid')
