local json=require('./lib/jsonlua')
local file=assert(io.open('events/lib/content/nyzul.json'))
local document=json.parse(file:read('*a')); file:close()
local rule=document.contributions[1].actions[1]
assert(document.contributions[1].when[1]=='zone_id == 77')

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
for _,candidate in ipairs(document.contributions[1].actions) do
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

local textRules=document.contributions[1].actions
local timeRule
for _,candidate in ipairs(textRules) do
    if candidate.id=='nyzul-time-remaining' then timeRule=candidate; break end
end
assert(timeRule)
local remaining
local env={zone_id=77,event={text='Notice\nTime Remaining: 1 minute (Earth time).',time=25},
    number=function(value,default) return tonumber(value) or tonumber(default) end,
    setSessionVar=function(name,value) if name=='nyzul.time_remaining_until' then remaining=value end end}
for _,source in ipairs(timeRule.when) do
    local expression=assert(loadstring('return '..source)); setfenv(expression,env); assert(expression())
end
for _,source in ipairs(timeRule.commands) do
    local command=assert(loadstring(source)); setfenv(command,env); command()
end
assert(remaining==85)
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

local leaveRule=document.contributions[2].actions[1]
assert(leaveRule.id=='nyzul-zone-leave' and leaveRule.commands[1]=="resetSessionVar('nyzul')")

local floorRule
for _,candidate in ipairs(textRules) do
    if candidate.id=='nyzul-floor' then floorRule=candidate; break end
end
assert(floorRule)
local floor
local floorEnv={zone_id=77,event={text='The transfer completes. Welcome to Floor 4.'},
    number=function(value,default) return tonumber(value) or tonumber(default) end,
    setSessionVar=function(name,value) if name=='nyzul.current_floor' then floor=value end end}
for _,source in ipairs(floorRule.when) do
    local expression=assert(loadstring('return '..source)); setfenv(expression,floorEnv); assert(expression())
end
for _,source in ipairs(floorRule.commands) do
    local command=assert(loadstring(source)); setfenv(command,floorEnv); command()
end
assert(floor==4)

local actionsFile=assert(io.open('actions/lib/checklists/nyzul.json'))
local actions=json.parse(actionsFile:read('*a')); actionsFile:close()
local tracking=actions.vars.panel['!tracking']
assert(tracking[1].references=='compact')
local timer=tracking[3]
assert(timer.name=='Nyzul Status')
local displayFloor=assert(loadstring('return '..timer.format[2]))
local displayTime=assert(loadstring('return '..timer.format[3]))
local panelEnv={session={nyzul={time_remaining_until=85,current_floor=4}},time=25,max=math.max,
    format=string.format,color_number=function(value) return value end}
setfenv(displayFloor,panelEnv); setfenv(displayTime,panelEnv)
assert(displayFloor()=='Floor 4' and displayTime()==' • 1:00')

-- The ordinary stock event entry point attaches Nyzul observation globally.
local Config=require('./lib/events/config')
local function read(path)
    local source=io.open(path)
    if not source then return end
    local value=json.parse(source:read('*a')); source:close(); return value
end
local compiled=Config.load({
    './settings/_namespaces/_nyzul/events/(all).json',
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
