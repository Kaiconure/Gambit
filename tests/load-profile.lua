local now=0
local clockReads=0
local factory=assert(loadfile('lib/load-profile.lua'))
local env=setmetatable({os={clock=function()clockReads=clockReads+1;return now end,date=function()return 'date 'end},
 print=function()end,windower={addon_path='test/',ffxi={get_player=function()return {name='Tester'}end},
 dir_exists=function()return true end},io={open=function()error('disk unavailable')end}}, {__index=_G})
setfenv(factory,env);local profile=factory()
profile.setEnabled(true)
local reports={}
local function report(message)reports[#reports+1]=message end
profile.begin('reload')
local file={read=function()now=now+0.01;return 'source'end}
assert(profile.read(file,'one')=='source')
profile.read(file,'one')
assert(profile.parse(function(text)now=now+0.02;return text..' parsed'end,'source')=='source parsed')
profile.stage('settings',0)
profile.sample('merge',0)
profile.finish(report)
assert(#reports==2 and reports[1]:find('reads=2 (1 unique, 20.0ms)',1,true))
assert(reports[2]:find('merge=40.0ms/1 calls',1,true))
assert(reports[1]:find('parses=1 (20.0ms)',1,true) and reports[1]:find('settings=40.0ms',1,true))
profile.finish(report);assert(#reports==2)
profile.begin('compile');profile.finish(report)
assert(reports[3]:find('reads=0',1,true))
profile.begin('equipment')
local first,middle,last=profile.measure('item lookup',function(a,b)
 now=now+0.01;return a,nil,b
end,1,3)
assert(first==1 and middle==nil and last==3)
profile.finish(report)
assert(reports[5]:find('item lookup=10.0ms/1 calls',1,true))
first,middle,last=profile.measure('inactive',function()return 4,nil,6 end)
assert(first==4 and middle==nil and last==6)
profile.report('Load succeeded despite unavailable log file')
-- Named timers support nesting, including the same name and nested scopes.
profile.begin('outer')
profile.start('work');now=now+0.01
profile.start('work');now=now+0.01;profile.stop('work');profile.stop('work')
profile.begin('inner');profile.start('inner work');now=now+0.01;profile.stop('inner work')
profile.finish(report);profile.checkpoint('after inner');profile.finish(report)
assert(reports[#reports]:find('work=30.0ms/2 calls',1,true))
profile.setEnabled(false)
local readsBefore=clockReads
local reportCount=#reports
profile.begin('disabled');profile.start('work');assert(profile.now()==nil)
profile.stop('work');profile.checkpoint('work');profile.sample('work',0);profile.stage('work',0)
assert(profile.read(file,'disabled')=='source')
assert(profile.parse(function(value)return value end,'value')=='value')
first,middle,last=profile.measure('disabled',function()return 1,nil,3 end)
assert(first==1 and middle==nil and last==3)
profile.finish(report);profile.report('disabled')
assert(clockReads==readsBefore and #reports==reportCount)
-- The switch persists locally, so a fresh addon can profile its own startup.
local markerExists=false
local controlEnv=setmetatable({windower={addon_path='test/',dir_exists=function()return true end},
    io={open=function(path,mode)
        assert(path=='test/.data/load-profile.enabled')
        if mode=='r' and not markerExists then return nil end
        if mode=='w' then markerExists=true end
        return {write=function()end,close=function()end}
    end},os={clock=function()return now end,remove=function()markerExists=false;return true end}}, {__index=_G})
local function fresh()
    local chunk=assert(loadfile('lib/load-profile.lua'));setfenv(chunk,controlEnv);return chunk()
end
local control=fresh();assert(not control.isEnabled())
control.configure(true);assert(control.isEnabled() and fresh().isEnabled())
control.configure(false);assert(not control.isEnabled() and not fresh().isEnabled())
print('PASS: load timing, read/parse counts, repeated-file detection, reset and isolated log-write failures')
