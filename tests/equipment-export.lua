local Export=require('./lib/equipment/export')
local json=require('./lib/jsonlua')
local slots={'main','sub','range','ammo','head','body','hands','legs','feet','neck','waist','left_ear','right_ear','left_ring','right_ring','back'}
local items={equipment={}}
for _,slot in ipairs(slots) do items.equipment[slot]=0 end
items.equipment.back=1
items.equipment.left_ring=2
local augmented={name="Nantosuelta's Cape",augments={'INT+30','Mag. Acc.+20','A "quoted" augment'}}
local inventory={find_equipment_in_slot=function(slot,snapshot,confirmed)
    assert(snapshot==items and confirmed)
    return slot=='back' and augmented or {name='Test Ring'}
end}
local output=Export.render(inventory,items)
local result=json.parse(output)
local gear=result.vars.gear['csv(battle, idle)']
assert(gear.back.name==augmented.name and gear.back.augments[3]==augmented.augments[3])
assert(gear.ring1.name=='Test Ring' and gear.main==nil)
assert(not gear.back.bagId and not gear.back.localId)
assert(output:find('"ring1": { "name": "Test Ring" }',1,true))
assert(output:find('"back": { "name": ',1,true))
assert(output:match('"back": [^\n]+"augments": %[ [^\n]+ %] }'))
assert(output:find('"ring1"',1,true)<output:find('"back"',1,true),'gear uses numeric slot order')
assert(output:find('\n  "vars": {',1,true) and output:sub(-1)=='\n')
for line in output:gmatch('[^\n]+') do
    local spaces=line:match('^( *)')
    assert(#spaces%2==0)
end
items.equipment.back=nil
assert(not pcall(Export.render,inventory,items))
assert(not pcall(Export.render,inventory,nil))
print('PASS: formatted gear export, canonical slots, augment preservation/escaping and incomplete inventory rejection')
