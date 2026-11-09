local Compiler=require('./lib/reaction-rules')
local function event(name,id,actor,kind,phase)
 return {name=name,id=id,actor={name=actor or 'Crab'},kind=kind or 'enemy_ability',
  phase=phase or 'pre',completed=true,matches=function()error('Compiled queries must not scan names')end}
end
local rules={
 {names={'Bubble Shower','bubble shower',12,'12','*'},options={wait=1}},
 {actor={'Other','Crab','Crab'},kind='enemy_ability',names=12},
 {actor='Other',names='Bubble Shower'},
 {actor={},names='*'},
 {key='bracket',start={abilities='Bubble Shower',spells='Fire',phase='pre'},
  release={abilities={'Bubble Shower'},phase='pre'}},
}
local query=Compiler.compile(rules)
local grouped=Compiler.compile({{rules[1],rules[2]},{{rules[3]},rules[4]},rules[5]})
local flatMatches=query(event('Bubble Shower',12))
local groupedMatches=grouped(event('Bubble Shower',12))
assert(#flatMatches==#groupedMatches)
for i,entry in ipairs(flatMatches)do
 assert(groupedMatches[i].order==entry.order and groupedMatches[i].operation==entry.operation
  and groupedMatches[i].options.key==entry.options.key)
end
assert(#Compiler.compile({{},{{}}})(event('Anything',1))==0)
local cycle={};cycle[1]=cycle;assert(not pcall(Compiler.compile,cycle))
assert(not pcall(Compiler.compile,{{[2]={names='Ability'}}}))
assert(not pcall(Compiler.compile,{{{names='Ability'},actor='No inheritance'}}))
local groupedOverride=Compiler.compile({{{key='stock-rule',disabled=true}}},
 {{{key='stock-rule',names='Bubble Shower'}}})
assert(#groupedOverride(event('Bubble Shower',12))==0)
local matches=query(event('BUBBLE SHOWER',12))
assert(#matches==3 and matches[1].order==1 and matches[2].order==2 and matches[3].order==5)
assert(matches[3].operation=='release' and matches[3].options.bracket)
assert(matches[3].options.key=='bracket')
matches[1].options.wait=42
assert(query(event('Bubble Shower',12))[1].options.wait==1)
assert(#query(event('Fire',10,'Crab','enemy_spell'))==2)
assert(#query(event('Unknown',99))==1) -- Wildcard rule only.
rules[1].options.wait=99
assert(query(event('Bubble Shower',12))[1].options.wait==1) -- Compiled snapshot.
local aliases=require('./meta/resource-name-aliases')
local aliasQuery=Compiler.compile({{names=aliases[1][1]}})
assert(#aliasQuery(event(aliases[1][2],1))==1)
local post=Compiler.compile({{start={spells='Fire'},release={abilities='End'}}})
assert(#post(event('Fire',10,'Crab','enemy_spell','post'))==1)
local interrupted=event('Fire',10,'Crab','enemy_spell','post');interrupted.completed=false
assert(#post(interrupted)==0)
assert(#post(event('Fire',10,'Crab','enemy_spell','pre'))==0)
assert(#query(event('Bubble Shower',12,'Other'))==4)
for _,invalid in ipairs({{{kind='invalid',names='Fire'}},{{start={},release={phase='mid'}}},{{names={true}}}})do
 assert(not pcall(Compiler.compile,invalid))
end
assert(not pcall(Compiler.compile,{{names='Ability',options={angle='rear'}}}))
assert(not pcall(Compiler.compile,{{names='Ability',options={distance=20,angle='invalid'}}}))
assert(Compiler.compile({{names='Ability',options={distance=20,angle='side'}}}))

-- A large unrelated list does not enter the query path or get copied into
-- either event-variable snapshot. Avoid timing thresholds dependent on the host.
local large={}
for i=1,10000 do large[i]={actor='Enemy '..i,names='Ability '..i} end
large[#large+1]={actor='Crab',names='Bubble Shower'}
local largeQuery=Compiler.compile(large)
assert(#largeQuery(event('Bubble Shower',12))==1)
local Runtime=require('./lib/events/runtime')
local config={vars={reactions={face_away=large}},rules={}}
local runtime=Runtime.new(config,{context=function()end,report=function(err)error(err)end})
local variables=runtime:eventVariables()
assert(variables.reactions.face_away==runtime.faceAwayRules)
assert(require('./lib/variable-values').copy(variables).reactions.face_away==runtime.faceAwayRules)
assert(type(config.vars.reactions.face_away)=='table')
-- Poison source iteration after compilation: no runtime query may touch it.
for i=1,#large do large[i]=false end
assert(#largeQuery(event('Bubble Shower',12))==1)
assert(runtime:eventVariables().reactions.face_away==runtime.faceAwayRules)
local oldCompile=Compiler.compile
Compiler.compile=function()error('Unexpected per-event compilation')end
assert(#runtime:eventVariables().reactions.face_away(event('Bubble Shower',12))==1)
Compiler.compile=oldCompile
print('PASS: keyed actor/kind/phase/name/ID/wildcard queries, aliases, ordering, dedup, release precedence, validation and immutable 10,001-rule runtime snapshots')
