local selectors=require('./lib/target-selectors')
local f=assert(io.open('lib/action-context.lua'));local source=f:read('*a');f:close()
local argsSource=assert(source:match('(local function varargs.-return args%s*end)'))
local argsChunk=assert(loadstring(argsSource..'\nreturn varargs'))
setfenv(argsChunk,setmetatable({table=setmetatable({
 pack=function(...)return {...}end,unpack=unpack},{__index=table})},{__index=_G}))
local varargs=argsChunk()
local start=assert(source:find('    context.partyNames = function',1,true))
local finish=assert(source:find('    -- Count the number of party members',start,true))
local chunk=assert(loadstring('return function(context)\n'..source:sub(start,finish-1)..'\nend'))
setfenv(chunk,setmetatable({targetSelectors=selectors,varargs=varargs},{__index=_G}))
local context={member={name='Unchanged'}}
for i,entry in ipairs({{'Aegis','PLD'},{'Cleave','WAR'},{'Dice','COR'},{'Chorus','BRD'},{'Earth','GEO'},{'Light','WHM'}})do
    context['p'..(i-1)]={name=entry[1],main_job=entry[2],id=i}
end
context.me=context.p5
chunk()(context)
assert(table.concat(context.partyNames({'melee_dps','ranged'}),',')=='Cleave,Dice')
assert(context.partyNames({'PLD','RUN'})[1]=='Aegis')
assert(context.partyMatches({'mages'}))
assert(not context.partyMatches({'melee_dps','ranged'}))
assert(context.partyMatches({'melee_dps','ranged'},context.p1))
assert(not context.partyMatches({'^mages'}))
assert(context.selfMatches('mages'))
assert(context.selfMatches({'mages'}))
assert(context.selfMatches('melee','ranged','WHM'))
assert(not context.selfMatches('melee','ranged'))
assert(not context.selfMatches('mages','~WHM'))
assert(not context.selfMatches({'mages','~WHM'}))
assert(not context.selfMatches('^mages'))
assert(not context.selfMatches())
assert(not context.selfMatches(nil))
assert(not context.selfMatches({}))
local targets={'mages','~BLM'}
assert(context.selfMatches(targets) and #targets==2 and targets[1]=='mages')
assert(#context.partyNames({'*'})==6)
assert(context.member.name=='Unchanged')
local names=context.partyNames({'mages'});names[1]='Changed'
assert(context.partyNames({'mages'})[1]~='Changed')
print('PASS: pure context selector queries, renamed roster, deterministic coordination, exclusions and no enumeration mutation')
