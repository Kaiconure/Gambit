local slots=require('./lib/action-slots')
local copy=require('./lib/variable-values').copy
local function expand(placeholder,contributions)
 local container={battle={copy(placeholder)}}
 local engine=slots.new(container,function(source)return ({entry=10,child=0,base=20})[source]end,
  function(message)error(message)end,nil,'entry')
 for _,definition in ipairs(contributions or {})do
  engine.collect({contributions=definition[2]},definition[1])
 end
 engine.expand({'battle'});return container.battle,container
end
local function action(name,priority)return {commands=name,priority=priority}end
local result=expand({slot='buffs',actions={action('inline')}},{{'child',{buffs={action('child')}}}})
assert(#result==2 and result[1].commands=='child' and result[2].commands=='inline')
result=expand({slot='!buffs',actions={action('inline')}},
 {{'child',{buffs={action('child')}}},{'base',{buffs={action('base')}}}})
assert(#result==2 and result[1].commands=='child' and result[2].commands=='inline')
result=expand({slot='buffs',actions={action('inline')}},{{'child',{['!buffs']={action('replacement')}}}})
assert(#result==1 and result[1].commands=='replacement')
result=expand({slot='^buffs',actions={action('default')}})
assert(#result==1 and result[1].commands=='default')
result=expand({slot='^buffs',actions={action('default')}},{{'child',{buffs={action('custom')}}}})
assert(#result==1 and result[1].commands=='custom')
result=expand({slot='buffs',actions={action('inline','high')}},{{'child',{buffs={action('child')}}}})
assert(result[1].commands=='inline' and result[1].priority==nil)
result=expand({slot='!buffs',actions={}},{{'base',{buffs={action('base')}}}})
assert(#result==0)
result=expand({slot='buffs',precondition={'ready()'},actions={action('inline')}})
assert(#require('./lib/action-preconditions').collect(result[1])==1)
assert(result[1].actions==nil and result[1].slot==nil)
for _,invalid in ipairs({{slots={'buffs'},actions={}}, {slot={'buffs'},actions={}},
 {slot='!^buffs',actions={}}, {slot='buffs',actions={{slot='nested'}}},
 {slot='buffs',actions={x=action('bad')}}})do assert(not pcall(expand,invalid))end

local Config=require('./lib/events/config')
local function config(slot,contributions)
 return Config.load({'entry'},function()
  return {spells={pre={slot}},contributions=contributions}
 end)
end
local c=config({slot='buffs',actions={{id='inline',commands='true'}}},
 {buffs={{id='external',commands='true'}}})
assert(#c.rules.spells.pre==2 and c.rules.spells.pre[1].id=='external' and c.rules.spells.pre[2].id=='inline')
c=config({slot='!buffs',actions={{id='inline',commands='true'}}})
assert(#c.rules.spells.pre==1 and c.available_slots.buffs)
c=config({slot='^buffs',actions={{id='default',commands='true'}}},
 {buffs={{id='custom',commands='true'}}})
assert(#c.rules.spells.pre==1 and c.rules.spells.pre[1].id=='custom')
assert(not pcall(config,{slot='buffs',actions={{slot='nested'}}}))
assert(not pcall(config,{slot='buffs',actions={{commands='broken('}}}))
print('PASS: inline action/event append, replacement, fallback, ordering, empty defaults, inheritance, slot discovery and validation')
