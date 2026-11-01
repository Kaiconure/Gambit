local Aliases=require('./lib/resource-name-aliases')
local Matches=require('./lib/events/matches')
for _,pair in ipairs(require('./meta/resource-name-aliases')) do
    assert(Aliases.spell(pair[1])==pair[2] and Aliases.spell(pair[2]:lower())==pair[2])
    assert(Aliases.monster(pair[2])==pair[1] and Aliases.monster(pair[1]:upper())==pair[1])
    for _,kind in ipairs({'spell','enemy_spell','enemy_ability','pet_ability'}) do
        for _,name in ipairs(pair) do
            local event={kind=kind,id=123,name=name}
            Matches.attach(event)
            assert(event.matches(pair[1]) and event.matches(pair[2]:upper()))
            assert(event.matches('123') and not event.matches(124) and event.name==name)
        end
    end
    local set={pre={head={name='Item'}}}
    local original={[pair[2]]=set,['123']={post={}}}
    local expanded=Aliases.keys(original)
    assert(expanded[pair[1]]==set and expanded[pair[2]]==set)
    assert(original[pair[1]]==nil and expanded['123']==original['123'])
    local twice=Aliases.keys(expanded)
    assert(twice[pair[1]]==set and twice[pair[2]]==set)
    assert(not pcall(Aliases.keys,{[pair[1]]={pre={}},[pair[2]]={mid={}}}))
end
local exact={id=2,name='Nat. Meditation'}
assert(Aliases.spell(exact)==exact and Aliases.monster(exact)==exact)
assert(Aliases.spell({name="Nature's Meditation"})=='Nat. Meditation')
assert(Aliases.monster(2)==2)
assert(Aliases.keys({Ordinary=1}).ordinary==nil) -- Not general case folding.
local buff={kind='buff',name="Nature's Meditation"}; Matches.attach(buff)
assert(not buff.matches('Nat. Meditation'))
-- Real cached resource lookup entry points share the mapping, but not IDs.
local file=assert(io.open('lib/resx.lua')); local source=file:read('*a'); file:close()
source=source:gsub('("[^"\r\n]*"):format','(%1):format'):gsub("('[^'\r\n]*'):format",'(%1):format')
local scans=0
local env=setmetatable({globals={language='English'},resources={
    spells={{id=1,en='Nat. Meditation'}},
    monster_abilities={{id=1,en="Nature's Meditation"},{id=2,en="Nature's Meditation"}},
},tableFirst=function(entries,predicate)
    scans=scans+1
    for _,entry in ipairs(entries) do if predicate(entry) then return entry end end
end},{__index=_G})
local chunk=assert(loadstring(source)); setfenv(chunk,env); chunk()
assert(env.findSpell("Nature's Meditation")==env.resources.spells[1])
local before=scans
assert(env.findSpell('nat. meditation')==env.resources.spells[1] and scans==before)
assert(env.findMonsterAbility('Nat. Meditation','English')==env.resources.monster_abilities[1])
before=scans
assert(env.findMonsterAbility("nature's meditation",'English')==env.resources.monster_abilities[1] and scans==before)
assert(env.findMonsterAbility(2)==env.resources.monster_abilities[2])
print('PASS: two-way English aliases, matching, opt-in gear expansion, collisions, ID isolation and resource-cache reuse')
