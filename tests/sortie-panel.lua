local json=require('./lib/jsonlua')
local Config=require('./lib/ux/status-config')

local file=assert(io.open('events/lib/content/sortie.json'))
local document=json.parse(file:read('*a')); file:close()
local slots={}
for _,contribution in ipairs(document.contributions) do slots[contribution.slot]=contribution end
assert(slots['loading.actions.after'].when[1]=='zone_id == 275 or zone_id == 133 or zone_id == 189')
assert(slots['loading.actions.after'].actions[1].commands[1]=="setPanelTrackingSupplement('sortie', true)")
assert(slots['zones.enter.after'].when[1]=='event.matches(275) or event.matches(133) or event.matches(189)')
assert(slots['zones.leave.after'].when[1]=='event.matches(275) or event.matches(133) or event.matches(189)')
assert(slots['zones.leave.after'].actions[1].commands[1]=="setPanelTrackingSupplement('sortie', false)")

local sets=Config.defaults.tracking.sets
local branch=sets.sortie[1]
assert(branch.default_branch=='a' and branch.branches.a.short_name
    and branch.branches.d.short_name)
for _,name in ipairs({'a','b','c','d'}) do
    local selected=Config.expandTracking(sets.sortie,sets,nil,{sortie=name})
    assert(selected[1].id=='sortie' and selected[1]._branch_selector.selected==name)
    assert(selected[2].id=='sortie_'..name)
end

for _,name in ipairs({'a','b','c','d'}) do
    local path='actions/lib/checklists/sortie/'..name..'.json'
    local checklistFile=assert(io.open(path))
    local checklist=json.parse(checklistFile:read('*a')); checklistFile:close()
    assert(checklist.vars.panel.tracking[2].references=='sortie_'..name)
end

local allEvents=assert(io.open('events/(all).json'))
local allDocument=json.parse(allEvents:read('*a')); allEvents:close()
for _,import in ipairs(allDocument.imports) do assert(import~='lib/content/sortie') end

print('PASS: opt-in Sortie lifecycle, branch selection, and reusable stock checklists')
