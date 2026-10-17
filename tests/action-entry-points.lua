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
check('base/blm.json', 'child/(all).json', 'base/blm.json')
check('base/blm.json', 'child/(mages).json', 'base/blm.json')
check('child/(!mages).json', 'child/(!mages).json', 'base/blm.json')
check('child/blm.json', 'child/blm.json', 'child/(!mages).json', 'base/blm-rdm.json')
check('base/blm-rdm.json', 'child/blm.json', 'base/blm-rdm.json')
check('child/(!mages).json', 'child/(!mages).json', 'child/(!all).json')
check('child/(!all).json', 'child/(!all).json', 'base/blm.json')
check('child/(mages).json', 'child/(nukers).json', 'child/(mages).json')
check('base/(mages).json', 'child/(all).json', 'base/(mages).json')
check('standard/blm.json', 'child/(all).json', 'standard/blm.json')
check('child/(all).json', 'child/(!healers).json', 'child/(all).json')
check(nil, 'child/all.json', 'child/(unknown).json')
assert(table.concat(selectors.entryPointGroups('blm'), ',') ==
    table.concat(selectors.entryPointGroups('BLM'), ','))
print('PASS: entry point specificity, important overrides, role ordering and catch-all fallbacks')
