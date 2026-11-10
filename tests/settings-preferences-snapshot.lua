local file=assert(io.open('lib/settings.lua'));local source=file:read('*a');file:close()
local definition=assert(source:match('(local function settingsSnapshot%(.-)\nlocal function sameSettings'))
local snapshot=assert(loadstring(definition..'\nreturn settingsSnapshot'))()
local ignored={};ignored.self=ignored -- Excluded trees must never be traversed.
local input={distance=6,nested={enabled=true,list={'a','b'}},actions=ignored,
    default_namespace='boss',ui=ignored}
local result=snapshot(input)
assert(result.distance==6 and result.nested.enabled)
assert(result.actions==nil and result.default_namespace==nil and result.ui==nil)
result.nested.list[1]='changed'
assert(input.nested.list[1]=='a' and input.actions==ignored and input.ui==ignored)
local json=require('./lib/jsonlua')
assert(json.stringify(snapshot({distance=6,nested={flag=false}}))==
    json.stringify(json.parse(json.stringify({distance=6,nested={flag=false}}))))
print('PASS: preferences snapshot excludes runtime trees before copying and isolates saved values')
