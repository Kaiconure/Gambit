-- Run from the addon directory: lua tests/plouton-profiles.lua
local json = dofile('lib/jsonlua.lua')
local root = 'settings/.ns/vagary/plouton/'
local paths = dofile('lib/settings-paths.lua')
paths.setLoadedNamespace('vagary/plouton')
local function read(path)
    local f = assert(io.open(path)); local value = json.parse(f:read('*a')); f:close()
    return value
end
local roster = {Carbonite='pld', Steris='whm', Aidelle='geo', Miyajima='blm', Ladrian='cor', Gavilar='cor'}
local checked = {}
local function validate(path, playerName)
    local key = playerName .. ':' .. path
    if checked[key] then return end
    checked[key] = true
    local data = read(path)
    for _, section in ipairs({'actions','idle','battle','pull','idle_battle','loading','functions'}) do
        for _, action in ipairs(data[section] or {}) do
            local refs = action.imports or (action.import and {action.import}) or {}
            for _, ref in ipairs(refs) do
                if ref:sub(1,2) ~= '--' then
                    local p = paths.firstExisting(paths.importCandidates(playerName, ref), function(candidate)
                        local f = io.open(candidate)
                        if f then f:close(); return true end
                        return false
                    end)
                    assert(p, 'Missing import: ' .. ref)
                    validate(p:gsub('^%./', ''), playerName)
                end
            end
            if path:sub(1,#root) == root then
                for _, field in ipairs({'when','commands'}) do
                    local values = action[field] or {}
                    if type(values) == 'string' then values = {values} end
                    for _, code in ipairs(values) do assert(loadstring('return ' .. code)) end
                end
            end
        end
    end
    return data
end
for name, job in pairs(roster) do
    local p = validate(root .. name .. '/actions/' .. job .. '.json', name)
    assert(not p.vars.plouton.cast and not p.vars.plouton.probe)
    assert(type(read(root .. name .. '/main.json').strategy) == 'string')
    assert(type(p.vars.frontline_engagement.distance) == 'number' and p.vars.frontline_engagement.distance > 0)
    assert(p.vars.keep_protectra_shellra == nil)
    assert((p.vars.plouton.protect_targets ~= nil) == (job == 'whm'))
    if job == 'geo' then
        assert(table.concat(p.vars.refresh_cycle.targets, ',') == 'Aidelle,Carbonite')
    elseif job == 'blm' or job == 'whm' then
        assert(#p.vars.refresh_cycle.targets == 1 and p.vars.refresh_cycle.targets[1] == name)
    end
end
local profile = read(root .. 'Miyajima/actions/blm.json')
local commands = read(root .. 'actions/lib/plouton/blm.json').actions[2].commands
assert(read(root .. 'actions/lib/plouton/blm.json').actions[2].disabled)
assert(read(root .. 'actions/lib/plouton/geo.json').actions[2].disabled)
assert(read(root .. 'actions/lib/plouton/blm.json').actions[3].commands[1]=='probePlouton()')
local known, activeTarget, available = false, 123, true
local used = 0
local env = {vars=profile.vars, find_result={id=123,hpp=90,has_claim=true},
    ploutonState=function() return {weakness_known=known,target_id=activeTarget,weak_element='thunder'} end,
    findByName=function() return true end,
    canUseSpell=function(spell) assert(spell == 'Thunder IV'); return available end,
    useSpell=function() used=used+1 end}
env.setVar=function(key,value) assert(key=='plouton.cast');env.vars.plouton.cast=value end
local function attempt()
    env.vars.plouton.cast=true
    for _,code in ipairs(commands) do local fn=assert(loadstring('return '..code));setfenv(fn,env);fn() end
    assert(not env.vars.plouton.cast)
end
attempt(); assert(used==0) -- unknown
known=true;activeTarget=999;attempt();assert(used==0) -- other target
activeTarget=123;available=false;attempt();assert(used==0) -- unavailable
available=true;attempt();assert(used==1) -- confirmed one-shot
env.find_result.has_claim=false;attempt();assert(used==1) -- unclaimed
local positioning = read(root .. 'actions/lib/frontline-engagement.json').actions[1]
local moved = false
local posEnv = {vars={frontline_engagement={distance=16,angle=180}},
    bt={name='Plouton',hpp=80,has_claim=true}, actionType='idle_battle',
    hasEffect=function() return false end, canAlign=function() return true end,
    aligned=function() return false end,
    align=function(target, angle, distance, duration)
        assert(angle==180 and distance==16 and duration==3); moved=true;return true
    end}
local function positionMatches()
    for _,code in ipairs(positioning.when) do
        local fn=assert(loadstring('return '..code));setfenv(fn,posEnv)
        if not fn() then return false end
    end
    return true
end
assert(positionMatches())
local move=assert(loadstring('return '..positioning.commands[1]));setfenv(move,posEnv);move()
assert(moved)
posEnv.vars.frontline_engagement.disabled=true;assert(not positionMatches())
posEnv.vars.frontline_engagement.disabled=false;posEnv.bt.has_claim=false;assert(not positionMatches())
print('PASS: profiles/imports, positioning including idle_battle and disable/claim guards, WHM ownership, Refresh assignments, one-shot offense')
