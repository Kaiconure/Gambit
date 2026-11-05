local Yellow=require('./lib/abyssea-yellow')
local resource={Fire={element=0},Water={element=5},['Ice Threnody']={element=0},['Katon: Ni']={element=0}}
local target={id=200,index=2,hpp=100}
local observation={yellow={}}
local storage={}
local config={state=storage,spells={'Fire','Water','Ice Threnody','Katon: Ni'}}
local attempts,ready,tools={}, {},true
local allowed=true
local now,busy=0,false
local deps={resource=function(name) return resource[name] end,log=function() end,
    clock=function() return now end,busy=function() return busy end,
    ready=function(name) return ready[name]~=false end,prepare=function(name) return name~='Katon: Ni' or tools end,
    allowed=function() return allowed end,use=function(name) attempts[#attempts+1]=name;return false,{started=true,outcome='interrupted'} end}
local function step() Yellow.step(config,target,observation,deps) end
Yellow.validate(config)
ready.Fire=false
step();assert(attempts[1]=='Water','cooldown must not block ready candidates')
observation.yellow.element='fire'
step();assert(attempts[2]=='Ice Threnody','filter by actual resource element, not spell name')
tools=false;step();assert(attempts[3]=='Ice Threnody','missing tools must not block other candidates or repeat passes')
tools=true;step();assert(attempts[4]=='Katon: Ni')
ready.Fire=true;step();assert(attempts[5]=='Fire','failed/interrupted attempts remain eligible on later passes')
observation.red={triggered=true};step();assert(attempts[6],'red stagger must not stop yellow')
observation.yellow.triggered=true
local before=#attempts;step();assert(#attempts==before,'yellow confirmation stops by default')
config.on_stagger='full_rotation';step()
assert(storage._yellow_rotation.element==nil,'full rotation removes the element restriction')
config.spells={'Water'};step();assert(attempts[#attempts]=='Water','new day pool resets iteration')
allowed=false;before=#attempts;step();assert(#attempts==before,'recheck after preparation')
assert(not pcall(Yellow.validate,{}))
assert(not pcall(Yellow.validate,{spells={'Fire'},on_stagger='invalid'}))
assert(not Yellow.matches({element=99},'fire'))
-- Calls that never started must not rapidly consume the search pool or pretend
-- to cast. Back off globally, and defer the failed candidate a little longer.
config={spells={'Fire','Water'}};observation={yellow={}};allowed=true;now=0
local debugMessages={}
deps.debug=function(message) debugMessages[#debugMessages+1]=message end
deps.use=function(name) attempts[#attempts+1]=name;return false,{started=false,outcome='start_timeout'} end
local count=#attempts;step();assert(#attempts==count+1 and not config._yellow_rotation.used.Fire)
now=1;step();now=2;step();assert(#attempts==count+1)
now=3;step();assert(attempts[#attempts]=='Water' and #attempts==count+2)
assert(debugMessages[1]:find('start_timeout',1,true))
busy=true;now=10;count=#attempts;step();assert(#attempts==count)
busy=false;step();assert(attempts[#attempts]=='Fire' and #attempts==count+1)
-- Waiting must be visible without repeating the same notice every scheduler tick.
config={spells={'Fire'}};observation={yellow={}};now=20
local notices={}
deps.log=function(prefix,reason) notices[#notices+1]=prefix..tostring(reason or '') end
deps.waitReason=function() return 'insufficient MP for candidates' end
ready.Fire=false
step();step();assert(#notices==1 and notices[1]:find('insufficient MP',1,true))
busy=true;step();step();assert(#notices==1 and debugMessages[#debugMessages]:find('still active',1,true))
busy=false;ready.Fire=true
step();step();assert(#notices==2 and notices[2]:find('cast did not start',1,true))
print('PASS: yellow elements, readiness, retries and deduplicated waiting diagnostics')
