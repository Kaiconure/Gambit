local json=require('./lib/jsonlua')
local file=assert(io.open('events/lib/content/nyzul.json'))
local document=json.parse(file:read('*a')); file:close()
local textContribution,leaveContribution,loadingContribution,enterContribution
for _,contribution in ipairs(document.contributions) do
    if contribution.slot=='texts.received.after' then textContribution=contribution
    elseif contribution.slot=='zones.leave.after' then leaveContribution=contribution
    elseif contribution.slot=='loading.actions.after' then loadingContribution=contribution
    elseif contribution.slot=='zones.enter.after' then enterContribution=contribution end
end
assert(textContribution and leaveContribution and loadingContribution and enterContribution)
local rule=textContribution.actions[1]
assert(textContribution.when[1]=='zone_id == 77')
assert(loadingContribution.actions[1].commands[1]=="setPanelTrackingSupplement('nyzul', true)")
assert(enterContribution.actions[1].commands[1]=="setPanelTrackingSupplement('nyzul', true)")

local objective
local function receive(text)
    local env={zone_id=77,event={text=text},setSessionVar=function(name,value)
        if name=='nyzul.objective' then objective=value end
    end}
    local matched=true
    for _,source in ipairs(rule.when) do
        local expression=assert(loadstring('return '..source))
        setfenv(expression,env)
        if not expression() then matched=false; break end
    end
    if matched then
        for _,source in ipairs(rule.commands) do
            local command=assert(loadstring(source))
            setfenv(command,env)
            command()
        end
    end
    return matched
end

assert(not receive('Objective: Complete on-site objectives'))
assert(not receive('Objective: Vanquish Multiple Enemies I\nThis objective may be repeated.'))
assert(objective==nil)
assert(receive('Floor 1\nObjective: Eliminate specified enemies.'))
assert(objective=='Objective: Eliminate specified enemies.')
assert(receive('Objective: Activate all lamps.'))
assert(objective=='Objective: Activate all lamps.')

local restrictionRule
for _,candidate in ipairs(textContribution.actions) do
    if candidate.id=='nyzul-archaic-gear-restriction' then restrictionRule=candidate; break end
end
assert(restrictionRule)
local restriction
local restrictionEnv={event={text='Do not destroy archaic gears!'},
    setSessionVar=function(name,value) if name=='nyzul.restriction' then restriction=value end end}
for _,source in ipairs(restrictionRule.when) do
    local expression=assert(loadstring('return '..source)); setfenv(expression,restrictionEnv); assert(expression())
end
for _,source in ipairs(restrictionRule.commands) do
    local command=assert(loadstring(source)); setfenv(command,restrictionEnv); command()
end
assert(restriction=='Do not destroy archaic gears!')
restrictionEnv.event.text='Avoid discovery by archaic gears!'
for _,source in ipairs(restrictionRule.commands) do
    local command=assert(loadstring(source)); setfenv(command,restrictionEnv); command()
end
assert(restriction=='Avoid discovery by archaic gears!')

local textRules=textContribution.actions
local timeRule
for _,candidate in ipairs(textRules) do
    if candidate.id=='nyzul-time-remaining' then timeRule=candidate; break end
end
assert(timeRule)
local remaining
local sessionState={}
local env={zone_id=77,event={text='Notice\nTime Remaining: 1 minute (Earth time).',time=25},
    number=function(value,default) return tonumber(value) or tonumber(default) end,
    setSessionVar=function(name,value) sessionState[name]=value; if name=='nyzul.time_remaining_until' then remaining=value end end,
    setPanelWaypoint=function() end}
for _,source in ipairs(timeRule.when) do
    local expression=assert(loadstring('return '..source)); setfenv(expression,env); assert(expression())
end
for _,source in ipairs(timeRule.commands) do
    local command=assert(loadstring(source)); setfenv(command,env); command()
end
assert(remaining==85)
sessionState['nyzul.completed_floor_count']=4
env.event={text='You have 30 minutes (Earth time) to complete this mission.',time=200}
for _,source in ipairs(timeRule.commands) do
    local command=assert(loadstring(source)); setfenv(command,env); command()
end
assert(remaining==2000 and sessionState['nyzul.completed_floor_count']==nil)
env.event={text='Time remaining: 30 seconds (Earth time).',time=100}
for _,source in ipairs(timeRule.commands) do
    local command=assert(loadstring(source)); setfenv(command,env); command()
end
assert(remaining==130)
env.event={text='You have 30 minutes (Earth time) to complete this mission.',time=200}
for _,source in ipairs(timeRule.when) do
    local expression=assert(loadstring('return '..source)); setfenv(expression,env); assert(expression())
end
for _,source in ipairs(timeRule.commands) do
    local command=assert(loadstring(source)); setfenv(command,env); command()
end
assert(remaining==2000)

local leaveRule=leaveContribution.actions[1]
assert(leaveRule.id=='nyzul-zone-leave' and leaveRule.commands[1]=="resetSessionVar('nyzul')"
    and leaveRule.commands[2]=="setPanelTrackingSupplement('nyzul', false)"
    and leaveRule.commands[3]=="setPanelWaypoint(nil)")

local floorRule
for _,candidate in ipairs(textRules) do
    if candidate.id=='nyzul-floor' then floorRule=candidate; break end
end
assert(floorRule)
local floor
local nyzulState={}
local waypoints={}
local floorEnv={zone_id=77,event={text='The transfer completes. Welcome to Floor 4.',time=100},
    number=function(value,default) return tonumber(value) or tonumber(default) end,
    getSessionVar=function(name) return nyzulState[name] end,
    setSessionVar=function(name,value)
        nyzulState[name]=value
        if name=='nyzul.current_floor' then floor=value end
    end,
    findByName=function(name)
        assert(name=='Rune of Transfer')
        return {mob={name=name,x=123.5,y=-45.25}}
    end,
    setPanelWaypoint=function(value)
        waypoints[#waypoints+1]=value==nil and 'cleared' or value
    end}
for _,source in ipairs(floorRule.when) do
    local expression=assert(loadstring('return '..source)); setfenv(expression,floorEnv); assert(expression())
end
for _,source in ipairs(floorRule.commands) do
    local command=assert(loadstring(source)); setfenv(command,floorEnv); command()
end
assert(floor==4)
assert(nyzulState['nyzul.floor_started_at']==100)
assert(waypoints[1]=='cleared' and waypoints[2].name=='Rune of Transfer'
    and waypoints[2].mob_name==nil and waypoints[2].zone==77
    and waypoints[2].x==123.5 and waypoints[2].y==-45.25)

local actionsFile=assert(io.open('actions/lib/checklists/nyzul.json'))
local actions=json.parse(actionsFile:read('*a')); actionsFile:close()
local tracking=actions.vars.panel['!tracking']
assert(tracking[1].references=='compact' and tracking[2].references=='nyzul')
local PanelConfig=require('./lib/ux/status-config')
local timer=PanelConfig.defaults.tracking.sets.nyzul[2]
assert(timer.name=='Nyzul Status')
local objectivePanel=PanelConfig.defaults.tracking.sets.nyzul[1]
assert(objectivePanel.checklist[2].id=='restriction'
    and objectivePanel.checklist[2].icon=='general/indicators/warning.png'
    and objectivePanel.checklist[2].show_when=='session.nyzul.restriction')
local displayFloor=assert(loadstring('return '..timer.expression[1]))
local displayTime=assert(loadstring('return '..timer.expression[2]))
local panelEnv={session={nyzul={time_remaining_until=85,current_floor=28,completed_floors='26 27'}},time=25,max=math.max,
    format=string.format,color_number=function(value) return value end,color_muted=function(value) return value end}
setfenv(displayFloor,panelEnv); setfenv(displayTime,panelEnv)
--[=[
assert(displayFloor()=='Floor 4' and displayTime()==' • 1:00')

]=]
assert(displayFloor():find('Floor: ',1,true) and displayFloor():find('26 27 28',1,true)
    and displayTime():find('Remaining: ',1,true)
    and displayTime():find('1:00',1,true))

local completeRule
for _,candidate in ipairs(textRules) do
    if candidate.id=='nyzul-objective-completed' then completeRule=candidate; break end
end
assert(completeRule)
nyzulState['nyzul.current_floor']=4
nyzulState['nyzul.floor_started_at']=100
floorEnv.event={text='Rune of Transfer activated.',time=190}
floorEnv.max=math.max
for _,source in ipairs(completeRule.commands) do
    local command=assert(loadstring(source)); setfenv(command,floorEnv); command()
end
assert(nyzulState['nyzul.objective_completed']==true)
assert(nyzulState['nyzul.completed_floor_count']==nil and nyzulState['nyzul.completed_floor_time']==nil)
for _,source in ipairs(completeRule.commands) do
    local command=assert(loadstring(source)); setfenv(command,floorEnv); command()
end
assert(nyzulState['nyzul.completed_floor_count']==nil)
floorEnv.event={text='The transfer completes. Welcome to Floor 5.',time=195}
local nextFloor=assert(loadstring(floorRule.commands[1])); setfenv(nextFloor,floorEnv); nextFloor()
assert(nyzulState['nyzul.completed_floors']=='4' and nyzulState['nyzul.current_floor']==5)
assert(nyzulState['nyzul.completed_floor_count']==1 and nyzulState['nyzul.completed_floor_time']==95)
assert(nyzulState['nyzul.longest_floor_time']==95)

local pace=PanelConfig.defaults.tracking.sets.nyzul[3]
assert(pace.name=='Nyzul Pace')
local paceDisplay=assert(loadstring('return '..pace.expression[1]))
panelEnv.session.nyzul.completed_floor_count=2
panelEnv.session.nyzul.completed_floor_time=210
panelEnv.session.nyzul.longest_floor_time=120
panelEnv.session.nyzul.floor_started_at=10
setfenv(paceDisplay,panelEnv)
assert(paceDisplay():find('Avg 1:15',1,true) and paceDisplay():find('Longest 2:00',1,true)
    and paceDisplay():find('Current 0:15',1,true))
panelEnv.session.nyzul.completed_floor_count=nil
assert(paceDisplay()=='Current 0:15')

-- The ordinary stock event entry point attaches Nyzul observation globally.
local Config=require('./lib/events/config')
local function read(path)
    local source=io.open(path)
    if not source then return end
    local value=json.parse(source:read('*a')); source:close(); return value
end
local compiled=Config.load({
    './settings/namespaces/nyzul/events/(all).json',
    './events/(all).json',
},read)
local foundFloor=false
for _,rule in ipairs(compiled.rules.texts.received) do
    for _,candidate in ipairs(rule.rules or {rule}) do
        if candidate.id=='nyzul-floor' then foundFloor=true; break end
    end
    if foundFloor then break end
end
assert(foundFloor and compiled.path=='./events/(all).json')
print('PASS: Nyzul floor objectives, remaining-time capture, and exit cleanup')
