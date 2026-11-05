local PanelContext=require('./lib/ux/panel-context')
local Config=require('./lib/ux/status-config')
local factory=require('./lib/execution-factory')
local env={format=string.format}
PanelContext.attach(env)
assert(env.job_string(nil)==nil)
assert(env.job_string({})==nil)
assert(env.job_string({sub_job='SAM',sub_job_level=59})==nil)
assert(env.job_string({main_job='WAR',main_job_level=3})=='WAR3')
assert(env.job_string({main_job='WAR',main_job_level=99,sub_job='SAM',sub_job_level=59})=='WAR99/SAM59')
assert(env.job_string({main_job='WAR'})=='WAR')
assert(env.job_string({main_job='WAR',sub_job='NON',sub_job_level=0})=='WAR')
assert(env.job_string({main_job='WAR',main_job_level=0,sub_job='SAM'})=='WAR/SAM')
assert(env.job_string({main_job=0})==nil)
for _,name in ipairs({'default','compact'}) do
    local expressions=Config.defaults.tracking.sets[name][1].expression
    local fn=factory.get(expressions[#expressions])
    setfenv(fn,env)
    env.cursor={name='Enemy',valid_target=true,id=123,index=10,distance=2}
    local before=fn()
    assert(not before:find('WAR',1,true))
    env.cursor.main_job='WAR'; env.cursor.main_job_level=3
    assert(fn():find(env.color_job('WAR3'),1,true))
    env.cursor.main_job_level=99; env.cursor.sub_job='SAM'; env.cursor.sub_job_level=59
    assert(fn():find(env.color_job('WAR99/SAM59'),1,true))
    env.cursor.valid_target=false
    assert(not fn():find('WAR',1,true))
    env.cursor=nil
    assert(fn():find('--',1,true))
end
print('PASS: job formatting, unknown/partial jobs and both built-in target tracking sets')