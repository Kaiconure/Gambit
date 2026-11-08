local json=require('./lib/jsonlua')
local factory=require('./lib/execution-factory')
local root='settings/_namespaces/ambuscade/dullahan/actions/lib/dullahan/'
local function read(name)
    local f=assert(io.open(root..name)); local d=json.parse(f:read('*a')); f:close(); return d
end
local vars=read('setup.json').vars
local allRules=read('positioning.json').actions
local approach=allRules[1]
local rules={allRules[2],allRules[3]}
local bossPhase='normal'
local ready=true
local env={vars=vars,me={name='Steris',x=137,y=-137},zone_search='LegionA',actionType='idle',
    bt={is_engaged=true},movementAvailable=function() return true end,hasBuff=function() return false end,
    evaluateAllConditions=function() return ready end,
    evaluateAll=function() return true end,
    any=function(name,list) for _,v in ipairs(list) do if v==name then return true end end end,
    encounters={state=function() return {phase=bossPhase} end}}
require('./tests/helpers/dullahan-party').attach(env)
env.findByName=function() env.find_result={}; return env.find_result end
env.distanceInRange=function(point,min,max)
    local d=((env.me.x-point.x)^2+(env.me.y-point.y)^2)^0.5
    return d>=min and d<=max
end
local function matches(rule)
    for _,expression in ipairs(rule.when) do
        local fn=factory.get(expression); setfenv(fn,env)
        if not fn() then return false end
    end
    return true
end
local p=vars.dullahan.positioning
assert(p.tank.x==132.99 and p.tank.y==-132.97 and p.mages.x==149.2 and p.mages.y==-139.63)
assert(matches(rules[2]))
env.zone_search='LegionB'; assert(matches(rules[2])); env.zone_search='LegionA'
for _,phase in ipairs({'miasma','boiling','charging','unknown'}) do
    bossPhase=phase; assert(not matches(rules[2]))
end
bossPhase='normal'; env.me.name='Aidelle'; assert(matches(rules[2]))
env.me.name='Miyajima'; env.zone_search='Elsewhere'; assert(not matches(rules[2]))
env.zone_search='LegionA'; ready=false; assert(not matches(rules[2]))
ready=true; env.me.x=p.mages.x; env.me.y=p.mages.y; assert(not matches(rules[2]))
env.me={name='Carbonite',x=150,y=-150}; env.actionType='pull'
assert(matches(rules[1]))
env.bt.is_engaged=false; assert(not matches(rules[1])) -- Do not fight the manual approach/pull.
env.bt.is_engaged=true; env.me.is_dead=true; assert(not matches(rules[1]))
env.me.is_dead=false; p.enabled=false; assert(not matches(rules[1]))
assert(p.move_duration==1 and p.tolerance==1)
print('PASS: measured anchors, mage roles, danger holds, zone/party guards, arrival tolerance and tank pull/death gates')

local correctlyAligned=true
env.aligned=function() return correctlyAligned end
local permitted=true
env.encounters.evaluate=function() return permitted end
p.enabled=true; env.me={name='Ladrian',x=149.2,y=-139.63}
env.bt={is_engaged=true,distance=18}
assert(matches(approach))
env.me.name='Gavilar'; assert(matches(approach))
permitted=false; assert(not matches(approach))
permitted=true; env.bt.distance=3; assert(not matches(approach))
correctlyAligned=false; assert(matches(approach))
permitted=false; assert(not matches(approach))
permitted=true; correctlyAligned=true
env.bt.distance=18; env.bt.is_engaged=false; assert(not matches(approach))
env.bt.is_engaged=true; env.me.name='Miyajima'; assert(not matches(approach))
print('PASS: both DDs approach, damage holds block movement, and support/pull/melee-range gates remain intact')
local combat=read('combat.json').actions
assert(combat[1].import=='dullahan/retreat')
table.remove(combat,1)
assert(combat[1].import=='dullahan/miasma-burst')
table.remove(combat,1)
-- Boiling bard actions take priority over routine actions.
table.remove(combat,1)
table.remove(combat,1) -- GEO Boiling Stone follows Dia.
local held=false
local facing=false
local trace={}
env.me={name='Carbonite',is_engaged=true}
env.bt={is_engaged=true,distance=6}
env.encounters.evaluate=function() return not held end
env.facingEnemy=function() return facing end
env.disengage=function() env.me.is_engaged=false; trace.disengaged=true end
env.faceEnemy=function() trace.forward=true; return true end
env.faceAway=function() trace.away=true; return true end
env.logf=function() return true end
env.settings={strategy='manual'}
local function commands(rule)
    for _,code in ipairs(rule.commands) do local fn=factory.get(code);setfenv(fn,env);fn() end
end
commands(combat[1])
assert(trace.disengaged and trace.forward and not trace.away)
assert(matches(combat[2])) -- Facing restoration does not require melee range or engagement.
env.me={name='Ladrian',is_engaged=true}; trace={}
held=true; commands(combat[1]); assert(trace.away and not trace.forward and not trace.disengaged and env.me.is_engaged)
assert(not matches(combat[2]))
held=false; env.me.is_engaged=true; assert(matches(combat[2]))
commands(combat[2]); assert(trace.forward)
facing=true; assert(not matches(combat[2]))
print('PASS: tank faces forward while disengaged; already-engaged DDs turn back only when damage is permitted')
local ws=combat[#combat]
held=false; env.me={name='Carbonite',main_job='PLD',is_engaged=true,tp=1500}
env.bt.distance=3
local selected
local function choose(pool) selected=pool; return true end
env.canUseWeaponSkill=choose
assert(matches(ws) and selected[1]=='Savage Blade' and selected[2]=='Chant du Cygne')
held=true; assert(not matches(ws))
print('PASS: DD holds retain engagement and tank WS use the sword pool only when policy allows')
-- Active DD movement does not depend on prebuff readiness or enemy status flags.
p.enabled=true; env.me={name='Ladrian',is_engaged=true};env.bt={distance=15,is_engaged=false}
env.actionType='battle';ready=false;held=false;correctlyAligned=false;facing=false
assert(matches(approach))
held=true;assert(not matches(approach))
held=false;env.me.is_engaged=false;env.actionType='pull';assert(not matches(approach))
print('PASS: engaged DD alignment survives lost prebuff readiness and missing enemy engagement while phase/pull holds remain enforced')
ready=true;bossPhase='normal';env.me={name='Miyajima',x=137,y=-137};env.bt={is_engaged=true}
env.actionType='idle';env.evaluateAll=function()return false end
assert(not matches(rules[2]))
env.evaluateAll=function()return true end;assert(matches(rules[2]))
print('PASS: mage camp movement waits until entry Protect/Shell coverage is complete')
