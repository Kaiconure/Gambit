local json=require('./lib/jsonlua')
local f=assert(io.open('actions/lib/buffs/keep-protectra-shellra.json'))
local doc=json.parse(f:read('*a'));f:close()
for index,buff in ipairs({'Protect','Shell'})do
 local selected,selfBuff,memberBuff
 local env={vars={keep_protectra_shellra={check_members={'PLD'},range=9}},type=type,
 arrayCount=function(t)return #t end}
 env.hasBuff=function(target,name)
  if name then assert(target==selected and name==buff);return memberBuff end
  assert(target==buff);return selfBuff
 end
 env.partyByName=function()env.member=selected;return selected end
 local condition=doc.actions[index+2].when[1]:gsub('\\$','')..doc.actions[index+2].when[2]
 local fn=assert(loadstring('return '..condition));setfenv(fn,env)
 selfBuff=true;memberBuff=false;selected={is_participant=true,center_distance=15,distance=8}
 assert(not fn(),'Out-of-range member must not trigger recasting')
 selected.center_distance=8;assert(fn())
 memberBuff=true;assert(not fn())
 memberBuff=false;selected.is_participant=false;assert(not fn())
 selected.is_participant=nil;selected.center_distance=nil;assert(not fn())
 selected=nil;assert(not fn())
 selfBuff=false;assert(fn(),'Self buff maintenance must remain independent of party range')
 local approached,casts,releases=0,0,0
 local reached=true
 env.me={is_party_leader=false};env.party_leader={is_participant=true,center_distance=15}
 env.vars.keep_protectra_shellra.align_leader=true
 env.hasBuff=function()return false end
 env.hasSpell=function()env.spell={name=buff..'ra'};return true end
 env.canUseSpell=function()return true end
 env.reserveMovement=function()return true end
 env.approachWithinRange=function(target,_,options)
  assert(target==env.party_leader and options.range==9 and options.duration==5)
  approached=approached+1;return reached
 end
 env.useSpell=function()casts=casts+1;return true end
 env.releaseMovement=function()releases=releases+1 end
 local leader=doc.actions[index]
 local check=assert(loadstring('return ('..table.concat(leader.when,') and (')..')'));setfenv(check,env)
 assert(check())
 env.vars.keep_protectra_shellra.align_leader=false;assert(not check())
 env.vars.keep_protectra_shellra.align_leader=true
 local move=assert(loadstring('return '..leader.commands[2]));setfenv(move,env)
 local release=assert(loadstring('return '..leader.commands[3]));setfenv(release,env)
 assert(move() and approached==1 and casts==1);release()
 reached=false;assert(not move() and casts==1);release()
 env.party_leader.center_distance=8
 assert(move() and approached==2 and casts==2);release()
 assert(releases==3)
 assert(#doc.actions[index+2].commands==2,'Ordinary buff actions must not move')
end
-- Single-target fallbacks remain last, after leader and nearby-area actions.
assert(#doc.actions==6)
for index,buff in ipairs({'Protect','Shell'})do
 local action=doc.actions[index+4]
 local selected={is_participant=true,center_distance=15}
 local buffed=false
 local env={vars={keep_protectra_shellra={check_members={'PLD'},range=9}},
 arrayCount=function(t)return #t end,
 hasBuff=function()return buffed end,
 canUseSpell=function(first,second,third,fourth,fifth)
  assert(first==buff..' V' and second==buff..' IV' and third==buff..' III' and fourth==buff..' II' and fifth==buff)
  return true
 end}
 env.partyByName=function()env.member=selected;return selected end
 local fn=assert(loadstring('return ('..table.concat(action.when,') and (')..')'));setfenv(fn,env)
 assert(fn())
 selected.center_distance=9;assert(not fn())
 selected.center_distance=15;buffed=true;assert(not fn())
 buffed=false;selected.is_participant=false;assert(not fn())
 selected.is_participant=true;env.vars.keep_protectra_shellra.check_members={};assert(not fn())
 env.useSpell=function(target)assert(target==selected);return true end
 local cast=assert(loadstring('return '..action.commands[1]));setfenv(cast,env);assert(cast())
end
print('PASS: Protectra/Shellra trigger only for missing self buffs or reachable living selected members')
print('PASS: lowest-priority single-target fallback, checked members, AoE boundary and descending spell tiers')
