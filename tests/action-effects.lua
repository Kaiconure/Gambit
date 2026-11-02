local function read(path)
    local file=assert(io.open(path)); local source=file:read('*a'); file:close(); return source
end
local function normalized(source)
    return (source:gsub("('[^'\r\n]*'):format",'(%1):format'))
end
local source=read('Gambit.lua')
local body=assert(source:match('(handleActionEffects = function%(rawAction%).-)\nlocal _handle_actionMessageChunk'))
local player={id=100,name='Self',spawn_type=1,valid_target=true}
local enemy={id=400,name='Caster',spawn_type=16,valid_target=true}
local targets={[200]={id=200,name='First',spawn_type=16,valid_target=true},
    [300]={id=300,name='Second',spawn_type=16,valid_target=true}}
local mobs={[100]=player,[400]=enemy,[200]=targets[200],[300]=targets[300]}
local resources={spells={
    [10]={id=10,name='Fire',type='BlackMagic',status=0},
    [11]={id=11,name='Blue spell',type='BlueMagic',element=6,status=0},
    [12]={id=12,name='Dispelga',status=0}},
    job_abilities={[317]={id=317,name='Immanence'},[94]={id=94,name='Chain Affinity'},
        [209]={id=209,name='Wild Flourish',status=0},[320]={id=320,name='Konzen-ittai',status=0},
        [233]={id=233,name='Sublimation'}},
    items={[1]={id=1,name='Status item'}},
    monster_abilities={[906]={id=906,name='Slow move',status=13,duration=60}},
    weapon_skills={[42]={id=42,name='Weapon skill',skillchain_a='Fragmentation'}},
    buffs={[13]={id=13,name='Slow'},[14]={id=14,name='Status 14'}},
    action_messages={[1]={en='damage'},[2]={en='status'},[3]={en='resisted'}}}
local chain,openers,order,writes,removed,timed=nil,{}, {}, {}, {},nil
local affinity=470
local member={hasBuff=function(id) return id==affinity end}
local context={player=player,me=player,alliance_by_id={[100]=member}}
local state={getContext=function() return context end,
    clearMobBuff=function() end,
    setMobBuff=function(_,target,id,active) writes[#writes+1]={target.id,id,active} end,
    markTimedAbility=function(_,ability,target) timed=target end}
local function opener(actor,skill,target)
    if actor.id~=100 then return end -- Same player-only policy as the real state manager.
    chain=nil; openers[#openers+1]=skill.id; order[#order+1]='opener'
end
local ffxi={get_mob_by_id=function(id) return mobs[id] end,
    get_mob_by_target=function(name) return name=='me' and player or targets[200] end}
local function indexOf(values,item) for _,value in ipairs(values) do if value==item then return true end end end
local env=setmetatable({actionObservation=require('./lib/action-observation'),resources=resources,
    windower={ffxi=ffxi},actionStateManager=state,partyInfo={canShareClaim=function() return true end},
    meta={dispel={spells={12},job_abilities={}},erase={spells={},job_abilities={}},
        monster_abilities={},immanence={category_of=function() return 'Fire' end}},
    findSpell=function(name) if name=='Fire' then return resources.spells[10] end end,
    arrayIndexOf=indexOf,setPartyWeaponSkill=opener,
    reaction_statusRemoval=function(_,actor,target) removed[#removed+1]=target.id end,
    reaction_statusAddition=function(_,actor,target,reaction,param,buff)
        state:setMobBuff(target,buff,reaction~=1)
    end,
    SPAWN_TYPE_MOB=16,SPAWN_TYPE_TRUST=14,SPAWN_TYPE_PET=2,
    BUFF_SLEEP1=2,BUFF_TERROR=28,BUFF_PETRIFIED=7,
    Colors={verbose=1},CHAR_RIGHT_ARROW='->',
    text_player=tostring,text_mob=tostring,text_weapon_skill=tostring,text_red=tostring,
    text_buff=tostring,text_number=tostring,writeVerbose=function() end,writeMessage=function() end,
},{__index=_G})
local chunk=assert(loadstring(normalized(body))); setfenv(chunk,env); chunk()
local effects=env.handleActionEffects
local listener
env.globals={event_system={deps={afterAction=effects},
    selfResultAction=function() return false end,selfSpellAction=function() order[#order+1]='event'; return false end,
    enemyAction=function() return false end}}
env.T=function(values)
    values.contains=function(_,value) return indexOf(values,value) end; return values
end
env.S=env.T
env.settings={verbosity=0}; env.VERBOSITY_DEBUG=2
env.fieldsearch=function(message) return message=='status' and {status=true} or {} end
env.compress_number=tostring; env.text_green=tostring
env.text_spell=tostring; env.text_target=tostring
env.writeError=function(err) error(err) end
env.setSkillchain=function(name,target) chain=name; order[#order+1]='skillchain' end
local categories={[3]='weaponskill_finish',[4]='spell_finish',[11]='mob_tp_finish',[14]='job_ability_unblinkable'}
env.ActionPacket={open_listener=function(fn) listener=fn end,new=function(raw)
    return {raw=raw,get_category_string=function() return categories[raw.category] end,
        get_id=function() return raw.actor_id end,get_targets=function()
            return function()
                local first=raw.targets[1]
                local detail=first.actions[1]
                detail.get_add_effect=function()
                    if raw.chain then return {message_id=288,animation={ucfirst=function() return raw.chain end}} end
                end
                return {id=first.id,get_actions=function() return function() return detail end end}
            end
        end}
end}
chunk=assert(loadstring(normalized(read('lib/eventing.lua')))); setfenv(chunk,env); chunk()
local function action(category,id,actor,entries,newChain)
    return {category=category,param=id,actor_id=actor or 100,targets=entries or {
        {id=200,actions={{param=100,message=1,reaction=0}}}},chain=newChain}
end
local function reset() chain='Old'; openers={}; order={}; writes={}; removed={} end
for _,setup in ipairs({{4,10,470},{4,11,164},{14,209,0},{14,320,0}}) do
    reset(); affinity=setup[3]
    listener(action(setup[1],setup[2],100,nil,'Fusion'))
    assert(chain=='Fusion' and #openers==1)
    assert(table.concat(order,',')=='event,opener,skillchain')
    reset(); listener(action(setup[1],setup[2]))
    assert(chain==nil and #openers==1) -- No new chain: clearing the old one is still correct.
end
-- Slow lands on one target and is resisted on another; legacy reactions remain
-- authoritative and the generic status observer must not write either twice.
reset()
listener(action(11,906,400,{
    {id=200,actions={{param=13,message=2,reaction=0}}},
    {id=300,actions={{param=13,message=3,reaction=1}}}}))
assert(#writes==2 and writes[1][1]==200 and writes[1][3]==true and writes[2][1]==300 and writes[2][3]==false)
-- WS-only generic statuses use each target's result, not the first target's.
reset()
listener(action(3,42,100,{
    {id=200,actions={{param=13,message=2,reaction=0}}},
    {id=300,actions={{param=0,message=3,reaction=1}}}}))
assert(#writes==1 and writes[1][1]==200)
-- Multi-target removal processes every valid target.
reset()
effects(action(4,12,100,{
    {id=200,actions={{param=13,message=2,reaction=0}}},
    {id=300,actions={{param=14,message=2,reaction=0}}}}))
assert(#removed==2 and removed[1]==200 and removed[2]==300)
-- Item status inference must not leak the first target's buff ID to the next.
reset()
effects(action(5,1,100,{
    {id=200,actions={{param=13,message=2,reaction=8}}},
    {id=300,actions={{param=14,message=2,reaction=8}}}}))
assert(#writes==2 and writes[1][2]==13 and writes[2][2]==14)
effects(action(6,233)); assert(timed==player)
effects(action(4,999)); effects(action(4,10,999)) -- Missing resources/actors cannot abort the shared listener.
local reports={}
env.globals.event_system.deps.afterAction=function() error('effect failure') end
env.writeError=function(message) reports[#reports+1]=message end
reset(); listener(action(4,10,100,nil,'Fusion'))
assert(chain=='Fusion' and #reports==1 and reports[1]:find('effect failure',1,true))
assert(not read('Gambit.lua'):find('_handle_actionChunk',1,true))
print('PASS: shared effect decoding, opener-before-chain order, preserved replacement, per-target/deduplicated buffs, removals, Sublimation and missing metadata')
