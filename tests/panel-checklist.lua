local Status=require('./lib/ux/status-panel')
local Config=require('./lib/ux/status-config')
local values=require('./lib/variable-values')
local Theme=require('./lib/ux/theme')
local vars={panel={sortie_a={kill_5_abject=true}}}
local session={}
local context={getVar=function(path) return values.get(vars,path) end,
    setVar=function(path,value)
        local parts=values.path(path)
        local target=vars
        for i=1,#parts-1 do target[parts[i]]=target[parts[i]] or {}; target=target[parts[i]] end
        target[parts[#parts]]=value
    end,
    getSessionVar=function(path) return values.get(session,path) end,
    setSessionVar=function(path,value)
        local parts=values.path(path)
        local target=session
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
context.showChecklist=true
local definition={id='sortie_a',name='Objectives',show_when='showChecklist',format={'%s','error("must not run")'},
    expression='error("must not run")',value=17,
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
context.showChecklist=false
panel.nextUpdate=0; panel:update()
assert(entry.hidden and entry.checks[1].icon.image.shown==false and entry.checks[1].button.hitWidth==0 and
    entry.checks[1].button.text.value=='')
context.showChecklist=true
panel.nextUpdate=0; panel:update()
assert(not entry.hidden and entry.checks[1].icon.image.shown==true and entry.checks[1].button.hitWidth>0)
local first=entry.checks[1].button
local hx,hy=panel.panel.x+first.hitX+1,panel.panel.y+first.y+1
assert(panel.panel:mouse(0,hx,hy,false)==nil) -- hover does not consume movement
assert(first.hovered and first.text.rgb[1]==Theme.colors.yellow[1])
panel.nextUpdate=0; panel:update()
assert(first.hovered and first.text.rgb[1]==Theme.colors.yellow[1])
panel.panel:mouse(0,hx,hy,true)
assert(not first.hovered and first.text.rgb[1]==Theme.colors.checklist[1])
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
invalid({name='Bad persistence',id='test',persistent='yes',checklist={}})
invalid({name='Duplicate',id='test',checklist={{id='objective_2',text='One'},{text='Two'}}})
invalid({name='Bad item',id='test',checklist={{text='Bad\1control'}}})
invalid({name='Not array',id='test',checklist={key={text='One'}}})
invalid({name='Bad condition',id='test',checklist={{text='One',checked_when='true'}}})
invalid({name='Bad condition item',id='test',checklist={{text='One',checked_when={true}}}})
invalid({name='Bad visibility',show_when=true,value='x'})
invalid({name='Bad visibility item',show_when={true},value='x'})
context.owned=false
context.calls=0
context.checkSecond=function() context.calls=context.calls+1; return true end
panel:setTemporaryTracking({{id='automatic',name='Items',checklist={
    {id='owned',text='Owned items',checked_when={'owned','checkSecond()'}},
    {text='Empty conditions',checked_when={}},
    {text='Compile error',checked_when={'not valid lua !'}},
    {text='Runtime error',checked_when={'missing.functionCall()'}},
}}})
panel.nextUpdate=0; panel:update()
local automatic=panel.entries[1].checks
assert(not automatic[1].checked and context.calls==0)
assert(automatic[2].checked and not automatic[3].checked and not automatic[4].checked)
assert(automatic[1].icon.image.texture=='content/ui/checklist/automatic-unchecked.png')
assert(automatic[2].icon.image.texture=='content/ui/checklist/automatic-checked.png')
click(automatic[1].button)
assert(not context.getVar('vars.panel.automatic.owned'))
context.owned=true
panel.nextUpdate=0; panel:update()
assert(automatic[1].checked and context.calls==1)
assert(automatic[1].icon.image.texture=='content/ui/checklist/automatic-checked.png')
click(automatic[1].button)
assert(automatic[1].checked and not context.getVar('vars.panel.automatic.owned'))
context.owned=false
panel.nextUpdate=0; panel:update()
assert(not automatic[1].checked)
local persistentDefinition={id='sortie_manual',name='Persistent',persistent=true,
    checklist={{id='manual',text='Manual objective'}}}
panel:setTemporaryTracking({persistentDefinition})
panel.nextUpdate=0; panel:update()
local persistent=panel.entries[1].checks[1]
assert(persistent.path=='panel_checklists.sortie_manual.manual' and not persistent.checked)
click(persistent.button)
assert(context.getSessionVar(persistent.path)==true)
vars={panel={}} -- Simulate action variables being reconstructed by a reload.
panel:setTemporaryTracking({persistentDefinition})
panel.nextUpdate=0; panel:update()
assert(panel.entries[1].checks[1].checked)
panel:setTemporaryTracking({{id='multiline',name='Multiline',checklist={
    {id='text',text='Hello\n\tworld'},
    {id='format',format={'First\n\t%s',"'second'"}},
    {id='expression',expression="'Top\\n\\tbottom'"},
}}})
panel.nextUpdate=0; panel:update()
local multiline=panel.entries[1].checks
local lineHeight=math.ceil(panel.options.font_size*1.8)
assert(multiline[1].display=='Hello\n    world' and multiline[1].lineCount==2)
assert(multiline[2].display=='First\n    second' and multiline[2].lineCount==2)
assert(multiline[3].display=='Top\n    bottom' and multiline[3].lineCount==2)
assert(multiline[1].button.height==lineHeight*2)
assert(multiline[2].button.y==multiline[1].button.y+lineHeight*2)
assert(multiline[1].icon.y==multiline[1].button.y+
    math.floor((lineHeight-multiline[1].size)/2))
panel:setTemporaryTracking({{id='labels',name='Labels',checklist={
    {text='Ignored',expression="color_ki('Tooth')",checked_when={'owned'}},
    {expression="color_item('Potion')"},
    {expression="color_latest('Independent')"},
    {expression='missing.call()'},
    {expression='not valid lua !'},
}}})
panel.nextUpdate=0; panel:update()
local labels=panel.entries[1].checks
assert(labels[1].display==('\\cs(%d,%d,%d)Tooth\\cr'):format(unpack(Theme.colors.key_item)) and not labels[1].checked)
assert(labels[2].display==('\\cs(%d,%d,%d)Potion\\cr'):format(unpack(Theme.colors.item)))
assert(labels[3].display==('\\cs(%d,%d,%d)Independent\\cr'):format(unpack(Theme.colors.body)))
assert(labels[4].display=='[error]' and labels[5].display=='[error]')
context.owned=true
panel.nextUpdate=0; panel:update()
assert(labels[1].checked)
click(labels[2].button)
assert(context.getVar('vars.panel.labels.objective_2')==true)
invalid({id='bad_expression',name='Bad expression',checklist={{expression={"'text'"}}}})
panel:setTemporaryTracking({{id='formats',name='Formats',checklist={
    {text='ignored',expression='missing.call()',format={'%s: %s (E-6)',"color_ki('Tooth')","color_mob('Amarok')"}},
    {format={'Literal location (E-6)'}},
    {format={'%d','nil'}},
    {format={'%s','missing.call()'}},
    {format={'%s','invalid lua !'}},
    {format={'%s%s',"color_item('Item')","color_latest(' suffix')"}},
}}})
panel.nextUpdate=0; panel:update()
local formats=panel.entries[1].checks
assert(formats[1].display==('\\cs(%d,%d,%d)Tooth\\cr: '):format(unpack(Theme.colors.key_item))..('\\cs(%d,%d,%d)Amarok\\cr (E-6)'):format(unpack(Theme.colors.target_engaged)))
assert(formats[2].display=='Literal location (E-6)')
for index=3,5 do assert(formats[index].display=='[error]') end
assert(formats[6].display==('\\cs(%d,%d,%d)Item\\cr'):format(unpack(Theme.colors.item))..
    ('\\cs(%d,%d,%d) suffix\\cr'):format(unpack(Theme.colors.item)))
invalid({id='empty_format',name='Bad format',checklist={{format={}}}})
invalid({id='bad_format',name='Bad format',checklist={{format={'%s',123}}}})
panel:setTrackingSupplement('sortie',true)
panel.nextUpdate=0; panel:update()
local selector,sortieA
for _,candidate in ipairs(panel.entries) do
    if candidate.definition.id=='sortie' then selector=candidate end
    if candidate.definition.id=='sortie_a' then sortieA=candidate end
end
assert(selector and sortieA and selector.checks[1].checked)
click(selector.checks[2].button)
assert(context.getSessionVar('panel_branches.sortie')=='b')
local sortieB
for _,candidate in ipairs(panel.entries) do
    assert(candidate.definition.id~='sortie_a')
    if candidate.definition.id=='sortie_b' then sortieB=candidate end
end
assert(sortieB)
panel:setTrackingSupplement('sortie',true,{branch='d'})
panel.nextUpdate=0; panel:update()
local sortieD
for _,candidate in ipairs(panel.entries) do
    if candidate.definition.id=='sortie_d' then sortieD=candidate end
end
assert(sortieD)
panel:destroy()
print('PASS: checklist precedence, rendering, branches, clicks, external updates, generated ids and validation')
