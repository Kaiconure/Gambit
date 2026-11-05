-- Load this new module in the existing addon VM to rescue a retained capture.
collectgarbage('collect')
local Export=require('./lib/events/discovery-export')
local Recovery={}
function Recovery.install(service,windower,files)
    local previous=service.deps.writeProcessed
    local function write(path,result)
        local destination=files.new(path)
        assert(destination:create_path())
        Export.write(windower.addon_path..path,result)
    end
    service.deps.writeDiscovery=write
    -- Already loaded Service:discovery implementations still call writeProcessed.
    service.deps.writeProcessed=function(path,result)
        if result==service.discoveryResult then return write(path,result) end
        return previous(path,result)
    end
end
if globals and globals.event_system then
    Recovery.install(globals.event_system,windower,require('files'))
    collectgarbage('collect')
    local ok,message=pcall(globals.event_system.discovery,globals.event_system,'stop')
    windower.add_to_chat(ok and 207 or 167,tostring(message))
end
return Recovery
