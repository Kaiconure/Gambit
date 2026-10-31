local PanelContext=require('./lib/ux/panel-context')
local Theme=require('./lib/ux/theme')
local context={}
local reset=PanelContext.attach(context)
assert(context.color_text('Ready',1,2,3)=='\\cs(1,2,3)Ready\\cr')
assert(context.color_latest('More')=='\\cs(1,2,3)More\\cr')
assert(context.color_mob(nil)=='\\cs(160,160,160)--\\cr')
assert(context.color_latest(' missing')=='\\cs(160,160,160) missing\\cr')
for flag,role in pairs({is_pet='target_idle',is_trust='target_npc',is_player='target_other_player',is_mob='target_idle',is_npc='target_npc'}) do
    local mob={valid_target=true,name='Target',[flag]=true}
    assert(context.color_mob(mob)==('\\cs(%d,%d,%d)Target\\cr'):format(unpack(Theme.colors[role])))
end
assert(context.color_mob({valid_target=true,name='Pet',is_pet=true,is_mob=true,is_npc=true})==
    ('\\cs(%d,%d,%d)Pet\\cr'):format(unpack(Theme.colors.target_idle)))
for _,membership in ipairs({'is_party_member','is_alliance_member'}) do
    assert(context.color_mob({valid_target=true,name='Player',is_player=true,[membership]=true})==
        ('\\cs(%d,%d,%d)Player\\cr'):format(unpack(Theme.colors.target_player)))
end
for _,kind in ipairs({'is_mob','is_pet'}) do
    assert(context.color_mob({valid_target=true,name='Enemy',[kind]=true,is_engaged=true,is_npc=true})==
        ('\\cs(%d,%d,%d)Enemy\\cr'):format(unpack(Theme.colors.target_engaged)))
    assert(context.color_latest(' extra')==('\\cs(%d,%d,%d) extra\\cr'):format(unpack(Theme.colors.target_engaged)))
end
assert(context.color_mob({valid_target=true,name='Other'})==
    ('\\cs(%d,%d,%d)Other\\cr'):format(unpack(Theme.colors.target_npc)))
assert(context.color_mob({valid_target=false,name='Gone'})=='\\cs(160,160,160)--\\cr')
for _,kind in ipairs({'is_player','is_mob','is_pet','is_trust','is_npc'}) do
    assert(context.color_mob({valid_target=true,name='Dead',is_dead=true,is_engaged=true,
        is_party_member=true,[kind]=true})=='\\cs(160,160,160)Dead\\cr')
    assert(context.color_latest(' extra')=='\\cs(160,160,160) extra\\cr')
end
reset()
assert(context.color_latest('Default')==('\\cs(%d,%d,%d)Default\\cr'):format(unpack(Theme.colors.body)))
local other={}; PanelContext.attach(other)
context.color_text('One',1,2,3)
assert(other.color_latest('Other')==('\\cs(%d,%d,%d)Other\\cr'):format(unpack(Theme.colors.body)))
assert(not pcall(context.color_text,'Bad',256,0,0))
assert(not pcall(context.color_text,'Bad',1,nil,3))
print('PASS: panel-only colors, target classification precedence and isolated latest color')
local Config=require('./lib/ux/status-config')
local factory=require('./lib/execution-factory')
for _,name in ipairs({'default','compact'}) do
    local env={format=string.format,gambit={entrypoint_relative='actions/pld.json',events_relative='events/common.json'},
        bt={name='Enemy',id=123,index=0xA,valid_target=true,is_mob=true,is_engaged=true}}
    local reset=PanelContext.attach(env)
    local function evaluate(index)
        reset()
        local fn=factory.get(Config.defaults.tracking.sets[name][1].expression[index])
        setfenv(fn,env)
        return fn()
    end
    assert(evaluate(1)=='Actions: \\cs(100,235,130)actions/pld.json (global namespace)\\cr')
    assert(evaluate(2)=='Events: \\cs(100,235,130)events/common.json (global namespace)\\cr')
    assert(#Config.defaults.tracking.sets[name][1].expression==3)
    assert(evaluate(3)=='Target: \\cs(160,160,160)--\\cr') -- Battle target is not the cursor.
    env.cursor=env.bt
    assert(evaluate(3):find('Target: ',1,true)==1)
    env.bt=nil
    assert(evaluate(3)=='Target: \\cs(255,130,130)Enemy\\cr (\\cs(241,241,183)123\\cr / \\cs(241,241,183)00A\\cr)')
    env.cursor=nil
    assert(evaluate(3)=='Target: \\cs(160,160,160)--\\cr')
end
print('PASS: default and compact stock helper expressions, target IDs and absent targets')
local claimed={}
local checks=0
PanelContext.attach(claimed,function(mob) checks=checks+1; return mob.claim_id==123 end)
local enemy={name='Claimed',valid_target=true,is_mob=true,is_engaged=true,mob={claim_id=456}}
assert(claimed.color_mob(enemy)==('\\cs(%d,%d,%d)Claimed\\cr'):format(unpack(Theme.colors.target_outside_claim)))
assert(claimed.color_latest(' details')==('\\cs(%d,%d,%d) details\\cr'):format(unpack(Theme.colors.target_outside_claim)))
enemy.mob.claim_id=123
assert(claimed.color_mob(enemy)==('\\cs(%d,%d,%d)Claimed\\cr'):format(unpack(Theme.colors.target_engaged)))
enemy.mob.claim_id=0
claimed.color_mob(enemy)
assert(checks==2) -- Unclaimed mobs do not require claim-sharing checks.
enemy.mob=nil; enemy.claim_id=456; enemy.is_mob=false; enemy.is_pet=true
assert(claimed.color_mob(enemy)==('\\cs(%d,%d,%d)Claimed\\cr'):format(unpack(Theme.colors.target_outside_claim)))
enemy.is_dead=true
assert(claimed.color_mob(enemy)=='\\cs(160,160,160)Claimed\\cr')
enemy.is_dead=false; enemy.is_engaged=false
assert(claimed.color_mob(enemy)==('\\cs(%d,%d,%d)Claimed\\cr'):format(unpack(Theme.colors.target_idle)))
print('PASS: outside/shared claims, raw and recorded targets, dead/idle precedence and latest color')
local target={name='Target',valid_target=true,is_mob=true,is_engaged=true}
local trackingEnv={format=string.format,bt=target,
    party_weapon_skill={name='Savage Blade',lifetime=4},skillchain={name='Light',lifetime=3},
    gambit={last_spell={name='Flash',age=1,status='completed',target=target},
        last_ability={name='Provoke',age=1,target=target}}}
local resetTracking=PanelContext.attach(trackingEnv)
for index=2,4 do
    resetTracking()
    local fn=factory.get(Config.defaults.tracking.sets.default[index].expression[1])
    setfenv(fn,trackingEnv)
    local result=fn()
    assert(result:find('\\cs(255,130,130)Target\\cr',1,true))
    if index==2 then assert(result:find('(~\\cs(241,241,183)3.0\\crs)',1,true)) end
    if index==3 then assert(result:find('(\\cs(100,235,130)completed\\cr)',1,true)) end
end
print('PASS: skillchain, spell and ability tracking color their targets')
local chains={'Liquefaction','Induration','Detonation','Scission','Impaction','Reverberation',
    'Transfixion','Compression','Fusion','Fragmentation','Distortion','Gravitation',
    'Light','Radiance','Darkness','Umbra'}
for _,name in ipairs(chains) do
    local result=context.color_skillchain(name)
    assert(result==context.color_skillchain({name=name}))
    assert(result:find(name..'\\cr',1,true))
    assert(context.color_latest(name)==result)
end
assert(context.color_skillchain(nil)=='\\cs(160,160,160)--\\cr')
assert(context.color_skillchain({})=='\\cs(160,160,160)--\\cr')
assert(context.color_skillchain('Unknown')==('\\cs(%d,%d,%d)Unknown\\cr'):format(unpack(Theme.colors.body)))
local fn=factory.get(Config.defaults.tracking.sets.default[2].expression[1])
setfenv(fn,trackingEnv)
assert(fn():find('\\cs(255,245,220)Light\\cr',1,true))
print('PASS: skillchain palette, object/name inputs, latest color and tracking integration')
assert(context.color_number('3.0')=='\\cs(241,241,183)3.0\\cr')
assert(context.color_number(42)=='\\cs(241,241,183)42\\cr')
for status,role in pairs({casting='status_pending',interrupted='status_interrupted',completed='status_completed'}) do
    local expected=('\\cs(%d,%d,%d)%s\\cr'):format(Theme.colors[role][1],Theme.colors[role][2],Theme.colors[role][3],status)
    assert(context.color_status(status)==expected)
    assert(context.color_latest(status)==expected)
end
assert(context.color_status('unknown')==('\\cs(%d,%d,%d)unknown\\cr'):format(unpack(Theme.colors.body)))
assert(context.color_status(nil)==('\\cs(%d,%d,%d)\\cr'):format(unpack(Theme.colors.body)))
print('PASS: number and spell status colors, latest color and unknown statuses')
for id,name in pairs({[0]='Fire','Ice','Wind','Earth','Lightning','Water','Light','Dark'}) do
    local result=context.color_element({name='Spell',element=id})
    assert(result==context.color_element({name='Spell',element=name}))
    assert(result:find('Spell\\cr',1,true))
    assert(context.color_latest('Spell')==result)
end
context.color_text('Existing',1,2,3)
for _,element in ipairs({-1,15,99,'Physical','None','Unknown',false}) do
    assert(context.color_element({name='Ability',element=element})=='Ability')
    assert(context.color_latest('Still')=='\\cs(1,2,3)Still\\cr')
end
assert(context.color_element({name='No element'})=='No element')
assert(context.color_element(nil)==nil and context.color_element({element=0})==nil)
assert(context.color_element('Passthrough')=='Passthrough')
print('PASS: element IDs/names, passthrough, missing names and latest color preservation')
trackingEnv.party_weapon_skill.skill={name='Savage Blade',element=0}
trackingEnv.gambit.last_spell.element=0
trackingEnv.gambit.last_ability.element=0
for index=2,4 do
    local expression=factory.get(Config.defaults.tracking.sets.default[index].expression[1])
    setfenv(expression,trackingEnv)
    assert(expression():find('\\cs(255,125,110)',1,true))
end
print('PASS: tracked weapon skill, spell and ability names use element colors')
