local Result=require('./lib/weapon-skill-result')
local results=Result.targets({
 {id=1,actions={{message=185,param=300},{message=185,param=400}}},
 {id=2,actions={{message=187,param=1200}}},
 {id=3,actions={{message=188,param=0}}},
 {id=4,actions={{message=185,param=0}}},
 {id=5,actions={{message=999,param=9000}}},
 {id=6,actions={{message=185}}},
})
assert(results[1].amount==700 and results[2].amount==1200)
assert(results[3].amount==nil and results[4].amount==0 and results[5].amount==nil and results[6].amount==nil)
local event={};Result.apply(event,results,2);assert(event.amount==1200)
Result.apply(event,results,3);assert(event.amount==nil)
Result.apply(event,results,1);results[1].amount=99;assert(event.results[1].amount==700)
assert(Result.summary({results=results,target_id=2,outcome='completed'}).amount==1200)
local json=require('./lib/jsonlua')
local f=assert(io.open('settings/_namespaces/boss/_s.behemoth/events/(leader).vars.json'))
local document=json.parse(f:read('*a'));f:close()
local rule=document.contributions['party_weapon_skills.post.after'][1]
local sent
local ctx={vars=document.vars,me={is_party_leader=true},bt={id=1},
 event={completed=true,landed=true,has_skillchain_properties=true,damage=999,target={id=1}},
 sendCommand=function(command)sent=command end}
local function run()
 for _,code in ipairs(rule.when)do local fn=assert(loadstring('return '..code));setfenv(fn,ctx);if not fn()then return false end end
 for _,code in ipairs(rule.commands)do local fn=assert(loadstring('return '..code));setfenv(fn,ctx);fn()end
 return true
end
assert(run() and sent=='gbtfn positioning/frontal')
ctx.event.has_skillchain_properties=false;assert(not run()) -- Spirit Taker and other non-chainable WS.
ctx.event.has_skillchain_properties=true
ctx.event.damage=1000;assert(not run())
ctx.event.damage=0;assert(run())
ctx.event.damage=nil;ctx.event.amount=500;assert(not run()) -- Drains do not count as low damage.
ctx.event.damage=500;ctx.event.landed=false;assert(not run())
ctx.event.landed=true;ctx.event.target.id=2;assert(not run())
ctx.event.target.id=1;ctx.me.is_party_leader=false;assert(not run())
print('PASS: WS per-target sums, zero/unknown/miss handling, requested-target amount, snapshots and low-amount positioning guards')
