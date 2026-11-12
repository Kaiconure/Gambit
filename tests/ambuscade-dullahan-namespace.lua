local json=require('./lib/jsonlua')
local factory=require('./lib/execution-factory')
local root='settings/_namespaces/ambuscade/dullahan/'
local function read(path)
    local f=assert(io.open(path)); local text=f:read('*a'); f:close()
    return json.parse(text)
end
local function compile(value,key)
    if type(value)=='table' then
        for k,v in pairs(value) do
            compile(v,(key=='commands' or key=='when' or key=='expression') and key or k)
        end
    elseif type(value)=='string' and (key=='commands' or key=='when' or key=='expression') then
        local fn,message=loadstring('return '..value)
        assert(fn,tostring(message)..'\n'..value)
    end
end
for _,path in ipairs({'.nsconfig','actions/(all).json','actions/lib/dullahan/setup.json',
    'actions/lib/dullahan/combat.json','actions/lib/dullahan/songs.json',
    'actions/lib/dullahan/positioning.json','actions/lib/dullahan/recovery.json',
    'actions/lib/dullahan/tank.json','actions/lib/dullahan/geo.json',
    'actions/lib/dullahan/buffs.json','actions/lib/dullahan/refresh.json',
    'actions/lib/dullahan/entry-buffs.json','actions/lib/dullahan/targeting.json',
    'actions/lib/dullahan/retreat.json','actions/lib/dullahan/miasma-burst.json',
    'actions/lib/dullahan/melee-buffs.json','events/common.vars.json'}) do
    compile(read(root..path))
end
assert(read(root..'.nsconfig').inherits_from==nil)
local config=read(root..'actions/lib/dullahan/setup.json').vars.dullahan
assert(config.miasma_order[1]=='melee_dps' and config.miasma_order[2]=='ranged')
for _,profile in ipairs(config.song_targets) do
    assert(#profile.songs==3)
    for _,song in ipairs(profile.songs) do assert(song~='Honor March') end
end
local Config=require('./lib/events/config')
local Paths=require('./lib/settings-paths')
-- Real stock event entry points plus the encounter's contributed dispatch guards.
Paths.setLoadedNamespace('ambuscade/dullahan')
local paths=Paths.eventFiles('Miyajima','BRD',{})
local loaded=Config.load(paths,function(path)
    local f=io.open(path); if not f then return end
    local text=f:read('*a'); f:close(); return json.parse(text)
end,function(message) error(message) end)
assert(loaded and #loaded.rules.weapon_skills.pre>0 and #loaded.rules.spells.pre>0)
print('PASS: independent namespace, all action expressions compile, three-song profiles and dispatch guards load with stock events')

local Tracker=require('./lib/encounter-state')
local M={text=Tracker.text,clear=Tracker.clear}
M.configure=function(config) Tracker.configure('dullahan',config.tracker,{miasma_order=config.miasma_order,miasma_spacing=config.miasma_spacing}) end
local boss={id=101,index=1,name='Bozzetto Retributionist'}
M.clear(); M.configure(config)
local guard=read(root..'events/common.vars.json').contributions
local actor='Ladrian'
local distance=20
local spikes=false
local function cancelled(section,name)
    local result=false
    local env={me={main_job=actor=='Aidelle' and 'GEO' or 'WAR'},event={target=boss,matches=function(value) return value==name end},
        encounters={state=Tracker.get,evaluate=function(tracker,condition,target) return Tracker.evaluate(tracker,condition,target,require('./tests/helpers/dullahan-party').attach({me={name=actor}})) end},
        hasBuff=function() return spikes end,mobById=function() return {distance=distance} end,
        cancelEvent=function() result=true end}
    require('./tests/helpers/dullahan-party').attach(env)
    for _,rule in ipairs(guard[section..'.pre.before']) do
        local matches=true
        for _,condition in ipairs(rule.when or {}) do
            local fn=factory.get(condition); setfenv(fn,env)
            if not fn() then matches=false; break end
        end
        if matches then for _,command in ipairs(rule.commands) do
            local fn=factory.get(command); setfenv(fn,env); fn()
        end end
    end
    return result
end
assert(not cancelled('weapon_skills','Upheaval'))
M.text('Bozzetto Retributionist begins charging up.',boss)
assert(cancelled('weapon_skills','Upheaval'))
M.text('Bozzetto Retributionist begins to emit a noxious miasma.',boss)
assert(not cancelled('weapon_skills','Upheaval'))
actor='Gavilar'; assert(cancelled('weapon_skills','Savage Blade'))
M.text("Bozzetto Retributionist's rage is beginning to boil over.",boss)
assert(cancelled('weapon_skills','Upheaval'))
assert(not cancelled('spells','Dia'))
distance=18.99; assert(not cancelled('spells','Dia')) -- Movement after action selection must not cancel TP feeding.
distance=10; assert(not cancelled('spells','Dia')) -- Event policy owns phase, not positioning.
assert(not cancelled('spells','Magic Finale') and not cancelled('spells','Flash'))
assert(cancelled('spells','Fire'))
assert(cancelled('spells','Stone'))
actor='Aidelle';assert(not cancelled('spells','Stone'));actor='Gavilar'
M.text('The boss begins charging up.',boss)
assert(cancelled('spells','Dia'))
actor='Aidelle';assert(cancelled('spells','Stone'));actor='Gavilar'
M.text('The boss begins to emit a noxious miasma.',boss)
assert(cancelled('spells','Dia'))
M.text("The boss's rage is beginning to boil over.",boss)
print('PASS: actual event guard expressions reject unsafe WS/spells and allow ranged Dia/Finale/Flash')

local rollIndex,positionIndex,wsIndex
for i,rule in ipairs(read(root..'actions/lib/dullahan/combat.json').actions) do
    if rule.import=='abilities/use-rolls' then rollIndex=i end
    if rule.import=='dullahan/positioning' then positionIndex=i end
    if rule.comment and rule.comment:find('No forced WS chains',1,true) then wsIndex=i end
end
assert(rollIndex and rollIndex>2 and rollIndex<positionIndex and rollIndex<wsIndex)
print('PASS: roll upkeep follows safety guards and precedes movement and weapon skills')

boss.name='Bozzetto Charger'
Tracker.enemy({actor=boss,kind='enemy_ability',phase='pre',resource={en='Grace of Hera'}})
assert(not cancelled('spells','Flash'))
assert(cancelled('spells','Dia') and cancelled('weapon_skills','Savage Blade'))
print('PASS: Charger hold permits non-damaging Flash recovery but rejects damage')
