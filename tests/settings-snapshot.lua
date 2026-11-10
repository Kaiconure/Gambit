local snapshot=require('./lib/settings-snapshot')
local json=require('./lib/jsonlua')
local function equal(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not equal(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
local shared={when={'ready()'},commands={'cast()'},vars={enabled=false}}
local source={actions={battle={shared,shared}},vars={numbers={1,2,3},empty={},
 map={[0]='zero',[12]='twelve'},mixed={[2]='two',name='value'},text='quote " and slash \\',
 unsupported=function()end}}
local copied=snapshot(source)
assert(equal(copied,json.parse(json.stringify(source))))
assert(copied.actions.battle[1]~=copied.actions.battle[2])
copied.actions.battle[1].vars.enabled=true
copied.actions.battle[1].commands[1]='different()'
assert(not source.actions.battle[1].vars.enabled and not copied.actions.battle[2].vars.enabled)
assert(source.actions.battle[1].commands[1]=='cast()' and copied.actions.battle[2].commands[1]=='cast()')
local cycle={};cycle.self=cycle;assert(not pcall(snapshot,cycle))
assert(not pcall(snapshot,math.huge))
-- Compare representative real action data, including defaults and contributions.
for _,path in ipairs({'actions/lib/abilities/use-rolls.json',
 'actions/lib/frontline-engagement.json','actions/lib/buffs/keep-protectra-shellra.json',
 'settings/_namespaces/_base/actions/lib/common/common.json'})do
 local f=assert(io.open(path));local data=json.parse(f:read('*a'));f:close()
 assert(equal(snapshot(data),json.parse(json.stringify(data))),path)
end
print('PASS: JSON-equivalent settings snapshots, nested isolation, shared-action independence, numeric keys and real configuration data')
