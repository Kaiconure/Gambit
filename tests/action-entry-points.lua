local entry = dofile('lib/action-entry-points.lua')
local selectors = dofile('lib/target-selectors.lua')
local locations = {'child', 'base', 'standard'}
local function check(expected, ...)
    local present = {}
    for _, path in ipairs({...}) do present[path] = true end
    local actual = entry.find(locations, 'BLM', 'RDM', selectors.entryPointGroups('BLM'),
        function(path) return present[path] end)
    assert(actual == expected, tostring(actual) .. ' ~= ' .. tostring(expected))
end
check('child/(all).json', 'child/(all).json', 'base/blm.json')
check('child/(mages).json', 'child/(mages).json', 'base/blm.json')
check('child/(!mages).json', 'child/(!mages).json', 'base/blm.json')
check('child/blm.json', 'child/blm.json', 'child/(!mages).json', 'base/blm-rdm.json')
check('child/blm.json', 'child/blm.json', 'base/blm-rdm.json')
check('child/(!mages).json', 'child/(!mages).json', 'child/(!all).json')
check('child/(!all).json', 'child/(!all).json', 'base/blm.json')
check('child/(nukers).json', 'child/(nukers).json', 'child/(mages).json')
check('child/(all).json', 'child/(all).json', 'base/(mages).json')
check('child/(all).json', 'child/(all).json', 'standard/blm.json')
check('child/(all).json', 'child/(!healers).json', 'child/(all).json')
check(nil, 'child/all.json', 'child/(unknown).json')
check('child/(~melee).json', 'child/(~melee).json', 'base/(mages).json')
check('child/(~melee).json', 'child/(~melee).json', 'base/blm.json')
check('child/(~melee).json', 'child/(~melee).json', 'base/(all).json')
check('child/(~melee).json', 'child/(~melee).json', 'base/(~melee).json')
check('base/(mages).json', 'child/(!~melee).json', 'base/(mages).json')
check(nil, 'child/(~mages).json')
assert(table.concat(selectors.entryPointGroups('blm'), ',') ==
    table.concat(selectors.entryPointGroups('BLM'), ','))
print('PASS: entry point specificity, important overrides, role ordering and catch-all fallbacks')

local layers={{'C/players/Tester/actions','C/actions'},{'B/players/Tester/actions','B/actions'},
    {'A/players/Tester/actions','A/actions'},'settings/Tester/actions','settings/actions','actions/standard'}
local function layered(expected,...)
    local present={}; for _,path in ipairs({...}) do present[path]=true end
    local path=entry.find(layers,'BLM','RDM',selectors.entryPointGroups('BLM'),function(p) return present[p] end)
    assert(path==expected,tostring(path)..' ~= '..tostring(expected))
end
layered('C/actions/(all).json','C/actions/(all).json','B/actions/blm.json','actions/standard/blm.json')
layered('C/actions/blm.json','C/players/Tester/actions/(all).json','C/actions/blm.json')
layered('C/players/Tester/actions/blm.json','C/players/Tester/actions/blm.json','C/actions/blm.json')
layered('C/actions/blm-rdm.json','C/players/Tester/actions/blm.json','C/actions/blm-rdm.json')
layered('C/actions/(nukers).json','C/players/Tester/actions/(mages).json','C/actions/(nukers).json')
layered('B/actions/(all).json','B/actions/(all).json','A/actions/blm.json')
layered('A/actions/(all).json','A/actions/(all).json','settings/Tester/actions/blm.json')
layered('settings/Tester/actions/(all).json','settings/Tester/actions/(all).json','settings/actions/blm.json')
layered('settings/actions/(all).json','settings/actions/(all).json','actions/standard/blm.json')
layered('actions/standard/blm.json','actions/standard/blm.json')
print('PASS: namespace layers, character/shared selector specificity, inheritance and separate global/shipped fallbacks')
