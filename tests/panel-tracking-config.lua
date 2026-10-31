local Config=require('./lib/ux/status-config')
local stock=Config.defaults.tracking.sets
local input={tracking={current='custom',sets={
    default='obsolete',none={{name='Old',value='Ignore'}},
    custom={{name='My row',value='Keep'}}}}}
local runtime=Config.normalize(input)
assert(runtime.tracking.sets.default[1].name==stock.default[1].name)
assert(#runtime.tracking.sets.none==0)
assert(runtime.tracking.sets.custom[1].value=='Keep')
for name in pairs(stock) do
    assert(runtime.tracking.sets[name]~=stock[name])
end
local saved=Config.forSave(runtime)
for name in pairs(stock) do assert(saved.tracking.sets[name]==nil) end
assert(saved.tracking.current=='custom' and saved.tracking.sets.custom[1].value=='Keep')
saved.tracking.sets.custom[1].value='Changed'
assert(runtime.tracking.sets.custom[1].value=='Keep')
assert(input.tracking.sets.default=='obsolete')
local restored=Config.normalize(Config.forSave(runtime))
assert(restored.tracking.sets.default[1].name==stock.default[1].name)
assert(restored.tracking.current=='custom')
assert(Config.normalize({tracking={current='none'}}).tracking.sets.none)
local legacy=Config.normalize({tracking={{name='Old',value='Ignored'}}})
assert(legacy.tracking.current=='default')
assert(legacy.tracking.sets.default[1].name==stock.default[1].name)
print('PASS: stock tracking ownership, custom merge, persistence roundtrip and legacy fallback')
local composed=Config.normalize({tracking={current='combined',sets={
    combined={{references='compact'},{name='After',value='Checklist goes here'}},
    nested={{name='Before',value='First'},{references='combined'},{references='none'}}}}})
local expanded=Config.expandTracking(composed.tracking.sets.nested,composed.tracking.sets)
assert(#expanded==#stock.compact+2)
assert(expanded[1].name=='Before' and expanded[#expanded].name=='After')
assert(expanded[2].name==stock.compact[1].name)
assert(Config.forSave(composed).tracking.sets.combined[1].references=='compact')
expanded[2].name='Changed'
assert(composed.tracking.sets.compact[1].name==stock.compact[1].name)
for _,sets in ipairs({
    {bad={{references='missing'}}},
    {bad={{references='bad'}}},
    {bad={{references='other'}},other={{references='bad'}}},
    {bad={{references=false}}},
}) do
    assert(not pcall(Config.normalize,{tracking={current='bad',sets=sets}}))
end
print('PASS: ordered nested references, persistence, empty sets, independent rows and cycle validation')
