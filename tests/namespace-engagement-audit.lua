-- Run with a JSON array of repository-relative file paths as arg[1].
-- Compare the shared-common refactor with its former per-entry definitions,
-- using real namespace resolution, imports, variables and slot expansion.
local json=require('./lib/jsonlua')
local copy=require('./lib/variable-values').copy
local function read(path)local f=assert(io.open(path));local s=f:read('*a');f:close();return s end
local manifest=json.parse(read(assert(arg[1],'file manifest required')))
local fileset,dirs,namespaces={},{},{}
local function norm(path)return path:gsub('\\','/'):gsub('^%./',''):lower()end
for _,path in ipairs(manifest)do
 path=norm(path);fileset[path]=true
 local dir=path:match('^(.*)/[^/]+$')
 while dir do dirs[dir]=true;dir=dir:match('^(.*)/[^/]+$')end
 local ns=path:match('^settings/_namespaces/(.*)/%.nsconfig$')
 if ns then namespaces[#namespaces+1]=ns end
end
table.sort(namespaces)
windower={addon_path='',dir_exists=function(path)return dirs[norm(path)] or false end}
local paths=require('./lib/settings-paths')
local selectors=require('./lib/target-selectors')
local slots=require('./lib/action-slots')
local baseline=false
local cache={}
local function exists(path)
 path=norm(path)
 if baseline and path=='settings/_namespaces/_base/actions/lib/common/(melee).json' then return false end
 return fileset[path] or false
end
local function document(path)
 path=norm(path)
 if not cache[path] then cache[path]=json.parse(read(path))end
 local doc=copy(cache[path])
 if not baseline then return doc end
 if path=='settings/_namespaces/_base/actions/lib/common/common.json' then
  for index=#doc.contributions,1,-1 do if doc.contributions[index].slot=='normal-engagement' then table.remove(doc.contributions,index) end end
 end
 local job=path:match('^settings/_namespaces/_base/actions/([^/]+)%.json$')
 if job then
  for _,kind in ipairs({'pull','battle'})do
   for i=#(doc[kind] or {}),1,-1 do
    local action=doc[kind][i]
    if action.slot=='normal-engagement' then
     if kind=='battle' then action.actions={{imports=job=='pld' and {'tank-alignment','dynamic-engagement'} or {'dynamic-engagement'}}}end
     if job=='war' or job=='(melee)' then table.insert(doc[kind],i,{import='tank-alignment'})end
    end
   end
  end
  if job=='pld' or job=='war' or job=='(melee)' then
   for _,a in ipairs(doc.idle or {})do if a.imports and a.imports[1]=='configuration' then a.imports={'configuration','tank-alignment'}end end
  end
 end
 return doc
end
local warnings={}
local leader=arg[2]~='nonleader'
local subJob=arg[3] or 'WAR'
local env=setmetatable({profiling=require('./lib/load-profile'),variableScopes=require('./lib/variable-scopes'),
 actionPreconditions=require('./lib/action-preconditions'),actionSlots=slots,variableLoader=require('./lib/variable-loader'),
 settingsPaths=paths,targetSelectors=selectors,loadingLeader=leader,
 firstSettingsPath=function(candidates)for _,path in ipairs(candidates)do if exists(path)then return path end end end,
 files={new=function(path)return {exists=function()return exists(path)end,read=function()return document(path)end}end},
 json={parse=function(value)return value end},writeWarning=function(s)warnings[#warnings+1]=s end,
 writeMessage=function(s)warnings[#warnings+1]=s end,text_action=tostring,text_gold=tostring,text_number=tostring,
 _processMacros=function()end,
 useArray=function(v)return type(v)=='table' and v or {v}end,
 arrayIndexOf=function(t,v)for i,x in ipairs(t or {})do if x==v then return i end end end}, {__index=_G})
local source=read('lib/settings.lua'):gsub("('[^'\r\n]*'):format",'(%1):format')
local code=assert(source:match('(local function _loadActionImportsInternal.-)local function _expandActionMacrosToArray'))..
 assert(source:match('(local function loadActionImports.-)local function _expandVariable'))..'\nreturn loadActionImports'
local chunk=assert(loadstring(code));setfenv(chunk,env);local load=chunk()
local function clean(value)
 if type(value)~='table' then return value end
 local result={}
 for key,child in pairs(value)do
  if type(key)~='string' or (key:sub(1,1)~='_' and key~='id' and key~='discriminator' and key~='importedFrom')then result[key]=clean(child)end
 end
 if value._inheritedPreconditions and #value._inheritedPreconditions>0 then
  result.inheritedConditions={}
  for _,condition in ipairs(value._inheritedPreconditions)do result.inheritedConditions[#result.inheritedConditions+1]=condition.expression end
 end
 return result
end
local function difference(a,b,path)
 if type(a)~=type(b)then return path..' (type)'end
 if type(a)~='table' then if a~=b then return path..' ('..tostring(a)..' -> '..tostring(b)..')'end;return end
 for k,v in pairs(a)do local diff=difference(v,b[k],path..'.'..tostring(k));if diff then return diff end end
 for k in pairs(b)do if a[k]==nil then return path..'.'..tostring(k)..' (added)'end end
end
local jobs={'WAR','MNK','WHM','BLM','RDM','THF','PLD','DRK','BST','BRD','RNG','SAM','NIN','DRG','SMN','BLU','COR','PUP','DNC','SCH','GEO','RUN'}
local count,changes,errors=0,0,0
for _,ns in ipairs(namespaces)do
 local chain=paths.resolveInheritance(ns,function(name)return document(paths.namespacePath(name)..'/.nsconfig')end,
  function(name)return exists(paths.namespacePath(name)..'/.nsconfig')end)
 local derived=false
 for _,name in ipairs(chain)do if norm(paths.namespacePath(name))=='settings/_namespaces/_base' then derived=true end end
 if derived then
  paths.setLoadedNamespace(ns,chain)
  local nsCount=0
  for _,job in ipairs(jobs)do
   local layers=paths.entryPointLayers('Audit', 'actions');layers[#layers+1]='./actions/standard'
   local entry=require('./lib/action-entry-points').find(layers,job,subJob,selectors.entryPointGroups(job,leader),exists)
   if entry then
    local versions={}
    for i=1,2 do
     baseline=i==1;warnings={}
     local actions=document(entry)
     local ok,err=pcall(load,'Audit',actions,{name='Audit',main_job=job,sub_job=subJob,main_job_level=99},entry)
     if not ok then versions[i]={error=tostring(err)}
     else
      local snapshot={vars=actions.vars}
      for _,kind in ipairs({'pull','battle','idle','idle_battle','loading','functions','mounted','dead'})do snapshot[kind]=actions[kind]end
      local normalized=clean(snapshot)
      normalized.vars=copy(actions.vars)
      for _,kind in ipairs({'pull','battle','idle','idle_battle','loading','functions','mounted','dead'})do
       for index,action in ipairs(actions[kind] or {})do
        local scope=action._variableScope
        if scope then
         local chain={}
         while scope do
          local definition=assert(actions._variableScopes[scope])
          table.insert(chain,1,copy(definition.overrides));scope=definition.parent
         end
         normalized[kind][index].variableScopeChain=chain
        end
       end
      end
      versions[i]={snapshot=normalized,warnings=copy(warnings)}
     end
    end
    baseline=false;count=count+1;nsCount=nsCount+1
    if versions[1].error or versions[2].error then
     errors=errors+1;print('LOAD ERROR '..ns..'/'..job..': '..tostring(versions[1].error)..' | '..tostring(versions[2].error))
    else
     local diff=difference(versions[1].snapshot,versions[2].snapshot,'compiled')
     local warn=difference(versions[1].warnings,versions[2].warnings,'warnings')
     if diff or warn then changes=changes+1;print('CHANGE '..ns..'/'..job..': '..(diff or warn))end
    end
   end
  end
  print('AUDITED '..ns..': '..nsCount..' jobs')
 end
end
print('TOTAL '..count..' configurations ('..(leader and 'leader' or 'nonleader')..', /'..subJob..'); '..changes..' differences; '..errors..' load errors')
assert(changes==0 and errors==0,'Namespace engagement audit found differences')
