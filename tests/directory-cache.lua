local calls=0
local disk={['/addon/settings/_namespaces']=true}
local factory=assert(loadfile('lib/settings-paths.lua'))
setfenv(factory,setmetatable({windower={addon_path='/addon/',dir_exists=function(path)
 calls=calls+1;return disk[path] or false
end}}, {__index=_G}))
local paths=factory()
paths.withDirectoryCache(function()
 assert(paths.namespaceRoot()=='./settings/_namespaces')
 local first=calls
 for i=1,100 do assert(paths.namespaceRoot()=='./settings/_namespaces')end
 assert(calls==first)
 paths.withDirectoryCache(function()paths.namespaceRoot();assert(calls==first)end)
 disk['/addon/settings/_namespaces']=nil
 assert(paths.namespaceRoot()=='./settings/_namespaces' and calls==first)
end)
-- A fresh load sees additions/removals, including formerly negative results.
disk['/addon/settings/namespaces']=true
paths.withDirectoryCache(function()
 assert(paths.namespaceRoot()=='./settings/namespaces')
 local first=calls
 disk['/addon/settings/_namespaces']=true
 assert(paths.namespaceRoot()=='./settings/namespaces' and calls==first)
end)
assert(paths.namespaceRoot()=='./settings/_namespaces')
local ok=pcall(paths.withDirectoryCache,function()
 paths.namespaceRoot();error('load failed')
end)
assert(not ok)
disk['/addon/settings/_namespaces']=nil
assert(paths.namespaceRoot()=='./settings/namespaces') -- Failure did not leak cache.
local a,b,c=paths.withDirectoryCache(function()return 1,nil,3 end)
assert(a==1 and b==nil and c==3)
print('PASS: per-load positive/negative directory caching, nested scope, refresh, error cleanup and return values')
