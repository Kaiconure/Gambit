local Config=require('./lib/ux/status-config')
local factory=require('./lib/execution-factory')
local PanelContext=require('./lib/ux/panel-context')

local target={name='Target',valid_target=true,is_mob=true,is_engaged=true}
local env={format=string.format,bt=target,
    party_weapon_skill={name='Savage Blade',lifetime=4},skillchain={name='Light',lifetime=3},
    gambit={last_spell={name='Flash',age=1,status='completed',target=target},
        last_ability={name='Provoke',age=1,target=target}}}
PanelContext.attach(env)

local entries=Config.defaults.tracking.sets.default
for index=2,4 do
    local entry=entries[index]
    assert(type(entry.show_when)=='string' and type(entry.expression)=='table' and #entry.expression==1)
    local show=factory.get(entry.show_when)
    local display=factory.get(entry.expression[1])
    setfenv(show,env); setfenv(display,env)
    assert(show())
    local result=display()
    assert(type(result)=='string' and result:find('Target',1,true))
end

env.party_weapon_skill=nil
env.gambit.last_spell.age=5
env.gambit.last_ability.age=5
for index=2,4 do
    local show=factory.get(entries[index].show_when)
    setfenv(show,env)
    assert(not show())
end

assert(Config.defaults.tracking.sets.compact[1].expression~=nil)
print('PASS: stock transient rows separate visibility predicates from vertical display expressions')
