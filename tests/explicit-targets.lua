local file=assert(io.open('lib/action-context.lua'))
local source=file:read('*all');file:close()
source=source:gsub("('[^'\r\n]*'):format", '(%1):format'):gsub('("[^"\r\n]*"):format', '(%1):format')
local context={me={symbol='me'},player={}}
local passed, sent, packetCategory
local current={id=123,valid_target=true}
local env=setmetatable({context=context,
 targetedAction={send=function(category,resource,id) packetCategory=category;sent=id;return true end},
 is_known_targeting_symbol=function(t) return t=='t' end,
 windower={ffxi={get_mob_by_id=function(id) assert(id==123);return current end,
 get_mob_by_target=function() return {id=999} end}},
 canUseSpell=function() return true end,canUseAbility=function() return true end,
 isMobPlayer=function() return false end, hasAnyFlagMatch=function() return false end,
 sendSpellCastingCommand=function(spell,target) passed=target;return true end,
 sendActionCommand=function(command) if type(command)=='function' then return command() end;sent=command;return true end,
 SPECIAL_NEXT_ATTACK_JOB_ABILITIES={},FAST_JOB_ABILITIES={},
 writeVerbose=function() end,text_ability=function(s) return s end,
 },{__index=_G})
for _, name in ipairs({'useAbility','useSpell'}) do
 local body=assert(source:match('(context%.'..name..' = function.-)\n    %-%-%-%-'))
 local chunk=assert(loadstring(body));setfenv(chunk,env);chunk()
end
local spell={id=23,name='Silence',prefix='/ma',targets={}}
local ability={name='Provoke',prefix='/ja',targets={}}
local mob={id=123,index=45}
assert(context.useSpell(mob,spell) and passed==123 and mob.symbol==nil)
assert(context.useAbility(mob,ability) and sent==123 and packetCategory==9 and mob.symbol==nil)
assert(context.useSpell({id=123,index=45,symbol='bt'},spell) and passed==123)
assert(context.useSpell('t',spell) and passed=='t')
assert(context.useAbility('t',ability) and sent=='input /ja "Provoke" <t>')
context.spell=spell;context.ability=ability
context.bt={symbol='bt'}
assert(context.useSpell() and passed=='bt')
assert(context.useSpell(nil,spell) and passed=='bt')
assert(context.useAbility() and sent=='input /ja "Provoke" <bt>')
assert(context.useAbility(nil,ability) and sent=='input /ja "Provoke" <bt>')
assert(not context.useSpell(spell) and not context.useAbility(ability))
current=nil
assert(not context.useSpell(mob,spell) and not context.useAbility(mob,ability))
current={id=123,valid_target=false}
assert(not context.useSpell(mob,spell) and not context.useAbility(mob,ability))
assert(not context.useSpell({id=123,index=45,symbol='bt',targets={}},spell))
assert(not context.useAbility({id=123,index=45,symbol='bt',targets={}},ability))
print('PASS: explicit mob IDs, symbols, no raw-mob mutation, invalid targets, no incompatible-target fallback')
