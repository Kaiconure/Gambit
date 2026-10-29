local Panel=require('./lib/ux/panel')
local toggles=0
local function primitive()
    return setmetatable({visible=function() toggles=toggles+1 end},
        {__index=function() return function() end end})
end
local panel=Panel.new({x=10,y=20,width=450,height=140,theme='ffxi'},
    {texts={new=primitive},images={new=primitive}})
panel:label(10,5,10,'body')
assert(not panel.visible)
panel:layout(); assert(not panel.visible)
panel:show(true)
local before=toggles
panel:layout()
panel.width=600; panel.height=200; panel:layout()
assert(panel.visible and toggles==before)
assert(panel:mouse(1,15,25,false))
assert(panel:mouse(0,25,35,false))
assert(panel.capture.drag and panel.visible and toggles==before)
panel:mouse(2,25,35,false)
panel:show(false); assert(not panel.visible and toggles>before)
panel:destroy()
print('PASS: initial hidden setup, live layout/resize/drag without visibility toggles, explicit hide')
