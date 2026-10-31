local Config=require('./lib/events/config')
local Paths=require('./lib/settings-paths')
local Runtime=require('./lib/events/runtime')
Paths.setLoadedNamespace('child',{'child','parent'})
local paths=Paths.eventFiles('Tester','GEO',{'mages'})
local root='./settings/_ns/child/players/Tester/events/geo.json'
local first='./settings/_ns/child/players/Tester/events/lib/spells.json'
local second='./settings/_ns/parent/events/lib/ws.json'
local shared='./events/lib/base.json'
local docs={
    [root]={imports={'lib/spells','lib/ws.json'},vars={choice='root'},
        spells={pre={{id='replace',commands={"mark('root')"}},{id='remove',disabled=true}}},
        loading={actions={{commands={"vars.ready=vars.ready..'R'"}}}}},
    [first]={imports={'lib/base'},vars={choice='first',first=true},
        spells={use_equipment_snapshot=true,pre={{id='replace',commands={"mark('first')"}},
            {id='remove',commands={"mark('removed')"}},{commands={"mark('first tail')"}}}},
        loading={actions={{commands={"vars.ready=vars.ready..'F'"}}}}},
    [second]={imports={'lib/base'},vars={choice='second',second=true},
        spells={pre={{commands={"mark('second')"}}}},loading={actions={{commands={"vars.ready=vars.ready..'S'"}}}}},
    [shared]={vars={ready='B',base=true},spells={pre={{commands={"mark('base')"}}}}},
    ['./settings/events/lib/spells.json']={spells={pre={{commands={"mark('wrong fallback')"}}}}},
    ['./settings/events/common.vars.json']={vars={choice='variable file'}},
    ['./events/lib/base.vars.json']={vars={must_not_load=true}},
}
local function load() return Config.load(paths,function(path) return docs[path] end) end
local c=load()
assert(c.path==root and #c.files==4 and c.files[1]==shared and c.files[4]==root)
assert(c.files[2]==first and c.files[3]==second)
assert(c.vars.choice=='variable file' and c.vars.first and c.vars.second and c.vars.base)
assert(not c.vars.must_not_load and #c.vars_files==1)
assert(c.rules.spells.use_equipment_snapshot==true) -- Omitted importing flag inherits.
assert(#c.rules.spells.pre==4 and c.rules.spells.pre[4].source:find(root,1,true))
local trace={}
local deps={clock=function() return 0 end,report=function(err) error(err) end,
    context=function(_,state) return {vars=state.vars,mark=function(v) trace[#trace+1]=v end} end}
local runtime=Runtime.new(c,deps)
runtime:loading(); runtime:loading()
assert(c.vars.ready=='BFSR')
-- Execute pre directly to inspect composition without equipment transport.
runtime:run({section='spells',event={},variables={vars={_={eq_stack={}}}}},'pre')
assert(table.concat(trace,',')=='base,first tail,second,root')
docs[root].spells.use_equipment_snapshot=false
assert(load().rules.spells.use_equipment_snapshot==false)
docs['./settings/events/common.vars.json']=nil
assert(load().vars.choice=='root')
docs[root].vars.choice=nil
assert(load().vars.choice=='second') -- Later sibling defaults precede earlier ones.
-- Closest existing import is validated; malformed files never fall through.
local saved=docs[first]
docs[first]=false; assert(not pcall(load)); docs[first]=saved
docs[root].imports={'lib/missing'}
local ok,err=pcall(load); assert(not ok and tostring(err):find(root,1,true) and tostring(err):find('missing',1,true))
docs[root].imports={'lib/spells'}; docs[shared].imports={'geo'}
ok,err=pcall(load); assert(not ok and tostring(err):find('cycle',1,true) and tostring(err):find(shared,1,true))
docs[shared].imports=nil
for _,bad in ipairs({false,'lib/base',{bad='lib/base'},{'../escape'},{'/absolute'},{'lib//base'},{'C:/outside'},{''}}) do
    docs[root].imports=bad
    assert(not pcall(load))
end
Paths.setLoadedNamespace(nil)
print('PASS: event hierarchy imports, recursive order/dedup, IDs, vars priorities, loading once, inherited policy and validation')
