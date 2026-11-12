local json=require('./lib/jsonlua')
local slots=require('./lib/action-slots')
local copy=require('./lib/variable-values').copy
local function read(path)
 local f=assert(io.open(path));local doc=json.parse(f:read('*a'));f:close();return doc
end
local function countImport(actions,name)
 local count=0
 for _,action in ipairs(actions)do
  local imports=action.import or action.imports or {}
  if type(imports)=='string' then imports={imports} end
  for _,value in ipairs(imports)do if value==name then count=count+1 end end
 end
 return count
end
local common=read('settings/_namespaces/_base/actions/lib/common/common.json')
local shared={contributions={}}
for _,entry in ipairs(common.contributions) do
 if entry.slot=='normal-engagement' then shared.contributions[#shared.contributions+1]=entry end
end
local melee=read('settings/_namespaces/_base/actions/lib/common/(melee).json')
assert(#melee.imports==1 and melee.imports[1]=='tank-alignment')
local selectors=require('./lib/target-selectors')
for _,job in ipairs({'WAR','PLD','SAM','RUN','BLU'})do
 local found=false
 for _,group in ipairs(selectors.entryPointGroups(job,false))do if group=='melee' then found=true end end
 assert(found,job)
end
for _,job in ipairs({'WHM','BLM','RDM','GEO','COR'})do
 for _,group in ipairs(selectors.entryPointGroups(job,false))do assert(group~='melee',job) end
end
for _,job in ipairs({'(melee)','pld','war','blm','cor','geo','rdm','whm'})do
 local doc=read('settings/_namespaces/_base/actions/'..job..'.json')
 for _,kind in ipairs({'pull','battle'})do
  local found=0
  for index,action in ipairs(doc[kind])do
   if action.slot=='normal-engagement' then
    found=found+1
    assert(action.actions==nil) -- Definitions live in common, not at slot occurrences.
   end
  end
  assert(found==1 and countImport(doc[kind],'frontline-engagement')==0)
 end
 for _,kind in ipairs({'pull','battle','idle','imports'})do
  assert(countImport(doc[kind] or {},'tank-alignment')==0)
  assert(countImport(doc[kind] or {},'dynamic-engagement')==0)
 end
 -- Exercise actual slot resolution for default, additive, empty replacement,
 -- and replacement imports, in both pull and battle. Definitions collect once.
 for _,mode in ipairs({'default','add','clear','replace'})do
  local container=copy(doc)
  local engine=slots.new(container,function(source)return source=='child' and 0 or 1 end,error,nil,'base')
  engine.collect(doc,'base');engine.collect(doc,'base')
  engine.collect(shared,'common');engine.collect(shared,'common')
  if mode~='default' then
   local key=mode=='add' and 'normal-engagement' or '!normal-engagement'
   local actions=mode=='clear' and {} or {{import='custom-engagement'}}
   engine.collect({contributions={[key]=actions}},'child')
  end
  engine.expand({'pull','battle'})
  for _,kind in ipairs({'pull','battle'})do
   assert(countImport(container[kind],'dynamic-engagement')==((mode=='default' or mode=='add') and 1 or 0))
   assert(countImport(container[kind],'custom-engagement')==((mode=='add' or mode=='replace') and 1 or 0))
   assert(countImport(container[kind],'tank-alignment')==0)
  end
 end
end
local dynamic=read('actions/lib/dynamic-engagement.json')
for _,model in ipairs({'frontline','member'})do
 local selected={}
 for _,action in ipairs(dynamic.actions)do
  local fn=assert(loadstring('return '..action.precondition[1]))
  setfenv(fn,{vars={dynamic_engagement={model=model}}})
  if fn() then selected[#selected+1]=action.import end
 end
 assert(#selected==1 and selected[1]==model..'-engagement')
end
print('PASS: all eight base entries, common engagement definition, melee setup import selection, additive/clear/replacement contributions and dynamic model selection')
