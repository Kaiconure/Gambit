local Export=require('./lib/events/discovery-export')
local json=require('./lib/jsonlua')
local Recovery=require('./lib/events/discovery-recovery')
local chunks={}
Export.encode({version=1,entries={{kind='text',original='quote" slash\\\n\t'}},truncated=false},
    function(chunk) chunks[#chunks+1]=chunk end)
local result=json.parse(table.concat(chunks))
assert(result.version==1 and result.entries[1].kind=='text' and result.truncated==false)
assert(table.concat(chunks):find('\\u000a',1,true) and table.concat(chunks):find('\\u0009',1,true))
local entry={original=string.char(0,1,30,31)..'"\\'}
local bytes={};Export.encode(entry,function(chunk) bytes[#bytes+1]=chunk end)
local encoded=table.concat(bytes)
assert(encoded:find('\\u0000\\u0001\\u001e\\u001f',1,true))
assert(not encoded:find('[%z\1-\31]'),'JSON must escape incoming chat control bytes')
local circular={};circular.self=circular
assert(not pcall(Export.encode,circular,function() end))
local path=(os.getenv('TEMP') or os.getenv('TMP') or '.')..'/'..
    os.tmpname():match('[^/\\]+$')..'-gambit-discovery.json'
local capture={version=1,metadata={player={name='Tester'}},entries={}}
for i=1,8192 do capture.entries[i]={step=i,time=i/10,kind='text',original=string.rep('recorded text ',30)} end
Export.write(path,capture)
local file=assert(io.open(path,'rb'));local content=file:read('*a');file:close()
local decoded=json.parse(content)
assert(#decoded.entries==8192 and decoded.entries[8192].step==8192)
assert(not io.open(path..'.partial','rb'))
assert(os.remove(path))
-- Failed writes leave the caller's data available; old loaded services can be
-- redirected without changing their methods or invoking an addon reload.
local service={deps={writeProcessed=function() error('old writer') end},discoveryResult=capture}
local previousWrite=Export.write
local saved
Export.write=function(destination,value) saved={destination,value} end
Recovery.install(service,{addon_path='addon/'},{new=function()
    return {create_path=function() return true end}
end})
service.deps.writeProcessed('capture.json',capture)
assert(saved[1]=='addon/capture.json' and saved[2]==capture and service.discoveryResult==capture)
Export.write=function() error('disk unavailable') end
assert(not pcall(service.deps.writeProcessed,'capture.json',capture))
assert(service.discoveryResult==capture)
Export.write=previousWrite
print('PASS: streaming 8192-entry export, control-byte escaping, atomic publication and live recovery routing')
