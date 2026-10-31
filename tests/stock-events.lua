local Config=require('./lib/events/config')
local Paths=require('./lib/settings-paths')
local selectors=require('./lib/target-selectors')
local Runtime=require('./lib/events/runtime')
local json=require('./lib/jsonlua')
local function load(job)
    return Config.load(Paths.eventFiles('Test',job,selectors.entryPointGroups(job,false)),function(path)
        if not path:match('^%./events/') then return end
        local file=io.open(path); if not file then return end
        local source=file:read('*a'); file:close()
        local document=json.parse(source)
        local function validate(section)
            for _,phase in ipairs({'pre','mid','post','enter','leave','actions'}) do
                local seen={}
                for _,rule in ipairs(section[phase] or {}) do
                    assert(rule.id and not seen[rule.id],path..': duplicate/missing rule ID')
                    seen[rule.id]=true
                end
            end
        end
        for _,section in ipairs({'spells','job_abilities','weapon_skills','pet_abilities','zones','loading'}) do
            if document[section] then validate(document[section]) end
        end
        for _,section in pairs(document.statuses or {}) do validate(section) end
        return document
    end)
end
local function set(name) return {head={name=name}} end
local function run(config,section,phase,event,buffs,magicBurst)
    local worn={}
    local context=function(_,state)
        local ctx
        ctx={vars=state.vars,ipairs=ipairs,
        canMagicBurst=function() return magicBurst or false end,
        hasBuff=function(...)
            for _,name in ipairs({...}) do if buffs and buffs[name] then return true end end
            return false
        end,
        equipMany=function(gear)
            ctx.equipment_set=gear
            for slot,piece in pairs(gear) do if slot~='meta' then worn[slot]=piece.name end end
        end,
        equip=function(slot,name) worn[slot]=name end,
        }
        ctx.evaluateAllConditions=function(conditions)
            if conditions==nil then return true end
            for _,condition in ipairs(conditions) do
                if not require('./lib/execution-factory').execute(condition,ctx) then return false end
            end
            return true
        end
        return ctx
    end
    local runtime=Runtime.new(config,{context=context,clock=function() return 0 end,report=function(err) error(err) end})
    config.vars._={eq_stack={}}
    event.target=event.target or {}
    assert(runtime:run({section=section,event=event,variables={vars=config.vars}},phase))
    return worn
end
for _,job in ipairs({'WAR','MNK','WHM','BLM','RDM','THF','PLD','DRK','BST','BRD','RNG','SAM','NIN','DRG',
    'SMN','BLU','COR','PUP','DNC','SCH','GEO','RUN'}) do
    local config=load(job)
    assert(config.path)
    local count=0
    for _,rule in ipairs(config.rules.spells.pre) do if rule.id=='general-spell-pre' then count=count+1 end end
    assert(count==1 and config.rules.spells.pre[1].id=='general-spell-pre',job)
end
for _,case in ipairs({{'BRD','songs','singing'},{'NIN','ninjutsu','ninjutsu'},{'SMN','summoning','summoning'}}) do
    local job,key,flag=unpack(case)
    local config=load(job)
    config.vars.gear.spells.pre=set('fast cast')
    local gear=key=='summoning' and config.vars.gear.summoning.avatar or config.vars.gear[key]
    gear.pre=set('specialized')
    gear.Test={pre={neck={name='specific'}}}
    local result=run(config,'spells','pre',{name='Test',[flag]=true})
    assert(result.head=='specialized' and result.neck=='specific',job)
end
local geo=load('GEO')
local divine=load('WHM')
divine.vars.gear.spells.pre=set('fast cast')
divine.vars.gear.spells.divine.pre=set('divine pre')
divine.vars.gear.spells.divine.mid=set('divine mid')
divine.vars.gear.spells.divine.Holy={mid={neck={name='Holy override'}}}
assert(run(divine,'spells','pre',{name='Holy',divine=true}).head=='divine pre')
local holy=run(divine,'spells','mid',{name='Holy',divine=true})
assert(holy.head=='divine mid' and holy.neck=='Holy override')
assert(run(divine,'spells','mid',{name='Fire',elemental=true}).head==nil)
divine.vars.gear.spells.divine.mid=nil
assert(run(divine,'spells','mid',{name='Holy',divine=true}).neck=='Holy override')
divine.vars.gear.spells.divine.mid=set('divine mid')
for _,phase in ipairs({'pre','mid'}) do
    divine.vars.gear.spells.magic_burst[phase]=set('divine burst')
    divine.vars.gear.spells.magic_burst.Holy=divine.vars.gear.spells.magic_burst.Holy or {}
    divine.vars.gear.spells.magic_burst.Holy[phase]={neck={name='named divine burst'}}
    local result=run(divine,'spells',phase,{name='Holy',divine=true},nil,true)
    assert(result.head=='divine burst' and result.neck=='named divine burst')
    divine.vars.gear.spells.magic_burst[phase]=nil
    assert(run(divine,'spells',phase,{name='Holy',divine=true},nil,true).neck=='named divine burst')
end
assert(run(divine,'spells','mid',{name='Holy',divine=true}).head=='divine mid')
local blm=load('BLM')
assert(blm.vars.gear.spells.magic_burst and blm.vars.gear.spells.burst==nil)
blm.vars.gear.spells.magic_burst.mid=set('burst general')
blm.vars.gear.spells.magic_burst.Burst={mid={neck={name='burst override'}}}
blm.vars.gear.spells.Burst={mid={waist={name='spell override'}}}
local burstResult=run(blm,'spells','mid',{name='Burst',elemental=true},nil,true)
assert(burstResult.head=='burst general' and burstResult.neck=='burst override' and burstResult.waist=='spell override')
assert(run(blm,'spells','mid',{name='Burst',elemental=true}).head==nil)
assert(geo.path=='./events/geo.json')
geo.vars.gear.spells.pre=set('fast cast'); geo.vars.gear.spells.geomancy.pre=set('geomancy')
assert(run(geo,'spells','pre',{name='Geo-Fury',geomancy=true}).head=='geomancy')
assert(load('WAR').vars.gear.spells.geomancy==nil)
local blu=load('BLU')
assert(blu.path=='./events/blu.json' and load('WAR').vars.gear.spells.blue==nil)
blu.vars.gear.spells.pre=set('fast cast')
blu.vars.gear.spells.blue.pre=set('blue general')
blu.vars.gear.spells.blue['White Wind']={pre={neck={name='blue specific'}}}
local blueResult=run(blu,'spells','pre',{name='White Wind',blue=true})
assert(blueResult.head=='blue general' and blueResult.neck=='blue specific')
local bst=load('BST')
bst.vars.gear.beastmaster.ready.pre=set('ready delay')
bst.vars.gear.beastmaster.ready.mid=set('ready potency')
bst.vars.gear.beastmaster.ready['Razor Fang']={mid=set('specific potency')}
assert(run(bst,'pet_abilities','pre',{name='Razor Fang',type='Monster'}).head=='ready delay')
assert(run(bst,'pet_abilities','mid',{name='Razor Fang',type='Monster'}).head=='specific potency')
local pup=load('PUP')
local runefencer=load('RUN')
assert(runefencer.path=='./events/run.json')
for _,case in ipairs({{'runes','Rune','Ignis'},{'wards','Ward','Vallation'},{'effusions','Effusion','Rayke'}}) do
    local group,kind,name=unpack(case)
    runefencer.vars.gear.runefencer[group].pre=set('general '..group)
    runefencer.vars.gear.runefencer[group][name]={pre={neck={name='specific '..name}}}
    local result=run(runefencer,'job_abilities','pre',{name=name,type=kind})
    assert(result.head=='general '..group and result.neck=='specific '..name)
end
runefencer.vars.gear.job_abilities.Rayke={pre=set('final Rayke')}
assert(run(runefencer,'job_abilities','pre',{name='Rayke',type='Effusion'}).head=='final Rayke')
assert(run(runefencer,'job_abilities','pre',{name='Other',type='Other'}).head==nil)
runefencer.vars.gear.runefencer.wards.pre={head={name='stop ward'},meta={stop=true}}
assert(run(runefencer,'job_abilities','pre',{name='Vallation',type='Ward'}).neck==nil)
pup.vars.gear.puppetmaster.abilities.Repair.pre=set('repair')
assert(run(pup,'job_abilities','pre',{name='Repair'}).head=='repair')
assert(run(pup,'job_abilities','pre',{name='Other'}).head==nil)
local sch=load('SCH')
sch.vars.gear.spells.pre=set('fast cast')
sch.vars.gear.scholar.light_arts.pre=set('light arts')
sch.vars.gear.scholar.dark_arts.pre=set('dark arts')
sch.vars.gear.scholar.stratagems={{buff='Rapture',pre=set('rapture first')},
    {buff='Rapture',pre=set('rapture last')}}
assert(run(sch,'spells','pre',{name='Cure',curing=true},{['Addendum: White']=true}).head=='light arts')
assert(run(sch,'spells','pre',{name='Fire',elemental=true},{['Dark Arts']=true}).head=='dark arts')
assert(run(sch,'spells','pre',{name='Cure',curing=true},{['Light Arts']=true,Rapture=true}).head=='rapture last')
-- A stop on a general set prevents later named/category/final layers, even for no-op gear.
local stopped=load('SMN')
stopped.vars.gear.summoning.ward.mid={head={name='ward'},meta={stop=true}}
stopped.vars.gear.summoning.ward.Test={mid=set('named ward')}
stopped.vars.gear.pet_abilities.Test={mid=set('final override')}
assert(run(stopped,'pet_abilities','mid',{name='Test',type='BloodPactWard'}).head=='ward')
stopped.vars.gear.summoning.ward.mid.meta=nil
assert(run(stopped,'pet_abilities','mid',{name='Test',type='BloodPactWard'}).head=='final override')
-- Ordered buff overlays require explicit spell predicates, then named overrides win.
local overlay=load('WAR')
overlay.vars.gear.spells.buff_overlays={
    {buff='Chainspell',when={'mustNotEvaluate()'},mid=set('mid only')},
    {buff='Chainspell',pre=set('missing condition')},
}
assert(run(overlay,'spells','pre',{name='Fire',elemental=true},{Chainspell=true}).head==nil)
overlay.vars.gear.spells.elemental.mid=set('elemental')
overlay.vars.gear.spells.buff_overlays={
    {buff='Divine Seal',when={'event.curing'},mid=set('wrong spell')},
    {buff='Chainspell',when={'event.elemental'},mid=set('overlay first')},
    {buff='Chainspell',when={'event.elemental'},mid=set('overlay last')},
    {buff='Chainspell',mid=set('missing predicate')},
}
assert(run(overlay,'spells','mid',{name='Fire',elemental=true},{Chainspell=true,['Divine Seal']=true}).head=='overlay last')
overlay.vars.gear.spells.Fire={mid=set('named final')}
assert(run(overlay,'spells','mid',{name='Fire',elemental=true},{Chainspell=true}).head=='named final')
overlay.vars.gear.spells.buff_overlays[2].mid.meta={stop=true}
assert(run(overlay,'spells','mid',{name='Fire',elemental=true},{Chainspell=true}).head=='overlay first')
-- Every rule has a stable ID and no module contains accidental equal-ID collisions.
for _,job in ipairs({'WAR','BRD','NIN','SMN','BST','PUP','SCH','GEO','BLU'}) do
    local config=load(job)
    for _,section in pairs(config.rules) do
        for phase,rules in pairs(section) do
            if type(rules)=='table' then
                local seen={}
                for _,rule in ipairs(rules) do assert(rule.id and not seen[rule.id]); seen[rule.id]=true end
            end
        end
    end
end
print('PASS: all stock entry points, shared pre ordering/dedup, GEO extraction, BST Ready, PUP player abilities and ordered SCH overlays')
