local anchor=require('./lib/frontline-anchor')
local config={anchor={capture='battle_start',return_distance=2,tolerance=0.5}}
local moves,faces,allowed=0,0,true
local ctx={vars={frontline_engagement=config},actionType='battle',battleScope=1,zone_id=100,me={x=10,y=20}}
ctx.setVar=function(path,value)
 if path=='frontline_engagement._anchor' then config._anchor=value
 elseif path=='frontline_engagement.anchor.position' then config.anchor.position=value
 elseif path=='frontline_engagement.arrived' then config.arrived=value
 elseif path=='frontline_engagement._anchor.cancelled' then config._anchor.cancelled=value
 else assert(path=='frontline_engagement._anchor.returning');config._anchor.returning=value end
end
ctx.distanceTo=function(x,y)return math.sqrt((ctx.me.x-x)^2+(ctx.me.y-y)^2)end
ctx.movementAvailable=function()return allowed end
ctx.faceEnemy=function()faces=faces+1 end
ctx.move=function(point)
 moves=moves+1
 assert(point.x==10 and point.y==20 and point.tolerance==0.5)
 ctx.me.x,ctx.me.y=point.x,point.y
 return true
end
anchor.capture(ctx);assert(config._anchor.x==10)
assert(config.anchor.position.x==10 and config.anchor.position.y==20 and config.anchor.position.zone==100)
assert(config.anchor.position~=config._anchor)
ctx.me.x=12;anchor.capture(ctx);assert(config._anchor.x==10 and not anchor.needsReturn(ctx))
ctx.me.x=13;assert(anchor.needsReturn(ctx))
allowed=false;assert(not anchor.run(ctx) and moves==0 and faces==0)
allowed=true;assert(anchor.run(ctx) and moves==1 and faces==1 and not anchor.needsReturn(ctx))
ctx.me.x=14;assert(anchor.run(ctx) and moves==2) -- Repeated displacement in the same battle.
ctx.move=function()moves=moves+1;ctx.me.x=11;allowed=false;return false,'reserved' end
ctx.me.x=14;assert(not anchor.run(ctx) and faces==2)
assert(anchor.needsReturn(ctx)) -- Interrupted inside trigger radius: finish returning after release.
assert(not anchor.run(ctx) and moves==3)
allowed=true;ctx.me.x=10;assert(not anchor.needsReturn(ctx))
ctx.me.x=11;assert(not anchor.needsReturn(ctx)) -- Arrival resets hysteresis.
ctx.battleScope=2;anchor.capture(ctx);assert(config._anchor.x==11)
ctx.zone_id=101;ctx.me.x=30;anchor.capture(ctx);assert(config._anchor.x==30)
ctx.actionType='idle';ctx.me.x=99;anchor.capture(ctx)
assert(config._anchor.x==30 and not anchor.needsReturn(ctx))
config.anchor=nil;ctx.actionType='battle'
assert(not anchor.enabled(config) and not anchor.needsReturn(ctx))
config.anchor={capture='battle_start'}
require('./lib/engagement-helpers').attach(ctx)
ctx.align=function()error('Anchored engagement must never align to the enemy')end
ctx.me.x=33
ctx.move=function(point)
 assert(point.x==30 and point.y==20)
 ctx.me.x=point.x;return true
end
assert(ctx.applyEngagement(config,'frontline'))
assert(not anchor.needsReturn(ctx))
-- Optional configurations change return thresholds/settings, not the captured point.
local override={anchor={capture='battle_start',return_distance=4,tolerance=0.75,duration=7}}
ctx.me.x=33
assert(ctx.frontlineAnchored() and ctx.frontlineAnchored(override))
assert(override.anchor.position.x==30 and override.anchor.position~=config.anchor.position)
assert(not ctx.frontlineAnchored({}))
assert(ctx.frontlineAnchorNeedsReturn() and not ctx.frontlineAnchorNeedsReturn(override))
local overrideMoves=0
ctx.move=function(point)
 overrideMoves=overrideMoves+1
 assert(point.x==30 and point.y==20 and point.tolerance==0.75 and point.duration==7)
 ctx.me.x=point.x;return true
end
assert(ctx.returnToFrontlineAnchor(override) and overrideMoves==0)
ctx.me.x=35;assert(ctx.returnToFrontlineAnchor(override) and overrideMoves==1)
ctx.me.x=35;assert(ctx.applyEngagement(override,'frontline') and overrideMoves==2)
ctx.me.x=35;assert(ctx.frontlineEngage(override) and overrideMoves==3)
assert(config._anchor.x==30 and config.anchor.return_distance==nil and override._anchor==nil)
-- Only the Shockmaw PLD override enables anchoring.
local f=assert(io.open('settings/_namespaces/_geas/shockmaw/actions/lib/common/pld.json'))
local pld=require('./lib/jsonlua').parse(f:read('*a'));f:close()
assert(anchor.enabled(pld.vars.frontline_engagement))
-- Actual stock action guards prevent every normal movement branch from running.
f=assert(io.open('actions/lib/frontline-engagement.json'))
local doc=require('./lib/jsonlua').parse(f:read('*a'));f:close()
local guarded=0
for _,action in ipairs(doc.actions)do
 if type(action.precondition)=='table' and action.precondition[2]=='not frontlineAnchored()' then guarded=guarded+1 end
end
assert(guarded==8)
-- Delayed mode uses ordinary engagement until the capture threshold.
config.anchor={capture='when_established'}
ctx.battleScope=3;ctx.state_time=0;ctx.me.x=40
anchor.capture(ctx);assert(not ctx.frontlineAnchored())
assert(config.anchor.position==nil)
ctx.bt={id=2,valid_target=true,hpp=100}
ctx.canAlign=function()return true end
local aligns=0
ctx.align=function()aligns=aligns+1;return true end
assert(ctx.applyEngagement(config,'frontline') and aligns==1)
ctx.state_time=9.99;ctx.me.x=45;anchor.capture(ctx)
assert(not ctx.frontlineAnchored() and config._anchor.x==30)
ctx.state_time=10;ctx.me.x=50;anchor.capture(ctx)
assert(ctx.frontlineAnchored() and config._anchor.x==50)
assert(ctx.applyEngagement(config,'frontline') and aligns==1)
ctx.state_time=20;ctx.me.x=60;anchor.capture(ctx)
assert(config._anchor.x==50 and ctx.frontlineAnchorNeedsReturn())
ctx.move=function(point)assert(point.x==50);ctx.me.x=50;return true end
assert(ctx.returnToFrontlineAnchor())
ctx.battleScope=4;ctx.state_time=0;anchor.capture(ctx)
assert(not ctx.frontlineAnchored() and not ctx.frontlineAnchorNeedsReturn())
config.anchor.capture_delay=3
ctx.state_time=2;anchor.capture(ctx);assert(not ctx.frontlineAnchored())
ctx.state_time=3;ctx.me.x=70;anchor.capture(ctx)
assert(ctx.frontlineAnchored() and config._anchor.x==70)
-- Reloaded runtime state can capture again after the delay has elapsed.
config._anchor=nil;ctx.state_time=15;ctx.me.x=80;anchor.capture(ctx)
assert(config._anchor.x==80)
ctx.battleScope=5;ctx.state_time=0;config.anchor.capture_delay=0
anchor.capture(ctx);assert(ctx.frontlineAnchored())
print('PASS: battle/zone capture, repeated anchor returns, reaction priority, interrupted return hysteresis and legacy movement guards')
print('PASS: delayed capture, default/custom/zero delay, ordinary engagement before capture, fixed position, next battle and reload')
-- Use the production condition evaluator (including AND and empty-array semantics).
f=assert(io.open('lib/action-context.lua'));local source=f:read('*a');f:close()
local evaluator=assert(source:match('(context%.evaluateAll = function.-)\n    %-%-+'))
local chunk=assert(loadstring(evaluator));setfenv(chunk,setmetatable({context=ctx},{__index=_G}));chunk()
ctx.execute=function(expression)
 local fn=assert(loadstring('return '..expression));setfenv(fn,ctx);return fn()
end
for _,mode in ipairs({'battle_start','when_established'})do
 ctx.battleScope=ctx.battleScope+1;ctx.state_time=20
 config.anchor={capture=mode,cancel_when={'lost_hate','too_far'}}
 ctx.lost_hate=false;ctx.too_far=false;anchor.capture(ctx)
 assert(ctx.frontlineAnchored())
 ctx.lost_hate=true;assert(ctx.frontlineAnchored())
 config.arrived=true;ctx.too_far=true
 assert(not ctx.frontlineAnchored() and config._anchor.cancelled and not config.arrived)
 assert(config.anchor.position.x==config._anchor.x) -- Released point remains inspectable this battle.
 assert(not ctx.frontlineAnchorNeedsReturn() and not ctx.returnToFrontlineAnchor())
 ctx.lost_hate=false;ctx.too_far=false;ctx.me.x=100;anchor.capture(ctx)
 assert(not ctx.frontlineAnchored()) -- Never recapture during the same battle.
 local before=aligns;assert(ctx.applyEngagement(config,'frontline') and aligns==before+1)
 ctx.battleScope=ctx.battleScope+1;anchor.capture(ctx)
 assert(ctx.frontlineAnchored() and not config._anchor.cancelled)
 config.anchor.cancel_when={};assert(ctx.frontlineAnchored())
 config.anchor.cancel_when=nil;assert(ctx.frontlineAnchored())
 config.anchor.cancel_when='lost_hate or too_far';ctx.too_far=true
 assert(not ctx.frontlineAnchored())
end
print('PASS: conditional anchor cancellation, AND/OR/empty conditions, normal engagement restoration and next-battle reset')
ctx.battleScope=ctx.battleScope+1;ctx.state_time=20
config.anchor.cancel_when='vars.frontline_engagement.anchor.position.x == me.x'
anchor.capture(ctx);assert(not ctx.frontlineAnchored()) -- Published before condition evaluation.
ctx.actionType='idle';anchor.capture(ctx);assert(config.anchor.position==nil)
anchor.needsReturn(ctx,override);assert(override.anchor.position==nil)
print('PASS: public position snapshots, explicit configuration publication, cancellation expressions and stale-position cleanup')
-- A shared pull/battle import must not suppress ordinary pull engagement.
for _,mode in ipairs({'battle_start','when_established'})do
 config.anchor={capture=mode}
 ctx.actionType='battle';ctx.battleScope=ctx.battleScope+1;ctx.state_time=20
 anchor.capture(ctx);local saved=config._anchor
 assert(ctx.frontlineAnchored())
 for _,phase in ipairs({'pull','idle','idle_battle','function'})do
  ctx.actionType=phase
  assert(not ctx.frontlineAnchored() and not ctx.frontlineAnchorNeedsReturn())
  assert(not ctx.returnToFrontlineAnchor())
  anchor.capture(ctx);assert(config._anchor==saved)
  local before=aligns
  assert(ctx.applyEngagement(config,'frontline') and aligns==before+1)
 end
 ctx.actionType='battle';anchor.capture(ctx)
 assert(ctx.frontlineAnchored() and config._anchor==saved)
end
print('PASS: both anchor modes leave pull/idle/manual engagement unchanged and activate only in battle')
