local values=require('./lib/variable-values')
local selectors=require('./lib/target-selectors')
local participation=require('./lib/multi-stage-participants')
local function read(path)
    local file=assert(io.open(path)); local source=file:read('*a'); file:close()
    return source:gsub("('[^'\r\n]*'):format", '(%1):format')
end
local compileCount=0
local function indexOf(list,value,ignoreCase)
    for index,item in ipairs(list or {}) do
        if ignoreCase and type(item)=='string' and type(value)=='string' then
            if item:lower()==value:lower() then return index end
        elseif item==value then return index end
    end
end
local testMath=setmetatable({clamp=function(value,low,high) return math.max(low,math.min(high,value)) end},{__index=math})
local env=setmetatable({
    math=testMath,
    globals={player={name='Alpha'}},
    arrayIndexOf=indexOf,
    arrayIndexOfStrI=function(list,value) return indexOf(list,value,true) end,
    makePlayerName=function(name) return name and (name:sub(1,1):upper()..name:sub(2):lower()) end,
    windower={ffxi={get_abilities=function() return {weapon_skills={}} end,
        get_player=function() return {name='Alpha',main_job='WAR'} end}},
    skillchain_helper={
        filter_weapon_skills=function(list) return values.copy(list) end,
        find_skillchain_openings=function() return {all_openers={'upheaval'},groupings={
            {open_with={'upheaval'},close_with={'savage blade'}}}} end,
        get_skillchain_continuation=function() return {"ukko's fury",'chant du cygne'} end,
    },
    writeJsonToFile=function() compileCount=compileCount+1 end,
    writeVerbose=function() end, pluralize=function() return '' end,
    writeWarning=function(message) error(message) end,
    text_number=tostring,text_weapon_skill=tostring,text_green=tostring,text_gray=tostring,
    Colors={warning=1},CHAR_RIGHT_ARROW='->',
}, {__index=_G})
local compiler=assert(loadstring(read('lib/multi-stage-compiler.lua'))); setfenv(compiler,env); compiler()
local runtime=assert(read('lib/action-context.lua'):match('(context.isNextSkillchainer = function.-)context.hasWeaponSkill'))
local function context(selfName)
    local members={
        {name='Theta',main_job='WAR',id=3},
        {name='Beta',main_job='PLD',id=2},
        {name='Alpha',main_job='WAR',id=1},
    }
    local ctx={pinfo={}}
    for index,member in ipairs(members) do
        member.is_me=member.name==selfName
        member.valid_target=true; member.is_engaged=true; member.distance=3; member.tp=1000
        ctx['p'..(index-1)]=member; ctx.pinfo[member.name]=member
        if member.is_me then ctx.me=member end
    end
    ctx.partyUsingWeaponSkill=function() return ctx.trigger end
    ctx.partyUsingWeaponSkill2=ctx.partyUsingWeaponSkill
    ctx.partyUsingWeaponSkillMapped2=function(map) return ctx.trigger and map[ctx.trigger] end
    ctx.skillchaining=function() return ctx.chain end
    ctx.skillchaining2=function(names) return indexOf(names,ctx.chain) end
    ctx.canUseWeaponSkill=function(names)
        if not names or #names==0 then return false end
        ctx.weapon_skill={name=names[1]}; return true
    end
    local chunk=assert(loadstring('local context=...\n'..runtime..'\nreturn context'))
    local runtimeEnv=setmetatable({multiStageParticipants=participation},{__index=env})
    setfenv(chunk,runtimeEnv); chunk(ctx)
    return ctx
end
local definition={participants={'melee'},stage_participants={['1']={'WAR'},['2']={'PLD'},['3']={'WAR','PLD'}},
    stages={{use={'Upheaval'}},{on_ws={{party_using={'Upheaval'},use={'Savage Blade'}}}},
        {on_sc={'Light I'},use={"Ukko's Fury",'Chant du Cygne'}}}}
local alpha,beta=context('Alpha'),context('Beta')
local a,b=values.copy(definition),values.copy(definition)
assert(alpha.isNextMultiStager(a)==1)
assert(not beta.isNextMultiStager(b))
assert(table.concat(a.stages[1].participants,',')=='Alpha,Theta')
assert(table.concat(a.stages[1].participants,',')==table.concat(b.stages[1].participants,','))
assert(table.concat(a.stages[2].on_ws[1].participants,',')=='Beta')
alpha.trigger='upheaval'; beta.trigger='upheaval'
assert(not alpha.isNextMultiStager(a) and beta.isNextMultiStager(b)==2)
alpha.chain='Light I'; beta.chain='Light I'
assert(alpha.isNextMultiStager(a)==3 and not beta.isNextMultiStager(b))
local before=compileCount
alpha.pinfo.Alpha.tp=0
assert(not alpha.isNextMultiStager(a)) -- Theta now owns priority.
assert(compileCount==before) -- TP updates do not recompile/reorder.
alpha.pinfo.Theta.main_job='WHM'
alpha.isNextMultiStager(a)
assert(compileCount==before+1 and table.concat(a.stages[1].participants,',')=='Alpha')
alpha.pinfo.Theta.main_job='WAR'
alpha.isNextMultiStager(a)
assert(table.concat(a.stages[1].participants,',')=='Alpha,Theta') -- Original selectors retained.

local excluded=values.copy(definition)
excluded.exclusions={WAR={3},Theta={1}}
participation.prepare(excluded,context('Beta'),env.compile_multi_stage)
assert(table.concat(excluded.stages[1].participants,',')=='Alpha')
assert(table.concat(excluded.stages[3].participants,',')=='Beta')
local missing=values.copy(definition)
missing.stage_participants['2']={'SAM'}
local missingContext=context('Alpha')
assert(not missingContext.isNextMultiStager(missing)) -- No closer: do not open.
local fullyExcluded=values.copy(definition)
fullyExcluded.exclusions={PLD={2}}
assert(not context('Alpha').isNextMultiStager(fullyExcluded))

local generated={participants={'melee'},stage_participants={['1']={'WAR'},['2.1']={'PLD'},['3']={'WAR','PLD'}},
    stages={{open_for='Fusion'},{continue_from='Light I',continue_to='Light II'}}}
participation.prepare(generated,context('Alpha'),env.compile_multi_stage)
assert(generated.stages[2].generated)
assert(table.concat(generated.stages[2].on_ws[1].participants,',')=='Beta')
assert(table.concat(generated.stages[3].participants,',')=='Alpha,Theta,Beta')
local manual=values.copy(definition)
manual.stage_participants['2.1']={'Theta'}
participation.prepare(manual,context('Alpha'),env.compile_multi_stage)
assert(table.concat(manual.stages[2].on_ws[1].participants,',')=='Theta')
local rotated={participants={'melee'},participant_shuffle='rotate-left',
    stages={{use={'Upheaval'}},{on_ws={{party_using={'Upheaval'},use={'Savage Blade'}}}},
        {on_sc={'Light I'},use={'Chant du Cygne'}}}}
participation.prepare(rotated,context('Alpha'),env.compile_multi_stage)
assert(table.concat(rotated.stages[2].on_ws[1].participants,',')=='Beta,Theta,Alpha')
assert(table.concat(rotated.stages[3].participants,',')=='Alpha,Beta,Theta')
assert(table.concat(selectors.orderedNames(alpha,{'Theta','melee','~PLD'}),',')=='Theta,Alpha')
local named=values.copy(definition)
named.stage_participants['1']={'Theta','Alpha'}
participation.prepare(named,context('Alpha'),env.compile_multi_stage)
assert(table.concat(named.stages[1].participants,',')=='Theta,Alpha')
local inline=values.copy(definition)
inline.stage_participants['1']={'melee','~PLD','~Theta'}
participation.prepare(inline,context('Alpha'),env.compile_multi_stage)
assert(table.concat(inline.stages[1].participants,',')=='Alpha')
local overlap=values.copy(definition)
overlap.exclusions={WAR={1},Alpha={3}}
participation.prepare(overlap,context('Alpha'),env.compile_multi_stage)
assert(overlap.stages[1].participants[1]=='--no-matching-participant--')
assert(table.concat(overlap.stages[3].participants,',')=='Theta,Beta')
local shorthand=values.copy(definition)
shorthand.stages[2]={party_using={'Upheaval'},use={'Savage Blade'}}
participation.prepare(shorthand,context('Beta'),env.compile_multi_stage)
assert(#shorthand.stages[2].on_ws==1 and shorthand.stages[2].on_ws[1].party_using.upheaval)
local enumeration=context('Alpha')
enumeration.member={name='Do not change'}; enumeration.members={'unchanged'}
local savedMember,savedMembers=enumeration.member,enumeration.members
participation.prepare(values.copy(definition),enumeration,env.compile_multi_stage)
assert(enumeration.member==savedMember and enumeration.members==savedMembers)
local failure=values.copy(definition)
assert(not pcall(participation.prepare,failure,enumeration,function() error('compile failed') end))
assert(failure.participants[1]=='melee' and not failure._compiled)
participation.prepare(failure,enumeration,env.compile_multi_stage)
assert(failure._compiled)
print('PASS: real multi-stage compiler/runtime integration, deterministic selectors, readiness, exclusions, generated/manual stages, rotation and roster refresh')
local protectedContext=context('Alpha')
protectedContext.pinfo.Alpha.is_party_leader=true
local protected=values.copy(definition)
protected.stage_participants['3']={'!leader','COR','melee','~WAR'}
protected.exclusions={WAR={1,3}}
participation.prepare(protected,protectedContext,env.compile_multi_stage)
assert(table.concat(protected.stages[3].participants,',')=='Alpha,Beta')
assert(protected.stages[1].participants[1]=='--no-matching-participant--') -- Protection is list-local.
protectedContext.trigger='savage blade'; protectedContext.chain='Light I'
protectedContext.pinfo.Alpha.tp=0; protectedContext.pinfo.Beta.tp=0
assert(not protectedContext.isNextMultiStager(protected)) -- Protection never overrides TP.
protectedContext.pinfo.Alpha.is_party_leader=false
protectedContext.pinfo.Theta.is_party_leader=true
participation.prepare(protected,protectedContext,env.compile_multi_stage)
assert(table.concat(protected.stages[3].participants,',')=='Theta,Beta')

local duplicates=values.copy(definition)
duplicates.stage_participants['3']={'melee','!leader'}
duplicates.exclusions={WAR={3}}
participation.prepare(duplicates,protectedContext,env.compile_multi_stage)
assert(table.concat(duplicates.stages[3].participants,',')=='Beta,Theta') -- Original order, not forced-first.
local protectedGenerated={participants={'melee'},stage_participants={['1']={'WAR'},['2.1']={'!PLD'}},
    exclusions={PLD={2,2.1}},stages={{open_for='Fusion'}}}
participation.prepare(protectedGenerated,protectedContext,env.compile_multi_stage)
assert(table.concat(protectedGenerated.stages[2].on_ws[1].participants,',')=='Beta')
local localProtection=values.copy(definition)
localProtection.stages[2].on_ws[1].participants={'!PLD'}
localProtection.stages[2].exclusions={PLD={1}}
localProtection.exclusions={PLD={2,2.1}}
participation.prepare(localProtection,protectedContext,env.compile_multi_stage)
assert(table.concat(localProtection.stages[2].on_ws[1].participants,',')=='Beta')
local protectedRotation={participants={'melee','!leader'},participant_shuffle='rotate-left',exclusions={WAR={2}},
    stages={{use={'Upheaval'}},{on_ws={{party_using={'Upheaval'},use={'Savage Blade'}}}}}}
participation.prepare(protectedRotation,protectedContext,env.compile_multi_stage)
assert(table.concat(protectedRotation.stages[2].on_ws[1].participants,',')=='Beta,Theta')
for _, bad in ipairs({'!','!!leader','!~leader'}) do
    local invalid=values.copy(definition); invalid.participants={bad}
    assert(not pcall(participation.prepare,invalid,protectedContext,env.compile_multi_stage))
end
local badExclusion=values.copy(definition); badExclusion.exclusions={['!leader']={3}}
assert(not pcall(participation.prepare,badExclusion,protectedContext,env.compile_multi_stage))
print('PASS: protected selectors override inline/global/local exclusions, retain order through rotation, refresh leaders and preserve readiness')
