local json=require('./lib/jsonlua')
local f=assert(io.open('lib/action-context.lua'));local source=f:read('*a');f:close()
local body=assert(source:match('(context.abyssea = {}.-)    context.usableWeaponSkills ='))
local Weakness=require('./lib/abyssea-weakness');Weakness.clear()
local target={id=200,index=2,hpp=100,status=1,spawn_type=16}
local items={
    ['Bronze Zaghnal']={id=1,name='Bronze Zaghnal',bagId=8,localId=1,item={skill=7,jobs={[1]=true},level=1}},
    ['Polearm']={id=2,name='Polearm',bagId=8,localId=2,item={skill=8,jobs={[1]=true},level=1}},
    ['Ophidian Sword']={id=3,name='Ophidian Sword',bagId=8,localId=3,item={skill=4,jobs={[1]=true},level=1}},
}
local missing=false
local equipped=items.Polearm
local selected,logs=nil,{}
local context={bt=target,player={main_job_id=1,main_job_level=99},
    log=function(a,b) logs[#logs+1]=tostring(a)..' '..tostring(b) end,
    usableWeaponSkills=function(names) return names end,canUseWeaponSkill=function() return false end,
    equipMany=function(gear) selected=gear;return 1 end}
local resources={['Ground Strike']={skill=4},['Shadow of Death']={skill=7}}
local env=setmetatable({writeDebug=function() end,context=context,variableValues=require('./lib/variable-values'),
    findWeaponSkill=function(name) return resources[name] end,
    inventory={find_equipment_in_slot=function(slot) if slot=='main' then return equipped end end,
        find_item=function(reference) if not missing then return items[reference.name] end end},
    windower={ffxi={get_player=function() return context.player end,
        get_info=function() return {zone=218} end,get_mob_by_target=function() return nil end,get_mob_by_id=function() return target end}}},{__index=_G})
local chunk=assert(loadstring(body));setfenv(chunk,env);chunk()
local weapons={{main={name='Bronze Zaghnal'}},{main={name='Polearm'}},{main={name='Ophidian Sword'}}}
context.abyssea.runBlueProc({all_ws={'Ground Strike'},weapons=weapons})
assert(selected==weapons[3],'WAR on polearm must select configured great sword without TP')
Weakness.update(218,target,'darkness',false,nil,'red');selected=nil
context.abyssea.runRedProc({all_ws={'Shadow of Death'},weapons=weapons})
assert(selected==weapons[1],'WAR on polearm must select configured scythe for darkness')
missing=true;selected=nil
context.abyssea.runBlueProc({all_ws={'Ground Strike'},weapons=weapons})
assert(not selected and logs[#logs]:find('Ophidian Sword: item not found in equippable bags',1,true))
Weakness.clear();context.player={main_job_id=3,main_job_level=99,vitals={tp=0}}
equipped={id=4,name='Club',bagId=8,localId=4,item={skill=11}}
resources['Seraph Strike']={skill=11}
local plan={all_ws={'Seraph Strike'}}
context.abyssea.runRedProc(plan)
assert(logs[#logs]:find('need 1000 TP (Seraph Strike)',1,true),'WHM must explain why an available WS is not being used')
local count=#logs;context.abyssea.runRedProc(plan);assert(#logs==count,'waiting output must be deduplicated')
print('PASS: WAR polearm to matching blue great sword/red scythe and per-weapon missing-item diagnostics')
