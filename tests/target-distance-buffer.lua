local settingsFile=assert(io.open('lib/settings.lua'))
local settingsSource=settingsFile:read('*a');settingsFile:close()
assert(settingsSource:find('targetDistanceBuffer = 5',1,true),
    'target distance buffer must default to five yalms')
assert(settingsSource:find('math.max(tonumber(tempSettings.targetDistanceBuffer) or 5, 0)',1,true),
    'target distance buffer must be validated as nonnegative')

local targetFile=assert(io.open('lib/target-processing.lua'))
local targetSource=targetFile:read('*a');targetFile:close()
assert(targetSource:find('settings.maxDistance + settings.targetDistanceBuffer',1,true),
    'target retention must combine acquisition distance and buffer')
assert(targetSource:find('local maxDistanceSquared = settings.maxDistance * settings.maxDistance',1,true),
    'new target acquisition must continue using maxDistance alone')

local commandsFile=assert(io.open('lib/commands.lua'))
local commandsSource=commandsFile:read('*a');commandsFile:close()
assert(commandsSource:find("'-distancebuffer'",1,true) and commandsSource:find("'-db'",1,true),
    'config command must support long and short buffer options')
assert(commandsSource:find('Target retention distance: %s (%s + %s)',1,true),
    'config output must explain the effective retention calculation')
print('PASS: target acquisition distance and configurable retention buffer remain distinct')
