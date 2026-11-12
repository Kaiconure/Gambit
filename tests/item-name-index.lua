local index=require('./lib/item-name-index')
local file=assert(io.open('lib/resx.lua'));local source=file:read('*a');file:close()
source=source:gsub('("[^"\r\n]*"):format','(%1):format'):gsub("('[^'\r\n]*'):format",'(%1):format')
local scans=0
local env=setmetatable({globals={language='English'},tableFirst=function(items,predicate)
    scans=scans+1
    for _,item in ipairs(items)do if predicate(item)then return item end end
end},{__index=_G})
local chunk=assert(loadstring(source));setfenv(chunk,env);chunk()
package.loaded['./meta/generated-item-name-index']={existing=1,stale=1,missing=99}
index.reload()
package.loaded['./meta/generated-item-name-index']={existing=1,stale=1,missing=99}
local items={{id=1,en='Existing',enl='Existing long name'},{id=2,en='Stale'},{id=3,en='Missing'},{id=4,en='New'}}
local function find(name)return env.findResourceByName(items,name,'English',index)end
assert(find('EXISTING')==items[1] and scans==0)
assert(find('"Existing"')==items[1] and scans==0)
assert(find('Stale')==items[2] and scans==1)
assert(find('Missing')==items[3] and scans==2)
assert(find('New')==items[4] and scans==3)
assert(find('Stale')==items[2] and find('New')==items[4] and scans==3)
assert(package.loaded['./meta/generated-item-name-index'].stale==1)
local names=index.build({{en='Duplicate',enl='Unique'},{en='Duplicate'}})
assert(names.duplicate==false and names.unique==1)
index.reload()
local real=assert(loadfile('meta/generated-item-name-index.lua'))()
local count=0;for name,id in pairs(real)do assert(type(name)=='string' and type(id)=='number');count=count+1 end
assert(count>10000)
print('PASS: generated hits, stale/missing/new fallback, live caching, ambiguity and shipped index ('..count..' names)')
