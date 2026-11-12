local selectors=require('./lib/target-selectors')
local M={}
local jobs={Carbonite='PLD',Ladrian='WAR',Gavilar='COR',Aidelle='GEO',Steris='WHM',Miyajima='BRD'}
function M.attach(env)
 if env.encounters and env.encounters.state then
  local state=env.encounters.state
  env.encounters.state=function(...)
   local result=state(...);env.encounter_state=result;return result
  end
 end
 local function roster()
  local context={me=env.me}
  local i=0
  for _,name in ipairs({'Carbonite','Ladrian','Gavilar','Aidelle','Steris','Miyajima'})do
   local member={name=name,main_job=jobs[name],id=i+1}
   if env.me and env.me.name==name then context.me=member end
   context['p'..i]=member;i=i+1
  end
  return context
 end
 env.partyNames=function(targets)return selectors.orderedNames(roster(),targets)end
 env.partyMatches=function(targets,member)
  member=member or env.me
  for _,name in ipairs(env.partyNames(targets))do if name==member.name then return true end end
  return false
 end
 return env
end
return M
