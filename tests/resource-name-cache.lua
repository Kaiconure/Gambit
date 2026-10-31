local file=assert(io.open('lib/resx.lua')); local source=file:read('*a'); file:close()
-- Windower permits string-literal method syntax; vanilla Lua 5.1 needs parentheses.
source=source:gsub('("[^"\r\n]*"):format','(%1):format'):gsub("('[^'\r\n]*'):format",'(%1):format')
local scans=0
local env=setmetatable({globals={language='English'},tableFirst=function(entries,predicate)
    scans=scans+1
    for _,entry in ipairs(entries) do if predicate(entry) then return entry end end
end},{__index=_G})
local chunk=assert(loadstring(source)); setfenv(chunk,env); chunk()
local first={id=1,en='Test Item',enl='Test Items',jp='Japanese name'}
local duplicate={id=2,en='Test Item',jp='Second Japanese name'}
local items={first,duplicate}
local find=env.findResourceByName
assert(find(items,'Test Item')==first and scans==1)
assert(find(items,'TEST ITEM')==first and scans==1)
assert(find(items,{name='test item'})==first and scans==1)
assert(find(items,'"Test Item"')==first)
assert(find(items,'Test Items')==first)
assert(find(items,'"Test Items"')==first)
local before=scans
for i=1,1000 do assert(find(items,'Provoke')==nil) end
assert(scans==before+1)
before=scans
assert(find(items,1)==first and find(items,{id=2,name='Test Item'})==duplicate and scans==before)
assert(find(items,'Japanese name','Japanese')==first)
before=scans
assert(find(items,'Test Item','Japanese')==nil)
assert(find(items,'Test Item','English')==first and scans==before+1)
env.globals.language='Japanese'
assert(find(items,'Japanese name')==first)
local other={{id=1,en='Test Item',jp='Japanese name'}}
assert(find(other,'Test Item','English')==other[1])
assert(find(nil,'Test Item')==nil and find(items,false)==nil)
-- A replacement resource table gets fresh matches/misses; capacity is bounded.
local replacement={{id=1,en='Provoke',jp='Other'}}
assert(find(replacement,'Provoke','English')==replacement[1])
for i=1,1030 do find(items,'missing '..i,'English') end
before=scans; assert(find(items,'test item','English')==first and scans==before+1)
print('PASS: positive/negative resource caching, normalization, quoted/plural names, language/table isolation, ID bypass, first match and eviction')
