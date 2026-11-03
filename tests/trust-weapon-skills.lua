local file=assert(io.open('lib/action-state-manager.lua')); local source=file:read('*a'); file:close()
local body=assert(source:match('(state_manager.setPartyWeaponSkill = function.-)\nend'))..'\nend'
local state={weaponSkills={},clearSkillchain=function(self,mob) self.cleared=mob.id end}
local environment=setmetatable({state_manager=state,SPAWN_TYPE_TRUST=14,MAX_WEAPON_SKILL_TIME=10,
    isMobPlayer=function(actor) return actor.spawn_type==1 end,
    arrayAppend=function(array,value) array[#array+1]=value end},{__index=_G})
local chunk=assert(loadstring(body));setfenv(chunk,environment);chunk()
local target={id=200}
local skill={name='Tachi: Kagero',skillchain_a='Liquefaction'}
local trust={id=100,name='Ayame',spawn_type=14}
state:setPartyWeaponSkill(trust,skill,target)
assert(state.weaponSkills[200].actor==trust and state.weaponSkills[200].name=='Tachi: Kagero')
assert(state.weaponSkills[200].skillchains[1]=='Liquefaction' and state.cleared==200)
file=assert(io.open('lib/action-context.lua'));source=file:read('*a');file:close()
body=assert(source:match('(context.partyUsingWeaponSkill = function.-)\n    %-%-%-%-'))
local context={bt=target,party_weapon_skill=state.weaponSkills[200]}
environment.context=context
environment.varargs=function(args) return args end
environment.arrayIndexOfStrI=function(array,value)
    for i,item in ipairs(array) do if item:lower()==value:lower() then return i end end
end
chunk=assert(loadstring(body));setfenv(chunk,environment);chunk()
assert(context.partyUsingWeaponSkill('Tachi: Kagero'))
assert(not context.partyUsingWeaponSkill('Tachi: Jinpu'))
context.bt={id=201}; assert(not context.partyUsingWeaponSkill())
state.weaponSkills={}
state:setPartyWeaponSkill({id=300,spawn_type=16},skill,target)
assert(not state.weaponSkills[200],'enemy skills must not become party openers')
print('PASS: Trust opener storage, skillchain attributes, named/target matching and enemy exclusion')
