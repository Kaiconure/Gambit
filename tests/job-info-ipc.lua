local function read(path)
    local file=assert(io.open(path))
    local source=file:read('*a'); file:close()
    return source
end
local source=read('Gambit.lua')
local messages={}
local player={name='Steris', main_job='WHM', main_job_level=99, sub_job='RDM', sub_job_level=49}
local party
local env=setmetatable({
    windower={send_ipc_message=function(message) messages[#messages+1]=message end,
        ffxi={get_player=function() return player end, get_party=function() return party end}},
    hasArg=function(args, flag)
        for _, arg in ipairs(args) do if arg==flag then return true end end
        return false
    end,
    jobInfoRecords=require('./lib/job-info'), globals={ipc_job_info={}},
    weaponSkillInfo=require('./lib/weapon-skill-info'),
    getArgValue=function(args, flag)
        for i, arg in ipairs(args) do if arg==flag then return args[i+1] end end
    end,
    handlers={}, meta={trusts={}}, writeMessage=function() end,
}, {__index=_G})
local function run(code)
    -- Windower's Lua accepts method calls directly on string literals.
    code=code:gsub("('[^'\r\n]*'):format", '(%1):format')
    local chunk=assert(loadstring(code)); setfenv(chunk,env); return chunk()
end
run(assert(source:match('(function sendJobInfoIpc.-)function reloadSettings')))
local ids={3,1}
env.windower.ffxi.get_abilities=function() return {weapon_skills=ids} end
env.syncWeaponSkillInfoIpc()
assert(messages[1]=='wsinfo -sync' and messages[2]=='wsinfo -n Steris -ids 1,3')
env.sendWeaponSkillInfoIpc(true)
assert(#messages==2)
ids={4}
env.sendWeaponSkillInfoIpc(true)
assert(#messages==3 and messages[3]=='wsinfo -n Steris -ids 4')
local wsHandler=assert(source:match("elseif command == 'wsinfo' then(.-)elseif command == 'job' then"))
run('function receiveWs(args) '..wsHandler..' end')
env.receiveWs({'wsinfo','-n','Carbonite','-ids','7,9'})
assert(env.weaponSkillInfo.records.Carbonite.encoded=='7,9')
env.receiveWs({'wsinfo','-sync'})
assert(#messages==4 and messages[4]=='wsinfo -n Steris -ids 4')
messages={}
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
env.text_weapon_skill=function(value) return value end
env.resources={weapon_skills={[4]={name='Savage Blade'},[7]={name='Chant du Cygne'},[9]={name='Burning Blade'}}}
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
env.meta={trusts=require('./meta/trusts'), trusts_by_party_name={}}
for _, trust in pairs(env.meta.trusts) do
    local name=trust.party_name:lower()
    local matches=env.meta.trusts_by_party_name[name] or {}
    matches[#matches+1]=trust
    env.meta.trusts_by_party_name[name]=matches
end
run(assert(read('lib/resx.lua'):match('(TrustSearchModes = .-\nfunction getTrustPartyMeta.-\nend)')))
env.canUseSpell=function() error('Trust job lookup must not depend on spell usability') end
assert(env.getTrustPartyMeta('Prishe',3082).name=='Prishe II')
assert(env.getTrustPartyMeta('Prishe').name=='Prishe')
output={}
env.handlers.jobinfo({'-n','ArKeV'})
env.handlers.jobinfo({'-name','pRiShE ii'})
assert(output[1]=='Job Info: AAEV is PLD/WHM')
assert(output[2]=='Job Info: Prishe II is WHM/MNK')
env.SPAWN_TYPE_TRUST=14
party={
    p1={mob={name='Prishe',spawn_type=14,models={3082}}},
    a10={mob={name='ArkEV',spawn_type=14}},
    a25={mob={name='Naji',spawn_type=14}},
    p2={mob={name='Ayame',spawn_type=13}},
    p3={name='Kupipi'},
    party1_count=4,
}
output={}
env.handlers.jobinfo({'-all'})
assert(#output==6)
local listed={}
local previousName=''
for _, line in ipairs(output) do
    local name=assert(line:match('^Job Info: (.-) is ')):lower()
    assert(previousName<=name, 'Job info must be sorted')
    previousName=name
    listed[line]=true
end
assert(listed['Job Info: Prishe II is WHM/MNK'])
assert(listed['Job Info: AAEV is PLD/WHM'] and listed['Job Info: Naji is WAR/WAR'])
assert(not listed['Job Info: Prishe is MNK/WHM'])
run(assert(read('lib/commands.lua'):match("(handlers%['wsinfo'%] = function.-)\nhandlers%['jobinfo'%]")))
output={}
env.handlers.wsinfo({})
assert(output[1]=='Weapon skills for Steris:' and output[2]=='  Savage Blade')
output={}
env.handlers.wsinfo({'-all'})
assert(#output==4 and output[1]=='Weapon skills for Carbonite:' and output[2]=='  Chant du Cygne, Burning Blade')
assert(output[3]=='Weapon skills for Steris:' and output[4]=='  Savage Blade')
local before=#messages
env.handlers.wsinfo({'-sync'})
assert(messages[before+1]=='wsinfo -sync' and messages[before+2]=='wsinfo -n Steris -ids 4')
env.handlers.wsinfo({'-send'})
assert(messages[#messages]=='wsinfo -n Steris -ids 4')
local loadHandler=assert(source:match("windower.register_event%('load', function%(%)(.-)windower.register_event%('login'"))
local loginHandler=assert(source:match("windower.register_event%('login', function%s*%(%)(.-)windower.register_event%('logout'"))
assert(loadHandler:find('syncJobInfoIpc()',1,true))
assert(loginHandler:find('syncJobInfoIpc()',1,true))
assert(loadHandler:find('syncWeaponSkillInfoIpc()',1,true))
assert(loginHandler:find('syncWeaponSkillInfoIpc()',1,true))
print('PASS: all-job requests, self broadcast, response handling, commands and startup hooks')
