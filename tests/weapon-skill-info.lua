local info=require('./lib/weapon-skill-info')
assert(info.encode({3,1,3})=='1,3')
assert(info.encode({})=='-')
assert(not info.encode({0}))
for _, encoded in ipairs({'', '1,', ',1', '1,,2', 'x', '65536'}) do
    assert(not info.apply('Steris', encoded), encoded)
end
assert(info.apply('sTERIS', '3,1'))
local revision=info.revision
assert(info.apply('Steris', '1,3') and info.revision==revision)
local helper={filter_weapon_skills=function(skills,ids)
    for _, skill in ipairs(skills) do
        for _, id in ipairs(ids) do if skill=='savage blade' and id==3 then return {'Savage Blade'} end end
    end
end}
local list=info.filter({'Unknown','Steris'}, {'Savage Blade'}, helper)
assert(#list==1 and list[1]=='Steris')
assert(info.filter({'Unknown'}, {'Savage Blade'}, helper)[1]=='--no-capable-participant--')
assert(info.apply('Steris','-') and info.revision==revision+1)
assert(info.filter({'Steris'}, {'Savage Blade'}, helper)[1]=='--no-capable-participant--')
print('PASS: capability validation, canonical snapshots, revisions, unknown and empty capability filtering')
