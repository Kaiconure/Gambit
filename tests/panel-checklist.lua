local Status=require('./lib/ux/status-panel')
local Config=require('./lib/ux/status-config')
local values=require('./lib/variable-values')
local Theme=require('./lib/ux/theme')
local vars={panel={sortie_a={kill_5_abject=true}}}
local context={getVar=function(path) return values.get(vars,path) end,
    setVar=function(path,value)
        local parts=values.path(path)
        local target=vars
        for i=1,#parts-1 do target[parts[i]]=target[parts[i]] or {}; target=target[parts[i]] end
        target[parts[#parts]]=value
    end}
local function primitive()
    return setmetatable({}, {__index=function(_,key)
        return function(self,value,...)
            if key=='color' then self.rgb={value,...} end
            if key=='text' then self.value=value end
            if key=='path' then self.texture=value; self.loads=(rawget(self,'loads') or 0)+1 end
            if key=='destroy' then self.destroyed=true end
            if key=='visible' then self.shown=value end
        end
    end})
end
local definition={id='sortie_a',name='Objectives',expression='error("must not run")',value=17,
    checklist={{id='kill_5_abject',text='Kill 5 abject mobs'}, {text='Kill 5 more abject mobs'}}}
local options={show_log=false,tracking={current='custom',sets={custom={definition}}}}
local panel=Status.new({texts={new=primitive},images={new=primitive},
    windower={register_event=function() return 1 end,unregister_event=function() end},
    loggedIn=function() return true end,enabled=function() return false end,
    subscribe=function() return function() end end,toggle=function() end,
    context=function() return context end},options)
panel:update()
local entry=panel.entries[1]
assert(not entry.inline and not entry.hidden and entry.lineCount==2)
assert(entry.checks[1].icon.image.texture=='content/ui/checklist/checked.png')
assert(entry.checks[2].icon.image.texture=='content/ui/checklist/unchecked.png')
assert(entry.checks[2].button.text.value=='Kill 5 more abject mobs')
assert(entry.checks[1].icon.image.shown==true)
panel.nextUpdate=0; panel:update()
assert(entry.checks[1].icon.image.loads==1)
assert(entry.valueLabel.text.value=='')
local first=entry.checks[1].button
local hx,hy=panel.panel.x+first.hitX+1,panel.panel.y+first.y+1
assert(panel.panel:mouse(0,hx,hy,false)==nil) -- hover does not consume movement
assert(first.hovered and first.text.rgb[1]==Theme.colors.yellow[1])
panel.nextUpdate=0; panel:update()
assert(first.hovered and first.text.rgb[1]==Theme.colors.yellow[1])
panel.panel:mouse(0,hx,hy,true)
assert(not first.hovered and first.text.rgb[1]==Theme.colors.subheading[1])
panel.panel:mouse(0,hx,hy,false)
panel.panel:show(false)
assert(not first.hovered)
panel.panel:show(true)
assert(first.hovered)
panel.panel:mouse(0,panel.panel.x-1,panel.panel.y-1,false)
assert(not first.hovered)
local function click(button)
    local x,y=panel.panel.x+(button.hitX or button.x)+1,panel.panel.y+button.y+1
    assert(panel.panel:mouse(1,x,y,false))
    assert(panel.panel:mouse(2,x,y,false))
end
click(entry.checks[2].button)
assert(vars.panel.sortie_a.objective_2==true)
click(entry.checks[1].button)
assert(vars.panel.sortie_a.kill_5_abject==false)
context.setVar('vars.panel.sortie_a.objective_2',false)
panel.nextUpdate=0; panel:update()
assert(entry.checks[2].button.text.value=='Kill 5 more abject mobs')
assert(entry.checks[2].icon.image.texture=='content/ui/checklist/unchecked.png')
assert(definition.checklist[2].id==nil) -- normalization does not mutate input
panel:setTemporaryTracking({{id='other',name='Other',checklist={{text='Something else'}}}})
assert(entry.checks[1].icon.image.destroyed==true)
panel:update()
assert(panel.entries[1].checks[1].path=='vars.panel.other.objective_1')
panel:setTemporaryTracking(nil)
panel:update()
assert(panel.entries[1].checks[1].button.text.value=='Kill 5 abject mobs')
panel:setTemporaryTracking({{references='compact'},definition})
assert(panel.entries[1].definition.name==Config.defaults.tracking.sets.compact[1].name)
assert(panel.entries[#panel.entries].definition.id=='sortie_a')
assert(panel.trackingOverride[1].references=='compact')
panel:setTemporaryTracking({{references='none'}},true)
assert(panel.entries[#panel.entries].definition.id=='sortie_a')
panel:setLogVisible(true)
assert(panel.trackingOverride[1].references=='compact')
assert(panel.entries[#panel.entries].definition.id=='sortie_a')
local function invalid(row)
    assert(not pcall(Config.normalize,{tracking={current='test',sets={test={row}}}}))
end
invalid({name='Missing id',checklist={}})
invalid({name='Bad path',id='a.b',checklist={}})
invalid({name='Duplicate',id='test',checklist={{id='objective_2',text='One'},{text='Two'}}})
invalid({name='Bad item',id='test',checklist={{text='Two\nlines'}}})
invalid({name='Not array',id='test',checklist={key={text='One'}}})
panel:destroy()
print('PASS: checklist precedence, rendering, clicks, external updates, generated ids and validation')
