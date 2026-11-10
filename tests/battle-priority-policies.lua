local json=require('./lib/jsonlua')
local Loader=require('./lib/variable-loader')
local root='settings/_namespaces/'
local function read(path)
 local f=assert(io.open(path));local doc=json.parse(f:read('*a'));f:close();return doc
end
local base=read(root..'_base/actions/lib/common/common.json')
local rules=read(root..'_base/actions/lib/battle-priority.json')
assert(base.vars.battle_priority==nil)
local function config(...)
 local vars={};local loader=Loader.new()
 for _,path in ipairs({...})do loader.merge(vars,read(root..path..'/actions/lib/common/common.json').vars,path)end
 loader.merge(vars,base.vars,'base')
 loader.merge(vars,rules.vars,'rules')
 return vars.battle_priority
end
local defaults=config()
assert(next(defaults.antidote_mobs)==nil and next(defaults.suppress_ws_mobs)==nil
 and next(defaults.suppress_offensive_magic_mobs)==nil)
local ghatjot=config('sortie/_ghatjot')
assert(ghatjot.antidote_mobs.Ghatjot and not ghatjot.suppress_ws_mobs.Ghatjot)
local glazemane=config('_unm/glazemane')
assert(glazemane.suppress_ws_mobs.Glazemane and glazemane.suppress_offensive_magic_mobs.Glazemane)
local perfidien=config('_boss/_vagary/perfidien')
assert(perfidien.suppress_ws_mobs.Perfidien==false and perfidien.suppress_offensive_magic_mobs.Perfidien)
local plouton=config('_boss/_vagary/plouton','_boss/_vagary/perfidien')
assert(plouton.suppress_offensive_magic_mobs.Plouton and not plouton.suppress_ws_mobs.Plouton)
local ws=read(root..'_base/actions/lib/ws/all-out-melee.json')
assert(ws.vars.ws.all_out_melee.allow_suppression==nil and ws.vars.ws.all_out_melee.suppression_targets==nil)
for _,action in ipairs(ws.actions)do
 for _,command in ipairs(action.commands or {})do assert(not command:find('resumeWeaponSkills',1,true))end
end
print('PASS: empty shared policies, encounter-local antidote/suppression, Perfidien exception and removal of competing WS suppression')
