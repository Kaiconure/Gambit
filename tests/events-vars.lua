local Config=require('./lib/events/config')
local Paths=require('./lib/settings-paths')
local selectors=require('./lib/target-selectors')
Paths.setLoadedNamespace('child',{'child','parent'})
local paths=Paths.eventFiles('Tester','GEO',selectors.entryPointGroups('GEO',false))
local root='./settings/'
local child=root..'_ns/child/'
local docs={
    [root..'events/geo.json']={vars={gear={head='default',body='default'},list={'default'},
        ['!locked']='inline lock',ordinary='inline',nested={['!locked']=true}},
        spells={pre={{commands={'mark(vars.gear.head)'}}}}},
    [root..'events/common.vars.json']={vars={gear={head='shared',feet='shared'},ordinary='shared',base=true}},
    [root..'events/(mages).vars.json']={vars={gear={body='mage'}}},
    [root..'events/geo.vars.json']={vars={gear={head='geo'},['^ordinary']='shared default',list={'geo'}}},
    [root..'Tester/events/geo.vars.json']={vars={gear={head='character'}}},
    [root..'_ns/parent/events/geo.vars.json']={vars={gear={body='parent'},inherited=true}},
    [child..'events/common.vars.json']={vars={gear={head='namespace'},['!priority']='namespace priority'}},
    [child..'players/Tester/events/geo.vars.json']={vars={gear={head='specific'},priority='ordinary',
        locked='attempt',nested={locked=false},['^ordinary']='specific default'}},
}
local function load() return Config.load(paths,function(path) return docs[path] end) end
local config=load()
assert(config.path==root..'events/geo.json' and #config.files==1 and #config.vars_files==7)
assert(config.vars_files[1]==child..'players/Tester/events/geo.vars.json')
assert(config.vars.gear.head=='specific' and config.vars.gear.body=='parent')
assert(config.vars.gear.feet=='shared' and config.vars.base and config.vars.inherited)
assert(config.vars.ordinary=='shared') -- Ordinary value beats more-specific ^ defaults.
assert(config.vars.priority=='namespace priority' and config.vars.locked=='inline lock')
assert(config.vars.nested.locked==true and config.vars.list[1]=='geo' and #config.vars.list==1)
assert(config.vars['!locked']==nil and config.vars['^ordinary']==nil)
-- Inline defaults don't acquire prefixes or share references with runtime vars.
assert(docs[root..'events/geo.json'].vars.gear.head=='default')
config.vars.gear.head='changed'; assert(load().vars.gear.head=='specific')
-- Invalid variable documents must fail the entire new configuration.
local extra=child..'events/geo.vars.json'
for _,bad in ipairs({false,42,{vars={},spells={}}, {vars=42}, {vars={[1]='bad'}}, {imports={}}}) do
    docs[extra]=bad
    local ok,err=pcall(load)
    assert(not ok and tostring(err):find(extra,1,true))
end
docs[extra]=nil
-- An empty selected rule file still wins; all applicable variable files remain discoverable.
docs[child..'events/geo.json']={}
config=load()
assert(config.path==child..'events/geo.json' and #config.rules.spells.pre==0)
assert(config.vars.gear.head=='specific' and config.vars.locked=='attempt')
Paths.setLoadedNamespace(nil)
print('PASS: event vars namespace/character/job/group layering, implicit defaults, explicit priorities, isolation and validation')
