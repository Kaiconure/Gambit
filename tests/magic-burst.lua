local burst=require('./lib/magic-burst')
local mapping=require('./lib/skillchain-elements')
local spells={Fire={id=1,element=0},Blizzard={id=2,element=1},Drain={id=3,element=7}}
local chains={[100]={name='Fusion',time=10},[200]={name='Distortion',time=10}}
local lookups=0
local deps={
    elements={[0]={en='Fire',name='localized fire'},[1]={en='Ice'},[7]={en='Dark'}},
    getSkillchain=function(target) lookups=lookups+1; return chains[target.id] end,
    findSpell=function(value)
        for name,spell in pairs(spells) do if value==name or value==spell.id then return spell end end
    end}
local context={bt={id=100},skillchain=chains[100]}
local function check(value,target) return burst.check(value,target,context,deps) end
assert(check('Fire') and check(1) and check(spells.Fire))
assert(lookups==0) -- The current context is authoritative for bt.
assert(not check('Blizzard'))
assert(check({kind='spell',id=2,target={id=200}}))
assert(not check({kind='spell',id=2,target={id=200}},{id=100}))
assert(check('Blizzard',200))
assert(not check({kind='job_ability',id=1,target={id=100}}))
assert(not check({kind='weapon_skill',id=1}))
assert(not check('unknown') and not check(nil) and not check({}))
assert(not check('Fire',false) and not check('Fire',{}) and not check('Fire',999))
assert(not check({id=1,target={id=999}})) -- No fallback to bt after explicit target failure.
context.skillchain=nil
assert(not check('Fire')) -- Never fall back to manager state for bt.
chains[200]=nil
assert(not check('Blizzard',200)) -- Other targets rely on manager expiry/filtering.
chains[200]={name='Distortion'}
assert(check('Blizzard',200)) -- No independent timestamp requirement.
context.skillchain={name='Compression'}; assert(check('Drain'))
context.skillchain={name='unknown'}; assert(not check('Drain'))
context.bt=nil; assert(not check('Fire'))
-- Every mapped chain accepts exactly its listed elements, including Radiance/Umbra.
local names={'Fire','Ice','Wind','Earth','Lightning','Water','Light','Dark'}
context.bt={id=100}
for chain,allowed in pairs(mapping) do
    context.skillchain={name=chain}
    for id,name in ipairs(names) do
        deps.elements[id+20]={en=name}
        spells.Probe={id=90,element=id+20}
        local expected=false
        for _,element in ipairs(allowed) do if element==name then expected=true end end
        assert(check('Probe')==expected,chain..' / '..name)
    end
end
-- Verify the actual context wrapper delegates target-aware queries.
local file=assert(io.open('lib/action-context.lua')); local source=file:read('*a'); file:close()
local body=assert(source:match('(    context.canMagicBurst = function.-)\n    context.spellHasSkill ='))
local ctx={bt={id=100},skillchain={name='Fusion'}}
local chunk=assert(loadstring(body))
setfenv(chunk,{context=ctx,magicBurst=burst,findSpell=deps.findSpell,resources={elements=deps.elements},
    actionStateManager={getSkillchain=function(_,target) return deps.getSkillchain(target) end}})
chunk()
chains[100]={name='Fusion',time=10}
assert(ctx.canMagicBurst('Fire'))
assert(ctx.canMagicBurst({kind='spell',id=2,target={id=200}}))
print('PASS: burst elements, spell/event/name/ID inputs, target precedence, authoritative context/manager state and context wrapper')
