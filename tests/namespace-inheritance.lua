local paths = dofile('lib/settings-paths.lua')
Colors = {red=1}
text_namespace = function(value) return value end
local configs = {fight={inherits_from='base'},base={inheritable=true,inherits_from='root'},root={inheritable=true}}
local function resolve(name)
    return paths.resolveInheritance(name, function(n) return configs[n] end, function(n) return configs[n] ~= nil end)
end
local chain=resolve('fight')
assert(table.concat(chain,',')=='fight,base,root')
configs.base.inheritable=nil
configs.root.inheritable=nil
assert(table.concat(resolve('fight'),',')=='fight,base,root')
configs.root.inheritable=false
assert(not pcall(resolve,'fight')) -- Opt-out is enforced throughout the chain.
configs.root.inheritable=nil
configs.base.inheritable='true'
assert(not pcall(resolve,'fight')) -- Still require boolean values when specified.
configs.base.inheritable=nil
local unconfigured=paths.resolveInheritance('child',function(n)
    if n=='child' then return {inherits_from='unconfigured'} end
end,function(n) return n=='unconfigured' end)
assert(table.concat(unconfigured,',')=='child,unconfigured')
paths.setLoadedNamespace('fight',chain)
local candidates=paths.candidates('Player','actions/war.json')
assert(candidates[1]=='./settings/.ns/fight/players/Player/actions/war.json')
assert(candidates[3]=='./settings/.ns/base/players/Player/actions/war.json')
assert(candidates[7]=='./settings/Player/actions/war.json')
local common=paths.commonFiles('Player','WAR')
assert(common[10]=='./settings/.ns/root/actions/lib/common/common.json')
assert(common[#common]=='./settings/.ns/fight/players/Player/actions/lib/common.json')
assert(paths.writePath('Player','main.json')=='./settings/.ns/fight/players/Player/main.json')
configs.base.inheritable=false
local ok, message = pcall(resolve,'fight')
assert(not ok and message == 'Namespace base explicitly disables inheritance (inheritable: false)')
assert(resolve('base')[1]=='base') -- Opt-out does not prevent direct selection.
configs.base.inheritable=true
configs.root.inherits_from='fight'
configs.fight.inheritable=true
assert(not pcall(resolve,'fight'))
configs.root.inherits_from=nil
configs.fight.inherits_from={'base'}
assert(not pcall(resolve,'fight'))
configs.fight.inherits_from='missing'
assert(not pcall(resolve,'fight'))
configs.fight.inherits_from='../base'
assert(not pcall(resolve,'fight'))
assert(#resolve(nil)==0)
assert(resolve('standalone')[1]=='standalone')
print('PASS: recursive precedence, common ordering, writes, default inheritability, explicit opt-out, cycles and invalid inputs')

local imports=paths.importCandidates('Player','$(PlayerLib)/buff')
assert(imports[1]=='./settings/.ns/fight/players/Player/actions/lib/buff.json')
assert(imports[2]=='./settings/.ns/base/players/Player/actions/lib/buff.json')
assert(imports[#imports]=='./settings/Player/actions/lib/buff.json')
assert(paths.writePath('Player','.output/test.json')=='./settings/.ns/fight/players/Player/.output/test.json')
paths.setLoadedNamespace(nil)
assert(paths.writePath('Player','main.json')=='./settings/Player/main.json')
assert(paths.candidates('Player','main.json')[1]=='./settings/Player/main.json')
print('PASS: namespace player imports/output and unchanged global character layout')

for _, segment in ipairs({'actions', 'PLAYERS', 'Actions', 'CON', 'nul', 'Aux', 'PRN', 'COM1', 'com9', 'LPT1', 'lpt9'}) do
    for _, name in ipairs({segment, 'bcnm/' .. segment, 'bcnm/' .. segment .. '/fight'}) do
        local valid, message = paths.validateNamespace(name)
        assert(not valid and message:find(segment, 1, true), name)
    end
end
for _, name in ipairs({'common', 'lib', 'bcnm/single/perfidien', 'player-training', 'actions-test', 'com0', 'com10', 'lpt10'}) do
    assert(paths.validateNamespace(name), name)
end
assert(paths.validateNamespace(nil))
assert(paths.setNamespace('bcnm/single'))
assert(not paths.setNamespace('bcnm/PLAYERS/fight'))
assert(paths.getNamespace() == 'bcnm/single')
configs.fight.inherits_from = 'bcnm/Actions'
local success, message = pcall(function()
    return paths.resolveInheritance('fight', function(name)
        assert(name == 'fight', 'Reserved namespace should not be read')
        return configs[name]
    end, function()
        error('Reserved namespace should not be checked for existence')
    end)
end)
assert(not success and message:find('reserved for namespace contents', 1, true))
print('PASS: reserved segments, device names, valid alternatives and inherited-name validation')
