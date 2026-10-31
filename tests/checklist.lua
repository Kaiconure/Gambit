local Checklist=require('./lib/checklist')
local values=require('./lib/variable-values')
local shared={}
local function set(path,value)
    local levels=values.path(path)
    local target=shared
    for i=1,#levels-1 do target[levels[i]]=target[levels[i]] or {}; target=target[levels[i]] end
    target[levels[#levels]]=value
end
local action,event={vars={}},{vars={}}
for _,context in ipairs({action,event}) do
    Checklist.attach(context,function(path) return values.get(shared,path) end,set)
end
assert(action.checklistGet('sortie_a','objective_1')==false)
for _,value in ipairs({true,0,'',{},'done'}) do
    assert(action.checklistSet('sortie_a','objective_1',value)==true)
    assert(shared.panel.sortie_a.objective_1==true)
    assert(event.checklistGet('sortie_a','objective_1')==true)
end
assert(event.checklistSet('sortie_a','objective_1',false)==false)
assert(action.checklistGet('sortie_a','objective_1')==false)
assert(event.checklistSet('sortie_a','objective_1')==false)
assert(shared.panel.sortie_a.objective_1==false)
assert(next(action.vars)==nil and next(event.vars)==nil)
assert(not pcall(action.checklistSet,'a.b','item',true))
assert(not pcall(action.checklistGet,'a',nil))
-- Verify real contexts use automation state even when event variables are supplied.
local file=assert(io.open('lib/action-context.lua')); local source=file:read('*a'); file:close()
local body=assert(source:match('(    local checklistVariables=.-checklist.attach%([^)]+%))'))
local fixture={}
local chunk=assert(loadstring(body))
setfenv(chunk,{context=fixture,actionStateManager={vars=shared},checklist=Checklist,
    attachVariableHelpers=function(context)
        assert(context.vars==shared)
        context.getVar=function(path) return values.get(context.vars,path) end
        context.setVar=set
    end})
chunk()
assert(fixture.checklistSet('sortie_a','objective_2',1)==true)
assert(shared.panel.sortie_a.objective_2==true)
print('PASS: checklist boolean helpers, shared event/action state and validation')
