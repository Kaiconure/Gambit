local function read(path)
    local file=assert(io.open(path))
    local source=file:read('*a'); file:close()
    return source
end
local source=read('Gambit.lua')
local messages={}
local player={name='Steris', main_job='WHM', main_job_level=99, sub_job='RDM', sub_job_level=49}
local env=setmetatable({
    windower={send_ipc_message=function(message) messages[#messages+1]=message end,
        ffxi={get_player=function() return player end}},
    hasArg=function(args, flag)
        for _, arg in ipairs(args) do if arg==flag then return true end end
        return false
    end,
    jobInfoRecords=require('./lib/job-info'), globals={ipc_job_info={}},
    getArgValue=function(args, flag)
        for i, arg in ipairs(args) do if arg==flag then return args[i+1] end end
    end,
    handlers={}, writeMessage=function() end,
}, {__index=_G})
local function run(code)
    -- Windower's Lua accepts method calls directly on string literals.
    code=code:gsub("('[^'\n]*'):", '(%1):')
    local chunk=assert(loadstring(code)); setfenv(chunk,env); return chunk()
end
run(assert(source:match('(function sendJobInfoIpc.-)function reloadSettings')))
env.syncJobInfoIpc()
assert(messages[1]=='job -sync')
assert(messages[2]=='job -n Steris -main WHM -main-l 99 -sub RDM -sub-l 49')
local jobHandler=assert(source:match("elseif command == 'job' then(.-)elseif command == 'set_bt' then"))
run('function receiveJob(args) '..jobHandler..' end')
env.receiveJob({'job','-sync'})
assert(#messages==3 and messages[3]==messages[2], 'Requests must produce one response without another request')
env.receiveJob({'job','-n','Carbonite','-main','WAR','-main-l','99'})
assert(env.globals.ipc_job_info.Carbonite.main_job=='WAR' and #messages==3)
run(assert(read('lib/commands.lua'):match("(handlers%['jobinfo'%] = function.-)\nhandlers%['ji'%] = handlers%['jobinfo'%]")))
env.handlers.jobinfo({'-sync'})
assert(#messages==5 and messages[4]=='job -sync' and messages[5]==messages[2])
env.handlers.jobinfo({'-send'})
assert(#messages==6 and messages[6]==messages[2])
local output={}
env.writeMessage=function(message) output[#output+1]=message end
env.makePlayerName=function(name) return name end
env.text_player=function(value) return value end
env.text_cornsilk=function(value) return value end
env.globals.ipc_job_info.Zebra={main_job='WAR',main_job_level=75}
env.handlers.jobinfo({'-all'})
assert(#output==3)
assert(output[1]=='Job Info: Carbonite is WAR99')
assert(output[2]=='Job Info: Steris is WHM99/RDM49')
assert(output[3]=='Job Info: Zebra is WAR75')
env.globals.ipc_job_info.Steris={main_job='BLM',main_job_level=1}
output={}
env.handlers.jobinfo({'-all'})
assert(#output==3 and output[2]=='Job Info: Steris is WHM99/RDM49', 'Self must use live information and appear only once')
local loadHandler=assert(source:match("windower.register_event%('load', function%(%)(.-)windower.register_event%('login'"))
local loginHandler=assert(source:match("windower.register_event%('login', function%s*%(%)(.-)windower.register_event%('logout'"))
assert(loadHandler:find('syncJobInfoIpc()',1,true))
assert(loginHandler:find('syncJobInfoIpc()',1,true))
print('PASS: all-job requests, self broadcast, response handling, commands and startup hooks')
