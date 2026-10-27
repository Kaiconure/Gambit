local json=dofile('lib/jsonlua.lua')
local file=assert(io.open('actions/lib/nukes/use-aspir.json'))
local config=json.parse(file:read('*a')); file:close()
local condition=config.actions[3].when[1]
local env={vars={use_aspir=config.vars['^use_aspir']}}
local check=assert(loadstring('return ' .. condition)); setfenv(check,env)
local function eligible(name)
    env.bt=name and {name=name} or nil
    return not not check()
end
assert(eligible('Air Elemental'))
assert(eligible('Biune Air Elemental'))
assert(eligible('Biune Water Elemental'))
assert(eligible('Biune Dark Elemental'))
assert(eligible('Apex Crab'))
assert(not eligible('Biune Umbril'))
assert(not eligible('Unknown Elemental'))
assert(not eligible(nil))
env.vars.use_aspir.targets['Biune Water Elemental']=false
assert(not eligible('Biune Water Elemental'))
env.vars.use_aspir.targets['Air Elemental']=false
assert(not eligible('Biune Air Elemental'))
env.vars.use_aspir.targets['Biune Air Elemental']=true
assert(eligible('Biune Air Elemental'))
print('PASS: Aspir base and prefixed elementals, Dark alias, explicit overrides and unrelated targets')
