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
local bundledPaths=Paths.eventFiles('Tester','GEO',{'mages'})
assert(bundledPaths[#bundledPaths-2]=='./events/geo.json')
assert(bundledPaths[#bundledPaths-1]=='./events/(mages).json')
assert(bundledPaths[#bundledPaths]=='./events/common.json')
local bundled={
    ['./events/geo.json']={vars={value='inline'},spells={pre={{commands={'true'}}}}},
    ['./events/common.vars.json']={vars={value='bundled',onlyBundled=true}},
    ['./settings/events/common.vars.json']={vars={value='user'}},
}
local function loadBundled() return Config.load(bundledPaths,function(path) return bundled[path] end) end
local shipped=loadBundled()
assert(shipped.path=='./events/geo.json' and shipped.vars.value=='user' and shipped.vars.onlyBundled)
bundled['./settings/events/common.json']={}
assert(loadBundled().path=='./settings/events/common.json') -- Even user common beats shipped exact job.
bundled['./settings/Tester/events/geo.json']={}
assert(loadBundled().path=='./settings/Tester/events/geo.json')
print('PASS: event vars namespace/character/job/group layering, implicit defaults, explicit priorities, isolation and validation')
