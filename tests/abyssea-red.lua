local Red=require('./lib/abyssea-red')
local now=0
local weapons={dagger={id=1,skill=2},staff={id=2,skill=12},scythe={id=3,skill=7}}
local skills={Cyclone=2,['Energy Drain']=2,Sunburst=12,['Earth Crusher']=12,['Shadow of Death']=7}
local current=weapons.dagger
local used,equipped={},{}
local success,ready=true,true
local config={enabled=true,all_ws={'Cyclone','Energy Drain','Sunburst','Earth Crusher','Shadow of Death'},
    weapons={weapons.staff,weapons.scythe,weapons.dagger}}
local target={id=200,index=2,hpp=100}
local observation={red={}}
local deps={clock=function() return now end,log=function() end,
    resource=function(name) return skills[name] and {skill=skills[name]} end,
    current=function() return current end,resolve=function(gear) return gear end,
    usable=function(names) local result={}; for _,name in ipairs(names) do
        if skills[name]==current.skill then result[#result+1]=name end end; return result end,
    ready=function() return ready end,allowed=function() return true end,
    use=function(name) used[#used+1]=name; return success end,
    equip=function(gear) equipped[#equipped+1]=gear; return true end}
local function step() Red.step(config,target,observation,deps) end
step(); assert(used[1]=='Cyclone')
success=false; step()
assert(used[2]=='Energy Drain' and config._rotation.used['Energy Drain']
    and not config._rotation.landed['Energy Drain'],'miss advances rotation without claiming a hit')
success=true
observation.red.element='darkness'
step(); assert(equipped[1]==weapons.scythe,'hint must skip the unrelated staff set')
step(); assert(#equipped==1,'pending equipment must not be requested repeatedly')
current=weapons.scythe; now=3; step()
assert(used[#used]=='Energy Drain','wait for refresh after equipment confirmation')
now=5;step()
assert(used[#used]=='Shadow of Death')
observation.red.triggered=true
local count=#used; step(); assert(#used==count,'red success stops search')
local swapsAfterProc=#equipped
current={id=100,skill=7}; step(); now=now+10; step()
assert(#equipped==swapsAfterProc and #used==count,'damage weapon equipped after proc must be left alone')
current=weapons.scythe
config.on_stagger='full_rotation'; step()
assert(config._rotation.element==nil,'full rotation clears hint restriction after success')
-- Reused target IDs with a new index cannot inherit attempt tracking.
target.index=3; current=weapons.dagger; observation={red={element='wind'}}
step(); assert(used[#used]=='Cyclone')
assert(#Red.candidates(config,'unknown',deps.resource)==0)
ready=false; config._rotation=nil; local equipmentCount=#equipped; step()
assert(#equipped==equipmentCount,'wait for readiness rather than swapping away a useful weapon')
-- An external swap while a rotation swap is pending should supersede the wait.
ready=true; now=20; config._rotation=nil; current=weapons.dagger
observation={red={element='light'}}
step(); assert(config._rotation.pending.id==weapons.staff.id)
current={id=100,skill=12,key='damage-staff'}
now=20.1; local before=#used; step()
assert(not config._rotation.pending and #used==before,'external swap cancels old pending wait and settles')
now=22.2; step()
assert(used[#used]=='Sunburst','resume with the externally selected weapon after settling')
-- Used candidates are ordering history for one pass, never permanent exclusions.
config={enabled=true,all_ws={'Cyclone','Energy Drain'}}
current=weapons.dagger; observation={red={}}; success=false
local start=#used
step(); step(); step(); step(); step()
assert(used[start+1]=='Cyclone' and used[start+2]=='Energy Drain'
    and used[start+3]=='Cyclone' and used[start+4]=='Energy Drain',
    'missed/uncertain attempts must cycle through all candidates and repeat')
-- Caller-selected storage preserves a pass across newly constructed argument
-- objects, while separate plans keep independent progress.
local storage={}
local function supplied() return {enabled=true,all_ws={'Cyclone','Energy Drain'},state=storage} end
local start=#used
Red.step(supplied(),target,observation,deps)
Red.step(supplied(),target,observation,deps)
assert(used[start+1]=='Cyclone' and used[start+2]=='Energy Drain')
local independent=supplied(); independent.state={}
Red.step(independent,target,observation,deps)
assert(used[#used]=='Cyclone' and independent.state._rotation~=storage._rotation)
local attempts=#used
Red.step({enabled=false,state=storage},target,observation,deps)
assert(#used==attempts)
print('PASS: red rotation, hint filtering, weapon selection/confirmation, failed attempts, completion policies')
